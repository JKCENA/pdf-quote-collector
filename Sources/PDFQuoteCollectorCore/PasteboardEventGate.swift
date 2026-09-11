/// Ensures that one NSPasteboard change count can be handled at most once.
public struct PasteboardEventGate: Sendable {
    public private(set) var lastChangeCount: Int

    public init(initialChangeCount: Int) {
        self.lastChangeCount = initialChangeCount
    }

    public mutating func accept(changeCount: Int) -> Bool {
        guard changeCount != lastChangeCount else { return false }
        lastChangeCount = changeCount
        return true
    }
}

