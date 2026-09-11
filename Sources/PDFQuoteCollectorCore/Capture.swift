import Foundation

public enum CaptureMethod: String, Codable, Sendable {
    case clipboard
    case ocr
}

public enum ExportStatus: String, Codable, Sendable {
    case pending
    case exported
    case failed
}

public struct Capture: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let rawText: String
    public let cleanedText: String
    public let timestamp: Date
    public let captureMethod: CaptureMethod
    public let sourceApplication: SourceApplication?
    public let sourceDocumentTitle: String?
    public let sourceFilename: String?
    public let pageNumber: Int?
    public let createdAt: Date
    public var markdownExportStatus: ExportStatus
    public var markdownExportError: String?
    public var wordExportStatus: ExportStatus
    public var wordExportError: String?

    public init(
        id: UUID = UUID(),
        rawText: String,
        cleanedText: String,
        timestamp: Date = Date(),
        captureMethod: CaptureMethod,
        sourceApplication: SourceApplication? = nil,
        sourceDocumentTitle: String? = nil,
        sourceFilename: String? = nil,
        pageNumber: Int? = nil,
        createdAt: Date = Date(),
        markdownExportStatus: ExportStatus = .pending,
        markdownExportError: String? = nil,
        wordExportStatus: ExportStatus = .pending,
        wordExportError: String? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.timestamp = timestamp
        self.captureMethod = captureMethod
        self.sourceApplication = sourceApplication
        self.sourceDocumentTitle = sourceDocumentTitle
        self.sourceFilename = sourceFilename
        self.pageNumber = pageNumber
        self.createdAt = createdAt
        self.markdownExportStatus = markdownExportStatus
        self.markdownExportError = markdownExportError
        self.wordExportStatus = wordExportStatus
        self.wordExportError = wordExportError
    }


    private enum CodingKeys: String, CodingKey {
        case id, rawText, cleanedText, timestamp, captureMethod
        case sourceApplication, sourceDocumentTitle, sourceFilename, pageNumber, createdAt
        case markdownExportStatus, markdownExportError, wordExportStatus, wordExportError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        rawText = try container.decode(String.self, forKey: .rawText)
        cleanedText = try container.decode(String.self, forKey: .cleanedText)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        captureMethod = try container.decode(CaptureMethod.self, forKey: .captureMethod)
        sourceApplication = try container.decodeIfPresent(SourceApplication.self, forKey: .sourceApplication)
        sourceDocumentTitle = try container.decodeIfPresent(String.self, forKey: .sourceDocumentTitle)
        sourceFilename = try container.decodeIfPresent(String.self, forKey: .sourceFilename)
        pageNumber = try container.decodeIfPresent(Int.self, forKey: .pageNumber)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        markdownExportStatus = try container.decodeIfPresent(ExportStatus.self, forKey: .markdownExportStatus) ?? .pending
        markdownExportError = try container.decodeIfPresent(String.self, forKey: .markdownExportError)
        wordExportStatus = try container.decodeIfPresent(ExportStatus.self, forKey: .wordExportStatus) ?? .pending
        wordExportError = try container.decodeIfPresent(String.self, forKey: .wordExportError)
    }
}
