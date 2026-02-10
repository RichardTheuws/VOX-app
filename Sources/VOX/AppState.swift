import SwiftUI
import Combine

/// Central application state that coordinates all VOX services.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var appMode: AppMode = .idle
    @Published var liveTranscription: String?
    @Published var currentTarget: TargetApp = .terminal
    @Published var currentVerbosity: VerbosityLevel = .summary
    @Published var pendingDestructiveCommand: DestructiveCommandInfo?

    // MARK: - Services

    let settings: VoxSettings
    let hexBridge: HexBridge
    let hotkeyManager: HotkeyManager
    let ttsEngine: TTSEngine
    let history: CommandHistory

    private let commandRouter: CommandRouter
    private let terminalExecutor: TerminalExecutor
    private let responseProcessor: ResponseProcessor
    private let safetyChecker: SafetyChecker

    // MARK: - Windows

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var pushToTalkPanel: NSPanel?
    private var destructiveConfirmPanel: NSPanel?

    private var appModeObserver: AnyCancellable?

    // MARK: - Init

    init() {
        self.settings = .shared
        self.hexBridge = HexBridge()
        self.hotkeyManager = HotkeyManager()
        self.ttsEngine = TTSEngine()
        self.history = CommandHistory()
        self.commandRouter = CommandRouter()
        self.terminalExecutor = TerminalExecutor()
        self.responseProcessor = ResponseProcessor()
        self.safetyChecker = SafetyChecker()

        self.currentVerbosity = settings.defaultVerbosity
        self.currentTarget = settings.defaultTarget

        // Observe mode changes to show/hide floating panels
        appModeObserver = $appMode.sink { [weak self] mode in
            Task { @MainActor in
                self?.handleModeChange(mode)
            }
        }

        // Auto-start if onboarding already completed
        if settings.hasCompletedOnboarding {
            start()
        } else {
            // Show onboarding window on first launch
            Task { @MainActor in
                showOnboarding()
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        // Register hotkeys
        hotkeyManager.register(
            onPushToTalkStart: { [weak self] in
                Task { @MainActor in
                    self?.startListening()
                }
            },
            onPushToTalkEnd: { [weak self] in
                Task { @MainActor in
                    self?.stopListening()
                }
            },
            onCycleVerbosity: { [weak self] in
                Task { @MainActor in
                    self?.cycleVerbosity()
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor in
                    self?.cancelCurrentAction()
                }
            }
        )

        // Start Hex bridge monitoring
        hexBridge.startMonitoring { [weak self] transcription in
            Task { @MainActor in
                self?.handleTranscription(transcription)
            }
        }

        // Periodically check Hex status
        hexBridge.checkHexStatus()
    }

    func stop() {
        hotkeyManager.unregister()
        hexBridge.stopMonitoring()
        ttsEngine.stop()
    }

    // MARK: - Voice Flow

    private func startListening() {
        guard appMode == .idle else { return }
        appMode = .listening
        liveTranscription = nil
    }

    private func stopListening() {
        guard appMode == .listening else { return }

        if let transcription = liveTranscription, !transcription.isEmpty {
            processTranscription(transcription)
        } else {
            appMode = .idle
        }
    }

    private func handleTranscription(_ text: String) {
        guard appMode == .listening else { return }
        liveTranscription = text
    }

    /// Confirm and execute the pending destructive command.
    func confirmDestructiveCommand() {
        guard let pending = pendingDestructiveCommand else { return }
        pendingDestructiveCommand = nil
        executeCommand(pending.routedCommand)
    }

    /// Cancel the pending destructive command.
    func cancelDestructiveCommand() {
        pendingDestructiveCommand = nil
        appMode = .idle
        ttsEngine.speak("Cancelled.")
    }

    /// Cancel whatever is currently happening (Escape key handler).
    func cancelCurrentAction() {
        switch appMode {
        case .listening:
            liveTranscription = nil
            appMode = .idle
        case .confirmingDestructive:
            cancelDestructiveCommand()
        case .processing:
            ttsEngine.stop()
        case .idle:
            break
        }
    }

    // MARK: - Command Processing

    private func processTranscription(_ transcription: String) {
        // Check for voice commands first
        let lower = transcription.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle pending destructive command confirmation
        if let pending = pendingDestructiveCommand {
            if lower == "confirm" || lower == "yes" {
                pendingDestructiveCommand = nil
                executeCommand(pending.routedCommand)
                return
            } else if lower == "cancel" || lower == "no" {
                pendingDestructiveCommand = nil
                appMode = .idle
                ttsEngine.speak("Cancelled.")
                return
            }
        }

        // Route the transcription
        let routed = commandRouter.route(transcription)
        currentTarget = routed.target

        // Safety check
        let safety = safetyChecker.check(routed.command)
        if safety.isDestructive {
            if case .destructive(let cmd, let reason, _) = safety {
                pendingDestructiveCommand = DestructiveCommandInfo(
                    routedCommand: routed,
                    reason: reason
                )
                appMode = .confirmingDestructive
                ttsEngine.speak("Destructive command detected: \(cmd). Say confirm or cancel.")
                return
            }
        }

        executeCommand(routed)
    }

    private func executeCommand(_ routed: RoutedCommand) {
        appMode = .processing

        // Mask secrets in logged command
        let loggedCommand = safetyChecker.containsSecrets(routed.command)
            ? safetyChecker.maskSecrets(in: routed.command)
            : routed.command

        // Create history entry
        var command = VoxCommand(
            transcription: routed.originalTranscription,
            resolvedCommand: loggedCommand,
            target: routed.target
        )
        command.status = .running
        history.add(command)

        // Execute asynchronously
        Task {
            do {
                let result: ExecutionResult

                if routed.target == .claudeCode {
                    result = try await terminalExecutor.executeClaudeCode(routed.command)
                } else {
                    result = try await terminalExecutor.execute(routed.command)
                }

                // Update command with result
                command.status = result.isSuccess ? .success : .error
                command.output = result.output
                command.exitCode = result.exitCode
                command.duration = result.duration

                if result.wasTimeout {
                    command.status = .timeout
                }

                // Process response based on verbosity
                let verbosity = responseProcessor.effectiveVerbosity(for: result, target: routed.target)
                let processed = responseProcessor.process(result, verbosity: verbosity, command: routed.command)

                command.summary = processed.spokenText
                history.update(command)

                // Speak the response
                if let text = processed.spokenText {
                    ttsEngine.speak(text)
                }

                appMode = .idle

            } catch {
                command.status = .error
                command.output = error.localizedDescription
                command.summary = "Error: \(error.localizedDescription)"
                history.update(command)

                ttsEngine.speak("Error: \(error.localizedDescription)")
                appMode = .idle
            }
        }
    }

    // MARK: - Verbosity

    private func cycleVerbosity() {
        currentVerbosity = currentVerbosity.next()
        settings.defaultVerbosity = currentVerbosity
        ttsEngine.speak("Verbosity: \(currentVerbosity.label)")
    }

    // MARK: - Computed Properties

    var statusText: String {
        switch appMode {
        case .idle: "Idle"
        case .listening: "Listening..."
        case .processing: "Processing..."
        case .confirmingDestructive: "Confirm?"
        }
    }

    var statusColor: Color {
        switch appMode {
        case .idle: .secondary
        case .listening: .accentBlue
        case .processing: .accentBlue
        case .confirmingDestructive: .statusOrange
        }
    }

    var menuBarIcon: String {
        switch appMode {
        case .idle: "mic"
        case .listening: "mic.fill"
        case .processing: "mic.badge.ellipsis"
        case .confirmingDestructive: "exclamationmark.triangle"
        }
    }

    // MARK: - Floating Panel Management

    private func handleModeChange(_ mode: AppMode) {
        switch mode {
        case .listening:
            showPushToTalkPanel()
            dismissDestructiveConfirmPanel()
        case .confirmingDestructive:
            dismissPushToTalkPanel()
            showDestructiveConfirmPanel()
        case .idle, .processing:
            dismissPushToTalkPanel()
            dismissDestructiveConfirmPanel()
        }
    }

    private func showPushToTalkPanel() {
        guard pushToTalkPanel == nil else { return }

        let overlay = PushToTalkOverlay(appState: self)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: overlay)
        panel.center()
        panel.orderFront(nil)

        pushToTalkPanel = panel
    }

    private func dismissPushToTalkPanel() {
        pushToTalkPanel?.close()
        pushToTalkPanel = nil
    }

    private func showDestructiveConfirmPanel() {
        guard let pending = pendingDestructiveCommand,
              destructiveConfirmPanel == nil else { return }

        let confirmView = DestructiveConfirmView(
            command: pending.routedCommand.command,
            reason: pending.reason,
            target: pending.routedCommand.target,
            onConfirm: { [weak self] in
                self?.confirmDestructiveCommand()
            },
            onCancel: { [weak self] in
                self?.cancelDestructiveCommand()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: confirmView)
        panel.center()
        panel.orderFront(nil)

        destructiveConfirmPanel = panel
    }

    private func dismissDestructiveConfirmPanel() {
        destructiveConfirmPanel?.close()
        destructiveConfirmPanel = nil
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
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
    case listening
    case processing
    case confirmingDestructive
}

struct DestructiveCommandInfo {
    let routedCommand: RoutedCommand
    let reason: String
}
