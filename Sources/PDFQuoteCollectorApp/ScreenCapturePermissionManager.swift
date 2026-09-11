import AppKit
import CoreGraphics

@MainActor
struct PermissionManager {
    var screenRecordingIsGranted: Bool { CGPreflightScreenCaptureAccess() }

    var screenRecordingStatusText: String {
        screenRecordingIsGranted ? "Granted" : "Not granted"
    }

    func ensurePermissionForExplicitCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // macOS itself suppresses repeated system prompts. Always ask the API
        // again so a permission granted after launch, or for a newly rebuilt
        // executable, is not blocked by stale app-owned UserDefaults state.
        if CGRequestScreenCaptureAccess() { return true }
        explainDenied()
        return false
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func explainDenied() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Needed"
        alert.informativeText = "Enable Screen Recording for PDF Quote Collector in System Settings, then quit and reopen the app. If it is already enabled after an app update, remove the old entry and add /Applications/PDF Quote Collector.app again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openScreenRecordingSettings() }
    }
}
