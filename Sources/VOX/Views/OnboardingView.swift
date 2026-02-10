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
    @State private var selectedHotkey: PushToTalkHotkey = .controlSpace
    // Voice test state
    @State private var isTestListening = false
    @State private var testTranscription: String?
    @State private var voiceTestPassed = false
    // Accessibility polling timer
    @State private var accessibilityTimer: Timer?

    private let totalSteps = 6

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("VOX")
                    .font(.custom("Titillium Web", size: 36).bold())
                Text("Voice-Operated eXecution")
                    .font(.custom("Inter", size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)

            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentBlue : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Divider()

            // Step content
            ScrollView {
                Group {
                    switch currentStep {
                    case 0: accessibilityStep
                    case 1: microphoneStep
                    case 2: hexStep
                    case 3: hotkeyStep
                    case 4: ttsStep
                    case 5: voiceTestStep
                    default: EmptyView()
                    }
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
                        appState.settings.pushToTalkHotkey = selectedHotkey
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentBlue)
                }
            }
            .padding(.bottom, 12)
        }
        .padding(24)
        .frame(width: 420, height: 560)
        .onAppear {
            checkAccessibility()
            checkMicAccess()
            selectedHotkey = appState.settings.pushToTalkHotkey
        }
    }

    // MARK: - Step 1: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 1/\(totalSteps): Accessibility Access")
                .font(.headline)

            Text("VOX needs Accessibility access to capture global hotkeys for push-to-talk.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)

            if accessibilityGranted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
            } else {
                VStack(spacing: 10) {
                    Button("Request Accessibility Access") {
                        requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentBlue)

                    Button("Open System Settings") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)

                    Text("After enabling in System Settings, VOX will detect it automatically.\nNote: After each rebuild, you may need to re-grant access.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .onAppear { startAccessibilityPolling() }
        .onDisappear { stopAccessibilityPolling() }
    }

    // MARK: - Step 2: Microphone

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
                .font(.callout)

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

    // MARK: - Step 3: Hex

    private var hexStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 3/\(totalSteps): Install Hex")
                .font(.headline)

            Text("VOX uses **Hex** for on-device speech recognition.\nNo data leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)

            HStack(spacing: 12) {
                Button("Download Hex") {
                    NSWorkspace.shared.open(URL(string: "https://hex.kitlangton.com")!)
                }
                .buttonStyle(.bordered)

                Button("Check Status") {
                    appState.hexBridge.checkHexStatus()
                    hexDetected = appState.hexBridge.isHexRunning
                }
                .buttonStyle(.bordered)
            }

            if hexDetected {
                Label("Hex detected and running!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
            } else {
                Text("Start Hex before continuing. You can also skip and install later.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Step 4: Hotkey Selection

    private var hotkeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 4/\(totalSteps): Choose Push-to-Talk Hotkey")
                .font(.headline)

            Text("Hold this key combo to talk to VOX.\nRelease to execute the command.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(PushToTalkHotkey.allCases, id: \.self) { hotkey in
                    TTSOptionRow(
                        title: hotkey.displayName,
                        subtitle: hotkeyDescription(hotkey),
                        isSelected: selectedHotkey == hotkey,
                        action: { selectedHotkey = hotkey }
                    )
                }
            }

            Text("You can change this later in Settings.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func hotkeyDescription(_ hotkey: PushToTalkHotkey) -> String {
        switch hotkey {
        case .controlSpace: return "Recommended — doesn't conflict with Spotlight or IME"
        case .optionSpace: return "Classic — may type special characters in some apps"
        case .commandShiftV: return "Safe — unlikely to conflict with other shortcuts"
        case .fnSpace: return "Minimal — uses the Fn/Globe key"
        }
    }

    // MARK: - Step 5: TTS Engine

    private var ttsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "speaker.wave.2.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 5/\(totalSteps): Choose TTS Engine")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TTSOptionRow(
                    title: "macOS Say (built-in)",
                    subtitle: "Basic quality, instant, no setup",
                    isSelected: selectedTTS == .macosSay,
                    action: { selectedTTS = .macosSay }
                )
                TTSOptionRow(
                    title: "Kokoro (coming soon)",
                    subtitle: "High quality, local, free — 82M params",
                    isSelected: selectedTTS == .kokoro,
                    isDisabled: true,
                    action: {}
                )
                TTSOptionRow(
                    title: "ElevenLabs (coming soon)",
                    subtitle: "Premium quality, cloud, requires API key",
                    isSelected: selectedTTS == .elevenLabs,
                    isDisabled: true,
                    action: {}
                )
            }

            Button("Test Voice") {
                appState.ttsEngine.speak("This is how VOX will talk to you.")
                ttsTestPassed = true
            }
            .buttonStyle(.bordered)

            if ttsTestPassed {
                Label("TTS working!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
            }
        }
    }

    // MARK: - Step 6: Voice Test

    private var voiceTestStep: some View {
        VStack(spacing: 16) {
            Image(systemName: voiceTestPassed ? "checkmark.circle.fill" : "ear.badge.waveform")
                .font(.system(size: 48))
                .foregroundColor(voiceTestPassed ? .statusGreen : .accentBlue)

            Text("Step 6/\(totalSteps): Test Your Voice")
                .font(.headline)

            // Hex status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.hexBridge.isHexRunning ? Color.statusGreen : Color.statusOrange)
                    .frame(width: 8, height: 8)
                Text(appState.hexBridge.isHexRunning ? "Hex is running" : "Hex is not running")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !appState.hexBridge.isHexRunning {
                    Button("Launch Hex") {
                        appState.hexBridge.launchHex()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !voiceTestPassed {
                VStack(spacing: 12) {
                    Text("**How VOX works:**")
                        .font(.callout)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.").font(.caption.bold()).foregroundColor(.accentBlue)
                            Text("Use **Hex** to dictate a command (Hex's own hotkey)")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.").font(.caption.bold()).foregroundColor(.accentBlue)
                            Text("VOX detects the transcription automatically")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("3.").font(.caption.bold()).foregroundColor(.accentBlue)
                            Text("VOX executes the command and speaks the result")
                                .font(.caption)
                        }
                    }

                    if isTestListening {
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for Hex transcription...")
                                .font(.caption)
                                .foregroundColor(.accentBlue)
                            Text("Dictate something with Hex now!")
                                .font(.caption.bold())
                        }
                    } else {
                        Button("Start Test") {
                            startTestListening()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentBlue)
                        .disabled(!appState.hexBridge.isHexRunning)

                        if !appState.hexBridge.isHexRunning {
                            Text("Launch Hex first to test voice input.")
                                .font(.caption2)
                                .foregroundColor(.statusOrange)
                        }
                    }
                }
            }

            // Transcription result
            if let transcription = testTranscription {
                VStack(spacing: 8) {
                    HStack {
                        Text("VOX heard:")
                            .font(.caption.bold())
                        Spacer()
                    }
                    Text("\"\(transcription)\"")
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentBlue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if voiceTestPassed {
                Label("VOX is ready!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusGreen)
                    .font(.headline)
            }

            // How it works summary
            VStack(alignment: .leading, spacing: 4) {
                Text("Your setup:")
                    .font(.caption.bold())
                HStack(spacing: 4) {
                    Text("Hex")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.accentBlue)
                    Text("Dictate → VOX auto-processes")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Text(selectedHotkey.shortLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.accentBlue)
                    Text("Push-to-talk (optional, needs Accessibility)")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Text("⌥V")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.accentBlue)
                    Text("Cycle verbosity")
                        .font(.caption)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .onAppear {
            appState.hexBridge.checkHexStatus()
            // Auto-launch Hex if not running
            if !appState.hexBridge.isHexRunning {
                appState.hexBridge.launchHex()
            }
        }
    }

    // MARK: - Voice Test Helpers

    private func startTestListening() {
        isTestListening = true
        testTranscription = nil
        // Start monitoring clipboard for Hex output
        appState.hexBridge.checkHexStatus()
        appState.hexBridge.startMonitoring { transcription in
            Task { @MainActor in
                testTranscription = transcription
                isTestListening = false
                voiceTestPassed = true
                appState.hexBridge.stopMonitoring()
                appState.ttsEngine.speak("I heard: \(transcription)")
            }
        }
    }

    // MARK: - Helpers

    private func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func requestAccessibility() {
        // This triggers the system prompt to grant accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityGranted = trusted
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Poll accessibility status every 2 seconds while on step 0.
    private func startAccessibilityPolling() {
        stopAccessibilityPolling()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                accessibilityGranted = AXIsProcessTrusted()
            }
        }
    }

    private func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
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
