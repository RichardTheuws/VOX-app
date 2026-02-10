import AppKit
import Carbon

/// Manages global keyboard shortcuts for VOX.
/// Uses Carbon HotKey API for reliable global hotkey capture.
@MainActor
final class HotkeyManager: ObservableObject {
    @Published var isListening = false

    private var pushToTalkMonitor: Any?
    private var pushToTalkFlagsMonitor: Any?
    private var onPushToTalkStart: (() -> Void)?
    private var onPushToTalkEnd: (() -> Void)?
    private var onCycleVerbosity: (() -> Void)?
    private var onCancel: (() -> Void)?

    private var isOptionSpaceHeld = false

    /// Register global hotkeys.
    func register(
        onPushToTalkStart: @escaping () -> Void,
        onPushToTalkEnd: @escaping () -> Void,
        onCycleVerbosity: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.onPushToTalkStart = onPushToTalkStart
        self.onPushToTalkEnd = onPushToTalkEnd
        self.onCycleVerbosity = onCycleVerbosity
        self.onCancel = onCancel

        // Monitor key down events globally
        pushToTalkMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .keyUp]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }

        // Also monitor local events (when our app is focused)
        pushToTalkFlagsMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
            return event
        }
    }

    func unregister() {
        if let monitor = pushToTalkMonitor {
            NSEvent.removeMonitor(monitor)
            pushToTalkMonitor = nil
        }
        if let monitor = pushToTalkFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            pushToTalkFlagsMonitor = nil
        }
    }

    // MARK: - Private

    private func handleKeyEvent(_ event: NSEvent) {
        let isOption = event.modifierFlags.contains(.option)
        let isSpace = event.keyCode == 49 // spacebar
        let isV = event.keyCode == 9 // V key

        // Option+Space: Push-to-talk
        if isOption && isSpace {
            if event.type == .keyDown && !isOptionSpaceHeld {
                isOptionSpaceHeld = true
                isListening = true
                onPushToTalkStart?()
            } else if event.type == .keyUp {
                isOptionSpaceHeld = false
                isListening = false
                onPushToTalkEnd?()
            }
        }

        // Option+V: Cycle verbosity
        if isOption && isV && event.type == .keyDown {
            onCycleVerbosity?()
        }

        // Escape: Cancel current action
        let isEscape = event.keyCode == 53
        if isEscape && event.type == .keyDown {
            onCancel?()
        }
    }
}
