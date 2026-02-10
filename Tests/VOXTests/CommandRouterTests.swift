import XCTest
@testable import VOX

final class CommandRouterTests: XCTestCase {
    private var router: CommandRouter!

    override func setUp() {
        super.setUp()
        router = CommandRouter()
    }

    // MARK: - Voice Prefix Routing

    func testTerminalPrefix() {
        let result = router.route("terminal git status")
        XCTAssertEqual(result.target, .terminal)
        XCTAssertEqual(result.command, "git status")
    }

    func testClaudePrefix() {
        let result = router.route("claude fix the login bug")
        XCTAssertEqual(result.target, .claudeCode)
        XCTAssertEqual(result.command, "fix the login bug")
    }

    func testCodePrefix() {
        let result = router.route("code open utils.py")
        // "code" is a prefix for vsCode, cursor, or windsurf
        XCTAssertTrue([.vsCode, .cursor, .windsurf].contains(result.target))
    }

    // MARK: - Shell Command Detection

    func testDirectShellCommand() {
        let result = router.route("git status")
        // Should be recognized as a shell command and passed through
        XCTAssertEqual(result.command, "git status")
    }

    func testLsCommand() {
        let result = router.route("ls -la")
        XCTAssertEqual(result.command, "ls -la")
    }

    func testNpmCommand() {
        let result = router.route("npm install express")
        XCTAssertEqual(result.command, "npm install express")
    }

    // MARK: - Natural Language Resolution

    func testListFiles() {
        let result = router.route("list files")
        XCTAssertEqual(result.command, "ls -la")
    }

    func testShowDirectory() {
        let result = router.route("where am i")
        XCTAssertEqual(result.command, "pwd")
    }

    func testGoTo() {
        let result = router.route("go to Documents")
        XCTAssertEqual(result.command, "cd Documents")
    }

    func testCreateFolder() {
        let result = router.route("create folder test-project")
        XCTAssertEqual(result.command, "mkdir -p test-project")
    }

    // MARK: - Transcription Preservation

    func testOriginalTranscriptionPreserved() {
        let input = "  git status  "
        let result = router.route(input)
        XCTAssertEqual(result.originalTranscription, input)
    }

    // MARK: - Fallback

    func testUnknownInputPassedThrough() {
        let result = router.route("deploy to production")
        // Unknown input should be passed through as-is to the default target
        XCTAssertEqual(result.command, "deploy to production")
    }
}
