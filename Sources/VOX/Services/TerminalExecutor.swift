import Foundation

/// Executes shell commands and captures their output.
final class TerminalExecutor {
    private let settings: VoxSettings

    init(settings: VoxSettings = .shared) {
        self.settings = settings
    }

    /// Execute a shell command and return the result.
    func execute(_ command: String) async throws -> ExecutionResult {
        let shell = detectShell()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment

        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            let timeout = settings.commandTimeout
            let maxOutput = settings.maxOutputCapture

            // Timeout task
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                continuation.resume(throwing: ExecutionError.launchFailed(error.localizedDescription))
                return
            }

            process.terminationHandler = { _ in
                timeoutTask.cancel()
                let duration = Date().timeIntervalSince(startTime)

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                var stdout = String(data: outputData, encoding: .utf8) ?? ""
                let stderr = String(data: errorData, encoding: .utf8) ?? ""

                // Truncate if too large
                if stdout.count > maxOutput {
                    stdout = String(stdout.prefix(maxOutput)) + "\n... [truncated at \(maxOutput) chars]"
                }

                let combinedOutput = stderr.isEmpty ? stdout : "\(stdout)\n\(stderr)"

                let result = ExecutionResult(
                    output: combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                    exitCode: process.terminationStatus,
                    duration: duration,
                    wasTimeout: process.terminationReason == .uncaughtSignal
                )

                continuation.resume(returning: result)
            }
        }
    }

    /// Execute a command specifically for Claude Code CLI.
    func executeClaudeCode(_ prompt: String) async throws -> ExecutionResult {
        let command = "claude \"\(prompt.replacingOccurrences(of: "\"", with: "\\\""))\""
        return try await execute(command)
    }

    // MARK: - Private

    private func detectShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"] {
            return shell
        }
        // Fallback to zsh (default on macOS)
        return "/bin/zsh"
    }
}

// MARK: - Types

struct ExecutionResult {
    let output: String
    let exitCode: Int32
    let duration: TimeInterval
    let wasTimeout: Bool

    var isSuccess: Bool { exitCode == 0 }
}

enum ExecutionError: LocalizedError {
    case launchFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): "Failed to launch process: \(reason)"
        case .timeout: "Command timed out"
        }
    }
}
