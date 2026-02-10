import SwiftUI
import AVFoundation

/// First-run onboarding wizard.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var currentStep = 0
    @State private var accessibilityGranted = false
    @State private var micAccessGranted = false
    @State private var hexDetected = false
    @State private var ttsTestPassed = false
    @State private var selectedTTS: TTSEngineType = .macosSay

    private let totalSteps = 5

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
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentBlue : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Divider()

            // Step content
            Group {
                switch currentStep {
                case 0: accessibilityStep
                case 1: microphoneStep
                case 2: hexStep
                case 3: ttsStep
                case 4: testStep
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
                if currentStep < totalSteps - 1 {
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
                }
            }
            .padding(.bottom, 16)
        }
        .padding(24)
        .frame(width: 400, height: 520)
        .onAppear {
            checkAccessibility()
            checkMicAccess()
        }
    }

    // MARK: - Steps

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 1/\(totalSteps): Accessibility Access")
                .font(.headline)

            Text("VOX needs Accessibility access to capture global hotkeys (Option+Space for push-to-talk).")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if accessibilityGranted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
            } else {
                VStack(spacing: 8) {
                    Button("Open System Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)

                    Button("Check Again") {
                        checkAccessibility()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Text("Add VOX in Privacy & Security → Accessibility")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 2/\(totalSteps): Microphone Access")
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

            Text("Step 3/\(totalSteps): Install Hex")
                .font(.headline)

            Text("VOX uses Hex for on-device speech recognition.\nNo data leaves your Mac.")
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
                }
                .buttonStyle(.bordered)
            }

            if hexDetected {
                Label("Hex detected and running!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
            } else {
                Text("Start Hex before continuing. You can skip this and install later.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var ttsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "speaker.wave.2.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 4/\(totalSteps): Choose TTS Engine")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TTSOptionRow(
                    title: "macOS Say (built-in)",
                    subtitle: "Basic quality, instant, no setup",
                    isSelected: selectedTTS == .macosSay,
                    action: { selectedTTS = .macosSay }
                )
                TTSOptionRow(
                    title: "Kokoro (coming in v0.3)",
                    subtitle: "High quality, local, free — 82M params",
                    isSelected: selectedTTS == .kokoro,
                    isDisabled: true,
                    action: {}
                )
                TTSOptionRow(
                    title: "ElevenLabs (coming in v0.3)",
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

            Text("Step 5/\(totalSteps): Test Your Setup")
                .font(.headline)

            Text("Press the button to test text-to-speech.\nAfter setup, use Option+Space to talk to VOX.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Test TTS") {
                appState.ttsEngine.speak("VOX is ready. Hold Option Space to talk to me.")
                ttsTestPassed = true
            }
            .buttonStyle(.bordered)

            if ttsTestPassed {
                Label("VOX is ready!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("After setup:")
                    .font(.caption.bold())
                HStack(spacing: 4) {
                    Text("⌥Space")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.accentBlue)
                    Text("Push-to-talk")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Text("⌥V")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.accentBlue)
                    Text("Cycle verbosity")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Text("Escape")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.accentBlue)
                    Text("Cancel")
                        .font(.caption)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Helpers

    private func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        // Re-check after delay
        Task {
            try? await Task.sleep(for: .seconds(3))
            checkAccessibility()
        }
    }

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
