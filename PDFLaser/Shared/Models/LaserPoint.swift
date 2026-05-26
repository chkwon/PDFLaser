import CoreGraphics
import Foundation

struct LaserPoint: Identifiable {
    let id = UUID()
    let normalizedPosition: CGPoint
    let timestamp: TimeInterval

    func age(at now: TimeInterval) -> TimeInterval {
        now - timestamp
    }
}
