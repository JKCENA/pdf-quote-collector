import AppKit
import CoreGraphics
import PDFQuoteCollectorCore

@MainActor
struct SourceContextDetector {
    func current() -> SourceContext {
        let application = NSWorkspace.shared.frontmostApplication
        let sourceApplication = SourceApplication(
            bundleIdentifier: application?.bundleIdentifier,
            displayName: application?.localizedName
        )
        let windowTitle = application.flatMap { frontmostWindowTitle(processIdentifier: $0.processIdentifier) }
        return SourceDocumentParser().context(application: sourceApplication, windowTitle: windowTitle)
    }

    private func frontmostWindowTitle(processIdentifier: pid_t) -> String? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        return windows.first { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == processIdentifier &&
                (info[kCGWindowLayer as String] as? Int) == 0
        }?[kCGWindowName as String] as? String
    }
}
