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
    private let terminalReader: TerminalReader
    private let responseProcessor: ResponseProcessor
    private let safetyChecker: SafetyChecker

    // MARK: - Windows

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var pushToTalkPanel: NSPanel?
    private var destructiveConfirmPanel: NSPanel?

    private var appModeObserver: AnyCancellable?
    private var hotkeyObserver: AnyCancellable?
    private var lastAppliedHotkey: PushToTalkHotkey = .controlSpace

    // MARK: - Init

    init() {
        self.settings = .shared
        self.hexBridge = HexBridge()
        self.hotkeyManager = HotkeyManager()
        self.ttsEngine = TTSEngine()
        self.history = CommandHistory()
        self.commandRouter = CommandRouter()
        self.terminalExecutor = TerminalExecutor()
        self.terminalReader = TerminalReader()
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

        // Observe hotkey changes from Settings and apply live
        lastAppliedHotkey = settings.pushToTalkHotkey
        hotkeyObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    let current = self.settings.pushToTalkHotkey
                    if current != self.lastAppliedHotkey {
                        self.lastAppliedHotkey = current
                        self.hotkeyManager.updateHotkey(current)
                    }
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
        // Register hotkeys with configured preset
        lastAppliedHotkey = settings.pushToTalkHotkey
        hotkeyManager.register(
            hotkey: settings.pushToTalkHotkey,
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

    /// Bundle IDs of apps whose output VOX should monitor (not execute).
    private static let monitorableBundleIDs: Set<String> = [
        "com.apple.Terminal",         // Terminal.app (incl. Claude Code)
        "com.googlecode.iterm2",      // iTerm2
    ]

    private func handleTranscription(_ entry: HexHistoryEntry) {
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        liveTranscription = text

        if appMode == .listening {
            // Push-to-talk mode: just store, will be processed on key release
            return
        }

        guard appMode == .idle else { return } // Busy — ignore

        let sourceApp = entry.sourceAppBundleID ?? ""

        // Route based on which app Hex dictated into
        if Self.monitorableBundleIDs.contains(sourceApp) {
            // Hex pasted text into Terminal/iTerm2 → monitor app output
            monitorTerminalResponse(transcription: text, bundleID: sourceApp)
        } else {
            // Other apps (Cursor, WhatsApp, Notes, etc.) → ignore
            // The user was dictating into a non-monitored app.
            // Don't execute, don't speak — just log for debugging.
        }
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
        case .processing, .monitoring:
            ttsEngine.stop()
            appMode = .idle
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

    // MARK: - Monitor Mode

    /// Monitor terminal output after Hex dictated a command into Terminal/iTerm2.
    /// Instead of executing, we read the terminal's response and speak it.
    private func monitorTerminalResponse(transcription: String, bundleID: String) {
        appMode = .monitoring

        let target: TargetApp = bundleID == "com.googlecode.iterm2" ? .iterm2 : .terminal

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
            let newOutput = await terminalReader.waitForNewOutput(
                bundleID: bundleID,
                initialSnapshot: snapshot,
                timeout: settings.commandTimeout,
                stabilizeDelay: 1.5
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
            let processed = responseProcessor.process(result, verbosity: verbosity, command: transcription)

            command.summary = processed.spokenText
            history.update(command)

            // 4. Speak the response
            if let text = processed.spokenText {
                ttsEngine.speak(text)
            }

            appMode = .idle
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
        case .monitoring: "Monitoring..."
        case .confirmingDestructive: "Confirm?"
        }
    }

    var statusColor: Color {
        switch appMode {
        case .idle: .secondary
        case .listening: .accentBlue
        case .processing, .monitoring: .accentBlue
        case .confirmingDestructive: .statusOrange
        }
    }

    var menuBarIcon: String {
        switch appMode {
        case .idle: "mic"
        case .listening: "mic.fill"
        case .processing: "mic.badge.ellipsis"
        case .monitoring: "eye"
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
        case .idle, .processing, .monitoring:
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
    case monitoring           // Waiting for terminal output after Hex dictation
    case confirmingDestructive
}

struct DestructiveCommandInfo {
    let routedCommand: RoutedCommand
    let reason: String
}
