import AppKit

/// Monitors the frontmost app for content changes without requiring Hex.
/// When enabled, VOX continuously polls monitored apps and detects new output,
/// enabling Notice/Summary/Full verbosity for keyboard interactions.
final class AppWatcher {
    private var isRunning = false
    private var pollTask: Task<Void, Never>?
    private var workspaceObserver: NSObjectProtocol?

    /// Current frontmost monitored app bundle ID (nil if not a monitored app)
    private(set) var currentBundleID: String?

    /// Baseline content per app — used to detect new output
    private var baselines: [String: String] = [:]

    /// Timestamp of last content change per app
    private var lastChangeTime: [String: Date] = [:]

    /// Whether content is actively changing (fast polling mode)
    private var isContentChanging: [String: Bool] = [:]

    private let terminalReader: TerminalReader
    private let monitorableBundleIDs: Set<String>

    /// Callback when new stabilized content is detected.
    /// Parameters: (bundleID, newContent)
    var onNewContent: ((String, String) -> Void)?

    // MARK: - Polling Configuration

    /// Idle polling interval (seconds) — low CPU usage when no changes detected
    private let idlePollInterval: TimeInterval = 3.0

    /// Active polling interval (seconds) — faster when content is changing
    private let activePollInterval: TimeInterval = 0.5

    /// Time (seconds) of no change before content is considered stable
    private let stabilizationDelay: TimeInterval = 5.0

    /// Minimum number of new characters to trigger processing (avoids false positives from small UI updates)
    private let minimumChangeThreshold = 100

    init(terminalReader: TerminalReader, monitorableBundleIDs: Set<String>) {
        self.terminalReader = terminalReader
        self.monitorableBundleIDs = monitorableBundleIDs
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Watch for frontmost app changes
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }

        // Check current frontmost app immediately
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontApp.bundleIdentifier,
           monitorableBundleIDs.contains(bundleID) {
            currentBundleID = bundleID
        }

        // Start polling loop
        startPolling()
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        currentBundleID = nil
    }

    /// Update baseline for a bundle ID (call after Hex-triggered monitoring completes).
    /// Prevents auto-monitor from re-triggering on content already processed by Hex flow.
    func updateBaseline(for bundleID: String, content: String) {
        baselines[bundleID] = content
        isContentChanging[bundleID] = false
    }

    // MARK: - App Activation

    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }

        if monitorableBundleIDs.contains(bundleID) {
            currentBundleID = bundleID
        } else {
            currentBundleID = nil
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self = self, self.isRunning, !Task.isCancelled {
                await self.pollOnce()

                // Adaptive poll interval
                let interval: TimeInterval
                if let bundleID = self.currentBundleID,
                   self.isContentChanging[bundleID] == true {
                    interval = self.activePollInterval
                } else {
                    interval = self.idlePollInterval
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func pollOnce() async {
        guard let bundleID = currentBundleID else { return }

        // Read current content
        guard let currentContent = await terminalReader.readContent(for: bundleID) else { return }

        let baseline = baselines[bundleID] ?? ""

        // Compare with baseline
        let newChars = currentContent.count - baseline.count
        let contentChanged = currentContent != baseline && newChars > 0

        if contentChanged {
            // Content is growing — mark as changing
            isContentChanging[bundleID] = true
            lastChangeTime[bundleID] = Date()
            // Don't trigger yet — wait for stabilization
        } else if isContentChanging[bundleID] == true {
            // Content was changing but now stopped — check stabilization
            if let lastChange = lastChangeTime[bundleID],
               Date().timeIntervalSince(lastChange) >= stabilizationDelay {
                // Content has been stable long enough — trigger!
                isContentChanging[bundleID] = false

                let newContent = extractNewContent(baseline: baseline, current: currentContent, bundleID: bundleID)

                if newContent.count >= minimumChangeThreshold {
                    // Update baseline BEFORE triggering callback to prevent re-processing
                    baselines[bundleID] = currentContent

                    // Notify on main thread
                    let content = newContent
                    let bid = bundleID
                    await MainActor.run {
                        onNewContent?(bid, content)
                    }
                } else {
                    // Change too small — just update baseline silently
                    baselines[bundleID] = currentContent
                }
            }
        }
    }

    /// Extract the new portion of content by comparing baseline and current.
    private func extractNewContent(baseline: String, current: String, bundleID: String) -> String {
        let isTerminal = TerminalReader.terminalBasedBundleIDs.contains(bundleID)

        if isTerminal {
            // For terminals: take lines that appear after the baseline content
            let baselineLines = baseline.components(separatedBy: "\n")
            let currentLines = current.components(separatedBy: "\n")

            if currentLines.count > baselineLines.count {
                let newLines = Array(currentLines[baselineLines.count...])
                return newLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // For AX-based apps or fallback: return any content beyond the baseline length
        if current.count > baseline.count {
            let startIndex = current.index(current.startIndex, offsetBy: baseline.count)
            return String(current[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Full content differs significantly — return the whole new content
        return current.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
