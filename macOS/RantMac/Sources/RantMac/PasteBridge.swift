import AppKit
import ApplicationServices
import CoreGraphics

enum PasteBridge {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @MainActor
    static func paste(_ text: String, into bundleID: String?) async -> Bool {
        copy(text)
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier,
              AXIsProcessTrusted() else { return false }
        guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        guard target.activate(options: []) else { return false }
        try? await Task.sleep(for: .milliseconds(300))
        guard !target.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
