import SwiftUI
import AVFoundation

/// First-run onboarding wizard.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var currentStep = 0
    @State private var micAccessGranted = false
    @State private var hexDetected = false
    @State private var ttsTestPassed = false
    @State private var selectedTTS: TTSEngineType = .macosSay

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("VOX")
                    .font(.custom("Titillium Web", size: 36).bold())
                Text("Voice-Operated eXecution")
                    .font(.custom("Inter", size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)

            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentBlue : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Divider()

            // Step content
            Group {
                switch currentStep {
                case 0: microphoneStep
                case 1: hexStep
                case 2: ttsStep
                case 3: testStep
                default: EmptyView()
                }
            }
            .frame(maxHeight: .infinity)

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") { currentStep -= 1 }
                }
                Spacer()
                if currentStep < 3 {
                    Button("Next") { currentStep += 1 }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentBlue)
                } else {
                    Button("Start Using VOX") {
                        appState.settings.hasCompletedOnboarding = true
                        appState.settings.ttsEngine = selectedTTS
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentBlue)
                    .disabled(!ttsTestPassed && !micAccessGranted)
                }
            }
            .padding(.bottom, 16)
        }
        .padding(24)
        .frame(width: 400, height: 460)
        .onAppear { checkMicAccess() }
    }

    // MARK: - Steps

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 1/4: Microphone Access")
                .font(.headline)

            Text("VOX needs microphone access to hear your voice commands.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if micAccessGranted {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
            } else {
                Button("Grant Access") {
                    requestMicAccess()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var hexStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 2/4: Install Hex")
                .font(.headline)

            Text("VOX uses Hex for on-device speech recognition. No data leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Download Hex") {
                    NSWorkspace.shared.open(URL(string: "https://hex.kitlangton.com")!)
                }
                .buttonStyle(.bordered)

                Button("I already have Hex") {
                    appState.hexBridge.checkHexStatus()
                    hexDetected = appState.hexBridge.isHexRunning
                    if hexDetected { currentStep += 1 }
                }
                .buttonStyle(.bordered)
            }

            if hexDetected {
                Label("Hex detected", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
            }
        }
    }

    private var ttsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "speaker.wave.2.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 3/4: Choose TTS Engine")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TTSOptionRow(
                    title: "macOS Say (built-in)",
                    subtitle: "Basic quality, instant, no setup",
                    isSelected: selectedTTS == .macosSay,
                    action: { selectedTTS = .macosSay }
                )
                TTSOptionRow(
                    title: "Kokoro (coming in v0.2)",
                    subtitle: "High quality, local, free — 82M params",
                    isSelected: selectedTTS == .kokoro,
                    isDisabled: true,
                    action: {}
                )
                TTSOptionRow(
                    title: "ElevenLabs (coming in v0.2)",
                    subtitle: "Premium quality, cloud, requires API key",
                    isSelected: selectedTTS == .elevenLabs,
                    isDisabled: true,
                    action: {}
                )
            }
        }
    }

    private var testStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(ttsTestPassed ? .statusGreen : .accentBlue)

            Text("Step 4/4: Test Your Setup")
                .font(.headline)

            Text("Press the button and say \"hello\" to test.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Test Now") {
                // Simple test: just play TTS
                appState.ttsEngine.speak("VOX is ready.")
                ttsTestPassed = true
            }
            .buttonStyle(.bordered)

            if ttsTestPassed {
                Label("VOX is ready!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
                    .font(.headline)
            }
        }
    }

    // MARK: - Helpers

    private func checkMicAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micAccessGranted = true
        default:
            micAccessGranted = false
        }
    }

    private func requestMicAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                micAccessGranted = granted
            }
        }
    }
}

// MARK: - TTS Option Row

struct TTSOptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .foregroundColor(isSelected ? .accentBlue : .secondary)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.caption.bold())
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.accentBlue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
