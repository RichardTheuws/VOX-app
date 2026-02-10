import SwiftUI

/// Confirmation dialog for destructive commands.
struct DestructiveConfirmView: View {
    let command: String
    let reason: String
    let target: TargetApp
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var countdown = 10
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.statusOrange)

            Text("DESTRUCTIVE COMMAND DETECTED")
                .font(.custom("Titillium Web", size: 16).bold())
                .foregroundColor(.statusOrange)

            // Command details
            VStack(spacing: 8) {
                HStack {
                    Text("Command:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                HStack {
                    Text("Reason:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(reason)
                        .font(.caption)
                }

                HStack {
                    Text("Target:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(target.rawValue)
                        .font(.caption)
                }
            }

            Text("Say \"confirm\" or \"cancel\" to proceed.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    stopTimer()
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)

                Button("Confirm & Run") {
                    stopTimer()
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.statusOrange)
            }

            // Auto-cancel countdown
            Text("Auto-cancel in: \(countdown)s")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.statusOrange.opacity(0.5), lineWidth: 1)
        )
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                countdown -= 1
                if countdown <= 0 {
                    stopTimer()
                    onCancel()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
