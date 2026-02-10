import Foundation

/// Checks commands for destructive patterns and enforces safety rules.
final class SafetyChecker {
    private let settings: VoxSettings

    /// Default destructive patterns to check against.
    static let defaultPatterns: [DestructivePattern] = [
        DestructivePattern(pattern: "rm -rf", description: "Recursive force delete"),
        DestructivePattern(pattern: "rm -r", description: "Recursive delete"),
        DestructivePattern(pattern: "rmdir", description: "Remove directory"),
        DestructivePattern(pattern: "DROP TABLE", description: "Drop database table"),
        DestructivePattern(pattern: "DROP DATABASE", description: "Drop database"),
        DestructivePattern(pattern: "TRUNCATE", description: "Truncate table"),
        DestructivePattern(pattern: "git push --force", description: "Force push"),
        DestructivePattern(pattern: "git push -f", description: "Force push"),
        DestructivePattern(pattern: "git reset --hard", description: "Hard reset"),
        DestructivePattern(pattern: "git clean -fd", description: "Force clean"),
        DestructivePattern(pattern: "docker rm", description: "Remove container"),
        DestructivePattern(pattern: "docker rmi", description: "Remove image"),
        DestructivePattern(pattern: "docker system prune", description: "Prune Docker system"),
        DestructivePattern(pattern: "sudo", description: "Superuser command"),
        DestructivePattern(pattern: "shutdown", description: "Shutdown system"),
        DestructivePattern(pattern: "reboot", description: "Reboot system"),
        DestructivePattern(pattern: "mkfs", description: "Format filesystem"),
        DestructivePattern(pattern: "dd if=", description: "Disk dump"),
        DestructivePattern(pattern: "> /dev/", description: "Write to device"),
        DestructivePattern(pattern: "chmod 777", description: "Open permissions"),
        DestructivePattern(pattern: ":(){ :|:& };:", description: "Fork bomb"),
    ]

    init(settings: VoxSettings = .shared) {
        self.settings = settings
    }

    /// Check if a command is destructive and needs confirmation.
    func check(_ command: String) -> SafetyResult {
        guard settings.confirmDestructive else {
            return .safe
        }

        let lower = command.lowercased()

        for pattern in Self.defaultPatterns {
            if lower.contains(pattern.pattern.lowercased()) {
                return .destructive(
                    command: command,
                    reason: pattern.description,
                    pattern: pattern.pattern
                )
            }
        }

        return .safe
    }

    /// Check if a command potentially contains secrets that should be masked.
    func containsSecrets(_ command: String) -> Bool {
        let secretPatterns = [
            "password", "passwd", "secret", "token", "api_key", "apikey",
            "api-key", "private_key", "ssh-key", "credential"
        ]

        let lower = command.lowercased()
        return secretPatterns.contains { lower.contains($0) }
    }

    /// Mask potential secrets in command text for logging.
    func maskSecrets(in text: String) -> String {
        var masked = text

        // Mask common secret patterns: KEY=value, --token value, etc.
        let patterns = [
            "(password|passwd|secret|token|api_key|apikey|api-key)\\s*[=:]\\s*\\S+",
            "--(password|token|secret|key)\\s+\\S+"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                masked = regex.stringByReplacingMatches(
                    in: masked, range: NSRange(masked.startIndex..., in: masked),
                    withTemplate: "$1=***"
                )
            }
        }

        return masked
    }
}

// MARK: - Types

struct DestructivePattern {
    let pattern: String
    let description: String
}

enum SafetyResult {
    case safe
    case destructive(command: String, reason: String, pattern: String)

    var isDestructive: Bool {
        if case .destructive = self { return true }
        return false
    }
}
