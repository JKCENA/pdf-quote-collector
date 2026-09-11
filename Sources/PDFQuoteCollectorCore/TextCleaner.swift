import Foundation

public struct TextCleaner: Sendable {
    public init() {}

    public func clean(_ input: String) -> String {
        var text = normalizeLineEndingsAndUnicodeWhitespace(input)
        text = replacing(#"\n[ ]*\n+"#, in: text, with: "\n\n")

        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map(cleanParagraph)
            .filter { !$0.isEmpty }

        return paragraphs.joined(separator: "\n\n")
    }

    /// Used by duplicate comparison without changing paragraph semantics.
    public func normalizedForComparison(_ input: String) -> String {
        replacing(#"\s+"#, in: clean(input), with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanParagraph(_ paragraph: String) -> String {
        var value = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        // A letter-hyphen followed by a line break and another letter is a PDF
        // extraction split. This intentionally does not touch hyphens elsewhere.
        value = replacing(#"([\p{L}\p{M}])-[ ]*\n[ ]*([\p{L}\p{M}])"#, in: value, with: "$1$2")
        value = replacing(#"[ ]*\n[ ]*"#, in: value, with: " ")
        value = replacing(#" {2,}"#, in: value, with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeLineEndingsAndUnicodeWhitespace(_ input: String) -> String {
        let lineNormalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var result = String.UnicodeScalarView()
        for scalar in lineNormalized.unicodeScalars {
            switch scalar.value {
            case 0x0A:
                result.append("\n")
            case 0x2028:
                result.append("\n")
            case 0x2029:
                result.append("\n")
                result.append("\n")
            default:
                if scalar.properties.isWhitespace {
                    result.append(" ")
                } else {
                    result.append(scalar)
                }
            }
        }
        return String(result)
    }

    private func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}

