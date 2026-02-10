import Foundation
import SwiftUI

/// Persistent settings for the VOX app.
final class VoxSettings: ObservableObject {
    static let shared = VoxSettings()

    // MARK: - General

    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("theme") var theme: AppTheme = .system
    @AppStorage("inputLanguage") var inputLanguage: InputLanguage = .autoDetect
    @AppStorage("responseLanguage") var responseLanguage: ResponseLanguage = .followInput

    // MARK: - Voice Input (STT)

    @AppStorage("sttEngine") var sttEngine: STTEngine = .hex
    @AppStorage("activationMode") var activationMode: ActivationMode = .pushToTalk
    @AppStorage("whisperModel") var whisperModel: WhisperModel = .largev3

    // MARK: - TTS Output

    @AppStorage("ttsEngine") var ttsEngine: TTSEngineType = .macosSay
    @AppStorage("ttsSpeed") var ttsSpeed: Double = 1.0
    @AppStorage("ttsVolume") var ttsVolume: Double = 0.8
    @AppStorage("interruptOnNewCommand") var interruptOnNewCommand = true

    // MARK: - Verbosity

    @AppStorage("defaultVerbosity") var defaultVerbosity: VerbosityLevel = .summary
    @AppStorage("errorEscalation") var errorEscalation = true
    @AppStorage("errorVerbosity") var errorVerbosity: VerbosityLevel = .summary

    // MARK: - Apps

    @AppStorage("autoDetectTarget") var autoDetectTarget = true
    @AppStorage("defaultTarget") var defaultTarget: TargetApp = .terminal
    @AppStorage("fallbackTarget") var fallbackTarget: TargetApp = .terminal

    // MARK: - Advanced

    @AppStorage("summarizationMethod") var summarizationMethod: SummarizationMethod = .heuristic
    @AppStorage("ollamaURL") var ollamaURL = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel = "llama3.2:3b"
    @AppStorage("maxSummaryLength") var maxSummaryLength = 2
    @AppStorage("commandTimeout") var commandTimeout: Double = 30
    @AppStorage("maxOutputCapture") var maxOutputCapture = 10000
    @AppStorage("confirmDestructive") var confirmDestructive = true
    @AppStorage("logToFile") var logToFile = false

    // MARK: - State

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

    // MARK: - Per-app verbosity

    func verbosity(for app: TargetApp) -> VerbosityLevel {
        let key = "verbosity_\(app.rawValue)"
        let raw = UserDefaults.standard.integer(forKey: key)
        if UserDefaults.standard.object(forKey: key) != nil {
            return VerbosityLevel(rawValue: raw) ?? defaultVerbosity
        }
        return defaultVerbosity
    }

    func setVerbosity(_ level: VerbosityLevel, for app: TargetApp) {
        let key = "verbosity_\(app.rawValue)"
        UserDefaults.standard.set(level.rawValue, forKey: key)
        objectWillChange.send()
    }

    private init() {}
}

// MARK: - Setting Enums

enum AppTheme: String, CaseIterable, Codable {
    case dark = "Dark"
    case light = "Light"
    case system = "System"
}

enum InputLanguage: String, CaseIterable, Codable {
    case autoDetect = "Auto-detect"
    case english = "English"
    case dutch = "Nederlands"
    case german = "Deutsch"
}

enum ResponseLanguage: String, CaseIterable, Codable {
    case followInput = "Follow input"
    case english = "English"
    case dutch = "Nederlands"
}

enum STTEngine: String, CaseIterable, Codable {
    case hex = "Hex"
    case builtIn = "Built-in (WhisperKit)"
}

enum TTSEngineType: String, CaseIterable, Codable {
    case macosSay = "macOS Say"
    case kokoro = "Kokoro"
    case piper = "Piper"
    case elevenLabs = "ElevenLabs"
    case disabled = "Disabled"
}

enum ActivationMode: String, CaseIterable, Codable {
    case pushToTalk = "Push-to-talk"
    case pushToToggle = "Push-to-toggle"
    case wakeWord = "Wake word"
    case alwaysListening = "Always listening"
}

enum WhisperModel: String, CaseIterable, Codable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largev3 = "large-v3"

    var displayName: String {
        switch self {
        case .tiny: "Tiny (fastest, least accurate)"
        case .base: "Base (fast, good accuracy)"
        case .small: "Small (balanced)"
        case .medium: "Medium (accurate, slower)"
        case .largev3: "Large v3 (most accurate)"
        }
    }

    var estimatedRAM: String {
        switch self {
        case .tiny: "~75MB"
        case .base: "~150MB"
        case .small: "~500MB"
        case .medium: "~1.0GB"
        case .largev3: "~1.5GB"
        }
    }
}

enum SummarizationMethod: String, CaseIterable, Codable {
    case heuristic = "Heuristic"
    case ollama = "Ollama"
    case claudeAPI = "Claude API"
    case openaiAPI = "OpenAI API"
}
