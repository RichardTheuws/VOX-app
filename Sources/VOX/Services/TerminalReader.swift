import Foundation

/// Reads application content to monitor command output.
/// Uses AppleScript for Terminal.app/iTerm2, Accessibility API for Electron-based editors.
final class TerminalReader {

    private let accessibilityReader = AccessibilityReader()

    /// Read the current content of Terminal.app's active tab via osascript.
    func readTerminalContent() async -> String? {
        await runAppleScript(
            "tell application \"Terminal\" to if (count of windows) > 0 then get contents of selected tab of front window"
        )
    }

    /// Read the current content of iTerm2's active session via osascript.
    func readITermContent() async -> String? {
        await runAppleScript(
            "tell application \"iTerm2\" to tell current session of current tab of current window to get contents"
        )
    }

    /// Read content for the given bundle ID.
    /// Terminal.app and iTerm2 use AppleScript; other apps use the Accessibility API.
    func readContent(for bundleID: String) async -> String? {
        switch bundleID {
        case "com.apple.Terminal":
            return await readTerminalContent()
        case "com.googlecode.iterm2":
            return await readITermContent()
        default:
            // Electron-based apps (Cursor, VS Code, Windsurf) via Accessibility API
            return await accessibilityReader.readContent(for: bundleID)
        }
    }

    // MARK: - Monitoring Phases

    /// Phases for the adaptive two-phase stabilization algorithm.
    /// Phase 1 (.active): Fast polling, watching for content changes.
    /// Phase 2 (.verifying): Slower polling with exponential backoff, confirming completion.
    enum MonitorPhase {
        case active     // Content recently changed — poll fast
        case verifying  // Content stable for initialStabilizeDelay — confirming it's done
    }

    /// Monitor app for new output after a Hex transcription.
    /// Takes an initial snapshot, then polls until output stabilizes.
    /// Returns the NEW output (diff from snapshot).
    ///
    /// Uses adaptive two-phase stabilization for long-running tasks (e.g., Claude Code):
    /// - **Phase 1 (active)**: Fast polling (0.5s). After `initialStabilizeDelay` seconds of
    ///   no changes, moves to Phase 2. Prompt detection can trigger early exit.
    /// - **Phase 2 (verifying)**: Exponential backoff polling (2s → 5s → 10s). After
    ///   `confirmationDelay` more seconds of stability, returns as "confirmed done".
    ///   If content changes, resets back to Phase 1.
    func waitForNewOutput(
        bundleID: String,
        initialSnapshot: String,
        timeout: TimeInterval = 3600,
        initialStabilizeDelay: TimeInterval = 3.0,
        confirmationDelay: TimeInterval = 15.0,
        usePromptDetection: Bool = true
    ) async -> String? {
        let startTime = Date()
        var lastContent = initialSnapshot
        var lastChangeTime = Date()
        let isTerminal = Self.terminalBasedBundleIDs.contains(bundleID)
        var pollCount = 0
        var changeCount = 0
        var nilCount = 0
        var hasSeenAnyChange = false
        var phase: MonitorPhase = .active

        AccessibilityReader.debugLog("=== waitForNewOutput START (adaptive) ===")
        AccessibilityReader.debugLog("  bundleID=\(bundleID) isTerminal=\(isTerminal) timeout=\(timeout)")
        AccessibilityReader.debugLog("  initialStabilize=\(initialStabilizeDelay)s confirm=\(confirmationDelay)s promptDetect=\(usePromptDetection)")
        AccessibilityReader.debugLog("  snapshot: \(initialSnapshot.count) chars")

        // Small initial delay to let the command start producing output
        try? await Task.sleep(for: .milliseconds(500))

        while Date().timeIntervalSince(startTime) < timeout {
            // Adaptive poll interval — fast when active, slow when verifying
            let secondsSinceChange = Date().timeIntervalSince(lastChangeTime)
            let currentPollInterval = Self.adaptivePollInterval(secondsSinceLastChange: secondsSinceChange)
            try? await Task.sleep(for: .seconds(currentPollInterval))
            pollCount += 1

            guard let content = await readContent(for: bundleID) else {
                nilCount += 1
                continue
            }

            if content != lastContent {
                changeCount += 1
                if phase == .verifying {
                    AccessibilityReader.debugLog("  poll[\(pollCount)] CHANGED in verification — back to active")
                } else {
                    AccessibilityReader.debugLog("  poll[\(pollCount)] CHANGED: \(content.count) chars (was \(lastContent.count))")
                }
                lastContent = content
                lastChangeTime = Date()
                hasSeenAnyChange = true
                phase = .active
                continue
            }

            let stableFor = Date().timeIntervalSince(lastChangeTime)

            switch phase {
            case .active:
                if stableFor >= initialStabilizeDelay {
                    // Terminal prompt detection: if shell prompt visible, command is done
                    if usePromptDetection && isTerminal && endsWithShellPrompt(lastContent) {
                        let newContent = extractNewContent(before: initialSnapshot, after: lastContent, isTerminalBased: isTerminal)
                        if !newContent.isEmpty {
                            AccessibilityReader.debugLog("  PROMPT DETECTED after \(pollCount) polls, \(changeCount) changes")
                            AccessibilityReader.debugLog("  diff result: \(newContent.count) chars: \(String(newContent.prefix(120)))")
                            return newContent
                        }
                    }

                    if !hasSeenAnyChange {
                        continue  // No output yet — keep waiting
                    }

                    // Move to verification phase
                    phase = .verifying
                    AccessibilityReader.debugLog("  poll[\(pollCount)] → VERIFYING (stable \(String(format: "%.1f", stableFor))s)")
                }

            case .verifying:
                // Terminal prompt detection in verification phase too
                if usePromptDetection && isTerminal && endsWithShellPrompt(lastContent) {
                    let newContent = extractNewContent(before: initialSnapshot, after: lastContent, isTerminalBased: isTerminal)
                    if !newContent.isEmpty {
                        AccessibilityReader.debugLog("  PROMPT DETECTED (verifying) after \(pollCount) polls, \(changeCount) changes")
                        AccessibilityReader.debugLog("  diff result: \(newContent.count) chars: \(String(newContent.prefix(120)))")
                        return newContent
                    }
                }

                // Confirmed done: stable for initialStabilizeDelay + confirmationDelay total
                if stableFor >= initialStabilizeDelay + confirmationDelay {
                    let newContent = extractNewContent(before: initialSnapshot, after: lastContent, isTerminalBased: isTerminal)
                    if !newContent.isEmpty {
                        AccessibilityReader.debugLog("  CONFIRMED DONE after \(pollCount) polls, \(changeCount) changes, \(nilCount) nils (stable \(String(format: "%.1f", stableFor))s)")
                        AccessibilityReader.debugLog("  diff result: \(newContent.count) chars: \(String(newContent.prefix(120)))")
                        return newContent
                    }
                    // No new content even after full stabilization — keep waiting
                    // (edge case: content reverted to original)
                }
            }
        }

        // Timeout — return whatever new content we have
        let newContent = extractNewContent(before: initialSnapshot, after: lastContent, isTerminalBased: isTerminal)
        AccessibilityReader.debugLog("  TIMEOUT after \(pollCount) polls, \(changeCount) changes, \(nilCount) nils")
        AccessibilityReader.debugLog("  final diff: \(newContent.count) chars")
        AccessibilityReader.debugLog("=== waitForNewOutput END ===")
        return newContent.isEmpty ? nil : newContent
    }

