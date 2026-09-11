import AppKit
import PDFQuoteCollectorCore
import SwiftUI

@main
struct PDFQuoteCollectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("PDF Quote Collector", systemImage: "quote.bubble") {
            MenuContentView(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)

        Window("PDF Quote Collector Captures", id: "captures") {
            CaptureHistoryView(model: appDelegate.model)
                .frame(minWidth: 520, minHeight: 360)
        }
        .defaultSize(width: 620, height: 460)

        Window("PDF Quote Collector Diagnostics", id: "diagnostics") {
            ClipboardDiagnosticsView(diagnostics: appDelegate.model.diagnostics)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 860, height: 640)

        Settings {
            SettingsView(model: appDelegate.model)
                .frame(width: 560, height: 700)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.clearCaptureHistoryForTermination()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--show-diagnostics") else { return false }
        DiagnosticsWindowPresenter.shared.show(diagnostics: model.diagnostics)
        return true
    }
}

private struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("PDF Quote Collector")
        Divider()
        Toggle("Capture: \(model.isCaptureEnabled ? "ON" : "OFF")", isOn: $model.isCaptureEnabled)
        Text("Captured this session: \(model.sessionCaptureCount)")
        if let error = model.lastErrorMessage {
            Text(error).foregroundStyle(.red)
        }
        Menu("Allowed Applications") {
            ForEach($model.allowedApplications) { $application in
                Toggle(application.name, isOn: $application.isEnabled)
            }
        }
        Toggle("Suppress Repeated Copies", isOn: $model.duplicateSuppressionEnabled)
        Menu("Output Style") {
            ForEach(OutputStyle.allCases, id: \.self) { style in
                Button {
                    model.outputStyle = style
                } label: {
                    if model.outputStyle == style {
                        Label(style.displayName, systemImage: "checkmark")
                    } else {
                        Text(style.displayName)
                    }
                }
            }
        }
        Menu("Blank Lines: \(model.blankLinesBetweenQuotes)") {
            ForEach(0...3, id: \.self) { count in
                Button("\(count)") { model.blankLinesBetweenQuotes = count }
            }
        }
        Divider()
        Text("Markdown: \(model.markdownDisplayName)")
        Text("Word: \(model.wordDisplayName)")
        Text("Pending: Markdown \(model.pendingMarkdownCount), Word \(model.pendingWordCount)")
        Button("Retry Failed Outputs") { model.retryFailedOutputs() }
        Menu("Retry Output") {
            Button("Retry Markdown Output") { model.retryMarkdownOutput() }
            Button("Retry Word Output") { model.retryWordOutput() }
        }
        Divider()
        Button("OCR Capture (\(model.shortcutConfiguration.displayName))") { model.beginOCRCapture() }
        Button("Show Captures") {
            openWindow(id: "captures")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Show Diagnostics") {
            openWindow(id: "diagnostics")
            NSApp.activate(ignoringOtherApps: true)
        }
        if #available(macOS 14.0, *) {
            ModernSettingsButton()
        } else {
            Button("Settings…") {
                SettingsWindowPresenter.shared.show(model: model)
            }
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct ClipboardDiagnosticsView: View {
    @ObservedObject var diagnostics: ClipboardDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clipboard Monitor")
                .font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                diagnosticRow("Monitor running", diagnostics.isMonitorRunning ? "true" : "false")
                diagnosticRow("Timer fire count", String(diagnostics.timerFireCount))
                diagnosticRow("Current pasteboard changeCount", String(diagnostics.currentChangeCount))
                diagnosticRow("Previous observed changeCount", String(diagnostics.previousObservedChangeCount))
                diagnosticRow("Pending changeCount", diagnostics.pendingChangeCount.map(String.init) ?? "none")
                diagnosticRow("Handled changeCount", String(diagnostics.handledChangeCount))
            }
            .padding(.horizontal, 4)

            Divider()
            Text("Observed Generations (newest first)")
                .font(.headline)

            if diagnostics.generations.isEmpty {
                Text("No clipboard generation has been observed since launch.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(diagnostics.generations) { generation in
                    DisclosureGroup("changeCount \(generation.changeCount) — \(generation.finalResult)") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 5) {
                            diagnosticRow("Monitor running", generation.monitorRunning ? "true" : "false")
                            diagnosticRow("Timer fire count", String(generation.timerFireCount))
                            diagnosticRow("Current pasteboard changeCount", String(generation.currentChangeCount))
                            diagnosticRow("Previous observed changeCount", String(generation.previousObservedChangeCount))
                            diagnosticRow("Pending changeCount", generation.pendingChangeCount.map(String.init) ?? "none")
                            diagnosticRow("Extraction attempt count", String(generation.extractionAttemptCount))
                            diagnosticRow("string(forType: .string) length", optionalLength(generation.stringLength))
                            diagnosticRow("readObjects NSString length", optionalLength(generation.readObjectsLength))
                            diagnosticRow("Foreground app", generation.foregroundApplicationName ?? "unknown")
                            diagnosticRow("Foreground bundle ID", generation.foregroundBundleIdentifier ?? "unknown")
                            diagnosticRow("Capture enabled", optionalBool(generation.captureEnabled))
                            diagnosticRow("Allowed", optionalBool(generation.allowed))
                            diagnosticRow("Duplicate decision", generation.duplicateDecision)
                            diagnosticRow("CaptureCoordinator invoked", generation.coordinatorInvoked ? "true" : "false")
                            diagnosticRow("CaptureStore invoked", generation.storeInvoked ? "true" : "false")
                            diagnosticRow("Persistence", generation.persistenceResult)
                            diagnosticRow("Final result", generation.finalResult)
                            diagnosticRow("Final rejection reason", rejectionReason(generation.finalResult))
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func optionalLength(_ value: Int?) -> String {
        value.map(String.init) ?? "nil"
    }

    private func optionalBool(_ value: Bool?) -> String {
        value.map { $0 ? "true" : "false" } ?? "not evaluated"
    }

    private func rejectionReason(_ finalResult: String) -> String {
        guard finalResult.hasPrefix("rejected: ") else { return "none" }
        return String(finalResult.dropFirst("rejected: ".count))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Toggle("Capture copied text", isOn: $model.isCaptureEnabled)
            GroupBox("Markdown output") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Save to Markdown", isOn: $model.saveToMarkdown)
                    HStack {
                        Text("Destination")
                        Spacer()
                        Button(model.markdownDisplayName) { model.chooseMarkdownDestination() }
                    }
                    Button("Retry Markdown Output") { model.retryMarkdownOutput() }
                }
                .padding(6)
            }
            GroupBox("Microsoft Word output") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Save to Microsoft Word", isOn: $model.saveToWord)
                    Toggle("Automatically open Word when needed", isOn: $model.automaticallyOpenWord)
                    HStack {
                        Text("Destination")
                        Spacer()
                        Button(model.wordDisplayName) { model.chooseWordDestination() }
                    }
                    Button("Retry Word Output") { model.retryWordOutput() }
                }
                .padding(6)
            }
            GroupBox("OCR shortcut") {
                HStack {
                    TextField("Key", text: Binding(
                        get: { model.shortcutConfiguration.key },
                        set: { model.updateShortcutKey($0) }
                    ))
                    .frame(width: 44)
                    shortcutToggle("⌘", .command)
                    shortcutToggle("⇧", .shift)
                    shortcutToggle("⌥", .option)
                    shortcutToggle("⌃", .control)
                    Spacer()
                    Text(model.shortcutConfiguration.displayName)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }
            GroupBox("Allowed source applications") {
                VStack(alignment: .leading) {
                    ForEach($model.allowedApplications) { $application in
                        Toggle(application.name, isOn: $application.isEnabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            Toggle("Suppress repeated copies", isOn: $model.duplicateSuppressionEnabled)
            Picker("Quotation style", selection: $model.outputStyle) {
                ForEach(OutputStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            Stepper(
                "Blank lines between quotations: \(model.blankLinesBetweenQuotes)",
                value: $model.blankLinesBetweenQuotes,
                in: 0...3
            )
            HStack {
                Text("Screen Recording: \(model.screenRecordingStatusText)")
                Spacer()
                Button("Open Privacy Settings") { model.openScreenRecordingSettings() }
            }
        }
        .padding(18)
    }

    private func shortcutToggle(_ label: String, _ modifier: ShortcutModifiers) -> some View {
        Toggle(label, isOn: Binding(
            get: { model.shortcutContains(modifier) },
            set: { model.setShortcutModifier(modifier, enabled: $0) }
        ))
        .toggleStyle(.checkbox)
    }
}

private struct CaptureHistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.captures.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No Captures Yet").font(.headline)
                    Text("Copy text while Capture is ON.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(model.captures.reversed())) { capture in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(capture.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(capture.cleanedText)
                            .textSelection(.enabled)
                        if let source = capture.sourceApplication?.displayName {
                            Text(source).font(.caption2).foregroundStyle(.tertiary)
                        }
                        if let filename = capture.sourceFilename {
                            Text(filename).font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Text("Markdown: \(capture.markdownExportStatus.rawValue)")
                            Text("Word: \(capture.wordExportStatus.rawValue)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("Captures")
    }
}
