import AppKit
import PDFQuoteCollectorCore

@MainActor
final class ClipboardMonitor: NSObject {
    typealias Handler = @MainActor (String, SourceContext) -> ClipboardPipelineOutcome
    typealias StateProvider = @MainActor (SourceContext) -> ClipboardPipelineState?

    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var handler: Handler?
    private var stateProvider: StateProvider?
    private let sourceDetector = SourceContextDetector()
    private let diagnostics: ClipboardDiagnostics
    private var isRunning = false
    private var timerFireCount: UInt64 = 0
    private var observedChangeCount: Int
    private var previousObservedChangeCount: Int
    private var pendingChangeCount: Int?
    private var handledChangeCount: Int
    private var extractionAttemptCount = 0
    private var pendingSource: SourceContext?
    private let maximumExtractionAttempts = 8

    init(pasteboard: NSPasteboard = .general, diagnostics: ClipboardDiagnostics) {
        self.pasteboard = pasteboard
        self.diagnostics = diagnostics
        self.observedChangeCount = pasteboard.changeCount
        self.previousObservedChangeCount = pasteboard.changeCount
        self.handledChangeCount = pasteboard.changeCount
        super.init()
    }

    func start(
        stateProvider: @escaping StateProvider,
        handler: @escaping Handler
    ) {
        self.stateProvider = stateProvider
        self.handler = handler
        guard timer == nil else { return }
        let timer = Timer(
            timeInterval: 0.35,
            target: self,
            selector: #selector(pollPasteboard),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        diagnostics.updateStatus(status(currentChangeCount: pasteboard.changeCount))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        handler = nil
        stateProvider = nil
        isRunning = false
        diagnostics.updateStatus(status(currentChangeCount: pasteboard.changeCount))
    }

    @objc private func pollPasteboard() {
        timerFireCount &+= 1
        let currentChangeCount = pasteboard.changeCount

        if currentChangeCount != observedChangeCount {
            if let superseded = pendingChangeCount {
                finalize(
                    changeCount: superseded,
                    outcome: ClipboardPipelineOutcome(
                        captureEnabled: nil,
                        allowed: nil,
                        duplicateDecision: "not evaluated",
                        coordinatorInvoked: false,
                        storeInvoked: false,
                        persistenceResult: "not attempted",
                        finalResult: "rejected: superseded by a newer pasteboard generation"
                    )
                )
            }
            previousObservedChangeCount = observedChangeCount
            observedChangeCount = currentChangeCount
            pendingChangeCount = currentChangeCount
            extractionAttemptCount = 0
            pendingSource = sourceDetector.current()
        }

        diagnostics.updateStatus(status(currentChangeCount: currentChangeCount))
        guard pendingChangeCount == currentChangeCount,
              handledChangeCount != currentChangeCount else { return }

        extractionAttemptCount += 1
        let string = pasteboard.string(forType: .string)
        let readObjectString = (pasteboard.readObjects(
            forClasses: [NSString.self],
            options: nil
        )?.first as? String)
        let source = pendingSource ?? sourceDetector.current()
        let attempt = ClipboardExtractionAttempt(
            status: status(currentChangeCount: currentChangeCount),
            extractionAttemptCount: extractionAttemptCount,
            stringLength: string?.count,
            readObjectsLength: readObjectString?.count,
            source: source,
            pipelineState: stateProvider?(source)
        )
        diagnostics.recordAttempt(attempt)

        if let string, !string.isEmpty {
            let outcome = handler?(string, source) ?? ClipboardPipelineOutcome(
                captureEnabled: nil,
                allowed: nil,
                duplicateDecision: "not evaluated",
                coordinatorInvoked: false,
                storeInvoked: false,
                persistenceResult: "not attempted",
                finalResult: "rejected: no pipeline handler"
            )
            finalize(changeCount: currentChangeCount, outcome: outcome)
            return
        }

        let advertisesText = pasteboard.availableType(from: [.string]) == .string
        if !advertisesText || extractionAttemptCount >= maximumExtractionAttempts {
            finalize(
                changeCount: currentChangeCount,
                outcome: ClipboardPipelineOutcome(
                    captureEnabled: nil,
                    allowed: nil,
                    duplicateDecision: "not evaluated",
                    coordinatorInvoked: false,
                    storeInvoked: false,
                    persistenceResult: "not attempted",
                    finalResult: advertisesText
                        ? "rejected: text remained nil or empty after \(extractionAttemptCount) attempts"
                        : "rejected: pasteboard generation does not advertise plain text"
                )
            )
        }
    }

    private func finalize(changeCount: Int, outcome: ClipboardPipelineOutcome) {
        handledChangeCount = changeCount
        if pendingChangeCount == changeCount {
            pendingChangeCount = nil
            pendingSource = nil
        }
        diagnostics.recordOutcome(changeCount: changeCount, outcome: outcome)
        diagnostics.updateStatus(status(currentChangeCount: pasteboard.changeCount))
    }

    private func status(currentChangeCount: Int) -> ClipboardMonitorStatus {
        ClipboardMonitorStatus(
            isRunning: isRunning,
            timerFireCount: timerFireCount,
            currentChangeCount: currentChangeCount,
            previousObservedChangeCount: previousObservedChangeCount,
            pendingChangeCount: pendingChangeCount,
            handledChangeCount: handledChangeCount
        )
    }

}
