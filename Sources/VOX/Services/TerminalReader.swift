import Foundation

/// Reads terminal content via AppleScript to monitor command output.
/// Used in "monitor mode" when Hex dictation is sent to Terminal.app.
final class TerminalReader {

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

    /// Read terminal content for the given bundle ID.
    func readContent(for bundleID: String) async -> String? {
        switch bundleID {
        case "com.apple.Terminal":
            return await readTerminalContent()
        case "com.googlecode.iterm2":
            return await readITermContent()
        default:
            return nil
        }
    }

    /// Monitor terminal for new output after a Hex transcription.
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
                let newContent = extractNewContent(before: initialSnapshot, after: lastContent)
                if !newContent.isEmpty {
                    return newContent
                }
                // If no new content after stabilization, keep waiting
                // (the command might not have started yet)
            }
        }

        // Timeout — return whatever new content we have
        let newContent = extractNewContent(before: initialSnapshot, after: lastContent)
        return newContent.isEmpty ? nil : newContent
    }

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

    /// Extract new content by diffing before/after terminal snapshots.
    /// Uses line-by-line comparison for robustness.
    private func extractNewContent(before: String, after: String) -> String {
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
}
