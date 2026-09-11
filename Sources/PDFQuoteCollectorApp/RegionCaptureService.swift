import AppKit
import CoreGraphics
import PDFQuoteCollectorCore

@MainActor
final class RegionCaptureService {
    enum CaptureError: LocalizedError {
        case invalidDisplay
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .invalidDisplay: return "The selected display could not be identified."
            case .captureFailed: return "macOS could not capture the selected region."
            }
        }
    }

    private var controllers: [NSWindowController] = []
    private var completion: ((Result<CGImage, Error>) -> Void)?

    func begin(completion: @escaping (Result<CGImage, Error>) -> Void) {
        cancel()
        self.completion = completion
        NSApp.activate(ignoringOtherApps: true)
        controllers = NSScreen.screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = NSColor.black.withAlphaComponent(0.16)
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onCancel = { [weak self] in self?.cancel() }
            view.onSelection = { [weak self, weak screen] rect in
                guard let self, let screen else { return }
                self.finish(selection: rect, on: screen)
            }
            window.contentView = view
            let controller = NSWindowController(window: window)
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            return controller
        }
        NSCursor.crosshair.push()
    }

    func cancel() {
        guard !controllers.isEmpty || completion != nil else { return }
        closeOverlays()
        completion = nil
    }

    private func finish(selection: CGRect, on screen: NSScreen) {
        guard selection.width >= 3, selection.height >= 3 else {
            cancel()
            return
        }
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            complete(.failure(CaptureError.invalidDisplay))
            return
        }
        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        let displayBounds = CGDisplayBounds(displayID)
        let captureRect = ScreenCoordinateConverter().coreGraphicsRect(
            localSelection: selection,
            screenSize: screen.frame.size,
            displayOrigin: displayBounds.origin
        )
        closeOverlays()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let image = CGWindowListCreateImage(
                captureRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                self.complete(.failure(CaptureError.captureFailed))
                return
            }
            self.complete(.success(image))
        }
    }

    private func complete(_ result: Result<CGImage, Error>) {
        let callback = completion
        completion = nil
        callback?(result)
    }

    private func closeOverlays() {
        controllers.forEach { $0.close() }
        if !controllers.isEmpty { NSCursor.pop() }
        controllers.removeAll()
    }
}

private final class RegionSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect else { onCancel?(); return }
        onSelection?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = selectionRect else { return }
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }
}
