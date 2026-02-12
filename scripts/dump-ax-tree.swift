#!/usr/bin/env swift
/// Diagnostic: dump Cursor's AX tree to understand what VOX can see.
/// Usage: swift scripts/dump-ax-tree.swift [bundleID]
/// Default: com.todesktop.230313mzl4w4u92 (Cursor)

import AppKit
import ApplicationServices

let bundleID = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "com.todesktop.230313mzl4w4u92"

guard AXIsProcessTrusted() else {
    print("ERROR: Accessibility permission not granted for this terminal.")
    print("Grant it in System Settings → Privacy & Security → Accessibility")
    exit(1)
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("ERROR: No running app with bundle ID: \(bundleID)")
    print("Running apps:")
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        print("  \(app.bundleIdentifier ?? "?") — \(app.localizedName ?? "?")")
    }
    exit(1)
}

print("=== AX Tree for \(app.localizedName ?? bundleID) (pid: \(app.processIdentifier)) ===\n")

let axApp = AXUIElementCreateApplication(app.processIdentifier)

// 1. Focused element
print("--- FOCUSED ELEMENT ---")
var focused: AnyObject?
if AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
   CFGetTypeID(focused) == AXUIElementGetTypeID() {
    let el = focused as! AXUIElement
    dumpElement(el, indent: 0, maxDepth: 3, label: "focused")

    // Parent chain
    print("\n--- FOCUSED ELEMENT PARENT CHAIN ---")
    var current: AXUIElement = el
    var depth = 0
    while depth < 10 {
        var parent: AnyObject?
        guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
              CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
        current = parent as! AXUIElement
        depth += 1
        let role = getAttr(current, kAXRoleAttribute) ?? "?"
        let desc = getAttr(current, kAXRoleDescriptionAttribute) ?? ""
        let title = getAttr(current, kAXTitleAttribute) ?? ""
        print("  ↑ [\(role)] desc=\(desc) title=\(title)")
    }
} else {
    print("  (no focused element)")
}

// 2. Focused window — deeper traversal looking for text
print("\n--- FOCUSED WINDOW TEXT ELEMENTS (depth ≤ 25) ---")
var window: AnyObject?
if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success,
   CFGetTypeID(window) == AXUIElementGetTypeID() {
    let win = window as! AXUIElement
    let title = getAttr(win, kAXTitleAttribute) ?? "(untitled)"
    print("Window: \(title)\n")

    var textElements: [(depth: Int, role: String, chars: Int, preview: String)] = []
    findTextElements(from: win, depth: 0, maxDepth: 25, results: &textElements)

    if textElements.isEmpty {
        print("  (no text elements found)")
    } else {
        print("  Found \(textElements.count) text-bearing elements:\n")
        for (i, el) in textElements.prefix(30).enumerated() {
            let indent = String(repeating: "  ", count: el.depth)
            print("  #\(i+1) \(indent)[\(el.role)] \(el.chars) chars: \"\(el.preview)\"")
        }
        if textElements.count > 30 {
            print("  ... and \(textElements.count - 30) more")
        }
    }
} else {
    print("  (no focused window)")
}

// 3. All windows — check for separate panels
print("\n--- ALL WINDOWS ---")
var windows: AnyObject?
if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows) == .success,
   let winArray = windows as? [AXUIElement] {
    for (i, win) in winArray.enumerated() {
        let title = getAttr(win, kAXTitleAttribute) ?? "(untitled)"
        let role = getAttr(win, kAXRoleAttribute) ?? "?"
        print("  Window \(i): [\(role)] \(title)")
    }
}

// MARK: - Helpers

func getAttr(_ el: AXUIElement, _ attr: String) -> String? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
    if let s = value as? String { return s }
    return nil
}

func dumpElement(_ el: AXUIElement, indent: Int, maxDepth: Int, label: String = "") {
    let pad = String(repeating: "  ", count: indent)
    let role = getAttr(el, kAXRoleAttribute) ?? "?"
    let roleDesc = getAttr(el, kAXRoleDescriptionAttribute) ?? ""
    let title = getAttr(el, kAXTitleAttribute) ?? ""
    let value = getAttr(el, kAXValueAttribute)
    let valuePreview = value.map { s in
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 80 ? String(trimmed.prefix(80)) + "... (\(trimmed.count) chars)" : trimmed
    } ?? "(no value)"

    print("\(pad)[\(role)] \(label) desc=\"\(roleDesc)\" title=\"\(title)\"")
    print("\(pad)  value: \(valuePreview)")

    guard indent < maxDepth else { return }

    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
          let childArray = children as? [AXUIElement] else { return }

    print("\(pad)  children: \(childArray.count)")
    for (i, child) in childArray.prefix(10).enumerated() {
        dumpElement(child, indent: indent + 1, maxDepth: maxDepth, label: "child[\(i)]")
    }
    if childArray.count > 10 {
        print("\(pad)  ... and \(childArray.count - 10) more children")
    }
}

func findTextElements(
    from element: AXUIElement,
    depth: Int,
    maxDepth: Int,
    results: inout [(depth: Int, role: String, chars: Int, preview: String)]
) {
    guard depth < maxDepth else { return }

    let role = getAttr(element, kAXRoleAttribute) ?? ""

    // Check for text value on this element
    if let value = getAttr(element, kAXValueAttribute),
       !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       value.count > 10 {
        let preview = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = preview.count > 100 ? String(preview.prefix(100)) + "..." : preview
        results.append((depth: depth, role: role, chars: preview.count, preview: short))
    }

    // Recurse into children
    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
          let childArray = children as? [AXUIElement] else { return }

    for child in childArray {
        findTextElements(from: child, depth: depth + 1, maxDepth: maxDepth, results: &results)
    }
}
