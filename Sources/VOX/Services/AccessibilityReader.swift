import AppKit
import ApplicationServices

/// Reads application content via macOS Accessibility API (AXUIElement).
/// Used for Electron-based editors (Cursor, VS Code, Windsurf) that lack AppleScript support.
///
/// Primary strategy: "Content Harvest" — deep scans the focused window's AX tree
/// to find ALL substantial text blocks. This finds AI chat responses regardless of
/// where focus is, since the response is in a sibling subtree of the input field.
///
/// Fallback strategies use the focused element for terminal-like apps.
final class AccessibilityReader {

    /// Track whether we've already shown the AX permission prompt this session.
    /// Prevents spamming the user with System Settings on every poll.
    private var hasRequestedPermission = false

    /// UserDefaults key to persist the "already prompted" state across launches.
    /// Once VOX has shown the AX permission dialog, it won't auto-prompt again.
    /// The user can still grant permission manually via Settings → Apps → "Grant Permission" button.
    private static let hasPromptedAXKey = "hasPromptedAccessibilityPermission"

    /// Whether we've run the one-time deep diagnostic dump.
    private var hasDumpedDiagnostic = false

    /// Minimum character count to consider text as "real content" (not UI labels).
    /// AI responses are typically > 100 chars. UI strings like "Add a follow-up" are < 50.
    private static let minimumContentLength = 80

    /// Minimum AX tree depth for chat content fragments.
    /// Cursor's chat panel renders at depth >= 30. UI chrome (explorer, status bar) is shallower.
    private static let chatMinDepth = 30

    /// Minimum concatenated chars for a fragment group to qualify as a "message".
    /// Short labels ("Thought", "2s", "Agent") won't pass; AI responses are typically > 200 chars.
    private static let chatMinGroupChars = 100

    // MARK: - Permission

    /// Check if Accessibility permission is granted.
    /// CRITICAL: Always call fresh — NEVER cache the result.
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission via System Settings.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Read Content

