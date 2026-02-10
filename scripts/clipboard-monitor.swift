#!/usr/bin/env swift
// clipboard-monitor.swift — Debug tool to watch clipboard changes in real-time.
// Run this while using Hex to see if VOX can detect Hex transcriptions.
// Usage: swift scripts/clipboard-monitor.swift

import AppKit
import Foundation

let hexBundleID = "com.kitlangton.Hex"
var lastChangeCount = NSPasteboard.general.changeCount
var lastContent = NSPasteboard.general.string(forType: .string) ?? ""

// Check Hex status
let hexRunning = NSRunningApplication.runningApplications(withBundleIdentifier: hexBundleID).first != nil
print("=== VOX Clipboard Monitor ===")
print("Hex running: \(hexRunning)")
print("Hex bundle ID: \(hexBundleID)")
print("Initial clipboard changeCount: \(lastChangeCount)")
print("Initial clipboard content: \"\(lastContent.prefix(80))\"")
print("---")
print("Monitoring clipboard... Use Hex to dictate something.")
print("Press Ctrl+C to stop.\n")

// Poll clipboard every 100ms
let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    let pasteboard = NSPasteboard.general
    let currentCount = pasteboard.changeCount

    guard currentCount != lastChangeCount else { return }

    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let content = pasteboard.string(forType: .string) ?? "(nil)"
    let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "none"

    // Check Hex status at time of change
    let hexNow = NSRunningApplication.runningApplications(withBundleIdentifier: hexBundleID).first != nil

    // Heuristic check (same as VOX HexBridge)
    let isLikelyTranscription: Bool = {
        guard content.count < 1000 else { return false }
        let codeIndicators = ["func ", "import ", "class ", "http://", "https://", "```", "->"]
        for indicator in codeIndicators {
            if content.contains(indicator) { return false }
        }
        let alphanumericCount = content.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }.count
        let ratio = Double(alphanumericCount) / Double(max(content.count, 1))
        return ratio > 0.7
    }()

    print("[\(timestamp)] CLIPBOARD CHANGED")
    print("  changeCount: \(lastChangeCount) → \(currentCount)")
    print("  content: \"\(content.prefix(200))\"")
    print("  content length: \(content.count)")
    print("  types: \(types)")
    print("  Hex running: \(hexNow)")
    print("  isLikelyTranscription: \(isLikelyTranscription)")
    print("  same as previous: \(content == lastContent)")
    print("")

    lastChangeCount = currentCount
    lastContent = content
}

RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
