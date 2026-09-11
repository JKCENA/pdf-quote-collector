import AppKit

@MainActor
final class OCRConfirmationPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var textView: NSTextView?
    private var onAdd: ((String) -> Bool)?
    private var onCancel: (() -> Void)?
    private var isCompleting = false

    func show(
        text: String,
        onAdd: @escaping (String) -> Bool,
        onCancel: @escaping () -> Void
    ) {
        closeWithoutCallback()
        self.onAdd = onAdd
        self.onCancel = onCancel

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 330),
            styleMask: [.titled, .closable, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Confirm OCR Text"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.minSize = NSSize(width: 420, height: 250)

        let textView = NSTextView(frame: .zero)
        textView.string = text
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancelButton.keyEquivalent = "\u{1b}"
        let addButton = NSButton(title: "Add", target: self, action: #selector(addPressed))
        addButton.keyEquivalent = "\r"
        addButton.keyEquivalentModifierMask = [.command]
        addButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [cancelButton, addButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .gravityAreas
        buttonRow.spacing = 10

        let content = NSStackView(views: [scrollView, buttonRow])
        content.orientation = .vertical
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        panel.contentView = content

        self.panel = panel
        self.textView = textView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func addPressed() {
        guard let text = textView?.string, let onAdd else { return }
        guard onAdd(text) else {
            NSSound.beep()
            return
        }
        isCompleting = true
        panel?.close()
        clear()
    }

    @objc private func cancelPressed() {
        isCompleting = true
        onCancel?()
        panel?.close()
        clear()
    }

    func windowWillClose(_ notification: Notification) {
        if !isCompleting { onCancel?() }
        clear()
    }

    private func closeWithoutCallback() {
        isCompleting = true
        panel?.close()
        clear()
    }

    private func clear() {
        panel = nil
        textView = nil
        onAdd = nil
        onCancel = nil
        isCompleting = false
    }
}

