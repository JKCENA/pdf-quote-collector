import Foundation

public struct SourceApplication: Codable, Equatable, Sendable {
    public let bundleIdentifier: String?
    public let displayName: String?

    public init(bundleIdentifier: String?, displayName: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

public struct SourceContext: Equatable, Sendable {
    public let application: SourceApplication
    public let documentTitle: String?
    public let filename: String?

    public init(application: SourceApplication, documentTitle: String? = nil, filename: String? = nil) {
        self.application = application
        self.documentTitle = documentTitle
        self.filename = filename
    }
}

public struct SourceDocumentParser: Sendable {
    public init() {}

    public func context(
        application: SourceApplication,
        windowTitle: String?
    ) -> SourceContext {
        guard var title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return SourceContext(application: application)
        }

        switch application.bundleIdentifier {
        case "com.apple.Safari":
            title = removingSuffix(" — Safari", from: title)
        case "com.google.Chrome":
            title = removingSuffix(" - Google Chrome", from: title)
        default:
            break
        }

        let filename: String?
        if title.lowercased().hasSuffix(".pdf") {
            filename = URL(fileURLWithPath: title).lastPathComponent
        } else {
            filename = nil
        }
        return SourceContext(application: application, documentTitle: title, filename: filename)
    }

    private func removingSuffix(_ suffix: String, from value: String) -> String {
        guard value.hasSuffix(suffix) else { return value }
        return String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
    }
}

public struct AllowedApplication: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String
    public var isEnabled: Bool

    public init(name: String, bundleIdentifier: String, isEnabled: Bool = true) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isEnabled = isEnabled
    }

    public static let defaults: [AllowedApplication] = [
        .init(name: "Preview", bundleIdentifier: "com.apple.Preview"),
        .init(name: "Adobe Acrobat Reader", bundleIdentifier: "com.adobe.Reader"),
        .init(name: "Adobe Acrobat", bundleIdentifier: "com.adobe.Acrobat.Pro"),
        .init(name: "PDF Expert", bundleIdentifier: "com.readdle.PDFExpert-Mac"),
        .init(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome")
    ]
}

public struct AllowedApplicationFilter: Sendable {
    private let enabledBundleIdentifiers: Set<String>

    public init(applications: [AllowedApplication]) {
        self.enabledBundleIdentifiers = Set(
            applications.lazy.filter(\.isEnabled).map(\.bundleIdentifier)
        )
    }

    public func allows(_ source: SourceApplication) -> Bool {
        guard let bundleIdentifier = source.bundleIdentifier else { return false }
        return enabledBundleIdentifiers.contains(bundleIdentifier)
    }
}
