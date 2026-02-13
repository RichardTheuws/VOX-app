import SwiftUI
import Combine

/// Central application state that coordinates all VOX services.
/// VOX is a Hex companion — it monitors terminal output and reads it back via TTS.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var appMode: AppMode = .idle
    @Published var liveTranscription: String?
    @Published var currentTarget: TargetApp = .terminal
    @Published var currentVerbosity: VerbosityLevel = .summary

    // MARK: - Services

    let settings: VoxSettings
    let hexBridge: HexBridge
    let ttsEngine: TTSEngine
    let history: CommandHistory
    let ollamaService: OllamaService
    let soundPackManager: SoundPackManager
    let soundPackStore: SoundPackStore

    private let terminalReader: TerminalReader
    private let responseProcessor: ResponseProcessor

    // MARK: - Windows

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    // MARK: - Init

    init() {
        self.settings = .shared
        self.hexBridge = HexBridge()
        self.ttsEngine = TTSEngine()
        self.history = CommandHistory()
        self.terminalReader = TerminalReader()
        self.ollamaService = OllamaService()
        self.soundPackManager = SoundPackManager()
        self.soundPackStore = SoundPackStore()
        self.responseProcessor = ResponseProcessor(ollamaService: ollamaService, soundPackManager: soundPackManager)

        // Scan for user-provided custom sound packs
        soundPackManager.scanForPacks()

        self.currentVerbosity = settings.defaultVerbosity
        self.currentTarget = settings.defaultTarget

        // Auto-start if onboarding already completed
        if settings.hasCompletedOnboarding {
            start()
        } else {
            Task { @MainActor in
                showOnboarding()
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        // Start Hex bridge monitoring — receives full entry with source app info
        hexBridge.startMonitoring { [weak self] entry in
            Task { @MainActor in
                self?.handleTranscription(entry)
            }
        }

        // Periodically check Hex status
        hexBridge.checkHexStatus()
    }

    func stop() {
        hexBridge.stopMonitoring()
        ttsEngine.stop()
    }

    // MARK: - Transcription Handling

    /// Bundle IDs of apps whose output VOX should monitor (not execute).
    /// Terminal.app/iTerm2 use AppleScript; Cursor/VS Code/Windsurf use Accessibility API.
    private static let monitorableBundleIDs: Set<String> = [
        "com.apple.Terminal",                  // Terminal.app (incl. Claude Code)
        "com.googlecode.iterm2",               // iTerm2
        "com.microsoft.VSCode",                // VS Code
        "com.todesktop.230313mzl4w4u92",       // Cursor
        "com.codeium.windsurf",                // Windsurf
    ]

    private func handleTranscription(_ entry: HexHistoryEntry) {
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        liveTranscription = text

        guard appMode == .idle else { return } // Busy — ignore

        let sourceApp = entry.sourceAppBundleID ?? ""

        // Route based on which app Hex dictated into
        if Self.monitorableBundleIDs.contains(sourceApp) {
            // Hex pasted text into a monitored app → read app output
            monitorTerminalResponse(transcription: text, bundleID: sourceApp)
        }
        // Other apps (WhatsApp, Notes, etc.) → ignore
    }

    /// Cancel whatever is currently happening (e.g. stop TTS).
    func cancelCurrentAction() {
        switch appMode {
        case .monitoring:
            ttsEngine.stop()
            appMode = .idle
        case .idle:
            break
        }
    }

    // MARK: - Monitor Mode

    /// Monitor app output after Hex dictated a command into a monitored app.
    /// Reads the app's response (via AppleScript or Accessibility API) and speaks it.
    private func monitorTerminalResponse(transcription: String, bundleID: String) {
        appMode = .monitoring

        let target = TargetApp.allCases.first { $0.bundleIdentifier == bundleID } ?? .terminal

        // Create history entry
        var command = VoxCommand(
            transcription: transcription,
            resolvedCommand: "(monitoring \(target.rawValue))",
            target: target
        )
        command.status = .running
        history.add(command)

        Task {
            // 1. Take a snapshot of current terminal content immediately
            let snapshot = await terminalReader.readContent(for: bundleID) ?? ""

            // 2. Wait for new output to appear and stabilize
            //    Uses adaptive two-phase stabilization:
            //    - Phase 1: 3s of no changes → move to verification
            //    - Phase 2: 15s more of stability → confirmed done
            //    - Shell prompt detection for instant completion
            //    - Exponential backoff reduces polling from ~8000 to ~500 over 40 min
            let newOutput = await terminalReader.waitForNewOutput(
                bundleID: bundleID,
                initialSnapshot: snapshot,
                timeout: settings.commandTimeout,
                initialStabilizeDelay: 3.0,
                confirmationDelay: 15.0,
                usePromptDetection: true
            )

            guard let output = newOutput, !output.isEmpty else {
                command.status = .success
                command.summary = "No new output detected."
                history.update(command)
                if currentVerbosity != .silent {
                    ttsEngine.speak("No new output.")
                }
                appMode = .idle
                return
            }

            // 3. Process the captured output
            command.output = output
            command.status = .success

            let result = ExecutionResult(
                output: output,
                exitCode: 0,
                duration: 0,
                wasTimeout: false
            )

            let verbosity = settings.verbosity(for: target)
            let processed = await responseProcessor.process(result, verbosity: verbosity, command: transcription)

            command.summary = processed.spokenText
            history.update(command)

            // 4. Play the response
            if let text = processed.spokenText {
                ttsEngine.speak(text)
            } else if let soundName = processed.soundName {
                ttsEngine.playSystemSound(soundName)
            } else if let soundURL = processed.customSoundURL {
                ttsEngine.playCustomSound(at: soundURL)
            }

            appMode = .idle
        }
    }

    // MARK: - Computed Properties

    var statusText: String {
        switch appMode {
        case .idle: "Idle"
        case .monitoring: "Monitoring..."
        }
    }

    var statusColor: Color {
        switch appMode {
        case .idle: .secondary
        case .monitoring: .accentBlue
        }
    }

    var menuBarIcon: String {
        switch appMode {
        case .idle: "ear"
        case .monitoring: "eye"
        }
    }

    // MARK: - Onboarding

    func showOnboarding() {
        guard onboardingWindow == nil else {
            onboardingWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Stop services while in onboarding
        stop()

        let onboardingView = OnboardingView(appState: self) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            // Return to accessory (menu bar-only) mode
            NSApp.setActivationPolicy(.accessory)
            self?.start()
        }

        // Temporarily switch to regular app so the window is visible and focusable
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to VOX"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    // MARK: - Window Management

    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settings: settings, appState: self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VOX Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func openHistory() {
        if let window = historyWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView(history: history)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VOX History"
        window.contentView = NSHostingView(rootView: historyView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }
}

// MARK: - Types

enum AppMode {
    case idle
    case monitoring           // Waiting for terminal output after Hex dictation
}
