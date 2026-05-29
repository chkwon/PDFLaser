import CoreGraphics
import Foundation

struct LaserSettings {
    var colorPreset: LaserColorPreset
    var width: CGFloat
    var trailDuration: TimeInterval
    var trailFadeDelay: TimeInterval
    var dotRadius: CGFloat

    var color: PlatformColor {
        colorPreset.mainColor
    }

    var haloColor: PlatformColor {
        colorPreset.haloColor
    }

    var shadowColor: PlatformColor {
        colorPreset.shadowColor
    }

    static let `default` = LaserSettings(
        colorPreset: .ruby,
        width: 6,
        trailDuration: 1.0,
        trailFadeDelay: 0.5,
        dotRadius: 6
    )
}
