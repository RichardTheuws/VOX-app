import Foundation

/// Processes command output into summaries based on verbosity level.
final class ResponseProcessor {
    private let settings: VoxSettings
    var ollamaService: OllamaService?
    var soundPackManager: SoundPackManager?

    init(settings: VoxSettings = .shared, ollamaService: OllamaService? = nil, soundPackManager: SoundPackManager? = nil) {
        self.settings = settings
        self.ollamaService = ollamaService
        self.soundPackManager = soundPackManager
    }

    /// Process command output according to verbosity level.
    func process(_ result: ExecutionResult, verbosity: VerbosityLevel, command: String) async -> ProcessedResponse {
        switch verbosity {
        case .silent:
            return ProcessedResponse(
                spokenText: nil,
                status: result.isSuccess ? .success : .error
            )

        case .notice:
            let status: CommandStatus = result.isSuccess ? .success : .error

            // Check for custom sound pack first
            if !settings.customSoundPackName.isEmpty,
               let customPack = soundPackManager?.selectedPack(named: settings.customSoundPackName),
               let soundURL = customPack.randomSound(isSuccess: result.isSuccess) {
                return ProcessedResponse(spokenText: nil, customSoundURL: soundURL, status: status)
            }

            let pack = settings.noticeSoundPack
            switch pack {
            case .tts:
                let notice = localizedNotice(isSuccess: result.isSuccess)
                return ProcessedResponse(spokenText: notice, status: status)

            case .warcraft, .mario, .commandConquer, .zelda:
                let phrase = pack.randomPhrase(isSuccess: result.isSuccess) ?? localizedNotice(isSuccess: result.isSuccess)
                return ProcessedResponse(spokenText: phrase, status: status)

            case .systemSounds:
                let sounds = result.isSuccess ? NoticeSoundPack.successSounds : NoticeSoundPack.errorSounds
                let soundName = sounds.randomElement() ?? "Glass"
                return ProcessedResponse(spokenText: nil, soundName: soundName, status: status)
            }

        case .summary:
            let cleaned = stripTerminalUI(result.output)
            let cleanedResult = ExecutionResult(
                output: cleaned, exitCode: result.exitCode,
                duration: result.duration, wasTimeout: result.wasTimeout
            )

            // Short responses: read directly, skip Ollama overhead.
            // For conversational development flow, short answers should be instant.
            let meaningfulLines = cleaned.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let sentenceCount = cleaned.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            if meaningfulLines.count <= 2 && sentenceCount <= 2 && cleaned.count <= 200 {
                let spoken = cleanForSpeech(cleaned)
                if !spoken.isEmpty {
                    return ProcessedResponse(spokenText: spoken, status: result.isSuccess ? .success : .error)
                }
            }

            // Long responses: try Ollama first, fallback to heuristic
            if settings.summarizationMethod == .ollama,
               let ollama = ollamaService,
               await ollama.isServerRunning {
                if let ollamaSummary = await ollama.summarize(
                    text: cleaned, command: command,
                    maxSentences: settings.maxSummaryLength,
                    language: effectiveLanguageCode()
                ) {
                    return ProcessedResponse(spokenText: ollamaSummary, status: result.isSuccess ? .success : .error)
                }
            }

            // Heuristic fallback
            let summary = summarize(cleanedResult, command: command)
            return ProcessedResponse(spokenText: summary, status: result.isSuccess ? .success : .error)

        case .full:
            let cleaned = cleanForSpeech(stripTerminalUI(result.output))
            return ProcessedResponse(spokenText: cleaned, status: result.isSuccess ? .success : .error)
        }
    }

    /// Determine effective verbosity considering error escalation.
    func effectiveVerbosity(for result: ExecutionResult, target: TargetApp) -> VerbosityLevel {
        let base = settings.verbosity(for: target)

        if !result.isSuccess && settings.errorEscalation {
            let errorLevel = settings.errorVerbosity
            return max(base, errorLevel)
        }

        return base
    }

    // MARK: - Localized Notice

    /// Generate a localized ready notice based on response language setting.
    private func localizedNotice(isSuccess: Bool) -> String {
        let lang = effectiveLanguageCode()

        if isSuccess {
            switch lang {
            case "nl": return "Klaar. Bekijk de terminal om verder te gaan."
            case "de": return "Fertig. Überprüfe das Terminal um fortzufahren."
            default:   return "Done. Check the terminal to continue."
            }
        } else {
            switch lang {
            case "nl": return "Er is een fout opgetreden. Bekijk de terminal."
            case "de": return "Ein Fehler ist aufgetreten. Überprüfe das Terminal."
            default:   return "An error occurred. Check the terminal."
            }
        }
    }

    /// Determine the effective language code based on settings.
    func effectiveLanguageCode() -> String {
        switch settings.responseLanguage {
        case .dutch: return "nl"
        case .english: return "en"
        case .german: return "de"
        case .followInput:
            switch settings.inputLanguage {
            case .dutch: return "nl"
            case .german: return "de"
            case .english: return "en"
            case .autoDetect: return "en"
            }
        }
    }

