import AppKit
import Foundation
import PDFQuoteCollectorCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    let diagnostics = ClipboardDiagnostics()
    @Published var isCaptureEnabled = true {
        didSet { saveSettings() }
    }
    @Published private(set) var captures: [Capture] = []
    @Published private(set) var sessionCaptureCount = 0
    @Published private(set) var lastErrorMessage: String?
    @Published var saveToMarkdown = true {
        didSet { saveSettings() }
    }
    @Published private(set) var markdownURL: URL?
    @Published var saveToWord = true {
        didSet { saveSettings() }
    }
    @Published private(set) var wordURL: URL?
    @Published var automaticallyOpenWord = false {
        didSet { saveSettings() }
    }
    @Published var allowedApplications: [AllowedApplication] {
        didSet { saveSettings() }
    }
    @Published var duplicateSuppressionEnabled: Bool {
        didSet { saveSettings() }
    }
    @Published var shortcutConfiguration: ShortcutConfiguration {
        didSet {
            saveSettings()
            if hasStarted { registerShortcut() }
        }
    }
    @Published var outputStyle: OutputStyle {
        didSet { saveSettings() }
    }
    @Published var blankLinesBetweenQuotes: Int {
        didSet {
            let clamped = min(max(blankLinesBetweenQuotes, 0), 3)
            if blankLinesBetweenQuotes != clamped {
                blankLinesBetweenQuotes = clamped
                return
            }
            saveSettings()
        }
    }

    private lazy var clipboardMonitor = ClipboardMonitor(diagnostics: diagnostics)
    private var hasStarted = false
    private let settingsStore: SettingsStore
    private var captureCoordinator: CaptureCoordinator
    private var markdownDestinationBookmark: Data?
    private var wordDestinationBookmark: Data?
    private let markdownOutputService = MarkdownOutputService()
    private let wordOutputService = WordOutputService()
    private let shortcutRegistrar = GlobalShortcutRegistrar()
    private let permissionManager = PermissionManager()
    private let regionCaptureService = RegionCaptureService()
    private let ocrService = OCRService()
    private let ocrConfirmation = OCRConfirmationPanelController()
    private var pendingOCRSource: SourceContext?

    init(defaults: UserDefaults = .standard, captureStore: CaptureStore? = nil) {
        let settingsStore = SettingsStore(defaults: defaults)
        let settings = settingsStore.load()
        self.settingsStore = settingsStore
        self.captureCoordinator = CaptureCoordinator(store: captureStore ?? Self.defaultCaptureStore())
        self.isCaptureEnabled = settings.captureEnabled
        self.saveToMarkdown = settings.saveToMarkdown
        self.saveToWord = settings.saveToWord
        self.automaticallyOpenWord = settings.automaticallyOpenWord
        self.duplicateSuppressionEnabled = settings.duplicateSuppressionEnabled
        self.shortcutConfiguration = settings.ocrShortcut
        self.outputStyle = settings.outputStyle
        self.blankLinesBetweenQuotes = settings.blankLinesBetweenQuotes
        self.allowedApplications = settings.allowedApplications
        self.markdownDestinationBookmark = settings.markdownDestinationBookmark
        self.wordDestinationBookmark = settings.wordDestinationBookmark
        // Capture history is session-scoped. Clear any recovery file left by a
        // previous build, force quit, crash, or power loss before monitoring.
        do {
            try self.captureCoordinator.clearHistory()
            self.captures = []
        } catch {
            self.lastErrorMessage = "Could not start a fresh capture session: \(error.localizedDescription)"
        }
        self.markdownURL = Self.resolveTargetBookmark(from: settings.markdownDestinationBookmark)
        self.wordURL = Self.resolveTargetBookmark(from: settings.wordDestinationBookmark)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        clipboardMonitor.start(
            stateProvider: { [weak self] source in
                self?.clipboardPipelineState(for: source)
            },
            handler: { [weak self] text, source in
                guard let self else {
                    return ClipboardPipelineOutcome(
                        captureEnabled: nil,
                        allowed: nil,
                        duplicateDecision: "not evaluated",
                        coordinatorInvoked: false,
                        storeInvoked: false,
                        persistenceResult: "not attempted",
                        finalResult: "rejected: application model unavailable"
                    )
                }
                return self.handleClipboardText(text, source: source)
            }
        )
        registerShortcut()
        if ProcessInfo.processInfo.arguments.contains("--show-diagnostics") {
            DiagnosticsWindowPresenter.shared.show(diagnostics: diagnostics)
        }
    }

    /// Called by the application delegate during a normal app termination.
    /// This clears only the local capture history; Markdown and Word output
    /// files remain unchanged.
    func clearCaptureHistoryForTermination() {
        clipboardMonitor.stop()
        do {
            try captureCoordinator.clearHistory()
            captures = []
            sessionCaptureCount = 0
        } catch {
            lastErrorMessage = "Could not clear capture history: \(error.localizedDescription)"
        }
    }

    private func handleClipboardText(
        _ text: String,
        source: SourceContext
    ) -> ClipboardPipelineOutcome {
        let state = clipboardPipelineState(for: source)
        let captureEnabled = state.captureEnabled
        guard captureEnabled else {
            return ClipboardPipelineOutcome(
                captureEnabled: false,
                allowed: state.allowed,
                duplicateDecision: "not evaluated",
                coordinatorInvoked: false,
                storeInvoked: false,
                persistenceResult: "not attempted",
                finalResult: "rejected: capture is disabled"
            )
        }

        let allowed = state.allowed
        guard allowed else {
            return ClipboardPipelineOutcome(
                captureEnabled: true,
                allowed: false,
                duplicateDecision: "not evaluated",
                coordinatorInvoked: false,
                storeInvoked: false,
                persistenceResult: "not attempted",
                finalResult: "rejected: foreground application is not enabled"
            )
        }

        var trace = ClipboardCaptureTrace()
        let saved = saveCandidate(
            rawText: text,
            method: .clipboard,
            source: source
        ) { event in
            trace.record(event)
        }
        let duplicateDecision: String
        if duplicateSuppressionEnabled {
            duplicateDecision = trace.isDuplicate.map(String.init) ?? "not evaluated"
        } else {
            duplicateDecision = "false (suppression disabled)"
        }
        return ClipboardPipelineOutcome(
            captureEnabled: true,
            allowed: true,
            duplicateDecision: duplicateDecision,
            coordinatorInvoked: true,
            storeInvoked: trace.storeInvoked,
            persistenceResult: trace.persistenceResult,
            finalResult: saved ? "accepted" : "rejected: \(lastErrorMessage ?? "unknown pipeline error")"
        )
    }

    private func clipboardPipelineState(for source: SourceContext) -> ClipboardPipelineState {
        ClipboardPipelineState(
            captureEnabled: isCaptureEnabled,
            allowed: AllowedApplicationFilter(applications: allowedApplications).allows(source.application)
        )
    }

    func beginOCRCapture() {
        guard permissionManager.ensurePermissionForExplicitCapture() else {
            lastErrorMessage = "OCR capture requires Screen Recording permission."
            return
        }
        lastErrorMessage = nil
        pendingOCRSource = SourceContextDetector().current()
        regionCaptureService.begin { [weak self] result in
            switch result {
            case .success(let image):
                self?.recognizeCapturedRegion(image)
            case .failure(let error):
                self?.lastErrorMessage = error.localizedDescription
            }
        }
    }

    var screenRecordingStatusText: String { permissionManager.screenRecordingStatusText }

    func openScreenRecordingSettings() {
        permissionManager.openScreenRecordingSettings()
    }

    private func recognizeCapturedRegion(_ image: CGImage) {
        lastErrorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await ocrService.recognize(image)
                showOCRConfirmation(text)
            } catch {
                lastErrorMessage = "OCR failed: \(error.localizedDescription)"
            }
        }
    }

    private func showOCRConfirmation(_ text: String) {
        let source = pendingOCRSource
        ocrConfirmation.show(
            text: text,
            onAdd: { [weak self] editedText in
                guard let self else { return false }
                let saved = self.saveCandidate(rawText: editedText, method: .ocr, source: source)
                if saved { self.pendingOCRSource = nil }
                return saved
            },
            onCancel: { [weak self] in self?.pendingOCRSource = nil }
        )
    }

    @discardableResult
    private func saveCandidate(
        rawText: String,
        method: CaptureMethod,
        source: SourceContext?,
        observer: ((CaptureTransactionEvent) -> Void)? = nil
    ) -> Bool {
        let acceptedCapture: Capture
        do {
            acceptedCapture = try captureCoordinator.accept(
                rawText: rawText,
                method: method,
                source: source,
                duplicateSuppressionEnabled: duplicateSuppressionEnabled,
                observer: observer
            )
            captures = captureCoordinator.captures
            sessionCaptureCount += 1
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Quotation was not saved: \(error.localizedDescription)"
            return false
        }
        attemptOutputs(for: acceptedCapture.id)
        return true
    }

    var markdownDisplayName: String {
        markdownURL?.lastPathComponent ?? "Not selected"
    }

    var wordDisplayName: String {
        wordURL?.lastPathComponent ?? "Not selected"
    }

    var pendingMarkdownCount: Int {
        captures.filter { $0.markdownExportStatus != .exported }.count
    }

    var pendingWordCount: Int {
        captures.filter { $0.wordExportStatus != .exported }.count
    }

    func chooseMarkdownDestination() {
        let panel = NSSavePanel()
        panel.title = "Choose Markdown Notes"
        panel.nameFieldStringValue = markdownURL?.lastPathComponent ?? "Reading Notes.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.setMarkdownDestination(url)
            }
        }
    }

    func chooseWordDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Microsoft Word Document"
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.setWordDestination(url)
            }
        }
    }

    func retryFailedOutputs() {
        retryOutputs(markdown: true, word: true)
    }

    func retryMarkdownOutput() {
        retryOutputs(markdown: true, word: false)
    }

    func retryWordOutput() {
        retryOutputs(markdown: false, word: true)
    }

    private func retryOutputs(markdown: Bool, word: Bool) {
        let captureIDs = captures.map(\.id)
        var messages: [String] = []
        for captureID in captureIDs {
            guard let capture = captureCoordinator.captures.first(where: { $0.id == captureID }) else { continue }
            if markdown, saveToMarkdown, capture.markdownExportStatus != .exported,
               let message = attemptMarkdownOutput(for: captureID) {
                messages.append(message)
            }
            guard let refreshed = captureCoordinator.captures.first(where: { $0.id == captureID }) else { continue }
            if word, saveToWord, refreshed.wordExportStatus != .exported,
               let message = attemptWordOutput(for: captureID) {
                messages.append(message)
            }
        }
        captures = captureCoordinator.captures
        lastErrorMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private func attemptOutputs(for captureID: UUID) {
        var messages: [String] = []
        if saveToMarkdown, let message = attemptMarkdownOutput(for: captureID) {
            messages.append(message)
        }
        if saveToWord, let message = attemptWordOutput(for: captureID) {
            messages.append(message)
        }
        captures = captureCoordinator.captures
        lastErrorMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private func attemptMarkdownOutput(for captureID: UUID) -> String? {
        guard let capture = captureCoordinator.captures.first(where: { $0.id == captureID }) else {
            return "Markdown output failed: capture not found."
        }
        guard let markdownURL else {
            return persistOutputState(
                captureID: captureID,
                output: .markdown,
                status: .pending,
                message: "Markdown destination is not selected."
            )
        }

        do {
            _ = try withSecurityScopedAccess(to: markdownURL) {
                try markdownOutputService.append(
                    capture: capture,
                    to: markdownURL,
                    style: outputStyle,
                    blankLines: blankLinesBetweenQuotes
                )
            }
            return persistOutputState(
                captureID: captureID,
                output: .markdown,
                status: .exported,
                message: nil
            )
        } catch {
            let message = error.localizedDescription
            _ = persistOutputState(
                captureID: captureID,
                output: .markdown,
                status: .failed,
                message: message
            )
            return "Markdown output failed: \(message)"
        }
    }

    private func attemptWordOutput(for captureID: UUID) -> String? {
        guard let capture = captureCoordinator.captures.first(where: { $0.id == captureID }) else {
            return "Word output failed: capture not found."
        }
        guard let wordURL else {
            return persistOutputState(
                captureID: captureID,
                output: .word,
                status: .pending,
                message: "Word destination is not selected."
            )
        }

        do {
            let result = try withSecurityScopedAccess(to: wordURL) {
                try wordOutputService.append(
                    capture: capture,
                    to: wordURL,
                    style: outputStyle,
                    blankLines: blankLinesBetweenQuotes,
                    automaticallyOpenWord: automaticallyOpenWord
                )
            }
            switch result {
            case .exported, .alreadyPresent:
                return persistOutputState(
                    captureID: captureID,
                    output: .word,
                    status: .exported,
                    message: nil
                )
            case .pending(let reason):
                return persistOutputState(
                    captureID: captureID,
                    output: .word,
                    status: .pending,
                    message: reason
                )
            }
        } catch {
            let message = error.localizedDescription
            _ = persistOutputState(
                captureID: captureID,
                output: .word,
                status: .failed,
                message: message
            )
            return "Word output failed: \(message)"
        }
    }

    private func persistOutputState(
        captureID: UUID,
        output: CaptureOutput,
        status: ExportStatus,
        message: String?
    ) -> String? {
        do {
            try captureCoordinator.updateExportStatus(
                for: captureID,
                output: output,
                status: status,
                errorMessage: message
            )
            captures = captureCoordinator.captures
            return status == .exported ? nil : message
        } catch {
            return "Could not persist output status: \(error.localizedDescription)"
        }
    }

    func updateShortcutKey(_ value: String) {
        let letters = value.uppercased().filter { $0.isLetter }
        guard let last = letters.last else { return }
        shortcutConfiguration.key = String(last)
    }

    func setShortcutModifier(_ modifier: ShortcutModifiers, enabled: Bool) {
        if enabled {
            shortcutConfiguration.modifiers.insert(modifier)
        } else {
            shortcutConfiguration.modifiers.remove(modifier)
        }
    }

    func shortcutContains(_ modifier: ShortcutModifiers) -> Bool {
        shortcutConfiguration.modifiers.contains(modifier)
    }

    private func saveSettings() {
        let settings = AppSettings(
            captureEnabled: isCaptureEnabled,
            saveToMarkdown: saveToMarkdown,
            markdownDestinationBookmark: markdownDestinationBookmark,
            saveToWord: saveToWord,
            wordDestinationBookmark: wordDestinationBookmark,
            automaticallyOpenWord: automaticallyOpenWord,
            ocrShortcut: shortcutConfiguration,
            allowedApplications: allowedApplications,
            duplicateSuppressionEnabled: duplicateSuppressionEnabled,
            outputStyle: outputStyle,
            blankLinesBetweenQuotes: blankLinesBetweenQuotes
        )
        do {
            try settingsStore.save(settings)
        } catch {
            lastErrorMessage = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func setMarkdownDestination(_ url: URL) {
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .atomic)
            }
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            markdownDestinationBookmark = bookmark
            markdownURL = url
            saveSettings()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Could not configure Markdown output: \(error.localizedDescription)"
        }
    }

    private func setWordDestination(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            wordDestinationBookmark = bookmark
            wordURL = url
            saveSettings()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Could not configure Word output: \(error.localizedDescription)"
        }
    }

    private func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    private func registerShortcut() {
        do {
            try shortcutRegistrar.register(shortcutConfiguration) { [weak self] in self?.beginOCRCapture() }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private static func resolveTargetBookmark(from data: Data?) -> URL? {
        guard let data else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    private static func defaultCaptureStore() -> CaptureStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return CaptureStore(
            fileURL: base
                .appendingPathComponent("PDF Quote Collector", isDirectory: true)
                .appendingPathComponent("captures.json")
        )
    }
}

private struct ClipboardCaptureTrace {
    var isDuplicate: Bool?
    var storeInvoked = false
    var persistenceResult = "not attempted"

    mutating func record(_ event: CaptureTransactionEvent) {
        switch event {
        case .duplicateEvaluated(let isDuplicate):
            self.isDuplicate = isDuplicate
        case .storeInvoked:
            storeInvoked = true
        case .persistenceSucceeded:
            persistenceResult = "success"
        case .persistenceFailed(let message):
            persistenceResult = "failure: \(message)"
        }
    }
}
