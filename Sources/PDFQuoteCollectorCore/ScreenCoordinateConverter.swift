import CoreGraphics

public struct ScreenCoordinateConverter: Sendable {
    public init() {}

    /// Converts a selection expressed in an NSScreen-local, bottom-left coordinate
    /// space into that display's CoreGraphics top-left coordinate space.
    public func coreGraphicsRect(
        localSelection: CGRect,
        screenSize: CGSize,
        displayOrigin: CGPoint
    ) -> CGRect {
        CGRect(
            x: displayOrigin.x + localSelection.minX,
            y: displayOrigin.y + screenSize.height - localSelection.maxY,
            width: localSelection.width,
            height: localSelection.height
        )
    }
}

