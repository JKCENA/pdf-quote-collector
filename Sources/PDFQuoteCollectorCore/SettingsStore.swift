import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift = ShortcutModifiers(rawValue: 1 << 1)
    public static let option = ShortcutModifiers(rawValue: 1 << 2)
    public static let control = ShortcutModifiers(rawValue: 1 << 3)
}

public struct ShortcutConfiguration: Codable, Equatable, Sendable {
    public var key: String
    public var modifiers: ShortcutModifiers

    public init(key: String = "X", modifiers: ShortcutModifiers = [.command, .shift]) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let `default` = ShortcutConfiguration()

    public var displayName: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value + key.uppercased()
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var captureEnabled: Bool
    public var saveToMarkdown: Bool
    public var markdownDestinationBookmark: Data?
    public var saveToWord: Bool
    public var wordDestinationBookmark: Data?
    public var automaticallyOpenWord: Bool
    public var ocrShortcut: ShortcutConfiguration
    public var allowedApplications: [AllowedApplication]
    public var duplicateSuppressionEnabled: Bool
    public var outputStyle: OutputStyle
    public var blankLinesBetweenQuotes: Int

    public init(
        schemaVersion: Int = 2,
        captureEnabled: Bool = true,
        saveToMarkdown: Bool = true,
        markdownDestinationBookmark: Data? = nil,
        saveToWord: Bool = true,
        wordDestinationBookmark: Data? = nil,
        automaticallyOpenWord: Bool = false,
        ocrShortcut: ShortcutConfiguration = .default,
        allowedApplications: [AllowedApplication] = AllowedApplication.defaults,
        duplicateSuppressionEnabled: Bool = true,
        outputStyle: OutputStyle = .plainParagraphs,
        blankLinesBetweenQuotes: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.captureEnabled = captureEnabled
        self.saveToMarkdown = saveToMarkdown
        self.markdownDestinationBookmark = markdownDestinationBookmark
        self.saveToWord = saveToWord
        self.wordDestinationBookmark = wordDestinationBookmark
        self.automaticallyOpenWord = automaticallyOpenWord
        self.ocrShortcut = ocrShortcut
        self.allowedApplications = allowedApplications
        self.duplicateSuppressionEnabled = duplicateSuppressionEnabled
        self.outputStyle = outputStyle
        self.blankLinesBetweenQuotes = blankLinesBetweenQuotes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, captureEnabled, saveToMarkdown, markdownDestinationBookmark
        case saveToWord, wordDestinationBookmark, automaticallyOpenWord
        case ocrShortcut, allowedApplications, duplicateSuppressionEnabled
        case outputStyle, blankLinesBetweenQuotes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard storedSchemaVersion == 1 || storedSchemaVersion == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported settings schema \(storedSchemaVersion)"
            )
        }
        schemaVersion = 2
        captureEnabled = try container.decodeIfPresent(Bool.self, forKey: .captureEnabled) ?? true
        saveToMarkdown = try container.decodeIfPresent(Bool.self, forKey: .saveToMarkdown) ?? true
        markdownDestinationBookmark = try container.decodeIfPresent(Data.self, forKey: .markdownDestinationBookmark)
        saveToWord = try container.decodeIfPresent(Bool.self, forKey: .saveToWord) ?? true
        wordDestinationBookmark = try container.decodeIfPresent(Data.self, forKey: .wordDestinationBookmark)
        automaticallyOpenWord = try container.decodeIfPresent(Bool.self, forKey: .automaticallyOpenWord) ?? false
        ocrShortcut = try container.decodeIfPresent(ShortcutConfiguration.self, forKey: .ocrShortcut) ?? .default
        allowedApplications = try container.decodeIfPresent([AllowedApplication].self, forKey: .allowedApplications)
            ?? AllowedApplication.defaults
        duplicateSuppressionEnabled = try container.decodeIfPresent(Bool.self, forKey: .duplicateSuppressionEnabled) ?? true
        outputStyle = try container.decodeIfPresent(OutputStyle.self, forKey: .outputStyle) ?? .plainParagraphs
        blankLinesBetweenQuotes = try container.decodeIfPresent(Int.self, forKey: .blankLinesBetweenQuotes) ?? 1
    }
}

public final class SettingsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "appSettings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data),
              settings.schemaVersion == 2 else { return AppSettings() }
        var repaired = settings
        let saved = Dictionary(uniqueKeysWithValues: settings.allowedApplications.map { ($0.bundleIdentifier, $0) })
        repaired.allowedApplications = AllowedApplication.defaults.map { saved[$0.bundleIdentifier] ?? $0 }
        repaired.blankLinesBetweenQuotes = min(max(settings.blankLinesBetweenQuotes, 0), 3)
        return repaired
    }

    public func save(_ settings: AppSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: key)
    }
}
