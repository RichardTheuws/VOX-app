import AppKit

/// Routes voice transcriptions to the appropriate target application.
final class CommandRouter {
    private let settings: VoxSettings

    init(settings: VoxSettings = .shared) {
        self.settings = settings
    }

    /// Route a transcription to the appropriate target and resolve the command.
    func route(_ transcription: String) -> RoutedCommand {
        let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Check for explicit voice prefixes
        for app in TargetApp.allCases {
            for prefix in app.voicePrefixes {
                if trimmed.hasPrefix(prefix + " ") {
                    let command = String(transcription.dropFirst(prefix.count + 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return RoutedCommand(
                        target: app,
                        command: resolveCommand(command, for: app),
                        originalTranscription: transcription
                    )
                }
            }
        }

        // Auto-detect based on active application
        if settings.autoDetectTarget {
            if let activeTarget = detectActiveTarget() {
                return RoutedCommand(
                    target: activeTarget,
                    command: resolveCommand(transcription, for: activeTarget),
                    originalTranscription: transcription
                )
            }
        }

        // Fall back to default target
        let target = settings.fallbackTarget
        return RoutedCommand(
            target: target,
            command: resolveCommand(transcription, for: target),
            originalTranscription: transcription
        )
    }

    // MARK: - Private

    /// Detect which supported app currently has focus.
    private func detectActiveTarget() -> TargetApp? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else { return nil }

        return TargetApp.allCases.first { $0.bundleIdentifier == bundleID }
    }

    /// Resolve natural language to a shell command where possible.
    private func resolveCommand(_ input: String, for target: TargetApp) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // For Claude Code, wrap as a prompt
        if target == .claudeCode {
            return trimmed // Will be passed to `claude` CLI
        }

        // For terminal-based targets, attempt to interpret as shell command
        if target.isTerminalBased {
            return resolveShellCommand(trimmed)
        }

        // For IDE targets, construct CLI command
        if let cli = target.cliCommand {
            return "\(cli) \(trimmed)"
        }

        return trimmed
    }

    /// Try to interpret natural language as a shell command.
    private func resolveShellCommand(_ input: String) -> String {
        let lower = input.lowercased()

        // Already looks like a command (starts with known commands)
        let shellCommands = ["git", "ls", "cd", "cat", "grep", "find", "npm", "node",
                            "python", "pip", "docker", "ssh", "curl", "wget", "brew",
                            "mkdir", "rm", "cp", "mv", "touch", "chmod", "chown",
                            "echo", "export", "source", "which", "man", "top", "ps",
                            "kill", "swift", "xcodebuild", "open", "pbcopy", "pbpaste"]

        let firstWord = lower.components(separatedBy: " ").first ?? ""
        if shellCommands.contains(firstWord) {
            return input // Already a shell command
        }

        // Natural language patterns
        if lower.hasPrefix("list files") || lower.hasPrefix("show files") {
            return "ls -la"
        }
        if lower.hasPrefix("show directory") || lower.hasPrefix("where am i") {
            return "pwd"
        }
        if lower.hasPrefix("go to ") {
            let path = String(input.dropFirst(6))
            return "cd \(path)"
        }
        if lower.hasPrefix("create folder ") || lower.hasPrefix("make directory ") {
            let name = String(input.dropFirst(lower.hasPrefix("create folder ") ? 14 : 15))
            return "mkdir -p \(name)"
        }
        if lower.hasPrefix("delete ") || lower.hasPrefix("remove ") {
            let target = String(input.dropFirst(7))
            return "rm \(target)"
        }

        // Default: pass through as-is (user probably said a direct command)
        return input
    }
}

// MARK: - Types

struct RoutedCommand {
    let target: TargetApp
    let command: String
    let originalTranscription: String
}