    func readContent(for bundleID: String) async -> String? {
        guard Self.isAccessibilityGranted() else {
            if !hasRequestedPermission && !UserDefaults.standard.bool(forKey: Self.hasPromptedAXKey) {
                Self.debugLog("AX permission NOT granted — showing permission prompt (first time)")
                Self.requestAccessibilityPermission()
                hasRequestedPermission = true
                UserDefaults.standard.set(true, forKey: Self.hasPromptedAXKey)
            } else {
                Self.debugLog("AX permission NOT granted — already prompted, skipping auto-prompt")
            }
            return nil
        }

        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first else {
            Self.debugLog("No running app for \(bundleID)")
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Enable accessibility tree for Electron-based apps.
        // Chromium disables its AX tree by default for performance.
        enableAccessibilityTree(for: axApp)

        // One-time deep diagnostic: dump the FULL AX tree structure.
        // Writes to ~/Library/Logs/VOX-ax-diagnostic.log for analysis.
        if !hasDumpedDiagnostic {
            hasDumpedDiagnostic = true
            dumpFullDiagnostic(axApp)
        }

        // Strategy 0: Chat fragment assembly for Electron editors.
        // Cursor's AI chat renders each response as many tiny AXStaticText fragments
        // (~12-18 chars each) at consistent tree depths. This reassembles them into
        // the complete latest AI response by grouping consecutive same-depth fragments.
        if let text = assembleChatFragments(axApp) {
            Self.debugLog("Strategy 0 (chatAssembly): \(text.count) chars — \(String(text.prefix(120)))")
            return text
        }

        // Strategy 1: Deep content harvest from focused window.
        // Scans the ENTIRE window AX tree for substantial text blocks.
        // This finds AI chat responses in Cursor regardless of where the cursor is.
        if let text = harvestWindowContent(axApp) {
            Self.debugLog("Strategy 1 (harvest): \(text.count) chars — \(String(text.prefix(120)))")
            return text
        }

        // Strategy 2: System-wide focused element text.
        // For apps where the focused element itself contains the content (e.g. terminal).
        // Only accept substantial content to skip UI strings.
        if let text = readSystemFocusedText(expectedPID: app.processIdentifier) {
            Self.debugLog("Strategy 2 (system): \(text.count) chars — \(String(text.prefix(120)))")
            return text
        }

        // Strategy 3: App-level focused element — last resort.
        if let text = readFocusedElementText(axApp) {
            Self.debugLog("Strategy 3 (focused): \(text.count) chars — \(String(text.prefix(120)))")
            return text
        }

        Self.debugLog("All strategies returned nil")
        return nil
    }

    // MARK: - Private: Electron Accessibility

    private func enableAccessibilityTree(for axApp: AXUIElement) {
        let result = AXUIElementSetAttributeValue(
            axApp,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        Self.debugLog("  AXManualAccessibility result: \(result.rawValue) (\(result == .success ? "OK" : "FAILED"))")
    }

    // MARK: - Strategy 0: Chat Fragment Assembly

    /// Assemble Cursor's fragmented AI chat response from many small AXStaticText elements.
    ///
    /// Chromium renders chat panel text as hundreds of AXStaticText fragments (~12-18 chars each)
    /// at consistent AX tree depths. AI responses are at depth ~33, user prompts at ~34-35,
    /// meta-info ("Thought", timestamps) at ~31, and UI chrome below depth 30.
    ///
    /// Algorithm:
    /// 1. Collect ALL AXStaticText values from the window tree with their depths
    /// 2. Filter to chat-depth elements only (depth >= chatMinDepth)
    /// 3. Group consecutive same-depth fragments into message blocks
    /// 4. Identify the "AI response depth" (the depth with the largest single group)
    /// 5. Return the LAST group at that depth (= latest AI response, not user prompt)
    private func assembleChatFragments(_ axApp: AXUIElement) -> String? {
        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &window
        ) == .success, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            Self.debugLog("  chatAssembly: could not get focused window")
            return nil
        }

        // Phase 1: Collect all AXStaticText fragments with tree depth
        var fragments: [(text: String, depth: Int)] = []
        collectStaticTextFragments(
            from: window as! AXUIElement,
            into: &fragments,
            depth: 0,
            maxDepth: 50
        )

        Self.debugLog("  chatAssembly: \(fragments.count) AXStaticText fragments total")

        guard !fragments.isEmpty else {
            Self.debugLog("  chatAssembly: no AXStaticText elements found")
            return nil
        }

        // Phase 2: Filter to chat-depth fragments (skip UI chrome, explorer, status bar)
        let chatFragments = fragments.filter { $0.depth >= Self.chatMinDepth }

        guard !chatFragments.isEmpty else {
            Self.debugLog("  chatAssembly: no fragments at depth >= \(Self.chatMinDepth)")
            return nil
        }

        Self.debugLog("  chatAssembly: \(chatFragments.count) fragments at depth >= \(Self.chatMinDepth)")

        // Phase 3: Group consecutive same-depth fragments into message blocks.
        // Each time the depth changes, a new group starts. This naturally separates:
        // - AI responses (depth ~33) from user prompts (depth ~34-35)
        // - Different chat messages from each other
        var groups: [(depth: Int, texts: [String])] = []
        var currentTexts: [String] = [chatFragments[0].text]
        var currentDepth = chatFragments[0].depth

        for frag in chatFragments.dropFirst() {
            if frag.depth == currentDepth {
                currentTexts.append(frag.text)
            } else {
                groups.append((depth: currentDepth, texts: currentTexts))
                currentTexts = [frag.text]
                currentDepth = frag.depth
            }
        }
        groups.append((depth: currentDepth, texts: currentTexts))

        // Log group summary for diagnostics
        let groupSummary = groups.map { "\($0.texts.joined().count)ch@d\($0.depth)" }
        Self.debugLog("  chatAssembly: \(groups.count) groups: \(groupSummary.joined(separator: ", "))")

        // Phase 4: Find the AI response depth and return the latest response.
        // AI responses (depth ~33) produce groups of 400-1000+ chars.
        // User prompts (depth ~34) produce groups of 75-120 chars.
        // Strategy: the depth with the largest single group is the AI response depth.
        // Then return the LAST group at that depth (= latest AI response).
        let substantialGroups = groups.filter {
            $0.texts.joined().count > Self.chatMinGroupChars
        }

        guard !substantialGroups.isEmpty else {
            Self.debugLog("  chatAssembly: no group > \(Self.chatMinGroupChars) chars")
            return nil
        }

        // Find depth with the largest single group (= AI response depth)
        let largestGroup = substantialGroups.max(by: {
            $0.texts.joined().count < $1.texts.joined().count
        })!
        let aiResponseDepth = largestGroup.depth

        Self.debugLog("  chatAssembly: AI response depth = \(aiResponseDepth) (largest group = \(largestGroup.texts.joined().count) chars)")

        // Return the LAST group at the AI response depth (= latest AI response)
        let aiGroups = substantialGroups.filter { $0.depth == aiResponseDepth }
        guard let lastAIGroup = aiGroups.last else {
            Self.debugLog("  chatAssembly: no groups at depth \(aiResponseDepth)")
            return nil
        }

        let assembled = lastAIGroup.texts.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Self.debugLog("  chatAssembly: returning \(assembled.count) chars from depth=\(lastAIGroup.depth) (\(lastAIGroup.texts.count) fragments)")
        Self.debugLog("  chatAssembly: preview: \(String(assembled.prefix(200)))")

        return assembled.isEmpty ? nil : assembled
    }

