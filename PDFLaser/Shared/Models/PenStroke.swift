import CoreGraphics
import Foundation

struct PenStroke: Identifiable {
    let id = UUID()
    var normalizedPoints: [CGPoint]
    var color: PlatformColor
    var width: CGFloat
}
