import CoreGraphics

extension CGPoint {
    var clampedToUnitSquare: CGPoint {
        CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }

    func denormalized(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    static func normalized(from point: CGPoint, in size: CGSize) -> CGPoint? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        return CGPoint(
            x: point.x / size.width,
            y: point.y / size.height
        ).clampedToUnitSquare
    }
}
