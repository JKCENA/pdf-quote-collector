import CoreGraphics
import Foundation
import Vision

public enum OCRServiceError: Error, LocalizedError {
    case noTextRecognized
    case noSupportedLanguage

    public var errorDescription: String? {
        switch self {
        case .noTextRecognized: return "No text was recognized in the selected region."
        case .noSupportedLanguage: return "This macOS Vision installation does not support the requested OCR languages."
        }
    }
}

public struct OCRLine: Equatable, Sendable {
    public let text: String
    public let bounds: CGRect

    public init(text: String, bounds: CGRect) {
        self.text = text
        self.bounds = bounds
    }
}

public struct OCRLineReconstructor: Sendable {
    public init() {}

    public func reconstruct(_ lines: [OCRLine]) -> String {
        lines.sorted { lhs, rhs in
            let verticalDifference = abs(lhs.bounds.midY - rhs.bounds.midY)
            if verticalDifference > 0.015 {
                return lhs.bounds.midY > rhs.bounds.midY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        .map(\.text)
        .joined(separator: "\n")
    }
}

public struct OCRService: Sendable {
    public init() {}

    public func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let supported = try request.supportedRecognitionLanguages()
            let requested = ["en-US", "ko-KR"].filter(supported.contains)
            guard !requested.isEmpty else { throw OCRServiceError.noSupportedLanguage }
            request.recognitionLanguages = requested

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let text = observation.topCandidates(1).first?.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return OCRLine(text: text, bounds: observation.boundingBox)
            }
            let text = OCRLineReconstructor().reconstruct(lines)
            guard !text.isEmpty else { throw OCRServiceError.noTextRecognized }
            return text
        }.value
    }
}

