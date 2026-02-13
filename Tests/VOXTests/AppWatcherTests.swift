import XCTest
@testable import VOX

final class AppWatcherTests: XCTestCase {

    func testStartStop() {
        // AppWatcher should start and stop without crashing
        let reader = TerminalReader()
        let watcher = AppWatcher(
            terminalReader: reader,
            monitorableBundleIDs: ["com.apple.Terminal"]
        )
        watcher.start()
        // Note: currentBundleID may be non-nil if Terminal is frontmost (e.g. during test runs)
        watcher.stop()
        // After stop, currentBundleID should be nil
        XCTAssertNil(watcher.currentBundleID)
    }

    func testUpdateBaseline() {
        let reader = TerminalReader()
        let watcher = AppWatcher(
            terminalReader: reader,
            monitorableBundleIDs: ["com.apple.Terminal"]
        )

        // Update baseline should not crash
        watcher.updateBaseline(for: "com.apple.Terminal", content: "some content")
        // Updating again should overwrite
        watcher.updateBaseline(for: "com.apple.Terminal", content: "new content")
    }

    func testMonitorableBundleIDsFilter() {
        let reader = TerminalReader()
        let watcher = AppWatcher(
            terminalReader: reader,
            monitorableBundleIDs: ["com.apple.Terminal", "com.microsoft.VSCode"]
        )

        // Initially no bundle ID is set
        XCTAssertNil(watcher.currentBundleID)

        // Start and stop cleanly
        watcher.start()
        watcher.stop()
        XCTAssertNil(watcher.currentBundleID)
    }

    func testMonitorKeyboardInputDefaultFalse() {
        // The monitorKeyboardInput setting should default to false
        let settings = VoxSettings.shared
        // Clear to ensure we test the default
        UserDefaults.standard.removeObject(forKey: "monitorKeyboardInput")
        XCTAssertFalse(settings.monitorKeyboardInput)
    }
}
