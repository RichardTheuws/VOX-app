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

        isSpeaking = true
        synthesizer.startSpeaking(text)
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
