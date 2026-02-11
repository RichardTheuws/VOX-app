import AppKit
import Combine

/// Bridges VOX with the Hex app for speech-to-text input.
/// Monitors Hex's `transcription_history.json` for new transcriptions.
/// Hex saves every dictation to this file with timestamp, text, and source app.
@MainActor
final class HexBridge: ObservableObject {
    @Published var lastTranscription: String?
    @Published var isHexRunning = false

    private var fileMonitorTimer: Timer?
    private var lastProcessedTimestamp: Double = 0
    private var lastFileModDate: Date?
    private var onTranscription: ((HexHistoryEntry) -> Void)?

    private let hexBundleID = "com.kitlangton.Hex"

    /// Path to Hex's transcription history file (inside its sandboxed container).
    private var historyFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/com.kitlangton.Hex/transcription_history.json"
    }

    init() {
        // Seed the last processed timestamp from the history file
        // so we don't re-process old transcriptions on launch.
        seedLastTimestamp()
    }

    /// Start monitoring for Hex transcriptions via history file.
    func startMonitoring(onTranscription: @escaping (HexHistoryEntry) -> Void) {
        stopMonitoring()
        self.onTranscription = onTranscription

        // Re-seed so we only process NEW transcriptions from this point forward.
        seedLastTimestamp()

        // Poll the history file every 0.3 seconds (no race condition like clipboard).
        fileMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkHistoryFile()
            }
        }
        checkHexStatus()
    }

    func stopMonitoring() {
        fileMonitorTimer?.invalidate()
        fileMonitorTimer = nil
        onTranscription = nil
    }

    /// Check if Hex is currently running.
    func checkHexStatus() {
        isHexRunning = NSRunningApplication.runningApplications(
            withBundleIdentifier: hexBundleID
        ).first != nil
    }

    /// Attempt to launch Hex if not running.
    func launchHex() {
        guard !isHexRunning else { return }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: hexBundleID) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
            // Re-check after a delay
            Task {
                try? await Task.sleep(for: .seconds(2))
                checkHexStatus()
            }
        }
    }

    // MARK: - Private

    /// Read the latest timestamp from history so we don't re-process old entries.
    private func seedLastTimestamp() {
        guard let entries = readHistoryEntries() else { return }
        if let latest = entries.max(by: { $0.timestamp < $1.timestamp }) {
            lastProcessedTimestamp = latest.timestamp
        }
    }

    /// Check the history file for new transcriptions.
    private func checkHistoryFile() {
        let fileManager = FileManager.default
        let path = historyFilePath

        // Quick check: has the file been modified since last check?
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else { return }

        if let lastMod = lastFileModDate, modDate <= lastMod {
            return // File hasn't changed
        }
        lastFileModDate = modDate

        // File changed — parse and find new entries
        guard let entries = readHistoryEntries() else { return }

        // Find entries newer than our last processed timestamp
        let newEntries = entries
            .filter { $0.timestamp > lastProcessedTimestamp }
            .sorted { $0.timestamp < $1.timestamp }

        for entry in newEntries {
            lastProcessedTimestamp = entry.timestamp
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            lastTranscription = text
            onTranscription?(entry)
        }

        // Also update Hex running status while we're at it
        checkHexStatus()
    }

    /// Parse the transcription_history.json file.
    private func readHistoryEntries() -> [HexHistoryEntry]? {
        let path = historyFilePath
        guard let data = FileManager.default.contents(atPath: path) else { return nil }

        do {
            let history = try JSONDecoder().decode(HexHistory.self, from: data)
            return history.history
        } catch {
            return nil
        }
    }
}

// MARK: - Hex History JSON Model

/// Matches the structure of Hex's transcription_history.json
private struct HexHistory: Decodable {
    let history: [HexHistoryEntry]
}

struct HexHistoryEntry: Decodable {
    let id: String
    let text: String
    let timestamp: Double
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let duration: Double?
}
