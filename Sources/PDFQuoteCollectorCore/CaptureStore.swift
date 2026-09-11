import Foundation

public enum CaptureStoreError: Error, LocalizedError {
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "The capture store uses unsupported schema version \(version)."
        }
    }
}

public struct CaptureStore {
    private struct Document: Codable {
        let schemaVersion: Int
        let captures: [Capture]
    }

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> [Capture] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let document = try decoder.decode(Document.self, from: data)
        guard document.schemaVersion == 1 || document.schemaVersion == 2 else {
            throw CaptureStoreError.unsupportedSchema(document.schemaVersion)
        }
        return document.captures
    }

    public func save(_ captures: [Capture]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = Document(schemaVersion: 2, captures: captures)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func appending(_ capture: Capture, to captures: [Capture]) throws -> [Capture] {
        let updated = captures + [capture]
        try save(updated)
        return updated
    }

    /// Removes the session's canonical history. Output documents are owned by
    /// their exporters and are intentionally left untouched.
    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
