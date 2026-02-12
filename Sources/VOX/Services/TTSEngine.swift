import AVFoundation
import AppKit

/// Text-to-speech engine that supports multiple backends.
/// Supports macOS native, Edge TTS (free Microsoft Neural voices), and ElevenLabs (paid premium).
@MainActor
final class TTSEngine: ObservableObject {
    @Published var isSpeaking = false

    private let synthesizer = NSSpeechSynthesizer()
    private let settings: VoxSettings
    private var delegate: TTSDelegate?
    private var audioPlayer: AVAudioPlayer?
    private var audioDelegate: AudioDelegate?

    init(settings: VoxSettings = .shared) {
        self.settings = settings
        self.delegate = TTSDelegate(engine: self)
        self.audioDelegate = AudioDelegate(engine: self)
        self.synthesizer.delegate = delegate
    }

    /// Speak text using the configured TTS engine.
    func speak(_ text: String) {
        guard settings.ttsEngine != .disabled else { return }
        guard !text.isEmpty else { return }

        // Interrupt if already speaking
        if isSpeaking && settings.interruptOnNewCommand {
            stop()
        }

        switch settings.ttsEngine {
        case .macosSay:
            speakWithNative(text)
        case .edgeTTS:
            Task { await speakWithEdgeTTS(text) }
        case .elevenLabs:
            Task { await speakWithElevenLabs(text) }
        case .kokoro, .piper:
            // Placeholder: fallback to native
            speakWithNative(text)
        case .disabled:
            break
        }
    }

    /// Stop any current speech.
    func stop() {
        synthesizer.stopSpeaking()
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }

