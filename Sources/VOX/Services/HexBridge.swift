import AppKit
import Combine

/// Bridges VOX with the Hex app for speech-to-text input.
/// MVP uses clipboard monitoring; future versions will use XPC.
@MainActor
final class HexBridge: ObservableObject {
    @Published var lastTranscription: String?
    @Published var isHexRunning = false

    private var clipboardTimer: Timer?
    private var lastClipboardContent: String?
    private var lastClipboardChangeCount: Int = 0
    private var onTranscription: ((String) -> Void)?

    private let hexBundleID = "com.kitlangton.Hex"

    init() {
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        lastClipboardContent = NSPasteboard.general.string(forType: .string)
    }

    /// Start monitoring for Hex transcriptions via clipboard.
    func startMonitoring(onTranscription: @escaping (String) -> Void) {
        self.onTranscription = onTranscription
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        lastClipboardContent = NSPasteboard.general.string(forType: .string)

        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
        checkHexStatus()
    }

    func stopMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
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

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentCount

        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty,
              content != lastClipboardContent else { return }

        let previous = lastClipboardContent
        lastClipboardContent = content

        // Heuristic: Hex places transcribed text on clipboard.
        // We detect this by checking if Hex is running and the clipboard changed.
        // Filter out obvious non-transcription content (URLs, code blocks, etc.)
        guard isHexRunning,
              isLikelyTranscription(content, previousContent: previous) else { return }

        lastTranscription = content
        onTranscription?(content)
    }

    /// Heuristic to determine if clipboard content is likely a Hex transcription.
    private func isLikelyTranscription(_ content: String, previousContent: String?) -> Bool {
        // Transcriptions are typically short-to-medium sentences
        guard content.count < 1000 else { return false }

        // Unlikely to be transcription if it looks like code or a URL
        let codeIndicators = ["func ", "import ", "class ", "http://", "https://", "```", "->"]
        for indicator in codeIndicators {
            if content.contains(indicator) { return false }
        }

        // Should contain mostly alphanumeric and basic punctuation
        let alphanumericRatio = content.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }.count
        let ratio = Double(alphanumericRatio) / Double(content.count)
        return ratio > 0.7
    }
}
