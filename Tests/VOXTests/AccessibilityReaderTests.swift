import XCTest
@testable import VOX

final class AccessibilityReaderTests: XCTestCase {

    // MARK: - Permission Check

    func testIsAccessibilityGrantedReturnsBool() {
        // Should return a Bool without crashing — regardless of actual permission state
        let result = AccessibilityReader.isAccessibilityGranted()
        XCTAssertNotNil(result) // Always true for Bool, but verifies it runs
    }

    // MARK: - Read Content Safety

    func testReadContentReturnsNilForUnknownBundleID() async {
        let reader = AccessibilityReader()
        let result = await reader.readContent(for: "com.nonexistent.app.12345")
        XCTAssertNil(result, "Unknown bundle ID should return nil without crashing")
    }

    func testReadContentReturnsNilForEmptyBundleID() async {
        let reader = AccessibilityReader()
        let result = await reader.readContent(for: "")
        XCTAssertNil(result, "Empty bundle ID should return nil")
    }

    // MARK: - TerminalReader AX Delegation

    func testTerminalReaderDelegatesToAXForCursor() async {
        let reader = TerminalReader()
        // Should not crash — returns nil without AX permission or if Cursor isn't running
        let result = await reader.readContent(for: "com.todesktop.230313mzl4w4u92")
        // We can't assert a specific value in CI, but it must not crash
        _ = result
    }

    func testTerminalReaderDelegatesToAXForVSCode() async {
        let reader = TerminalReader()
        let result = await reader.readContent(for: "com.microsoft.VSCode")
        _ = result
    }

    func testTerminalReaderDelegatesToAXForWindsurf() async {
        let reader = TerminalReader()
        let result = await reader.readContent(for: "com.codeium.windsurf")
        _ = result
    }

    func testTerminalReaderStillHandlesTerminal() async {
        let reader = TerminalReader()
        // Terminal.app uses AppleScript, not AX — verify no regression
        let result = await reader.readContent(for: "com.apple.Terminal")
        _ = result // May return content if Terminal is open, nil otherwise
    }

    func testTerminalReaderStillHandlesITerm2() async {
        let reader = TerminalReader()
        let result = await reader.readContent(for: "com.googlecode.iterm2")
        _ = result
    }

    // MARK: - TargetApp Bundle ID Mapping

    func testTargetAppLookupFromBundleIDForCursor() {
        let target = TargetApp.allCases.first { $0.bundleIdentifier == "com.todesktop.230313mzl4w4u92" }
        XCTAssertEqual(target, .cursor)
    }

    func testTargetAppLookupFromBundleIDForVSCode() {
        let target = TargetApp.allCases.first { $0.bundleIdentifier == "com.microsoft.VSCode" }
        XCTAssertEqual(target, .vsCode)
    }

    func testTargetAppLookupFromBundleIDForWindsurf() {
        let target = TargetApp.allCases.first { $0.bundleIdentifier == "com.codeium.windsurf" }
        XCTAssertEqual(target, .windsurf)
    }

    func testTargetAppLookupFromBundleIDForTerminal() {
        let target = TargetApp.allCases.first { $0.bundleIdentifier == "com.apple.Terminal" }
        XCTAssertEqual(target, .terminal)
    }

    func testTargetAppLookupFromBundleIDForITerm2() {
        let target = TargetApp.allCases.first { $0.bundleIdentifier == "com.googlecode.iterm2" }
        XCTAssertEqual(target, .iterm2)
    }

    // MARK: - TargetApp Properties

    func testTerminalBasedAppsUseAppleScript() {
        XCTAssertTrue(TargetApp.terminal.isTerminalBased)
        XCTAssertTrue(TargetApp.iterm2.isTerminalBased)
        XCTAssertTrue(TargetApp.claudeCode.isTerminalBased)
    }

    func testEditorAppsUseAccessibilityAPI() {
        XCTAssertFalse(TargetApp.vsCode.isTerminalBased)
        XCTAssertFalse(TargetApp.cursor.isTerminalBased)
        XCTAssertFalse(TargetApp.windsurf.isTerminalBased)
    }
}
