import AVFoundation
import AppKit

/// Text-to-speech engine that supports multiple backends.
/// MVP uses macOS NSSpeechSynthesizer; future versions add Kokoro, Piper, ElevenLabs.
@MainActor
final class TTSEngine: ObservableObject {
    @Published var isSpeaking = false

    private let synthesizer = NSSpeechSynthesizer()
    private let settings: VoxSettings
    private var delegate: TTSDelegate?

    init(settings: VoxSettings = .shared) {
        self.settings = settings
        self.delegate = TTSDelegate(engine: self)
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
        case .kokoro, .piper:
            // Future: implement local TTS
            speakWithNative(text) // Fallback to native for MVP
        case .elevenLabs:
            // Future: implement cloud TTS
            speakWithNative(text) // Fallback to native for MVP
        case .disabled:
            break
        }
    }

    /// Stop any current speech.
    func stop() {
        synthesizer.stopSpeaking()
        isSpeaking = false
    }

    // MARK: - Native macOS TTS

    private func speakWithNative(_ text: String) {
        // Set volume
        synthesizer.volume = Float(settings.ttsVolume)

        // Set rate (default is ~180 words per minute)
        let baseRate = Float(NSSpeechSynthesizer.defaultRate)
        synthesizer.rate = baseRate * Float(settings.ttsSpeed)

        // Select voice based on language setting
        if let voice = preferredVoice() {
            synthesizer.setVoice(voice)
        }

        isSpeaking = true
        synthesizer.startSpeaking(text)
    }

    /// Select the best available voice for the configured response language.
    private func preferredVoice() -> NSSpeechSynthesizer.VoiceName? {
        let targetLang: String
        switch settings.responseLanguage {
        case .dutch: targetLang = "nl"
        case .english: targetLang = "en"
        case .followInput:
            switch settings.inputLanguage {
            case .dutch: targetLang = "nl"
            case .german: targetLang = "de"
            case .english: targetLang = "en"
            case .autoDetect: return nil // use system default
            }
        }

        let voices = NSSpeechSynthesizer.availableVoices
        let voiceAttrs: [(NSSpeechSynthesizer.VoiceName, [NSSpeechSynthesizer.VoiceAttributeKey: Any])] = voices.compactMap { voice in
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
            return (voice, attrs)
        }

        // Prefer premium voices (not "compact") for better quality
        let premium = voiceAttrs.first { _, attrs in
            let locale = attrs[.localeIdentifier] as? String ?? ""
            let name = attrs[.name] as? String ?? ""
            return locale.hasPrefix(targetLang) && !name.lowercased().contains("compact")
        }

        if let premium { return premium.0 }

        // Fallback: any voice matching the language
        let fallback = voiceAttrs.first { _, attrs in
            let locale = attrs[.localeIdentifier] as? String ?? ""
            return locale.hasPrefix(targetLang)
        }

        return fallback?.0
    }

    /// Called by delegate when speech finishes.
    func didFinishSpeaking() {
        isSpeaking = false
    }
}

// MARK: - Delegate

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

// Extend NSSpeechSynthesizer to get default rate
extension NSSpeechSynthesizer {
    static let defaultRate: Float = 180.0
}
