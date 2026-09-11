import Foundation

public struct DuplicateDetector: Sendable {
    private struct Entry: Sendable {
        let comparisonText: String
        let date: Date
    }

    private var recent: [Entry] = []
    private let suppressionInterval: TimeInterval
    private let capacity: Int
    private let cleaner: TextCleaner

    public init(
        suppressionInterval: TimeInterval = 15,
        capacity: Int = 20,
        cleaner: TextCleaner = TextCleaner()
    ) {
        self.suppressionInterval = suppressionInterval
        self.capacity = max(capacity, 1)
        self.cleaner = cleaner
    }

    public mutating func shouldAccept(
        _ text: String,
        at date: Date = Date(),
        isEnabled: Bool = true
    ) -> Bool {
        let comparisonText = cleaner.normalizedForComparison(text)
        guard !comparisonText.isEmpty else { return false }

        recent.removeAll { date.timeIntervalSince($0.date) > suppressionInterval }
        let isDuplicate = isEnabled && recent.contains { $0.comparisonText == comparisonText }
        guard !isDuplicate else { return false }

        recent.append(Entry(comparisonText: comparisonText, date: date))
        if recent.count > capacity {
            recent.removeFirst(recent.count - capacity)
        }
        return true
    }
}

