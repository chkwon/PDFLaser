import Foundation

enum PresentationTool: String, CaseIterable, Identifiable {
    case none
    case laserDot
    case laserTrail
    case pen
    case erase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .laserDot:
            return "Dot Laser"
        case .laserTrail:
            return "Trail Laser"
        case .pen:
            return "Pen"
        case .erase:
            return "Erase"
        }
    }
}
