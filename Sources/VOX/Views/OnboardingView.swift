import SwiftUI

/// First-run onboarding wizard.
/// VOX is a Hex companion — 3 simple steps: Hex, TTS, Test.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var currentStep = 0
    @State private var hexDetected = false
    @State private var ttsTestPassed = false
    @State private var selectedTTS: TTSEngineType = .macosSay
    @State private var selectedSummarization: SummarizationMethod = .heuristic
    @State private var ollamaChecked = false
    // Voice test state
    @State private var isTestListening = false
    @State private var testTranscription: String?
    @State private var voiceTestPassed = false

    private let totalSteps = 3

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("VOX")
                    .font(.custom("Titillium Web", size: 36).bold())
                Text("Talk to your terminal. Hear what matters.")
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
                    case 0: hexStep
                    case 1: ttsStep
                    case 2: voiceTestStep
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
                        appState.settings.summarizationMethod = selectedSummarization
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentBlue)
                }
            }
            .padding(.bottom, 12)
        }
        .padding(24)
        .frame(width: 420, height: 480)
    }

    // MARK: - Step 1: Hex

    private var hexStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 1/\(totalSteps): Install Hex")
                .font(.headline)

            Text("VOX uses **Hex** for on-device speech recognition.\nHex dictates into Terminal, VOX reads the response back.\nNo data leaves your Mac.")
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

    // MARK: - Step 2: TTS Engine

    private var ttsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "speaker.wave.2.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentBlue)

            Text("Step 2/\(totalSteps): Choose TTS Engine")
                .font(.headline)

            Text("VOX reads terminal output back to you.\nChoose how it should sound.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)

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

            Divider()
                .padding(.vertical, 4)

            // Summary engine choice
            Text("How should VOX summarize?")
                .font(.callout.bold())

            VStack(alignment: .leading, spacing: 8) {
                TTSOptionRow(
                    title: "Heuristic (basic)",
                    subtitle: "Pattern matching — no setup needed, limited accuracy",
                    isSelected: selectedSummarization == .heuristic,
                    action: { selectedSummarization = .heuristic }
                )
                TTSOptionRow(
                    title: "Ollama (smart, local AI)",
                    subtitle: "LLM summarization — free, private, needs Ollama installed",
                    isSelected: selectedSummarization == .ollama,
                    action: {
                        selectedSummarization = .ollama
                        if !ollamaChecked {
                            Task { await appState.ollamaService.checkServer() }
                            ollamaChecked = true
                        }
                    }
                )
            }

            if selectedSummarization == .ollama {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.ollamaService.isServerRunning ? Color.statusGreen : Color.statusRed)
                            .frame(width: 6, height: 6)
                        Text(appState.ollamaService.isServerRunning ? "Ollama running" : "Ollama not running")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !OllamaService.isOllamaInstalled() {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Link("Download Ollama", destination: OllamaService.downloadURL)
                                .font(.caption)
                        }
                    }

                    Text("You can configure Ollama in Settings → Advanced later.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Step 3: Voice Test

    private var voiceTestStep: some View {
        VStack(spacing: 16) {
            Image(systemName: voiceTestPassed ? "checkmark.circle.fill" : "ear.badge.waveform")
                .font(.system(size: 48))
                .foregroundColor(voiceTestPassed ? .statusGreen : .accentBlue)

            Text("Step 3/\(totalSteps): Test Your Setup")
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
                        // Re-check and start monitoring after launch
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            appState.hexBridge.checkHexStatus()
                            if appState.hexBridge.isHexRunning && !isTestListening && !voiceTestPassed {
                                startTestListening()
                            }
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !voiceTestPassed {
                VStack(spacing: 12) {
                    if isTestListening {
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Listening for Hex transcription...")
                                .font(.caption)
                                .foregroundColor(.accentBlue)
                            Text("Try it now — dictate something with Hex!")
                                .font(.caption.bold())

                            Text("Open Terminal.app and use Hex to speak a command.\nVOX will detect it and read the response back.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        // Hex not running — show instructions
                        VStack(spacing: 8) {
                            Text("Start **Hex** to test the voice flow.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Text("VOX will automatically start listening once Hex is running.")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
        }
        .onAppear {
            appState.hexBridge.checkHexStatus()
            if !appState.hexBridge.isHexRunning {
                appState.hexBridge.launchHex()
            }
            // Auto-start monitoring when step 3 appears
            if !voiceTestPassed {
                // Small delay to let Hex launch if needed
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    appState.hexBridge.checkHexStatus()
                    if !isTestListening && !voiceTestPassed {
                        startTestListening()
                    }
                }
            }
        }
        .onDisappear {
            // Stop monitoring when navigating away from step 3
            if isTestListening {
                appState.hexBridge.stopMonitoring()
                isTestListening = false
            }
        }
    }

    // MARK: - Voice Test Helpers

    private func startTestListening() {
        isTestListening = true
        testTranscription = nil
        appState.hexBridge.checkHexStatus()
        appState.hexBridge.startMonitoring { entry in
            Task { @MainActor in
                testTranscription = entry.text
                isTestListening = false
                voiceTestPassed = true
                appState.hexBridge.stopMonitoring()
                appState.ttsEngine.speak("I heard: \(entry.text)")
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
