import XCTest
@testable import VOX

/// Integration tests that verify the full command pipeline.
/// These test the flow: transcription → routing → execution → processing → summary.
final class IntegrationTests: XCTestCase {
    private var router: CommandRouter!
    private var executor: TerminalExecutor!
    private var processor: ResponseProcessor!
    private var checker: SafetyChecker!

    override func setUp() {
        super.setUp()
        router = CommandRouter()
        executor = TerminalExecutor()
        processor = ResponseProcessor()
        checker = SafetyChecker()
    }

    // MARK: - Full Pipeline: Voice → Terminal → Summary

    func testFullPipelineGitStatus() async throws {
        // Step 1: Route transcription
        let routed = router.route("git status")
        XCTAssertEqual(routed.command, "git status")
        XCTAssertTrue(routed.target.isTerminalBased)

        // Step 2: Safety check
        let safety = checker.check(routed.command)
        XCTAssertFalse(safety.isDestructive)

        // Step 3: Execute command
        let result = try await executor.execute(routed.command)
        // We're in the vox-app dir which is a git repo
        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(result.output.isEmpty)

        // Step 4: Process response
        let response = processor.process(result, verbosity: .summary, command: routed.command)
        XCTAssertNotNil(response.spokenText)
        XCTAssertEqual(response.status, .success)

        // Summary should mention branch
        XCTAssertTrue(response.spokenText!.contains("main") ||
                       response.spokenText!.lowercased().contains("branch"))
    }

    func testFullPipelineEcho() async throws {
        let routed = router.route("echo hello VOX")

        let safety = checker.check(routed.command)
        XCTAssertFalse(safety.isDestructive)

        let result = try await executor.execute(routed.command)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.output, "hello VOX")

        let response = processor.process(result, verbosity: .summary, command: routed.command)
        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("hello VOX"))
    }

    func testFullPipelineLs() async throws {
        let routed = router.route("list files")
        XCTAssertEqual(routed.command, "ls -la")

        let result = try await executor.execute(routed.command)
        XCTAssertTrue(result.isSuccess)

        let response = processor.process(result, verbosity: .summary, command: routed.command)
        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("items listed"))
    }

    // MARK: - Full Pipeline: Destructive Command

    func testFullPipelineDestructiveBlocked() {
        let routed = router.route("rm -rf node_modules")

        let safety = checker.check(routed.command)
        XCTAssertTrue(safety.isDestructive)

        if case .destructive(_, let reason, _) = safety {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected destructive safety result")
        }
    }

    func testFullPipelineSecretMasking() async throws {
        let routed = router.route("export TOKEN=sk-abc123xyz")

        // Check secrets
        XCTAssertTrue(checker.containsSecrets(routed.command))

        // Mask for logging
        let masked = checker.maskSecrets(in: routed.command)
        XCTAssertFalse(masked.contains("sk-abc123xyz"))
    }

    // MARK: - Full Pipeline: Error Path

    func testFullPipelineCommandFailure() async throws {
        let routed = router.route("cat /nonexistent/file/path/xyz")
        let result = try await executor.execute(routed.command)
        XCTAssertFalse(result.isSuccess)

        let response = processor.process(result, verbosity: .summary, command: routed.command)
        XCTAssertNotNil(response.spokenText)
        XCTAssertEqual(response.status, .error)
        XCTAssertTrue(response.spokenText!.lowercased().contains("error") ||
                       response.spokenText!.lowercased().contains("no such"))
    }

    // MARK: - Full Pipeline: Verbosity Levels

    func testVerbosityLevelsSameCommand() async throws {
        let result = try await executor.execute("echo test output")

        // Silent: no text
        let silent = processor.process(result, verbosity: .silent, command: "echo test")
        XCTAssertNil(silent.spokenText)

        // Ping: short confirmation
        let ping = processor.process(result, verbosity: .ping, command: "echo test")
        XCTAssertEqual(ping.spokenText, "Done.")

        // Summary: summarized output
        let summary = processor.process(result, verbosity: .summary, command: "echo test")
        XCTAssertNotNil(summary.spokenText)

        // Full: complete output
        let full = processor.process(result, verbosity: .full, command: "echo test")
        XCTAssertNotNil(full.spokenText)
        XCTAssertTrue(full.spokenText!.contains("test output"))
    }

    // MARK: - Voice Prefix Routing

    func testVoicePrefixRouting() {
        let terminal = router.route("terminal ls -la")
        XCTAssertEqual(terminal.target, .terminal)
        XCTAssertEqual(terminal.command, "ls -la")

        let claude = router.route("claude explain this code")
        XCTAssertEqual(claude.target, .claudeCode)
        XCTAssertEqual(claude.command, "explain this code")
    }

    // MARK: - Natural Language to Command

    func testNaturalLanguageMappings() {
        let tests: [(input: String, expected: String)] = [
            ("list files", "ls -la"),
            ("show files", "ls -la"),
            ("where am i", "pwd"),
            ("show directory", "pwd"),
            ("go to Documents", "cd Documents"),
            ("create folder my-project", "mkdir -p my-project"),
        ]

        for test in tests {
            let routed = router.route(test.input)
            XCTAssertEqual(routed.command, test.expected,
                           "Input '\(test.input)' should resolve to '\(test.expected)' but got '\(routed.command)'")
        }
    }
}
