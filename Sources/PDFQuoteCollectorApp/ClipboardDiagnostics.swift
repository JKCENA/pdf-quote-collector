import AppKit
import Foundation
import PDFQuoteCollectorCore
import SwiftUI

struct ClipboardMonitorStatus: Sendable {
    let isRunning: Bool
    let timerFireCount: UInt64
    let currentChangeCount: Int
    let previousObservedChangeCount: Int
    let pendingChangeCount: Int?
    let handledChangeCount: Int
}

struct ClipboardExtractionAttempt: Sendable {
    let status: ClipboardMonitorStatus
    let extractionAttemptCount: Int
    let stringLength: Int?
    let readObjectsLength: Int?
    let source: SourceContext
    let pipelineState: ClipboardPipelineState?
}

struct ClipboardPipelineState: Sendable {
    let captureEnabled: Bool
    let allowed: Bool
}

struct ClipboardPipelineOutcome: Sendable {
    let captureEnabled: Bool?
    let allowed: Bool?
    let duplicateDecision: String
    let coordinatorInvoked: Bool
    let storeInvoked: Bool
    let persistenceResult: String
    let finalResult: String
}

struct ClipboardGenerationDiagnostic: Identifiable, Sendable {
    var id: Int { changeCount }
    let changeCount: Int
    let monitorRunning: Bool
    let timerFireCount: UInt64
    let currentChangeCount: Int
    let previousObservedChangeCount: Int
    var pendingChangeCount: Int?
    var extractionAttemptCount = 0
    var stringLength: Int?
    var readObjectsLength: Int?
    var foregroundApplicationName: String?
    var foregroundBundleIdentifier: String?
    var captureEnabled: Bool?
    var allowed: Bool?
    var duplicateDecision = "not evaluated"
    var coordinatorInvoked = false
    var storeInvoked = false
    var persistenceResult = "not attempted"
    var finalResult = "pending"
}

@MainActor
final class ClipboardDiagnostics: ObservableObject {
    @Published private(set) var isMonitorRunning = false
    @Published private(set) var timerFireCount: UInt64 = 0
    @Published private(set) var currentChangeCount = 0
    @Published private(set) var previousObservedChangeCount = 0
    @Published private(set) var pendingChangeCount: Int?
    @Published private(set) var handledChangeCount = 0
    @Published private(set) var generations: [ClipboardGenerationDiagnostic] = []

    func updateStatus(_ status: ClipboardMonitorStatus) {
        isMonitorRunning = status.isRunning
        timerFireCount = status.timerFireCount
        currentChangeCount = status.currentChangeCount
        previousObservedChangeCount = status.previousObservedChangeCount
        pendingChangeCount = status.pendingChangeCount
        handledChangeCount = status.handledChangeCount

        if status.pendingChangeCount != nil,
           !generations.contains(where: { $0.changeCount == status.currentChangeCount }) {
            generations.insert(
                ClipboardGenerationDiagnostic(
                    changeCount: status.currentChangeCount,
                    monitorRunning: status.isRunning,
                    timerFireCount: status.timerFireCount,
                    currentChangeCount: status.currentChangeCount,
                    previousObservedChangeCount: status.previousObservedChangeCount,
                    pendingChangeCount: status.pendingChangeCount
                ),
                at: 0
            )
            if generations.count > 100 { generations.removeLast(generations.count - 100) }
        }
    }

    func recordAttempt(_ attempt: ClipboardExtractionAttempt) {
        updateStatus(attempt.status)
        update(changeCount: attempt.status.currentChangeCount) { record in
            record.pendingChangeCount = attempt.status.pendingChangeCount
            record.extractionAttemptCount = attempt.extractionAttemptCount
            record.stringLength = attempt.stringLength
            record.readObjectsLength = attempt.readObjectsLength
            record.foregroundApplicationName = attempt.source.application.displayName
            record.foregroundBundleIdentifier = attempt.source.application.bundleIdentifier
            record.captureEnabled = attempt.pipelineState?.captureEnabled
            record.allowed = attempt.pipelineState?.allowed
        }
    }

    func recordOutcome(changeCount: Int, outcome: ClipboardPipelineOutcome) {
        update(changeCount: changeCount) { record in
            record.pendingChangeCount = nil
            if let captureEnabled = outcome.captureEnabled {
                record.captureEnabled = captureEnabled
            }
            if let allowed = outcome.allowed {
                record.allowed = allowed
            }
            record.duplicateDecision = outcome.duplicateDecision
            record.coordinatorInvoked = outcome.coordinatorInvoked
            record.storeInvoked = outcome.storeInvoked
            record.persistenceResult = outcome.persistenceResult
            record.finalResult = outcome.finalResult
        }
    }

    private func update(
        changeCount: Int,
        mutation: (inout ClipboardGenerationDiagnostic) -> Void
    ) {
        guard let index = generations.firstIndex(where: { $0.changeCount == changeCount }) else { return }
        mutation(&generations[index])
    }
}

/// Opt-in packaged-app diagnostic window used when UI automation cannot bind
/// directly to an LSUIElement process. The normal menu uses SwiftUI openWindow.
@MainActor
final class DiagnosticsWindowPresenter {
    static let shared = DiagnosticsWindowPresenter()
    private var windowController: NSWindowController?

    private init() {}

    func show(diagnostics: ClipboardDiagnostics) {
        let controller: NSWindowController
        if let windowController {
            controller = windowController
        } else {
            let hostingController = NSHostingController(
                rootView: ClipboardDiagnosticsView(diagnostics: diagnostics)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "PDF Quote Collector Diagnostics"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 860, height: 640))
            window.minSize = NSSize(width: 760, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            controller = NSWindowController(window: window)
            self.windowController = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
