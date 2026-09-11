import Foundation
import PDFQuoteCollectorCore

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private func testPasteboardEventGate() throws {
    var gate = PasteboardEventGate(initialChangeCount: 10)
    try expect(!gate.accept(changeCount: 10), "initial event must not be accepted")
    try expect(gate.accept(changeCount: 11), "new event must be accepted")
    try expect(!gate.accept(changeCount: 11), "event must not be accepted twice")
    try expect(gate.accept(changeCount: 12), "subsequent event must be accepted")
}

private func testAllowedApplicationFilter() throws {
    var applications = AllowedApplication.defaults
    let preview = SourceApplication(bundleIdentifier: "com.apple.Preview", displayName: "Preview")
    let textEdit = SourceApplication(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit")
    let unknown = SourceApplication(bundleIdentifier: nil, displayName: "Unknown")
    try expect(AllowedApplicationFilter(applications: applications).allows(preview), "Preview should be allowed")
    try expect(!AllowedApplicationFilter(applications: applications).allows(textEdit), "TextEdit should be blocked")
    try expect(!AllowedApplicationFilter(applications: applications).allows(unknown), "unknown bundle ID should be blocked")

    let index = applications.firstIndex { $0.bundleIdentifier == "com.apple.Preview" }!
    applications[index].isEnabled = false
    try expect(!AllowedApplicationFilter(applications: applications).allows(preview), "disabled Preview should be blocked")
}

private func testSourceDocumentParser() throws {
    let parser = SourceDocumentParser()
    let preview = SourceApplication(bundleIdentifier: "com.apple.Preview", displayName: "Preview")
    let previewContext = parser.context(application: preview, windowTitle: "Fearon_1991.pdf")
    try expect(previewContext.documentTitle == "Fearon_1991.pdf", "observed window title should be retained")
    try expect(previewContext.filename == "Fearon_1991.pdf", "unambiguous PDF title should become filename")

    let chrome = SourceApplication(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
    let chromeContext = parser.context(application: chrome, windowTitle: "Clarke_Primo_2012.pdf - Google Chrome")
    try expect(chromeContext.filename == "Clarke_Primo_2012.pdf", "known browser suffix may be removed")
    let ambiguous = parser.context(application: chrome, windowTitle: "Research portal - Google Chrome")
    try expect(ambiguous.filename == nil, "non-PDF browser title must not invent a filename")
}

private func testTextCleaner() throws {
    let cleaner = TextCleaner()
    try expect(cleaner.clean("treat-\nment") == "treatment", "hyphenated line split must be repaired")
    try expect(
        cleaner.clean("The causal effect\nof treatment\ncan be identified.") ==
            "The causal effect of treatment can be identified.",
        "PDF line wraps must be joined"
    )
    try expect(
        cleaner.clean("First paragraph.\n\nSecond paragraph.") ==
            "First paragraph.\n\nSecond paragraph.",
        "meaningful paragraph separation must survive"
    )
    try expect(
        cleaner.clean("  Smart\u{00A0}\u{2007}quotes “stay.”\t ") == "Smart quotes “stay.”",
        "Unicode whitespace should normalize without changing punctuation"
    )
    try expect(
        cleaner.clean("The causal effect of treat-\nment can be identified under the\nfollowing assumptions.") ==
            "The causal effect of treatment can be identified under the following assumptions.",
        "academic PDF example should clean conservatively"
    )
}

private func testDuplicateDetector() throws {
    var detector = DuplicateDetector(suppressionInterval: 10, capacity: 3)
    let start = Date(timeIntervalSince1970: 1_000)
    try expect(detector.shouldAccept("Same quote", at: start), "first quote should be accepted")
    try expect(!detector.shouldAccept("  Same\nquote  ", at: start.addingTimeInterval(1)), "whitespace-equivalent repeat should be suppressed")
    try expect(detector.shouldAccept("Different quote", at: start.addingTimeInterval(2)), "different text should be accepted")
    try expect(detector.shouldAccept("Same quote", at: start.addingTimeInterval(11)), "same quote should be accepted later")

    var disabled = DuplicateDetector()
    try expect(disabled.shouldAccept("Again", at: start, isEnabled: false), "first disabled capture should pass")
    try expect(disabled.shouldAccept("Again", at: start, isEnabled: false), "suppression setting should be honored")
}

private func testCapturePersistence() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PDFQuoteCollectorTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CaptureStore(fileURL: directory.appendingPathComponent("captures.json"))
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let capture = Capture(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        rawText: "treat-\nment",
        cleanedText: "treatment",
        timestamp: date,
        captureMethod: .clipboard,
        sourceApplication: SourceApplication(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
        sourceDocumentTitle: nil,
        sourceFilename: nil,
        pageNumber: nil,
        createdAt: date
    )

    let updated = try store.appending(capture, to: [])
    try expect(updated == [capture], "append should return durable collection")
    let loaded = try store.load()
    try expect(loaded == [capture], "capture should survive a fresh load")
    try expect(capture.sourceFilename == nil && capture.pageNumber == nil, "unknown metadata must remain nil")
}

private func testCaptureHistoryClear() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PDFQuoteCollectorClearTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("captures.json")
    let store = CaptureStore(fileURL: fileURL)
    let capture = Capture(
        rawText: "Session-only quotation",
        cleanedText: "Session-only quotation",
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        captureMethod: .clipboard,
        sourceApplication: nil,
        sourceDocumentTitle: nil,
        sourceFilename: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    _ = try store.appending(capture, to: [])
    try expect(FileManager.default.fileExists(atPath: fileURL.path), "capture file should exist before clearing")
    try store.clear()
    try expect(!FileManager.default.fileExists(atPath: fileURL.path), "clear should remove captures.json")
    let clearedCaptures = try store.load()
    try expect(clearedCaptures.isEmpty, "a cleared store should load as empty")

    // Clearing an already-empty store is intentionally idempotent.
    try store.clear()
}

private func testCaptureStoreFailureDoesNotPretendToAppend() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PDFQuoteCollectorStoreFailure-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blockingFile = directory.appendingPathComponent("not-a-directory")
    try Data("block".utf8).write(to: blockingFile)
    let store = CaptureStore(fileURL: blockingFile.appendingPathComponent("captures.json"))
    let capture = Capture(rawText: "Safe", cleanedText: "Safe", captureMethod: .clipboard)
    do {
        _ = try store.appending(capture, to: [])
        throw TestFailure(description: "unwritable store should fail")
    } catch is TestFailure {
        throw TestFailure(description: "unwritable store should fail")
    } catch {
        try expect(!FileManager.default.fileExists(atPath: store.fileURL.path), "failed append must not create a partial capture file")
    }
}

private func testMarkdownOutput() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PDFQuoteCollectorOutputTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("Reading Notes.md")
    try Data().write(to: url)
    let service = MarkdownOutputService()
    let first = Capture(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        rawText: "첫 번째 — café",
        cleanedText: "첫 번째 — café",
        captureMethod: .clipboard
    )
    let second = Capture(
        id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        rawText: "Second",
        cleanedText: "Second",
        captureMethod: .ocr
    )

    let firstResult = try service.append(capture: first, to: url, blankLines: 1)
    guard case .appended = firstResult else {
        throw TestFailure(description: "first Markdown output should append")
    }
    let afterFirst = try String(contentsOf: url, encoding: .utf8)
    try expect(afterFirst.contains("첫 번째 — café"), "Markdown append must preserve Unicode")
    try expect(
        afterFirst.contains("pdf-quote-collector:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        "Markdown append should persist its capture idempotency marker"
    )

    let duplicateResult = try service.append(capture: first, to: url, blankLines: 1)
    guard case .alreadyPresent = duplicateResult else {
        throw TestFailure(description: "retrying the same capture should be idempotent")
    }
    let afterDuplicate = try Data(contentsOf: url)
    try expect(
        afterDuplicate == Data(afterFirst.utf8),
        "retrying Markdown must not duplicate or rewrite the file"
    )

    try service.append(capture: second, to: url, style: .quotationMarks, blankLines: 2)
    let final = try String(contentsOf: url, encoding: .utf8)
    try expect(final.contains("“Second”"), "quotation-mark style should be applied")
    try expect(
        final.contains("-->\n\n\n“Second”"),
        "configured blank lines should separate Markdown quotation blocks"
    )

    let missing = directory.appendingPathComponent("Missing.md")
    do {
        try service.append(capture: first, to: missing)
        throw TestFailure(description: "missing Markdown destination should fail")
    } catch MarkdownOutputError.destinationMissing {
        // Expected. The independent Word exporter may still proceed.
    }
}

private func testOutputFormatting() throws {
    let formatter = NotesFormatter()
    try expect(formatter.format("First") == "First", "default format should preserve cleaned text")
    try expect(
        formatter.format("First\nSecond", style: .bulletList) == "- First\n  Second",
        "Markdown bullet style should indent continuation lines"
    )
    try expect(
        formatter.format("First", style: .quotationMarks) == "“First”",
        "quotation style should wrap the cleaned quotation"
    )
}

private func testScreenCoordinateConversion() throws {
    let converted = ScreenCoordinateConverter().coreGraphicsRect(
        localSelection: CGRect(x: 10, y: 20, width: 100, height: 40),
        screenSize: CGSize(width: 800, height: 600),
        displayOrigin: CGPoint(x: 800, y: 0)
    )
    try expect(converted == CGRect(x: 810, y: 540, width: 100, height: 40), "selection coordinates should flip vertically within its display")
}

private func testOCRLineReconstruction() throws {
    let lines = [
        OCRLine(text: "right", bounds: CGRect(x: 0.6, y: 0.8, width: 0.3, height: 0.05)),
        OCRLine(text: "second line", bounds: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.05)),
        OCRLine(text: "left", bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.05))
    ]
    try expect(
        OCRLineReconstructor().reconstruct(lines) == "left\nright\nsecond line",
        "OCR lines should reconstruct top-to-bottom and left-to-right"
    )
}

