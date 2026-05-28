import AppKit
import SwiftUI

struct MacMouseActivityView: NSViewRepresentable {
    var onMove: (CGPoint) -> Void

    func makeNSView(context: Context) -> MouseActivityNSView {
        let view = MouseActivityNSView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ nsView: MouseActivityNSView, context: Context) {
        nsView.onMove = onMove
    }
}

final class MouseActivityNSView: NSView {
    var onMove: ((CGPoint) -> Void)?

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        report(event)
    }

    override func mouseDragged(with event: NSEvent) {
        report(event)
    }

    private func report(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMove?(point)
    }
}
