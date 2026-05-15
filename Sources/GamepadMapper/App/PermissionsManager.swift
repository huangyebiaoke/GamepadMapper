import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class PermissionsManager {
    static let shared = PermissionsManager()

    var hasAccessibilityPermission = false

    private init() {
        checkPermission()
    }

    func checkPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    /// Opens the Accessibility pane in System Settings.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Requests accessibility permission. Shows a prompt if not yet granted.
    @discardableResult
    func requestPermission() -> Bool {
        if hasAccessibilityPermission { return true }

        let promptKey = String(describing: kAXTrustedCheckOptionPrompt.takeUnretainedValue())
        let options: NSDictionary = [promptKey: true]
        let granted = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = granted
        return granted
    }
}
