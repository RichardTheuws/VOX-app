import SwiftUI

/// Floating HUD overlay shown during push-to-talk.
struct PushToTalkOverlay: View {
    @ObservedObject var appState: AppState
    @State private var waveAmplitudes: [CGFloat] = Array(repeating: 0.3, count: 5)
    @State private var animationTimer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            // Waveform visualizer
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentBlue)
                        .frame(width: 6, height: 20 * waveAmplitudes[index])
                }
            }
            .frame(height: 40)

            // Live transcription
            if let transcription = appState.liveTranscription, !transcription.isEmpty {
                Text("\"\(transcription)\"")
                    .font(.custom("Inter", size: 16))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 20)
            } else {
                Text("Listening...")
                    .font(.custom("Inter", size: 14))
                    .foregroundColor(.secondary)
            }

            // Target info
            HStack(spacing: 4) {
                Text("Target:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(appState.currentTarget.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(.accentBlue)
            }

            // Shortcut hint
            Text("⌥Space to stop")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentBlue.opacity(0.3), lineWidth: 1)
        )
        .onAppear { startWaveAnimation() }
        .onDisappear { stopWaveAnimation() }
    }

    // MARK: - Wave Animation

    private func startWaveAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                for i in 0..<waveAmplitudes.count {
                    waveAmplitudes[i] = CGFloat.random(in: 0.2...1.0)
                }
            }
        }
    }

    private func stopWaveAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
