import Foundation

public enum OutputStyle: String, Codable, CaseIterable, Sendable {
    case plainParagraphs
    case bulletList
    case quotationMarks

    public var displayName: String {
        switch self {
        case .plainParagraphs: return "Plain paragraphs"
        case .bulletList: return "Bullet list"
        case .quotationMarks: return "Quotation marks"
        }
    }
}

public enum MarkdownOutputError: Error, LocalizedError {
    case destinationMissing
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .destinationMissing:
            return "The Markdown destination is missing. Choose it again in Settings."
        case .invalidUTF8:
            return "The Markdown destination is not valid UTF-8."
        }
    }
}

public enum MarkdownAppendResult: Sendable {
    case appended
    case alreadyPresent
}

public struct NotesFormatter: Sendable {
    public init() {}

    public func format(
        _ text: String,
        style: OutputStyle = .plainParagraphs
    ) -> String {
        switch style {
        case .plainParagraphs:
            return text
        case .bulletList:
            return "- " + text.replacingOccurrences(of: "\n", with: "\n  ")
        case .quotationMarks:
            return "“\(text)”"
        }
    }
}

public struct MarkdownOutputService: Sendable {
    private let formatter: NotesFormatter

    public init(formatter: NotesFormatter = NotesFormatter()) {
        self.formatter = formatter
    }

    @discardableResult
    public func append(
        capture: Capture,
        to url: URL,
        style: OutputStyle = .plainParagraphs,
        blankLines: Int = 1
    ) throws -> MarkdownAppendResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw MarkdownOutputError.destinationMissing
        }

        let existingData = try Data(contentsOf: url)
        guard let existing = String(data: existingData, encoding: .utf8) else {
            throw MarkdownOutputError.invalidUTF8
        }

        let marker = "<!-- pdf-quote-collector:\(capture.id.uuidString.lowercased()) -->"
        guard !existing.contains(marker) else { return .alreadyPresent }

        let formatted = formatter.format(capture.cleanedText, style: style)
        let requiredNewlines = existing.isEmpty ? 0 : max(0, blankLines) + 1
        let existingTrailingNewlines = existing.reversed().prefix(while: { $0 == "\n" }).count
        let separator = String(repeating: "\n", count: max(0, requiredNewlines - existingTrailingNewlines))
        let block = separator + formatted + "\n" + marker + "\n"
        guard let data = block.data(using: .utf8) else { throw MarkdownOutputError.invalidUTF8 }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        return .appended
    }
}
