import Foundation

public enum CaptureCoordinatorError: Error, LocalizedError {
    case emptyText
    case recentDuplicate
    case captureNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyText: return "No text was available to save."
        case .recentDuplicate: return "This quotation was captured recently and was suppressed as a duplicate."
        case .captureNotFound: return "The capture could not be found for output status update."
        }
    }
}

public enum CaptureTransactionEvent: Sendable {
    case duplicateEvaluated(isDuplicate: Bool)
    case storeInvoked
    case persistenceSucceeded
    case persistenceFailed(message: String)
}

public enum CaptureOutput: Sendable {
    case markdown
    case word
}

/// Owns the canonical capture transaction. Its duplicate state is committed only
/// after durable storage succeeds, so a failed save can be retried safely.
public struct CaptureCoordinator {
    public private(set) var captures: [Capture] = []

    private let store: CaptureStore
    private let inputPolicy: CaptureInputPolicy
    private let cleaner: TextCleaner
    private var duplicateDetector: DuplicateDetector

    public init(
        store: CaptureStore,
        inputPolicy: CaptureInputPolicy = CaptureInputPolicy(),
        cleaner: TextCleaner = TextCleaner(),
        duplicateDetector: DuplicateDetector = DuplicateDetector()
    ) {
        self.store = store
        self.inputPolicy = inputPolicy
        self.cleaner = cleaner
        self.duplicateDetector = duplicateDetector
    }

    public mutating func load() throws {
        captures = try store.load()
    }

    public mutating func clearHistory() throws {
        try store.clear()
        captures = []
    }

    @discardableResult
    public mutating func accept(
        rawText: String,
        method: CaptureMethod,
        source: SourceContext?,
        duplicateSuppressionEnabled: Bool,
        now: Date = Date(),
        observer: ((CaptureTransactionEvent) -> Void)? = nil
    ) throws -> Capture {
        try inputPolicy.validate(rawText)
        let cleaned = cleaner.clean(rawText)
        guard !cleaned.isEmpty else { throw CaptureCoordinatorError.emptyText }

        var proposedDetector = duplicateDetector
        let shouldAccept = proposedDetector.shouldAccept(
            cleaned,
            at: now,
            isEnabled: duplicateSuppressionEnabled
        )
        observer?(.duplicateEvaluated(isDuplicate: !shouldAccept))
        guard shouldAccept else { throw CaptureCoordinatorError.recentDuplicate }

        let capture = Capture(
            rawText: rawText,
            cleanedText: cleaned,
            timestamp: now,
            captureMethod: method,
            sourceApplication: source?.application,
            sourceDocumentTitle: source?.documentTitle,
            sourceFilename: source?.filename,
            createdAt: now
        )
        observer?(.storeInvoked)
        let updated: [Capture]
        do {
            updated = try store.appending(capture, to: captures)
            observer?(.persistenceSucceeded)
        } catch {
            observer?(.persistenceFailed(message: error.localizedDescription))
            throw error
        }
        captures = updated
        duplicateDetector = proposedDetector
        return capture
    }

    public mutating func updateExportStatus(
        for captureID: UUID,
        output: CaptureOutput,
        status: ExportStatus,
        errorMessage: String? = nil
    ) throws {
        guard let index = captures.firstIndex(where: { $0.id == captureID }) else {
            throw CaptureCoordinatorError.captureNotFound
        }
        var updated = captures
        switch output {
        case .markdown:
            updated[index].markdownExportStatus = status
            updated[index].markdownExportError = errorMessage
        case .word:
            updated[index].wordExportStatus = status
            updated[index].wordExportError = errorMessage
        }
        try store.save(updated)
        captures = updated
    }

}
