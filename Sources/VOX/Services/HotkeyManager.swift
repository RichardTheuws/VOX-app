import AppKit
import Carbon

/// Manages global keyboard shortcuts for VOX using CGEventTap.
/// CGEventTap intercepts AND consumes key events so they don't propagate
/// (fixes the "Option+Space types spaces" problem).
@MainActor
final class HotkeyManager: ObservableObject {
    @Published var isListening = false
    @Published var isHotkeyActive = false

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onPushToTalkStart: (() -> Void)?
    private var onPushToTalkEnd: (() -> Void)?
    private var onCycleVerbosity: (() -> Void)?
    private var onCancel: (() -> Void)?

    // Shared state for the C callback
    fileprivate static var shared: HotkeyManager?
    private var isPushToTalkHeld = false
    private var currentHotkey: PushToTalkHotkey = .controlSpace

    /// Register global hotkeys with CGEventTap.
    func register(
        hotkey: PushToTalkHotkey = .controlSpace,
        onPushToTalkStart: @escaping () -> Void,
        onPushToTalkEnd: @escaping () -> Void,
        onCycleVerbosity: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        // Store callbacks
        self.onPushToTalkStart = onPushToTalkStart
        self.onPushToTalkEnd = onPushToTalkEnd
        self.onCycleVerbosity = onCycleVerbosity
        self.onCancel = onCancel
        self.currentHotkey = hotkey
        HotkeyManager.shared = self

        // Create event tap
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: nil
        ) else {
            // CGEventTap failed (no accessibility permission).
            // Hotkey won't work, but VOX still works via Hex clipboard monitoring.
            isHotkeyActive = false
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isHotkeyActive = true
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        HotkeyManager.shared = nil
    }

    /// Update the hotkey preset at runtime.
    func updateHotkey(_ hotkey: PushToTalkHotkey) {
        currentHotkey = hotkey
        // Reset held state when changing hotkey
        isPushToTalkHeld = false
        isListening = false
    }

    // MARK: - CGEventTap Callback

    /// Handles a key event from the CGEventTap. Returns true if the event should be consumed.
    fileprivate func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Push-to-talk hotkey
        let matchesModifier = flags.contains(currentHotkey.modifierFlags)
        let matchesKey = keyCode == currentHotkey.keyCode

        if matchesModifier && matchesKey {
            if type == .keyDown && !isPushToTalkHeld {
                isPushToTalkHeld = true
                isListening = true
                onPushToTalkStart?()
                return true // Consume the event
            } else if type == .keyUp && isPushToTalkHeld {
                isPushToTalkHeld = false
                isListening = false
                onPushToTalkEnd?()
                return true // Consume the event
            } else if type == .keyDown && isPushToTalkHeld {
                return true // Suppress key repeat while held
            }
        }

        // Handle key-up for push-to-talk when modifier is released
        if isPushToTalkHeld && type == .keyUp && keyCode == currentHotkey.keyCode {
            isPushToTalkHeld = false
            isListening = false
            onPushToTalkEnd?()
            return true
        }

        // Escape: Cancel current action (don't consume — let other apps handle it too)
        if keyCode == 53 && type == .keyDown {
            onCancel?()
            // Don't consume Escape — other apps might need it
        }

        // Cycle verbosity: Option+V (only if not using Option+Space as hotkey, or always since it's a different key)
        if keyCode == 9 && type == .keyDown && flags.contains(.maskAlternate) {
            onCycleVerbosity?()
            return true
        }

        return false // Let event through
    }

    // MARK: - Fallback (NSEvent monitors, no event consumption)

    private var fallbackGlobalMonitor: Any?
    private var fallbackLocalMonitor: Any?

    private func registerFallback() {
        fallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in self?.handleNSEvent(event) }
        }
        fallbackLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in self?.handleNSEvent(event) }
            return event
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags

        let matchesModifier: Bool
        switch currentHotkey {
        case .controlSpace: matchesModifier = flags.contains(.control)
        case .optionSpace: matchesModifier = flags.contains(.option)
        case .commandShiftV: matchesModifier = flags.contains(.command) && flags.contains(.shift)
        case .fnSpace: matchesModifier = flags.contains(.function)
        }

        if matchesModifier && keyCode == currentHotkey.keyCode {
            if event.type == .keyDown && !isPushToTalkHeld {
                isPushToTalkHeld = true
                isListening = true
                onPushToTalkStart?()
            } else if event.type == .keyUp {
                isPushToTalkHeld = false
                isListening = false
                onPushToTalkEnd?()
            }
        }

        if keyCode == 53 && event.type == .keyDown { onCancel?() }
        if keyCode == 9 && event.type == .keyDown && flags.contains(.option) { onCycleVerbosity?() }
    }
}

// MARK: - CGEventTap C Callback

/// Global C function callback for CGEventTap — dispatches to HotkeyManager.shared.
/// CGEventTap callbacks run on the main run loop (main thread), so MainActor.assumeIsolated is safe.
private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Handle tap disabled events (system can disable taps under heavy load)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            if let tap = HotkeyManager.shared?.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passRetained(event)
    }

    // Ask the shared manager to handle the event (safe: callback runs on main thread)
    let consumed = MainActor.assumeIsolated {
        HotkeyManager.shared?.handleCGEvent(type: type, event: event) ?? false
    }

    if consumed {
        return nil // Suppress the event entirely
    }
    return Unmanaged.passRetained(event)
}
