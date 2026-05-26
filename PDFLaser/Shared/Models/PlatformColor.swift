import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    static var defaultLaserColor: PlatformColor {
        #if os(macOS)
        return .systemRed
        #else
        return .systemRed
        #endif
    }

    static var defaultPenColor: PlatformColor {
        #if os(macOS)
        return .systemRed
        #else
        return .systemRed
        #endif
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
