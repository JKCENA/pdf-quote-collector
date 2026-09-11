import AppKit
import Foundation
import PDFQuoteCollectorCore

enum WordOutputResult {
    case exported
    case alreadyPresent
    case pending(reason: String)
}

enum WordOutputError: Error, LocalizedError {
    case destinationMissing
    case automationFailed(String)

    var errorDescription: String? {
        switch self {
        case .destinationMissing:
            return "The Word destination is missing. Choose it again in Settings."
        case .automationFailed(let message):
            return "Microsoft Word automation failed: \(message)"
        }
    }
}

@MainActor
struct WordOutputService {
    static let bundleIdentifier = "com.microsoft.Word"

    func append(
        capture: Capture,
        to url: URL,
        style: OutputStyle,
        blankLines: Int,
        automaticallyOpenWord: Bool
    ) throws -> WordOutputResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WordOutputError.destinationMissing
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil else {
            return .pending(reason: "Microsoft Word is not installed.")
        }

        let wordIsRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        ).isEmpty
        guard wordIsRunning || automaticallyOpenWord else {
            return .pending(reason: "Microsoft Word is closed and automatic opening is off.")
        }

        let quote = formatted(capture.cleanedText, style: style)
        let separator = String(repeating: "\n", count: max(0, blankLines) + 1)
        let markerName = "PQC_" + capture.id.uuidString.replacingOccurrences(of: "-", with: "")
        let source = Self.scriptSource(
            documentPath: url.path,
            quote: quote,
            separator: separator,
            markerName: markerName
        )

        guard let script = NSAppleScript(source: source) else {
            throw WordOutputError.automationFailed("The AppleScript could not be compiled.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                ?? "Unknown Apple Events error"
            throw WordOutputError.automationFailed(message)
        }
        switch result.stringValue {
        case "already-exported":
            return .alreadyPresent
        case "exported":
            return .exported
        default:
            throw WordOutputError.automationFailed("Microsoft Word returned an unexpected response.")
        }
    }

    private func formatted(_ text: String, style: OutputStyle) -> String {
        switch style {
        case .plainParagraphs:
            return text
        case .bulletList:
            return "• " + text.replacingOccurrences(of: "\n", with: "\n  ")
        case .quotationMarks:
            return "“\(text)”"
        }
    }

    static func scriptSource(
        documentPath: String,
        quote: String,
        separator: String,
        markerName: String
    ) -> String {
        """
        set documentPath to \(appleScriptExpression(documentPath))
        set quoteText to \(appleScriptExpression(quote))
        set separatorText to \(appleScriptExpression(separator))
        set markerName to \(appleScriptExpression(markerName))

        tell application id "com.microsoft.Word"
            open (POSIX file documentPath)
            set targetDocument to active document

            set markerValue to variable value of variable markerName of targetDocument
            if markerValue is not missing value then
                save targetDocument
                return "already-exported"
            end if

            set existingText to (content of text object of targetDocument) as text
            set existingTextLength to length of existingText
            set appendText to quoteText
            if existingTextLength > 1 then
                set appendText to separatorText & quoteText
            end if

            set insertionPosition to existingTextLength - 1
            if insertionPosition < 0 then set insertionPosition to 0
            set insertionRange to create range targetDocument start insertionPosition end insertionPosition
            set content of insertionRange to appendText
            make new variable at targetDocument with properties {name:markerName, variable value:"exported"}
            save targetDocument
            return "exported"
        end tell
        """
    }

    private static func appleScriptExpression(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let pieces = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        return pieces.map { piece in
            let escaped = piece
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }.joined(separator: " & return & ")
    }
}
