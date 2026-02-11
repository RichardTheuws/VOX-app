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

    /// Monitor app for new output after a Hex transcription.
    /// Takes an initial snapshot, then polls until output stabilizes.
    /// Returns the NEW output (diff from snapshot).
    func waitForNewOutput(
        bundleID: String,
        initialSnapshot: String,
        timeout: TimeInterval = 30,
        stabilizeDelay: TimeInterval = 1.5,
        pollInterval: TimeInterval = 0.3
    ) async -> String? {
        let startTime = Date()
        var lastContent = initialSnapshot
        var lastChangeTime = Date()
        let isTerminal = Self.terminalBasedBundleIDs.contains(bundleID)

        // Small initial delay to let the command start producing output
        try? await Task.sleep(for: .milliseconds(500))

        while Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(for: .seconds(pollInterval))

            guard let content = await readContent(for: bundleID) else { continue }

            if content != lastContent {
                lastContent = content
                lastChangeTime = Date()
            }

            // Content has stabilized (no changes for stabilizeDelay seconds)
            if Date().timeIntervalSince(lastChangeTime) >= stabilizeDelay {
                let newContent = extractNewContent(before: initialSnapshot, after: lastContent, isTerminalBased: isTerminal)
                if !newContent.isEmpty {
                    return newContent
                }
                // If no new content after stabilization, keep waiting
                // (the command might not have started yet)
            }
        }

        // Timeout — return whatever new content we have
        let newContent = extractNewContent(before: initialSnapshot, after: lastContent, isTerminalBased: isTerminal)
        return newContent.isEmpty ? nil : newContent
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