    /// Collect only AXStaticText element values with their tree depths.
    /// No minimum character filter — we need ALL fragments for reassembly.
    private func collectStaticTextFragments(
        from element: AXUIElement,
        into fragments: inout [(text: String, depth: Int)],
        depth: Int,
        maxDepth: Int
    ) {
        guard depth < maxDepth else { return }
        guard fragments.count < 2000 else { return }  // Safety limit

        var roleObj: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleObj)
        let role = (roleObj as? String) ?? ""

        // Only collect AXStaticText elements — these are Chromium's text nodes
        if role == "AXStaticText" {
            if let text = textValue(of: element), !text.isEmpty {
                fragments.append((text: text, depth: depth))
            }
        }

        // Recurse into children
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children
        ) == .success, let childArray = children as? [AXUIElement] else { return }

        for child in childArray {
            collectStaticTextFragments(from: child, into: &fragments, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    // MARK: - Deep Diagnostic Dump

    /// One-time comprehensive AX tree dump to understand the full structure.
    /// Writes to ~/Library/Logs/VOX-ax-diagnostic.log
    /// This dumps EVERYTHING: all elements, all attributes, all text (no minimum).
    private func dumpFullDiagnostic(_ axApp: AXUIElement) {
        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/VOX-ax-diagnostic.log")

        // Start fresh
        try? "".data(using: .utf8)?.write(to: logFile)

        func diagLog(_ msg: String) {
            if let data = "\(msg)\n".data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }

        diagLog("=== VOX AX DIAGNOSTIC DUMP ===")
        diagLog("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        diagLog("")

        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &window
        ) == .success, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            diagLog("ERROR: Could not get focused window")
            return
        }

        // Counters for the full tree
        var totalElements = 0
        var roleCounts: [String: Int] = [:]
        var webAreas: [(title: String, depth: Int, textCount: Int, totalChars: Int)] = []
        var allTextFragments: [(role: String, attr: String, depth: Int, chars: Int, text: String)] = []

        // Phase 1: Full tree scan — count everything, find all AXWebAreas
        diagLog("--- PHASE 1: Full tree scan (maxDepth=60, maxElements=5000) ---")
        diagLog("")

        func scanTree(element: AXUIElement, depth: Int) {
            guard depth < 60 else { return }
            guard totalElements < 5000 else { return }

            totalElements += 1

            var roleObj: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleObj)
            let role = (roleObj as? String) ?? "unknown"
            roleCounts[role, default: 0] += 1

            // Check for ANY text content (no minimum filter!)
            let val = textValue(of: element)
            let desc = descriptionValue(of: element)
            let title = titleValue(of: element)

            if let v = val, !v.isEmpty {
                allTextFragments.append((role: role, attr: "value", depth: depth, chars: v.count, text: v))
            }
            if let d = desc, !d.isEmpty, d != val {
                allTextFragments.append((role: role, attr: "desc", depth: depth, chars: d.count, text: d))
            }
            if let t = title, !t.isEmpty, t != val, t != desc {
                allTextFragments.append((role: role, attr: "title", depth: depth, chars: t.count, text: t))
            }

            // Track AXWebArea elements — these are webviews
            if role == "AXWebArea" {
                let webTitle = title ?? val ?? desc ?? "(no title)"
                var textInArea = 0
                var charsInArea = 0
                countTextInSubtree(element, &textInArea, &charsInArea, depth: 0)
                webAreas.append((title: webTitle, depth: depth, textCount: textInArea, totalChars: charsInArea))
            }

            // Check for Chromium-specific attributes
            var domId: AnyObject?
            if AXUIElementCopyAttributeValue(element, "AXDOMIdentifier" as CFString, &domId) == .success,
               let id = domId as? String, !id.isEmpty {
                allTextFragments.append((role: role, attr: "domId", depth: depth, chars: id.count, text: id))
            }

            var domClass: AnyObject?
            if AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &domClass) == .success,
               let classes = domClass as? [String], !classes.isEmpty {
                let classStr = classes.joined(separator: " ")
                if classStr.count > 3 {
                    allTextFragments.append((role: role, attr: "domClass", depth: depth, chars: classStr.count, text: classStr))
                }
            }

            // Check ARIA live region attributes
            var liveStatus: AnyObject?
            if AXUIElementCopyAttributeValue(element, "AXARIALive" as CFString, &liveStatus) == .success,
               let status = liveStatus as? String, !status.isEmpty {
                allTextFragments.append((role: role, attr: "ariaLive", depth: depth, chars: status.count, text: "ARIA-LIVE=\(status)"))
            }

            // Check kAXNumberOfCharactersAttribute (for text fields with readable content)
            var numChars: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &numChars) == .success,
               let count = numChars as? Int, count > 50 {
                // This element has significant text accessible via StringForRange
                if val == nil || (val?.count ?? 0) < count {
                    // Text not in value — try reading via StringForRange
                    var range = CFRange(location: 0, length: min(count, 2000))
                    let rangeValue = AXValueCreate(.cfRange, &range)!
                    var stringResult: AnyObject?
                    if AXUIElementCopyParameterizedAttributeValue(
                        element,
                        kAXStringForRangeParameterizedAttribute as CFString,
                        rangeValue,
                        &stringResult
                    ) == .success, let str = stringResult as? String, !str.isEmpty {
                        allTextFragments.append((role: role, attr: "stringForRange", depth: depth, chars: str.count, text: str))
                    }
                }
            }

            // Recurse into children
            var children: AnyObject?
            guard AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &children
            ) == .success, let childArray = children as? [AXUIElement] else { return }

            for child in childArray {
                scanTree(element: child, depth: depth + 1)
            }
        }

        // Helper to count text in a subtree (for AXWebArea analysis)
        func countTextInSubtree(_ element: AXUIElement, _ textCount: inout Int, _ totalChars: inout Int, depth: Int) {
            guard depth < 30 else { return }

            if let v = textValue(of: element), !v.isEmpty {
                textCount += 1
                totalChars += v.count
            }
            if let d = descriptionValue(of: element), !d.isEmpty, d != textValue(of: element) {
                textCount += 1
                totalChars += d.count
            }

            var children: AnyObject?
            guard AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &children
            ) == .success, let childArray = children as? [AXUIElement] else { return }

            for child in childArray {
                countTextInSubtree(child, &textCount, &totalChars, depth: depth + 1)
            }
        }

        scanTree(element: window as! AXUIElement, depth: 0)

        // Write results
        diagLog("Total elements scanned: \(totalElements)")
        diagLog("")

        diagLog("--- ROLE DISTRIBUTION ---")
        for (role, count) in roleCounts.sorted(by: { $0.value > $1.value }) {
            diagLog("  \(role): \(count)")
        }
        diagLog("")

        diagLog("--- AXWebArea ELEMENTS (webviews) ---")
        if webAreas.isEmpty {
            diagLog("  NONE FOUND! This is the problem.")
        } else {
            for (i, area) in webAreas.enumerated() {
                diagLog("  [\(i)] depth=\(area.depth) title=\"\(area.title)\" texts=\(area.textCount) chars=\(area.totalChars)")
            }
        }
        diagLog("")

        diagLog("--- ALL TEXT FRAGMENTS (\(allTextFragments.count) total) ---")
        diagLog("  By size: <10=\(allTextFragments.filter { $0.chars < 10 }.count), 10-50=\(allTextFragments.filter { $0.chars >= 10 && $0.chars < 50 }.count), 50-80=\(allTextFragments.filter { $0.chars >= 50 && $0.chars < 80 }.count), 80+=\(allTextFragments.filter { $0.chars >= 80 }.count)")
        diagLog("")

        // Log ALL fragments with text > 30 chars (to find chat content)
        diagLog("--- FRAGMENTS > 30 CHARS ---")
        for (i, frag) in allTextFragments.filter({ $0.chars > 30 }).enumerated() {
            diagLog("  [\(i)] role=\(frag.role) attr=\(frag.attr) depth=\(frag.depth) \(frag.chars)ch: \(String(frag.text.prefix(200)))")
        }
        diagLog("")

        // Log Chromium DOM attributes
        diagLog("--- CHROMIUM DOM ATTRIBUTES ---")
        let domFrags = allTextFragments.filter { $0.attr == "domId" || $0.attr == "domClass" || $0.attr == "ariaLive" }
        if domFrags.isEmpty {
            diagLog("  NONE FOUND — Chromium DOM attributes not exposed")
        } else {
            for frag in domFrags {
                diagLog("  \(frag.attr) depth=\(frag.depth): \(String(frag.text.prefix(200)))")
            }
        }
        diagLog("")

        // Log StringForRange results (text accessible via parameterized attributes)
        diagLog("--- STRING-FOR-RANGE TEXT ---")
        let sfrFrags = allTextFragments.filter { $0.attr == "stringForRange" }
        if sfrFrags.isEmpty {
            diagLog("  NONE FOUND — no elements with hidden text via StringForRange")
        } else {
            for frag in sfrFrags {
                diagLog("  role=\(frag.role) depth=\(frag.depth) \(frag.chars)ch: \(String(frag.text.prefix(500)))")
            }
        }
        diagLog("")

        // Log ALL AXStaticText elements (these should contain web page text)
        diagLog("--- ALL AXStaticText ELEMENTS ---")
        let staticTexts = allTextFragments.filter { $0.role == "AXStaticText" }
        if staticTexts.isEmpty {
            diagLog("  NONE FOUND — Chromium may not be exposing text nodes")
        } else {
            for (i, frag) in staticTexts.enumerated() {
                diagLog("  [\(i)] attr=\(frag.attr) depth=\(frag.depth) \(frag.chars)ch: \(String(frag.text.prefix(200)))")
            }
        }
        diagLog("")

        diagLog("=== END DIAGNOSTIC ===")

        Self.debugLog("DIAGNOSTIC: Full dump written to ~/Library/Logs/VOX-ax-diagnostic.log (\(totalElements) elements, \(allTextFragments.count) text fragments, \(webAreas.count) webviews)")
    }

    // MARK: - Strategy 1: Deep Content Harvest

    /// Scan the entire focused window AX tree for substantial text blocks.
    /// Unlike focused-element strategies, this finds content in ANY part of the window.
    /// Designed for Cursor's AI chat panel where the response is in a sibling
    /// subtree of the focused input field.
    private func harvestWindowContent(_ axApp: AXUIElement) -> String? {
        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &window
        ) == .success, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            Self.debugLog("  harvest: could not get focused window")
            return nil
        }

        var allTexts: [HarvestedText] = []
        collectAllText(from: window as! AXUIElement, into: &allTexts, maxDepth: 50, depth: 0)

        Self.debugLog("  harvest: found \(allTexts.count) text blocks (maxDepth=50)")
        for (i, item) in allTexts.prefix(15).enumerated() {
            Self.debugLog("    [\(i)] role=\(item.role) attr=\(item.attribute) depth=\(item.depth) \(item.text.count) chars: \(String(item.text.prefix(80)))")
        }
        if allTexts.count > 15 {
            Self.debugLog("    ... and \(allTexts.count - 15) more")
        }

        // Filter: keep only substantial text blocks (> minimumContentLength chars).
        // This skips UI labels like "Add a follow-up", "Review", "53 Files", etc.
        let substantial = allTexts.filter { $0.text.count > Self.minimumContentLength }

        guard !substantial.isEmpty else {
            Self.debugLog("  harvest: no substantial text blocks (> \(Self.minimumContentLength) chars)")
            return nil
        }

        let combined = substantial.map(\.text).joined(separator: "\n")
        Self.debugLog("  harvest: returning \(combined.count) chars from \(substantial.count) blocks")
        return combined
    }

    /// A text block found during the harvest, with metadata for logging.
    private struct HarvestedText {
        let text: String
        let role: String
        let attribute: String  // "value", "description", or "title"
        let depth: Int
    }

    /// Collect text from ALL elements regardless of role.
    /// Reads kAXValue, kAXDescription, AND kAXTitle from every element.
    /// This is broader than collectTextValues which only checks specific roles.
    private func collectAllText(
        from element: AXUIElement,
        into texts: inout [HarvestedText],
        maxDepth: Int,
        depth: Int = 0
    ) {
        guard depth < maxDepth else { return }
        guard texts.count < 500 else { return }  // Safety limit

        var roleObj: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleObj)
        let role = (roleObj as? String) ?? "unknown"

        // Try kAXValueAttribute
        if let text = textValue(of: element), text.count > 10 {
            texts.append(HarvestedText(text: text, role: role, attribute: "value", depth: depth))
        }

        // Try kAXDescriptionAttribute (Chromium often uses this for text content)
        if let desc = descriptionValue(of: element), desc.count > 10 {
            // Don't duplicate if same as value
            if desc != textValue(of: element) {
                texts.append(HarvestedText(text: desc, role: role, attribute: "desc", depth: depth))
            }
        }

        // Try kAXTitleAttribute (some elements carry text in title)
        if let title = titleValue(of: element), title.count > 10 {
            if title != textValue(of: element) && title != descriptionValue(of: element) {
                texts.append(HarvestedText(text: title, role: role, attribute: "title", depth: depth))
            }
        }

        // Recurse into children
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children
        ) == .success, let childArray = children as? [AXUIElement] else { return }

        for child in childArray {
            collectAllText(from: child, into: &texts, maxDepth: maxDepth, depth: depth + 1)
        }
    }

    // MARK: - Strategy 2: System-Wide Focused Element

    /// Use the system-wide focused element. Verifies it belongs to the expected app.
    /// Only returns content > minimumContentLength chars to skip UI strings.
    private func readSystemFocusedText(expectedPID: pid_t) -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            Self.debugLog("  system: could not get system-wide focused element")
            return nil
        }

        let element = focused as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        guard pid == expectedPID else {
            Self.debugLog("  system: PID mismatch — focused element belongs to different app")
            return nil
        }

        // Try direct value read — only accept substantial content
        if let text = textValue(of: element), text.count > Self.minimumContentLength {
            return text
        }

        // Try description
        if let desc = descriptionValue(of: element), desc.count > Self.minimumContentLength {
            return desc
        }

        return nil
    }

    // MARK: - Strategy 3: App-Level Focused Element

    /// Read text from the app's focused UI element.
    /// Only accept substantial content (> minimumContentLength chars).
    private func readFocusedElementText(_ axApp: AXUIElement) -> String? {
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }

        let element = focused as! AXUIElement

        if let text = textValue(of: element), text.count > Self.minimumContentLength {
            return text
        }

        return nil
    }

    // MARK: - Private: AX Attribute Helpers

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

    /// Read kAXDescriptionAttribute as String from an element.
    private func descriptionValue(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXDescriptionAttribute as CFString, &value
        ) == .success else { return nil }

        guard let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    /// Read kAXTitleAttribute as String from an element.
    private func titleValue(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXTitleAttribute as CFString, &value
        ) == .success else { return nil }

        guard let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    // MARK: - Debug Logging

    /// Write debug info to ~/Library/Logs/VOX-ax-debug.log
    /// Remove this after diagnosing the Cursor AX issue.
    static func debugLog(_ message: String) {
        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/VOX-ax-debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
}
