import SwiftUI

/// Main entry point for the VOX application.
/// VOX is a menu bar app — it has no main window, only a menu bar icon with dropdown.
/// Floating windows (onboarding, push-to-talk, destructive confirm) are managed by AppState.
@main
struct VOXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Menu bar always shows the dropdown view
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 260, height: 300)
    }
}

// MARK: - App Delegate

/// Handles app lifecycle and ensures menu bar-only behavior.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar app only
        NSApp.setActivationPolicy(.accessory)
    }
}
