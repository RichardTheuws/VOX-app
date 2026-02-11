import AppKit
import ApplicationServices

/// Reads application content via macOS Accessibility API (AXUIElement).
/// Used for Electron-based editors (Cursor, VS Code, Windsurf) that lack AppleScript support.
///
/// Strategy:
/// 1. Find the focused UI element (where Hex just typed)
/// 2. Read its text value via kAXValueAttribute
/// 3. Fallback: traverse parent/window for text-bearing elements
final class AccessibilityReader {

    // MARK: - Permission

    /// Check if Accessibility permission is granted.
    /// CRITICAL: Always call fresh — NEVER cache the result.
    /// The user explicitly reported that caching caused VOX to miss granted permissions.
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission via System Settings.
    /// Returns true if already trusted (may not reflect newly-granted permission until app restart).
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Read Content

    /// Read text content from the focused element of the given app.
    /// Returns the text value of the focused UI element (terminal panel, chat area, etc.)
    func readContent(for bundleID: String) async -> String? {
        // Always check fresh — never rely on cached permission state
        guard Self.isAccessibilityGranted() else { return nil }

        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Strategy 1: Read the focused element's value directly
        if let text = readFocusedElementText(axApp) {
            return text
        }

        // Strategy 2: Traverse the focused window for text-bearing elements
        return readWindowText(axApp)
    }

    // MARK: - Private: Reading Strategies

    /// Read text from the currently focused UI element.
    /// This is where Hex just typed — the terminal panel or chat input stays focused.
    private func readFocusedElementText(_ axApp: AXUIElement) -> String? {
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success else { return nil }

        // Safe cast — AXUIElementCopyAttributeValue returns AXUIElement for this attribute
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        // Try direct value read (works for AXTextArea in terminal panels)
        if let text = textValue(of: element), text.count > 10 {
            return text
        }

        // Try parent's children — the focused element might be an input cursor,
        // while the actual output text is in a sibling or parent container
        var parent: AnyObject?
        if AXUIElementCopyAttributeValue(
            element, kAXParentAttribute as CFString, &parent
        ) == .success, CFGetTypeID(parent) == AXUIElementGetTypeID() {
            var texts: [String] = []
            collectTextValues(from: parent as! AXUIElement, into: &texts, maxDepth: 5)
            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }

        return nil
    }

    /// Fallback: read text from the focused window by traversing the AX tree.
    /// Filters for substantial text blocks to skip UI labels and buttons.
    private func readWindowText(_ axApp: AXUIElement) -> String? {
        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &window
        ) == .success, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }

        var texts: [String] = []
        collectTextValues(from: window as! AXUIElement, into: &texts, maxDepth: 15)

        // Filter: only keep substantial text blocks (skip labels, buttons, etc.)
        let substantial = texts.filter { $0.count > 20 }
        return substantial.isEmpty ? nil : substantial.joined(separator: "\n")
    }

    // MARK: - Private: AX Helpers

    /// Read kAXValueAttribute as String from an element.
    private func textValue(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &value
        ) == .success else { return nil }

        guard let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    /// Recursively collect text from text-bearing AX elements (AXTextArea, AXStaticText, AXTextField).
    private func collectTextValues(
        from element: AXUIElement,
        into texts: inout [String],
        maxDepth: Int,
        depth: Int = 0
    ) {
        guard depth < maxDepth else { return }

        // Check role — only read text-bearing elements
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = (role as? String) ?? ""

        if Self.textRoles.contains(roleStr), let text = textValue(of: element) {
            texts.append(text)
        }

        // Recurse into children
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children
        ) == .success, let childArray = children as? [AXUIElement] else { return }

        for child in childArray {
            collectTextValues(from: child, into: &texts, maxDepth: maxDepth, depth: depth + 1)
        }
    }

    /// AX roles that typically contain user-readable text content.
    private static let textRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXStaticTextRole as String,
        kAXTextFieldRole as String
    ]
}
