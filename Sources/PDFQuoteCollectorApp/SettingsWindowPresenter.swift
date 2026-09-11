import AppKit
import SwiftUI

/// Ventura fallback for presenting settings from an LSUIElement menu-bar app.
/// The retained controller ensures repeated menu actions focus one window.
@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var windowController: NSWindowController?

    private init() {}

    func show(model: AppModel) {
        let controller: NSWindowController
        if let existing = windowController {
            controller = existing
        } else {
            let hostingController = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "PDF Quote Collector Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 700))
            window.minSize = NSSize(width: 520, height: 620)
            window.isReleasedWhenClosed = false
            window.center()
            controller = NSWindowController(window: window)
            windowController = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        if controller.window?.isMiniaturized == true {
            controller.window?.deminiaturize(nil)
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
    }
}

@available(macOS 14.0, *)
struct ModernSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
            // Accessory apps have no Dock activation to raise their window. Run
            // once more after SwiftUI creates or reuses the Settings scene.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.keyWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }
}