    // MARK: - Adaptive Polling

    /// Calculate poll interval based on how long content has been unchanged.
    /// Fast polling when content is actively changing, exponential backoff when stable.
    /// This reduces CPU usage from ~8000 polls to ~500 over a 40-minute session.
    static func adaptivePollInterval(secondsSinceLastChange: TimeInterval) -> TimeInterval {
        switch secondsSinceLastChange {
        case ..<3:    return 0.5   // Active: fast polling
        case 3..<8:   return 2.0   // First pause: slow down
        case 8..<15:  return 5.0   // Longer pause: slower
        default:      return 10.0  // Waiting: minimal polling (6/min)
        }
    }

    // MARK: - Terminal Prompt Detection

    /// Check if terminal content ends with a shell prompt, indicating the command is done.
    /// Detects common prompt patterns: bash ($), zsh (%), starship (❯), and others.
    /// Only useful for Terminal.app/iTerm2 where we read the scrollback buffer.
    func endsWithShellPrompt(_ content: String) -> Bool {
        // Find the last non-empty line
        let lastLine = content.components(separatedBy: .newlines)
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let trimmed = lastLine.trimmingCharacters(in: .whitespaces)

        // Empty or very long lines are not prompts
        guard !trimmed.isEmpty, trimmed.count < 200 else { return false }

        // Common shell prompt patterns:
        // $ (bash default), % (zsh default), ❯ (starship/custom), # (root)
        // user@host:~$ , hostname% , ❯ , (venv) user$
        let promptPatterns = [
            #"[$%❯›#]\s*$"#,                     // Prompt char at end of line
            #"\w+@[\w.-]+.*[$%#]\s*$"#,           // user@host$
        ]

        return promptPatterns.contains { pattern in
            trimmed.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Bundle IDs that use AppleScript (append-only scrollback).
    /// All other apps use Accessibility API (content changes in-place).
    private static let terminalBasedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2"
    ]

    // MARK: - Private

    /// Run an AppleScript via osascript and return the output.
    private func runAppleScript(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = pipe
            process.standardError = Pipe() // discard errors

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: output?.isEmpty == true ? nil : output)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Extract new content by diffing before/after snapshots.
    /// Terminal apps grow line-by-line (append-only scrollback).
    /// AX apps (Cursor, VS Code, Windsurf) may change content in-place.
    func extractNewContent(before: String, after: String, isTerminalBased: Bool) -> String {
        if before == after { return "" }

        if !isTerminalBased {
            return extractAXNewContent(before: before, after: after)
        }

        return extractTerminalNewContent(before: before, after: after)
    }

    /// Terminal-specific diff: content grows by appending new lines.
    private func extractTerminalNewContent(before: String, after: String) -> String {
        let beforeLines = before.components(separatedBy: .newlines)
        let afterLines = after.components(separatedBy: .newlines)

        guard afterLines.count > beforeLines.count else {
            // No new lines — check if last lines changed
            if after != before, after.count > before.count {
                // Content grew on existing lines (e.g., streaming output)
                return String(after.dropFirst(before.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }

        // Find where content diverges
        var commonPrefixCount = 0
        for (a, b) in zip(beforeLines, afterLines) {
            if a == b {
                commonPrefixCount += 1
            } else {
                break
            }
        }

        // New content = lines after the common prefix
        let newLines = Array(afterLines.dropFirst(commonPrefixCount))
        return newLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// AX-specific diff: content changes in-place rather than appending.
    /// Uses set comparison to find genuinely new lines.
    /// Falls back to returning full content if it changed but line-level diff is inconclusive.
    private func extractAXNewContent(before: String, after: String) -> String {
        let beforeLines = Set(
            before.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let afterLines = after.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Find lines that are genuinely new (not in the snapshot)
        let newLines = afterLines.filter {
            !beforeLines.contains($0.trimmingCharacters(in: .whitespaces))
        }

        if !newLines.isEmpty {
            return newLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Content changed but no individual new lines found → return full after content
        // (ResponseProcessor handles summarization)
        return after.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