private func testSettingsPersistence() throws {
    let suiteName = "PDFQuoteCollectorTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "could not create defaults suite")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)
    var settings = AppSettings()
    settings.captureEnabled = false
    settings.saveToMarkdown = false
    settings.saveToWord = true
    settings.automaticallyOpenWord = true
    settings.ocrShortcut = ShortcutConfiguration(key: "K", modifiers: [.command, .option])
    settings.outputStyle = .bulletList
    settings.blankLinesBetweenQuotes = 3
    settings.allowedApplications[0].isEnabled = false
    try store.save(settings)
    try expect(store.load() == settings, "settings should survive a fresh load")

    defaults.set(Data("corrupt".utf8), forKey: "appSettings")
    try expect(store.load() == AppSettings(), "corrupt settings should fall back to safe defaults")
}

private func testCaptureInputPolicy() throws {
    let policy = CaptureInputPolicy(maximumCharacterCount: 5)
    try policy.validate("12345")
    do {
        try policy.validate("123456")
        throw TestFailure(description: "oversized capture should be rejected")
    } catch CaptureInputError.tooLarge(let limit) {
        try expect(limit == 5, "size error should report configured bound")
    }
}

private func testCaptureCoordinatorTransaction() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PDFQuoteCollectorCoordinator-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CaptureStore(fileURL: directory.appendingPathComponent("captures.json"))
    var coordinator = CaptureCoordinator(store: store)
    try coordinator.load()
    let now = Date(timeIntervalSince1970: 1234)
    let source = SourceContext(
        application: SourceApplication(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
        documentTitle: "Paper.pdf",
        filename: "Paper.pdf"
    )
    let capture = try coordinator.accept(
        rawText: "treat-\nment",
        method: .clipboard,
        source: source,
        duplicateSuppressionEnabled: true,
        now: now
    )
    try expect(capture.cleanedText == "treatment", "coordinator should run cleanup")
    try expect(capture.markdownExportStatus == .pending, "new Markdown output should begin pending")
    try expect(capture.wordExportStatus == .pending, "new Word output should begin pending")
    try expect(coordinator.captures.count == 1, "coordinator should update only after durable save")
    try coordinator.updateExportStatus(for: capture.id, output: .markdown, status: .exported)
    try coordinator.updateExportStatus(
        for: capture.id,
        output: .word,
        status: .failed,
        errorMessage: "automation denied"
    )
    var reloaded = CaptureCoordinator(store: store)
    try reloaded.load()
    try expect(reloaded.captures[0].markdownExportStatus == .exported, "Markdown status should persist")
    try expect(reloaded.captures[0].wordExportStatus == .failed, "Word status should persist independently")
    try expect(reloaded.captures[0].wordExportError == "automation denied", "Word failure should remain retryable")
    do {
        _ = try coordinator.accept(
            rawText: "treatment",
            method: .clipboard,
            source: source,
            duplicateSuppressionEnabled: true,
            now: now.addingTimeInterval(1)
        )
        throw TestFailure(description: "coordinator should suppress recent duplicate")
    } catch CaptureCoordinatorError.recentDuplicate {
        try expect(coordinator.captures.count == 1, "duplicate must not alter canonical captures")
    }
    try coordinator.clearHistory()
    try expect(coordinator.captures.isEmpty, "coordinator clear should empty in-memory history")
    try expect(!FileManager.default.fileExists(atPath: store.fileURL.path), "coordinator clear should remove canonical history")
}

let tests: [(String, () throws -> Void)] = [
    ("pasteboard event gate", testPasteboardEventGate),
    ("allowed application filter", testAllowedApplicationFilter),
    ("source document parser", testSourceDocumentParser),
    ("text cleaner", testTextCleaner),
    ("duplicate detector", testDuplicateDetector),
    ("capture persistence", testCapturePersistence),
    ("capture history clear", testCaptureHistoryClear),
    ("capture store failure", testCaptureStoreFailureDoesNotPretendToAppend),
    ("Markdown output", testMarkdownOutput),
    ("output formatting", testOutputFormatting),
    ("screen coordinate conversion", testScreenCoordinateConversion),
    ("OCR line reconstruction", testOCRLineReconstruction),
    ("settings persistence", testSettingsPersistence),
    ("capture input policy", testCaptureInputPolicy),
    ("capture coordinator transaction", testCaptureCoordinatorTransaction)
]

var failures = 0
for (name, test) in tests {
    do {
        try test()
        print("PASS: \(name)")
    } catch {
        failures += 1
        print("FAIL: \(name): \(error)")
    }
}

if failures > 0 {
    print("\(failures) test(s) failed")
    exit(1)
}
print("All \(tests.count) tests passed")