    /// Return localized string based on response language setting.
    func localized(en: String, nl: String, de: String) -> String {
        switch effectiveLanguageCode() {
        case "nl": return nl
        case "de": return de
        default: return en
        }
    }

    // MARK: - Terminal UI Stripping

    /// Remove CLI UI artifacts that shouldn't be read aloud.
    /// Strips progress bars, model info, keyboard hints, cost/token lines, version strings.
    private func stripTerminalUI(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)

        let filtered = lines.filter { line in
            let l = line.trimmingCharacters(in: .whitespaces)

            // Keep empty lines for paragraph structure
            if l.isEmpty { return true }

            // Progress bars (block characters)
            if l.contains("█") || l.contains("▓") || l.contains("░") || l.contains("■") || l.contains("□") {
                return false
            }

            // Arrow/play indicators (Claude Code footer)
            if l.contains("►") || l.contains("▶") { return false }

            // Model info lines: "Opus 4.6 |" or "Sonnet 4 |"
            if l.range(of: #"^(Opus|Sonnet|Haiku|Claude)\s+[\d.]+"#, options: .regularExpression) != nil {
                return false
            }

            // Version strings: "Claude Code v2.1.39"
            if l.range(of: #"Claude Code v[\d.]+"#, options: .regularExpression) != nil {
                return false
            }

            // Keyboard hints: "(shift+tab to cycle)", "(esc to cancel)"
            if l.range(of: #"\([a-z+]+\s+to\s+\w+\)"#, options: .regularExpression) != nil {
                return false
            }

            // Cost/token lines: "$0.12 | 1.2k tokens"
            if l.range(of: #"\$[\d.]+\s*[|│]"#, options: .regularExpression) != nil {
                return false
            }

            // Bypass permissions lines
            if l.contains("bypass permissions") { return false }

            // Box drawing characters (UI frames)
            if l.range(of: #"^[╭╮╰╯│─┌┐└┘├┤┬┴┼]"#, options: .regularExpression) != nil {
                return false
            }

            return true
        }

