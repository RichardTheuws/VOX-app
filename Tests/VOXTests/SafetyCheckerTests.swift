import XCTest
@testable import VOX

final class SafetyCheckerTests: XCTestCase {
    private var checker: SafetyChecker!

    override func setUp() {
        super.setUp()
        checker = SafetyChecker()
    }

    // MARK: - Safe Commands

    func testSafeCommandGitStatus() {
        let result = checker.check("git status")
        XCTAssertFalse(result.isDestructive)
    }

    func testSafeCommandLs() {
        let result = checker.check("ls -la")
        XCTAssertFalse(result.isDestructive)
    }

    func testSafeCommandEcho() {
        let result = checker.check("echo hello world")
        XCTAssertFalse(result.isDestructive)
    }

    func testSafeCommandNpmInstall() {
        let result = checker.check("npm install express")
        XCTAssertFalse(result.isDestructive)
    }

    func testSafeCommandGitPush() {
        let result = checker.check("git push origin main")
        XCTAssertFalse(result.isDestructive)
    }

    // MARK: - Destructive Commands

    func testDestructiveRmRf() {
        let result = checker.check("rm -rf node_modules/")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveRmR() {
        let result = checker.check("rm -r old_directory")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveDropTable() {
        let result = checker.check("psql -c 'DROP TABLE users'")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveGitForcePush() {
        let result = checker.check("git push --force origin main")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveGitForcePushShort() {
        let result = checker.check("git push -f origin main")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveGitResetHard() {
        let result = checker.check("git reset --hard HEAD~3")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveSudo() {
        let result = checker.check("sudo rm /etc/hosts")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveDockerRm() {
        let result = checker.check("docker rm my-container")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveShutdown() {
        let result = checker.check("shutdown -h now")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveChmod777() {
        let result = checker.check("chmod 777 /var/www")
        XCTAssertTrue(result.isDestructive)
    }

    func testDestructiveTruncate() {
        let result = checker.check("TRUNCATE TABLE sessions")
        XCTAssertTrue(result.isDestructive)
    }

    // MARK: - Case Insensitive

    func testDestructiveCaseInsensitive() {
        let result = checker.check("DROP DATABASE production")
        XCTAssertTrue(result.isDestructive)
    }

    // MARK: - Destructive Details

    func testDestructiveReturnsDetails() {
        let result = checker.check("rm -rf /")
        if case .destructive(let cmd, let reason, let pattern) = result {
            XCTAssertEqual(cmd, "rm -rf /")
            XCTAssertEqual(pattern, "rm -rf")
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected destructive result")
        }
    }

    // MARK: - Secret Detection

    func testContainsSecretsPassword() {
        XCTAssertTrue(checker.containsSecrets("export PASSWORD=abc123"))
    }

    func testContainsSecretsToken() {
        XCTAssertTrue(checker.containsSecrets("curl -H 'Authorization: Bearer token_xyz'"))
    }

    func testContainsSecretsApiKey() {
        XCTAssertTrue(checker.containsSecrets("export API_KEY=sk-1234"))
    }

    func testNoSecrets() {
        XCTAssertFalse(checker.containsSecrets("git status"))
    }

    // MARK: - Secret Masking

    func testMaskPasswordEquals() {
        let masked = checker.maskSecrets(in: "password=my_secret_value")
        XCTAssertFalse(masked.contains("my_secret_value"))
    }

    func testMaskTokenFlag() {
        let masked = checker.maskSecrets(in: "curl --token abc123 https://api.com")
        XCTAssertFalse(masked.contains("abc123"))
    }

    // MARK: - Default Patterns Count

    func testDefaultPatternsCount() {
        // Ensure we have a reasonable number of patterns
        XCTAssertGreaterThanOrEqual(SafetyChecker.defaultPatterns.count, 20)
    }
}
