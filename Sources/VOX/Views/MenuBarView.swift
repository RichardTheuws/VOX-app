import SwiftUI

/// The menu bar dropdown content shown when clicking the VOX icon.
struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.accentBlue)
                Text("VOX")
                    .font(.custom("Titillium Web", size: 16).bold())
                Spacer()
                Text("v\(VOXVersion.current)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Status
            VStack(alignment: .leading, spacing: 4) {
                statusRow(label: "Status", value: appState.statusText, color: appState.statusColor)
                statusRow(label: "Target", value: appState.currentTarget.rawValue)
                statusRow(
                    label: "Hex",
                    value: appState.hexBridge.isHexRunning ? "Running" : "Not detected",
                    color: appState.hexBridge.isHexRunning ? .statusGreen : .statusOrange
                )
                HStack {
                    Text("Verbosity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(appState.currentVerbosity.dots)
                        .font(.caption)
                    Text(appState.currentVerbosity.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Last command
            if let lastCommand = appState.history.commands.first {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(lastCommand.statusIcon)
                            .font(.caption)
                        Text("Last: \"\(lastCommand.transcription)\"")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    if let summary = lastCommand.summary {
                        Text("  \(summary)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()
            }

            // Mode info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Circle()
                        .fill(appState.hexBridge.isHexRunning ? Color.statusGreen : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(appState.hexBridge.isHexRunning ? "Monitoring Hex — dictate to execute" : "Start Hex to use voice commands")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if appState.hotkeyManager.isHotkeyActive {
                    shortcutRow(keys: appState.settings.pushToTalkHotkey.shortLabel, action: "Push-to-talk")
                } else {
                    HStack {
                        Text(appState.settings.pushToTalkHotkey.shortLabel)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Push-to-talk (needs Accessibility)")
                            .font(.caption)
                            .foregroundColor(.statusOrange)
                    }
                }
                shortcutRow(keys: "⌥V", action: "Cycle verbosity")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Actions
            Button(action: appState.openSettings) {
                Label("Settings...", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button(action: appState.openHistory) {
                Label("History", systemImage: "clock")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button(action: {
                appState.settings.hasCompletedOnboarding = false
                appState.showOnboarding()
            }) {
                Label("Setup Wizard...", systemImage: "wand.and.stars")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit VOX", systemImage: "power")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(width: 260)
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private func statusRow(label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(color)
        }
    }

    private func shortcutRow(keys: String, action: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.accentBlue)
            Text(action)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Brand Colors

extension Color {
    static let accentBlue = Color(red: 0, green: 0.384, blue: 0.608) // #00629B
    static let voidBlack = Color(red: 0.067, green: 0.067, blue: 0.067) // #111111
    static let surfaceDark = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
    static let statusGreen = Color(red: 0.157, green: 0.780, blue: 0.435) // #28C76F
    static let statusOrange = Color(red: 1.0, green: 0.624, blue: 0.263) // #FF9F43
    static let statusRed = Color(red: 1.0, green: 0.278, blue: 0.341) // #FF4757
}