    /// Play a macOS system sound by name.
    func playSystemSound(_ name: String) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = Float(settings.ttsVolume)
        sound.play()
    }

    /// Play a custom audio file from URL.
    func playCustomSound(at url: URL) {
        guard let sound = NSSound(contentsOf: url, byReference: true) else { return }
        sound.volume = Float(settings.ttsVolume)
        sound.play()
    }

    // MARK: - Native macOS TTS

    private func speakWithNative(_ text: String) {
        // Set volume
        synthesizer.volume = Float(settings.ttsVolume)

        // Set rate (default is ~180 words per minute)
        let baseRate = Float(NSSpeechSynthesizer.defaultRate)
        synthesizer.rate = baseRate * Float(settings.ttsSpeed)

        // Select voice adaptively: detect text language + match gender preference
        if let voice = preferredVoice(for: text) {
            synthesizer.setVoice(voice)
        }

        isSpeaking = true
        synthesizer.startSpeaking(text)
    }

    /// Select the best native voice matching detected text language + gender preference.
    /// Uses NLLanguageRecognizer to detect language, then filters voices by locale and gender.
    private func preferredVoice(for text: String) -> NSSpeechSynthesizer.VoiceName? {
        let targetLang = LanguageDetector.detect(text)
        let targetGender = settings.voiceGender

        let voices = NSSpeechSynthesizer.availableVoices
        let voiceAttrs: [(NSSpeechSynthesizer.VoiceName, [NSSpeechSynthesizer.VoiceAttributeKey: Any])] = voices.compactMap { voice in
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
            return (voice, attrs)
        }

        // macOS voice gender attribute values
        let genderMatch = targetGender == .male ? "VoiceGenderMale" : "VoiceGenderFemale"

        // Best: language + gender + premium (not "compact")
        let best = voiceAttrs.first(where: { pair in
            let attrs = pair.1
            let locale = attrs[NSSpeechSynthesizer.VoiceAttributeKey.localeIdentifier] as? String ?? ""
            let gender = attrs[NSSpeechSynthesizer.VoiceAttributeKey.gender] as? String ?? ""
            let name = attrs[NSSpeechSynthesizer.VoiceAttributeKey.name] as? String ?? ""
            return locale.hasPrefix(targetLang) && gender == genderMatch && !name.lowercased().contains("compact")
        })
        if let best { return best.0 }

        // Fallback: language + gender (any quality)
        let langGender = voiceAttrs.first(where: { pair in
            let attrs = pair.1
            let locale = attrs[NSSpeechSynthesizer.VoiceAttributeKey.localeIdentifier] as? String ?? ""
            let gender = attrs[NSSpeechSynthesizer.VoiceAttributeKey.gender] as? String ?? ""
            return locale.hasPrefix(targetLang) && gender == genderMatch
        })
        if let langGender { return langGender.0 }

        // Fallback: language only (any gender, prefer premium)
        let langOnly = voiceAttrs.first(where: { pair in
            let attrs = pair.1
            let locale = attrs[NSSpeechSynthesizer.VoiceAttributeKey.localeIdentifier] as? String ?? ""
            let name = attrs[NSSpeechSynthesizer.VoiceAttributeKey.name] as? String ?? ""
            return locale.hasPrefix(targetLang) && !name.lowercased().contains("compact")
        })
        if let langOnly { return langOnly.0 }

        // Last resort: language only (any quality, any gender)
        let anyMatch = voiceAttrs.first(where: { pair in
            let attrs = pair.1
            let locale = attrs[NSSpeechSynthesizer.VoiceAttributeKey.localeIdentifier] as? String ?? ""
            return locale.hasPrefix(targetLang)
        })
        return anyMatch?.0
    }

    // MARK: - ElevenLabs TTS

    /// Speak text via ElevenLabs REST API.
    /// Uses eleven_multilingual_v2 model for excellent Dutch/English/German support.
    /// Falls back to native TTS on any error.
    private func speakWithElevenLabs(_ text: String) async {
        guard !settings.elevenLabsAPIKey.isEmpty else {
            speakWithNative(text)
            return
        }

        // Use configured voice or default to Rachel (multilingual)
        let voiceID = settings.elevenLabsVoiceID.isEmpty
            ? "21m00Tcm4TlvDq8ikWAM"
            : settings.elevenLabsVoiceID

        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)") else {
            speakWithNative(text)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(settings.elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                speakWithNative(text)
                return
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vox-elevenlabs-\(UUID().uuidString).mp3")
            try data.write(to: tempURL)
            playAudioFile(at: tempURL)
        } catch {
            speakWithNative(text)
        }
    }

    // MARK: - Edge TTS

    /// Pick the right Edge TTS voice for detected language + gender preference.
    /// Maps (language × gender) → Microsoft Neural voice name.
    func adaptiveEdgeTTSVoice(for text: String) -> String {
        let lang = LanguageDetector.detect(text)
        let gender = settings.voiceGender

        switch (lang, gender) {
        case ("nl", .female): return "nl-NL-ColetteNeural"
        case ("nl", .male):   return "nl-NL-MaartenNeural"
        case ("de", .female): return "de-DE-AmalaNeural"
        case ("de", .male):   return "de-DE-ConradNeural"
        case (_, .female):    return "en-US-JennyNeural"
        case (_, .male):      return "en-US-GuyNeural"
        }
    }

    /// Speak text via edge-tts CLI (free Microsoft Neural voices).
    /// Automatically selects voice based on detected text language + gender preference.
    /// Falls back to native TTS if edge-tts is not installed.
    private func speakWithEdgeTTS(_ text: String) async {
        guard let edgeTTSPath = Self.findEdgeTTSBinary() else {
            speakWithNative(text)
            return
        }

        let voice = adaptiveEdgeTTSVoice(for: text)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-edge-\(UUID().uuidString).mp3")

        // Run edge-tts in background thread to avoid blocking main actor
        let result: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: edgeTTSPath)
                process.arguments = ["--voice", voice, "--text", text,
                                     "--write-media", tempURL.path]
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }

        guard result else {
            speakWithNative(text)
            return
        }

        playAudioFile(at: tempURL)
    }

    /// Find edge-tts binary in common pip3 install locations.
    static func findEdgeTTSBinary() -> String? {
        let home = NSHomeDirectory()
        let paths = [
            "/opt/homebrew/bin/edge-tts",
            "/usr/local/bin/edge-tts",
            "\(home)/.local/bin/edge-tts",
            "\(home)/Library/Python/3.13/bin/edge-tts",
            "\(home)/Library/Python/3.12/bin/edge-tts",
            "\(home)/Library/Python/3.11/bin/edge-tts",
            "\(home)/Library/Python/3.10/bin/edge-tts",
            "\(home)/Library/Python/3.9/bin/edge-tts",
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Check if edge-tts is installed and available.
    static var isEdgeTTSInstalled: Bool {
        findEdgeTTSBinary() != nil
    }

    // MARK: - Audio Playback

    /// Play an audio file (mp3/wav) with volume and speed settings.
    /// Used by ElevenLabs and edge-tts engines.
    private func playAudioFile(at url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(settings.ttsVolume)
            player.enableRate = true
            player.rate = Float(settings.ttsSpeed)
            player.delegate = audioDelegate
            self.audioPlayer = player
            isSpeaking = true
            player.play()
        } catch {
            isSpeaking = false
        }
    }

    /// Called by delegates when speech/audio finishes.
    func didFinishSpeaking() {
        isSpeaking = false
        // Clean up temp audio files
        audioPlayer = nil
    }
}

// MARK: - NSSpeechSynthesizer Delegate

private final class TTSDelegate: NSObject, NSSpeechSynthesizerDelegate, @unchecked Sendable {
    private weak var engine: TTSEngine?

    init(engine: TTSEngine) {
        self.engine = engine
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        Task { @MainActor in
            engine?.didFinishSpeaking()
        }
    }
}

// MARK: - AVAudioPlayer Delegate

private final class AudioDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private weak var engine: TTSEngine?

    init(engine: TTSEngine) {
        self.engine = engine
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            engine?.didFinishSpeaking()
        }
    }
}

// Extend NSSpeechSynthesizer to get default rate
extension NSSpeechSynthesizer {
    static let defaultRate: Float = 180.0
}
