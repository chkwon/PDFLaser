import CoreGraphics
import Foundation

struct LaserSettings {
    var color: PlatformColor
    var width: CGFloat
    var trailDuration: TimeInterval
    var trailFadeDelay: TimeInterval
    var dotRadius: CGFloat

    static let `default` = LaserSettings(
        color: .defaultLaserColor,
        width: 6,
        trailDuration: 1.0,
        trailFadeDelay: 0.5,
        dotRadius: 6
    )
}