        return filtered.joined(separator: "\n")
    }

    // MARK: - Heuristic Summarization

    func summarize(_ result: ExecutionResult, command: String) -> String {
        let output = result.output

        if result.wasTimeout {
            let secs = Int(result.duration)
            return localized(
                en: "Command timed out after \(secs) seconds.",
                nl: "Commando verlopen na \(secs) seconden.",
                de: "Befehl nach \(secs) Sekunden abgelaufen."
            )
        }

        if !result.isSuccess {
            return summarizeError(output, exitCode: result.exitCode)
        }

        return summarizeSuccess(output, command: command)
    }

    private func summarizeSuccess(_ output: String, command: String) -> String {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        if lines.isEmpty {
            return localized(
                en: "Done. No output.",
                nl: "Klaar. Geen uitvoer.",
                de: "Fertig. Keine Ausgabe."
            )
        }

        // Git status
        if command.hasPrefix("git status") {
            return summarizeGitStatus(lines)
        }

        // Git log
        if command.hasPrefix("git log") {
            let count = lines.count
            return localized(
                en: "Showing \(count) commit\(count == 1 ? "" : "s").",
                nl: "\(count) commit\(count == 1 ? "" : "s") weergegeven.",
                de: "\(count) Commit\(count == 1 ? "" : "s") angezeigt."
            )
        }

        // npm/build commands
        if command.contains("npm") || command.contains("build") {
            if output.lowercased().contains("error") {
                let errorLines = lines.filter { $0.lowercased().contains("error") }
                if let firstError = errorLines.first {
                    let detail = truncate(firstError, maxLength: 80)
                    return localized(
                        en: "Build error: \(detail)",
                        nl: "Build fout: \(detail)",
                        de: "Build-Fehler: \(detail)"
                    )
                }
            }
            if output.lowercased().contains("success") || output.lowercased().contains("compiled") {
                return localized(
                    en: "Build completed successfully.",
                    nl: "Build succesvol afgerond.",
                    de: "Build erfolgreich abgeschlossen."
                )
            }
        }

        // ls / file listing
        if command.hasPrefix("ls") {
            let count = lines.count
            return localized(
                en: "\(count) items listed.",
                nl: "\(count) items weergegeven.",
                de: "\(count) Einträge aufgelistet."
            )
        }

        // Claude Code output
        if command.hasPrefix("claude") {
            return summarizeClaudeOutput(lines)
        }

        // Generic: first meaningful line + count
        let firstLine = truncate(lines[0], maxLength: 80)
        if lines.count == 1 {
            return firstLine
        }
        let count = lines.count
        return localized(
            en: "\(firstLine) (\(count) lines total)",
            nl: "\(firstLine) (\(count) regels totaal)",
            de: "\(firstLine) (\(count) Zeilen gesamt)"
        )
    }

    private func summarizeError(_ output: String, exitCode: Int32) -> String {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        let unknownError = localized(en: "Unknown error", nl: "Onbekende fout", de: "Unbekannter Fehler")

        // Find the most informative error line
        let errorLine = lines.first(where: { line in
            let lower = line.lowercased()
            return lower.contains("error") || lower.contains("fatal") ||
                   lower.contains("failed") || lower.contains("not found") ||
                   lower.contains("permission denied")
        }) ?? lines.last ?? unknownError

        let detail = truncate(errorLine, maxLength: 100)
        return localized(
            en: "Error (exit \(exitCode)): \(detail)",
            nl: "Fout (exit \(exitCode)): \(detail)",
            de: "Fehler (exit \(exitCode)): \(detail)"
        )
    }

    private func summarizeGitStatus(_ lines: [String]) -> String {
        var modified = 0, untracked = 0, staged = 0
        var branch = "unknown"

        for line in lines {
            if line.contains("On branch") {
                branch = line.replacingOccurrences(of: "On branch ", with: "")
            }
            if line.contains("modified:") { modified += 1 }
            if line.contains("new file:") { staged += 1 }
            if line.contains("Untracked files:") { untracked += 1 }
        }

        if modified == 0 && untracked == 0 && staged == 0 {
            if lines.contains(where: { $0.contains("nothing to commit") }) {
                return localized(
                    en: "On \(branch), working tree clean.",
                    nl: "Op \(branch), werkboom schoon.",
                    de: "Auf \(branch), Arbeitsbaum sauber."
                )
            }
        }

        let onBranch = localized(en: "On \(branch)", nl: "Op \(branch)", de: "Auf \(branch)")
        var parts: [String] = [onBranch]
        if modified > 0 {
            parts.append(localized(
                en: "\(modified) modified",
                nl: "\(modified) gewijzigd",
                de: "\(modified) geändert"
            ))
        }
        if staged > 0 {
            parts.append(localized(
                en: "\(staged) staged",
                nl: "\(staged) staged",
                de: "\(staged) bereitgestellt"
            ))
        }
        if untracked > 0 {
            parts.append(localized(
                en: "untracked files",
                nl: "niet-getrackte bestanden",
                de: "nicht verfolgte Dateien"
            ))
        }
        return parts.joined(separator: ", ") + "."
    }

    private func summarizeClaudeOutput(_ lines: [String]) -> String {
        // Look for file modification indicators
        let filePatterns = lines.filter { $0.contains("Created") || $0.contains("Modified") || $0.contains("Updated") }
        let testPatterns = lines.filter { $0.lowercased().contains("test") && $0.lowercased().contains("pass") }

        let done = localized(en: "Done.", nl: "Klaar.", de: "Fertig.")
        var parts: [String] = []

        if !filePatterns.isEmpty {
            let count = filePatterns.count
            parts.append(localized(
                en: "\(count) file\(count == 1 ? "" : "s") changed",
                nl: "\(count) bestand\(count == 1 ? "" : "en") gewijzigd",
                de: "\(count) Datei\(count == 1 ? "" : "en") geändert"
            ))
        }
        if !testPatterns.isEmpty {
            parts.append(localized(
                en: "tests passing",
                nl: "tests geslaagd",
                de: "Tests bestanden"
            ))
        }

        if parts.isEmpty {
            // Fallback: use last non-empty line
            if let lastLine = lines.last {
                return "\(done) \(truncate(lastLine, maxLength: 80))"
            }
            return done
        }

        return "\(done) \(parts.joined(separator: ", "))."
    }

    // MARK: - Helpers

    private func cleanForSpeech(_ text: String) -> String {
        var cleaned = text

        // Remove code blocks
        let codeBlockPattern = "```[\\s\\S]*?```"
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: "(code block omitted)"
            )
        }

        // Remove ANSI escape codes
        let ansiPattern = "\\x1B\\[[0-9;]*m"
        if let regex = try? NSRegularExpression(pattern: ansiPattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Remove URLs (read domain only)
        let urlPattern = "https?://([\\w.-]+)[\\S]*"
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: "link to $1"
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }
}

// MARK: - Types

struct ProcessedResponse {
    let spokenText: String?
    let soundName: String?        // NSSound name for system sounds
    let customSoundURL: URL?      // URL to custom audio file
    let status: CommandStatus

    init(spokenText: String?, soundName: String? = nil, customSoundURL: URL? = nil, status: CommandStatus) {
        self.spokenText = spokenText
        self.soundName = soundName
        self.customSoundURL = customSoundURL
        self.status = status
    }
}

/// Result from terminal monitoring (or command execution).
struct ExecutionResult {
    let output: String
    let exitCode: Int32
    let duration: TimeInterval
    let wasTimeout: Bool

    var isSuccess: Bool { exitCode == 0 }
}

// Allow VerbosityLevel to be compared
extension VerbosityLevel: Comparable {
    static func < (lhs: VerbosityLevel, rhs: VerbosityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
