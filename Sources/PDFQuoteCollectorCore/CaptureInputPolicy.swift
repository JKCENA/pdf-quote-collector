import Foundation

public enum CaptureInputError: Error, LocalizedError {
    case tooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .tooLarge(let limit):
            return "Clipboard text exceeds the safe capture limit of \(limit) characters."
        }
    }
}

public struct CaptureInputPolicy: Sendable {
    public let maximumCharacterCount: Int

    public init(maximumCharacterCount: Int = 250_000) {
        self.maximumCharacterCount = maximumCharacterCount
    }

    public func validate(_ text: String) throws {
        guard text.count <= maximumCharacterCount else {
            throw CaptureInputError.tooLarge(maximumCharacterCount)
        }
    }
}

