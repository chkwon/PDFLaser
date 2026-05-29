import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    static func presentationColor(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1
    ) -> PlatformColor {
        #if os(macOS)
        return PlatformColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        return PlatformColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    static var defaultLaserColor: PlatformColor {
        LaserColorPreset.ruby.mainColor
    }

    static var defaultPenColor: PlatformColor {
        PenColorPreset.crimson.color
    }
}

enum LaserColorPreset: String, CaseIterable, Identifiable {
    case ruby
    case electricCyan
    case signalAmber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruby:
            return "Ruby"
        case .electricCyan:
            return "Electric Cyan"
        case .signalAmber:
            return "Signal Amber"
        }
    }

    var mainColor: PlatformColor {
        switch self {
        case .ruby:
            return .presentationColor(red: 1.0, green: 0.176, blue: 0.333)
        case .electricCyan:
            return .presentationColor(red: 0.0, green: 0.780, blue: 1.0)
        case .signalAmber:
            return .presentationColor(red: 1.0, green: 0.584, blue: 0.0)
        }
    }

    var haloColor: PlatformColor {
        switch self {
        case .ruby:
            return .presentationColor(red: 1.0, green: 0.478, blue: 0.635)
        case .electricCyan:
            return .presentationColor(red: 0.553, green: 0.922, blue: 1.0)
        case .signalAmber:
            return .presentationColor(red: 1.0, green: 0.839, blue: 0.039)
        }
    }

    var shadowColor: PlatformColor {
        switch self {
        case .ruby:
            return .presentationColor(red: 0.545, green: 0.0, blue: 0.102)
        case .electricCyan:
            return .presentationColor(red: 0.0, green: 0.361, blue: 1.0)
        case .signalAmber:
            return .presentationColor(red: 0.761, green: 0.255, blue: 0.0)
        }
    }
}

enum PenColorPreset: String, CaseIterable, Identifiable {
    case crimson
    case royalBlue
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crimson:
            return "Crimson"
        case .royalBlue:
            return "Royal Blue"
        case .purple:
            return "Purple"
        }
    }

    var color: PlatformColor {
        switch self {
        case .crimson:
            return .presentationColor(red: 0.843, green: 0.0, blue: 0.082)
        case .royalBlue:
            return .presentationColor(red: 0.0, green: 0.4, blue: 1.0)
        case .purple:
            return .presentationColor(red: 0.686, green: 0.322, blue: 0.871)
        }
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}
