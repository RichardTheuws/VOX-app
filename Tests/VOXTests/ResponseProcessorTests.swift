import XCTest
@testable import VOX

final class ResponseProcessorTests: XCTestCase {
    private var processor: ResponseProcessor!

    override func setUp() {
        super.setUp()
        processor = ResponseProcessor()
    }

    // MARK: - Silent Mode

    func testSilentModeReturnsNoText() {
        let result = ExecutionResult(output: "some output", exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = processor.process(result, verbosity: .silent, command: "ls")
        XCTAssertNil(response.spokenText)
        XCTAssertEqual(response.status, .success)
    }

    func testSilentModeErrorStatus() {
        let result = ExecutionResult(output: "error", exitCode: 1, duration: 0.5, wasTimeout: false)
        let response = processor.process(result, verbosity: .silent, command: "ls")
        XCTAssertNil(response.spokenText)
        XCTAssertEqual(response.status, .error)
    }

    // MARK: - Ping Mode

    func testPingModeSuccess() {
        let result = ExecutionResult(output: "output", exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = processor.process(result, verbosity: .ping, command: "ls")
        XCTAssertEqual(response.spokenText, "Done.")
        XCTAssertEqual(response.status, .success)
    }

    func testPingModeError() {
        let result = ExecutionResult(output: "error", exitCode: 1, duration: 0.5, wasTimeout: false)
        let response = processor.process(result, verbosity: .ping, command: "ls")
        XCTAssertEqual(response.spokenText, "Error occurred.")
        XCTAssertEqual(response.status, .error)
    }

    // MARK: - Summary Mode: Git Status

    func testSummaryGitStatusClean() {
        let output = """
        On branch main
        Your branch is up to date with 'origin/main'.

        nothing to commit, working tree clean
        """
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.3, wasTimeout: false)
        let response = processor.process(result, verbosity: .summary, command: "git status")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("main"))
        XCTAssertTrue(response.spokenText!.contains("clean"))
    }

    func testSummaryGitStatusModified() {
        let output = """
        On branch feature
        Changes not staged for commit:
          modified:   src/app.ts
          modified:   src/utils.ts
          modified:   package.json
        """
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.3, wasTimeout: false)
        let response = processor.process(result, verbosity: .summary, command: "git status")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("feature"))
        XCTAssertTrue(response.spokenText!.contains("3 modified"))
    }

    // MARK: - Summary Mode: Build Commands

    func testSummaryBuildSuccess() {
        let output = "Successfully compiled 42 files."
        let result = ExecutionResult(output: output, exitCode: 0, duration: 2.0, wasTimeout: false)
        let response = processor.process(result, verbosity: .summary, command: "npm run build")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.lowercased().contains("success") ||
                       response.spokenText!.lowercased().contains("compiled"))
    }

    func testSummaryBuildError() {
        let output = """
        ERROR in src/index.ts
        Module not found: Can't resolve 'react-dom'
        """
        let result = ExecutionResult(output: output, exitCode: 1, duration: 1.5, wasTimeout: false)
        let response = processor.process(result, verbosity: .summary, command: "npm run build")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.lowercased().contains("error"))
    }

    // MARK: - Summary Mode: Ls

    func testSummaryLsOutput() {
        let output = """
        total 24
        drwxr-xr-x  5 user  staff  160 Jan  1 12:00 .
        drwxr-xr-x  3 user  staff   96 Jan  1 12:00 ..
        -rw-r--r--  1 user  staff   42 Jan  1 12:00 file1.txt
        -rw-r--r--  1 user  staff   42 Jan  1 12:00 file2.txt
        """
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.1, wasTimeout: false)
        let response = processor.process(result, verbosity: .summary, command: "ls -la")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("items listed"))
    }

    // MARK: - Summary Mode: Timeout

    func testSummaryTimeout() {
        let result = ExecutionResult(output: "", exitCode: -1, duration: 30.0, wasTimeout: true)
        let response = processor.process(result, verbosity: .summary, command: "sleep 999")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("timed out"))
    }

    // MARK: - Summary Mode: Empty Output

    func testSummaryEmptyOutput() {
        let result = ExecutionResult(output: "", exitCode: 0, duration: 0.1, wasTimeout: false)
        let response = processor.process(result, verbosity: .summary, command: "touch file.txt")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("No output"))
    }

    // MARK: - Summary Mode: Generic Error

    func testSummaryGenericError() {
        let output = "fatal: not a git repository"
        let result = ExecutionResult(output: output, exitCode: 128, duration: 0.1, wasTimeout: false)
        let response = processor.process(result, verbosity: .summary, command: "git log")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("128") || response.spokenText!.contains("fatal"))
    }

    // MARK: - Full Mode

    func testFullModeReturnsCleanedOutput() {
        let output = "Hello world\nhttps://example.com/path\nDone"
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = processor.process(result, verbosity: .full, command: "echo test")

        XCTAssertNotNil(response.spokenText)
        // URLs should be cleaned
        XCTAssertTrue(response.spokenText!.contains("link to example.com"))
        XCTAssertFalse(response.spokenText!.contains("https://"))
    }

    func testFullModeStripsCodeBlocks() {
        let output = "Here is code:\n```swift\nlet x = 1\n```\nEnd."
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = processor.process(result, verbosity: .full, command: "claude explain")

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("code block omitted"))
        XCTAssertFalse(response.spokenText!.contains("let x = 1"))
    }

    // MARK: - VerbosityLevel Comparable

    func testVerbosityComparable() {
        XCTAssertTrue(VerbosityLevel.silent < VerbosityLevel.ping)
        XCTAssertTrue(VerbosityLevel.ping < VerbosityLevel.summary)
        XCTAssertTrue(VerbosityLevel.summary < VerbosityLevel.full)
    }
}
