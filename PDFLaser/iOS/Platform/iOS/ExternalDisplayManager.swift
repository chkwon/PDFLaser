import SwiftUI
import UIKit

@MainActor
final class ExternalDisplayManager: ObservableObject {
    @Published private(set) var isExternalDisplayConnected = false

    func startMonitoring(state: PDFPresentationState) {
        // TODO: Attach a UIWindowScene on an external UIScreen and render PDFSlideView
        // without PresenterToolbar while the iPad keeps the control surface.
        isExternalDisplayConnected = UIApplication.shared.openSessions.contains { session in
            session.role == .windowExternalDisplayNonInteractive
        }
    }

    func stopMonitoring() {
        isExternalDisplayConnected = false
    }
}
