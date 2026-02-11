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

    // MARK: - Notice Sound Pack

    @AppStorage("noticeSoundPack") var noticeSoundPack: NoticeSoundPack = .tts
    @AppStorage("customSoundPackName") var customSoundPackName: String = ""

    // MARK: - Advanced

    @AppStorage("summarizationMethod") var summarizationMethod: SummarizationMethod = .heuristic
    @AppStorage("ollamaURL") var ollamaURL = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel = "llama3.2:3b"
    @AppStorage("maxSummaryLength") var maxSummaryLength = 2
    @AppStorage("commandTimeout") var commandTimeout: Double = 30
    @AppStorage("maxOutputCapture") var maxOutputCapture = 10000
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

enum TTSEngineType: String, CaseIterable, Codable {
    case macosSay = "macOS Say"
    case kokoro = "Kokoro"
    case piper = "Piper"
    case elevenLabs = "ElevenLabs"
    case disabled = "Disabled"
}

enum SummarizationMethod: String, CaseIterable, Codable {
    case heuristic = "Heuristic"
    case ollama = "Ollama"
    case claudeAPI = "Claude API"
    case openaiAPI = "OpenAI API"
}
