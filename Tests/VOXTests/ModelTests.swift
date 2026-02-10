import XCTest
@testable import VOX

final class VerbosityLevelTests: XCTestCase {

    func testAllLevels() {
        XCTAssertEqual(VerbosityLevel.allCases.count, 4)
    }

    func testLabels() {
        XCTAssertEqual(VerbosityLevel.silent.label, "Silent")
        XCTAssertEqual(VerbosityLevel.ping.label, "Ping")
        XCTAssertEqual(VerbosityLevel.summary.label, "Summary")
        XCTAssertEqual(VerbosityLevel.full.label, "Full")
    }

    func testDots() {
        XCTAssertEqual(VerbosityLevel.silent.dots.count, 4) // "○○○○"
        XCTAssertEqual(VerbosityLevel.full.dots.count, 4) // "●●●●"
    }

    func testNextCycles() {
        XCTAssertEqual(VerbosityLevel.silent.next(), .ping)
        XCTAssertEqual(VerbosityLevel.ping.next(), .summary)
        XCTAssertEqual(VerbosityLevel.summary.next(), .full)
        XCTAssertEqual(VerbosityLevel.full.next(), .silent) // wraps around
    }

    func testComparable() {
        XCTAssertTrue(VerbosityLevel.silent < .ping)
        XCTAssertTrue(VerbosityLevel.ping < .summary)
        XCTAssertTrue(VerbosityLevel.summary < .full)
        XCTAssertFalse(VerbosityLevel.full < .silent)
    }

    func testCodable() throws {
        let original = VerbosityLevel.summary
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VerbosityLevel.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class TargetAppTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(TargetApp.allCases.count, 6)
    }

    func testBundleIdentifiers() {
        XCTAssertEqual(TargetApp.terminal.bundleIdentifier, "com.apple.Terminal")
        XCTAssertFalse(TargetApp.claudeCode.bundleIdentifier.isEmpty)
    }

    func testTerminalBased() {
        XCTAssertTrue(TargetApp.terminal.isTerminalBased)
        XCTAssertTrue(TargetApp.iterm2.isTerminalBased)
        XCTAssertFalse(TargetApp.vsCode.isTerminalBased)
    }

    func testVoicePrefixes() {
        XCTAssertTrue(TargetApp.terminal.voicePrefixes.contains("terminal"))
        XCTAssertTrue(TargetApp.claudeCode.voicePrefixes.contains("claude"))
    }

    func testMoSCoWTiers() {
        XCTAssertEqual(TargetApp.terminal.tier, .must)
        XCTAssertEqual(TargetApp.claudeCode.tier, .must)
        XCTAssertEqual(TargetApp.vsCode.tier, .should)
        XCTAssertEqual(TargetApp.cursor.tier, .should)
    }

    func testCodable() throws {
        let original = TargetApp.vsCode
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TargetApp.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class VoxCommandTests: XCTestCase {

    func testInitialization() {
        let cmd = VoxCommand(
            transcription: "git status",
            resolvedCommand: "git status",
            target: .terminal
        )
        XCTAssertEqual(cmd.status, .pending)
        XCTAssertEqual(cmd.transcription, "git status")
        XCTAssertEqual(cmd.resolvedCommand, "git status")
        XCTAssertEqual(cmd.target, .terminal)
        XCTAssertNil(cmd.output)
        XCTAssertNil(cmd.summary)
        XCTAssertNil(cmd.exitCode)
    }

    func testStatusIcons() {
        var cmd = VoxCommand(transcription: "test", resolvedCommand: "test", target: .terminal)
        XCTAssertEqual(cmd.statusIcon, "⏳") // pending

        cmd.status = .running
        XCTAssertEqual(cmd.statusIcon, "🔵")

        cmd.status = .success
        XCTAssertEqual(cmd.statusIcon, "🟢")

        cmd.status = .error
        XCTAssertEqual(cmd.statusIcon, "🔴")

        cmd.status = .timeout
        XCTAssertEqual(cmd.statusIcon, "🟡")
    }

    func testFormattedTime() {
        let cmd = VoxCommand(transcription: "test", resolvedCommand: "test", target: .terminal)
        // Should be HH:mm format
        XCTAssertEqual(cmd.formattedTime.count, 5)
        XCTAssertTrue(cmd.formattedTime.contains(":"))
    }

    func testCodable() throws {
        var cmd = VoxCommand(transcription: "git status", resolvedCommand: "git status", target: .terminal)
        cmd.status = .success
        cmd.output = "On branch main"
        cmd.summary = "On main, clean."
        cmd.exitCode = 0
        cmd.duration = 0.5

        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(VoxCommand.self, from: data)

        XCTAssertEqual(decoded.transcription, cmd.transcription)
        XCTAssertEqual(decoded.resolvedCommand, cmd.resolvedCommand)
        XCTAssertEqual(decoded.target, cmd.target)
        XCTAssertEqual(decoded.status, cmd.status)
        XCTAssertEqual(decoded.output, cmd.output)
        XCTAssertEqual(decoded.summary, cmd.summary)
        XCTAssertEqual(decoded.exitCode, cmd.exitCode)
    }

    func testIsSuccessAndIsError() {
        var cmd = VoxCommand(transcription: "test", resolvedCommand: "test", target: .terminal)
        cmd.status = .success
        XCTAssertTrue(cmd.isSuccess)
        XCTAssertFalse(cmd.isError)

        cmd.status = .error
        XCTAssertFalse(cmd.isSuccess)
        XCTAssertTrue(cmd.isError)
    }
}
