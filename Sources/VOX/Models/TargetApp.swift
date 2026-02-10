import Foundation

/// Supported target applications that VOX can send commands to.
enum TargetApp: String, CaseIterable, Codable, Identifiable {
    case terminal = "Terminal"
    case iterm2 = "iTerm2"
    case claudeCode = "Claude Code"
    case vsCode = "VS Code"
    case cursor = "Cursor"
    case windsurf = "Windsurf"

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm2: "com.googlecode.iterm2"
        case .claudeCode: "com.apple.Terminal" // Claude Code runs in terminal
        case .vsCode: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .windsurf: "com.codeium.windsurf"
        }
    }

    var cliCommand: String? {
        switch self {
        case .vsCode: "code"
        case .cursor: "cursor"
        case .windsurf: "windsurf"
        default: nil
        }
    }

    /// Voice prefixes that route commands to this target.
    var voicePrefixes: [String] {
        switch self {
        case .terminal: ["terminal", "shell", "bash", "zsh"]
        case .iterm2: ["iterm"]
        case .claudeCode: ["claude", "claude code"]
        case .vsCode: ["code", "vs code", "vscode"]
        case .cursor: ["cursor"]
        case .windsurf: ["windsurf", "surf"]
        }
    }

    var isTerminalBased: Bool {
        switch self {
        case .terminal, .iterm2, .claudeCode: true
        case .vsCode, .cursor, .windsurf: false
        }
    }

    /// MoSCoW tier for this app.
    var tier: MoSCoWTier {
        switch self {
        case .terminal, .iterm2, .claudeCode: .must
        case .vsCode, .cursor, .windsurf: .should
        }
    }
}

enum MoSCoWTier: String, Codable {
    case must = "Must Have"
    case should = "Should Have"
    case could = "Could Have"
}
