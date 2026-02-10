import XCTest
@testable import VOX

final class TerminalExecutorTests: XCTestCase {
    private var executor: TerminalExecutor!

    override func setUp() {
        super.setUp()
        executor = TerminalExecutor()
    }

    // MARK: - Basic Execution

    func testEchoCommand() async throws {
        let result = try await executor.execute("echo 'hello world'")
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output, "hello world")
    }

    func testPwdCommand() async throws {
        let result = try await executor.execute("pwd")
        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(result.output.isEmpty)
    }

    func testDateCommand() async throws {
        let result = try await executor.execute("date +%Y")
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.output.contains("202"))
    }

    // MARK: - Exit Codes

    func testSuccessExitCode() async throws {
        let result = try await executor.execute("true")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.isSuccess)
    }

    func testFailureExitCode() async throws {
        let result = try await executor.execute("false")
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.isSuccess)
    }

    func testCommandNotFound() async throws {
        let result = try await executor.execute("nonexistentcommand_xyz_123")
        XCTAssertFalse(result.isSuccess)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    // MARK: - Output Capture

    func testMultiLineOutput() async throws {
        let result = try await executor.execute("echo 'line1' && echo 'line2' && echo 'line3'")
        XCTAssertTrue(result.isSuccess)
        let lines = result.output.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
    }

    func testStderrCapture() async throws {
        let result = try await executor.execute("echo 'error message' >&2")
        // stderr should be captured in output
        XCTAssertTrue(result.output.contains("error message"))
    }

    // MARK: - Duration Tracking

    func testDurationTracked() async throws {
        let result = try await executor.execute("sleep 0.1")
        XCTAssertGreaterThanOrEqual(result.duration, 0.1)
        XCTAssertLessThan(result.duration, 5.0) // sanity check
    }

    // MARK: - Piped Commands

    func testPipedCommand() async throws {
        let result = try await executor.execute("echo 'hello world' | tr 'h' 'H'")
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.output, "Hello world")
    }

    // MARK: - Environment

    func testEnvironmentVariables() async throws {
        let result = try await executor.execute("echo $HOME")
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.output.hasPrefix("/"))
    }

    // MARK: - ExecutionResult Properties

    func testExecutionResultIsSuccess() {
        let success = ExecutionResult(output: "", exitCode: 0, duration: 0.1, wasTimeout: false)
        XCTAssertTrue(success.isSuccess)

        let failure = ExecutionResult(output: "", exitCode: 1, duration: 0.1, wasTimeout: false)
        XCTAssertFalse(failure.isSuccess)
    }
}
