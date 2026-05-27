import AppKit
import SwiftUI

struct MacPointerInputView: NSViewRepresentable {
    @ObservedObject var state: PDFPresentationState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> PointerInputNSView {
        let view = PointerInputNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: PointerInputNSView, context: Context) {
        context.coordinator.state = state
        nsView.coordinator = context.coordinator
        nsView.refreshCursor()
    }

    @MainActor
    final class Coordinator {
        var state: PDFPresentationState
        private var scrollAccumulator: CGFloat = 0
        private var lastScrollNavigationTime: TimeInterval = 0

        init(state: PDFPresentationState) {
            self.state = state
        }

        func handleMove(at normalizedPoint: CGPoint) {
            switch state.selectedTool {
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint, isPressed: false, persistsUntilCleared: true)
            case .none, .laserTrail, .pen, .erase:
                break
            }
        }

        func beginDrag(at normalizedPoint: CGPoint) {
            switch state.selectedTool {
            case .pen:
                state.beginPenStroke(at: normalizedPoint)
            case .erase:
                state.beginErase(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint, isPressed: true, persistsUntilCleared: true)
            case .laserTrail:
                state.beginLaserTrail(at: normalizedPoint)
            case .none:
                break
            }
        }

        func continueDrag(at normalizedPoint: CGPoint) {
            switch state.selectedTool {
            case .pen:
                state.appendPenStroke(at: normalizedPoint)
            case .erase:
                state.continueErase(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint, isPressed: true, persistsUntilCleared: true)
            case .laserTrail:
                state.appendLaserTrail(at: normalizedPoint)
            case .none:
                break
            }
        }

        func endDrag(at normalizedPoint: CGPoint) {
            switch state.selectedTool {
            case .pen:
                state.endPenStroke(at: normalizedPoint)
            case .erase:
                state.endErase(at: normalizedPoint)
            case .laserTrail:
                state.endLaserTrail(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint, isPressed: false, persistsUntilCleared: true)
            case .none:
                break
            }
        }

        func cancelInteraction() {
            state.cancelPenStroke()
            state.cancelErase()
            state.cancelLaserTrail()
            state.clearLaserDot()
        }

        func handleScroll(deltaY: CGFloat, hasPreciseDeltas: Bool, timestamp: TimeInterval) {
            guard state.pageCount > 0 else {
                return
            }

            let cooldown: TimeInterval = 0.28
            guard timestamp - lastScrollNavigationTime >= cooldown else {
                return
            }

            let scaledDelta = hasPreciseDeltas ? deltaY : deltaY * 40
            scrollAccumulator += scaledDelta

            let threshold: CGFloat = 30
            guard abs(scrollAccumulator) >= threshold else {
                return
            }

            if scrollAccumulator < 0 {
                state.nextPage()
            } else {
                state.previousPage()
            }

            scrollAccumulator = 0
            lastScrollNavigationTime = timestamp
        }
    }
}

@MainActor
final class PointerInputNSView: NSView {
    weak var coordinator: MacPointerInputView.Coordinator?
    private var isMouseInside = false

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
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
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .enabledDuringMouseDrag, .inVisibleRect, .cursorUpdate],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: activeCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        activeCursor.set()
    }

    func refreshCursor() {
        window?.invalidateCursorRects(for: self)

        if isMouseInside {
            activeCursor.set()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        activeCursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard let normalizedPoint = normalizedPoint(from: event) else {
            return
        }

        coordinator?.handleMove(at: normalizedPoint)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard let normalizedPoint = normalizedPoint(from: event) else {
            return
        }

        coordinator?.beginDrag(at: normalizedPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let normalizedPoint = normalizedPoint(from: event) else {
            return
        }

        coordinator?.continueDrag(at: normalizedPoint)
    }

    override func mouseUp(with event: NSEvent) {
        guard let normalizedPoint = normalizedPoint(from: event) else {
            return
        }

        coordinator?.endDrag(at: normalizedPoint)
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        NSCursor.arrow.set()
        coordinator?.cancelInteraction()
    }

    override func scrollWheel(with event: NSEvent) {
        coordinator?.handleScroll(
            deltaY: event.scrollingDeltaY,
            hasPreciseDeltas: event.hasPreciseScrollingDeltas,
            timestamp: event.timestamp
        )
    }

    private func normalizedPoint(from event: NSEvent) -> CGPoint? {
        let localPoint = convert(event.locationInWindow, from: nil)
        return CGPoint.normalized(from: localPoint, in: bounds.size)
    }

    private var activeCursor: NSCursor {
        switch coordinator?.state.selectedTool {
        case .erase:
            return .pdfLaserEraser
        case .laserDot:
            return .pdfLaserTransparent
        case .pen:
            return .pdfLaserPen
        default:
            return .arrow
        }
    }
}

private extension NSCursor {
    @MainActor
    static let pdfLaserTransparent: NSCursor = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: .zero)
    }()

    @MainActor
    static let pdfLaserPen: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: -45)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        let tipX: CGFloat = 4
        let woodEndX: CGFloat = 9
        let bodyEndX: CGFloat = 19
        let metalEndX: CGFloat = 21
        let eraserEndX: CGFloat = 25
        let centerY: CGFloat = 14
        let halfHeight: CGFloat = 3.2
        let top = centerY + halfHeight
        let bottom = centerY - halfHeight

        NSColor.black.withAlphaComponent(0.18).setFill()
        let shadow = NSBezierPath()
        shadow.move(to: NSPoint(x: tipX + 1, y: centerY - 0.6))
        shadow.line(to: NSPoint(x: woodEndX + 1, y: top - 1))
        shadow.line(to: NSPoint(x: eraserEndX + 1, y: top - 1))
        shadow.line(to: NSPoint(x: eraserEndX + 1, y: bottom - 1))
        shadow.line(to: NSPoint(x: woodEndX + 1, y: bottom - 1))
        shadow.close()
        shadow.fill()

        NSColor(calibratedRed: 0.96, green: 0.85, blue: 0.6, alpha: 1).setFill()
        let wood = NSBezierPath()
        wood.move(to: NSPoint(x: tipX, y: centerY))
        wood.line(to: NSPoint(x: woodEndX, y: top))
        wood.line(to: NSPoint(x: woodEndX, y: bottom))
        wood.close()
        wood.fill()

        NSColor(calibratedRed: 0.99, green: 0.82, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: woodEndX, y: bottom, width: bodyEndX - woodEndX, height: top - bottom)).fill()

        NSColor(calibratedRed: 0.78, green: 0.78, blue: 0.8, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: bodyEndX, y: bottom, width: metalEndX - bodyEndX, height: top - bottom)).fill()

        NSColor(calibratedRed: 0.99, green: 0.55, blue: 0.6, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: metalEndX, y: bottom, width: eraserEndX - metalEndX, height: top - bottom),
            xRadius: 1.2,
            yRadius: 1.2
        ).fill()

        NSColor.black.withAlphaComponent(0.88).setFill()
        let graphite = NSBezierPath()
        graphite.move(to: NSPoint(x: tipX, y: centerY))
        graphite.line(to: NSPoint(x: tipX + 2.2, y: centerY + 1.1))
        graphite.line(to: NSPoint(x: tipX + 2.2, y: centerY - 1.1))
        graphite.close()
        graphite.fill()

        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: tipX, y: centerY))
        outline.line(to: NSPoint(x: woodEndX, y: top))
        outline.line(to: NSPoint(x: eraserEndX, y: top))
        outline.line(to: NSPoint(x: eraserEndX, y: bottom))
        outline.line(to: NSPoint(x: woodEndX, y: bottom))
        outline.close()
        NSColor.black.withAlphaComponent(0.82).setStroke()
        outline.lineWidth = 1.2
        outline.stroke()

        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: bodyEndX, y: top))
        divider.line(to: NSPoint(x: bodyEndX, y: bottom))
        divider.lineWidth = 0.8
        divider.stroke()

        return NSCursor(image: image, hotSpot: NSPoint(x: 7, y: 7))
    }()

    @MainActor
    static let pdfLaserEraser: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: -35)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        let bodyRect = NSRect(x: 5, y: 9, width: 18, height: 10)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 2.5, yRadius: 2.5)

        NSColor.black.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bodyRect.offsetBy(dx: 1, dy: -1), xRadius: 2.5, yRadius: 2.5).fill()

        NSColor(calibratedRed: 0.98, green: 0.98, blue: 1, alpha: 1).setFill()
        bodyPath.fill()

        NSColor(calibratedRed: 0.99, green: 0.44, blue: 0.50, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 5, y: 9, width: 7, height: 10),
            xRadius: 2.5,
            yRadius: 2.5
        ).fill()

        NSColor.black.withAlphaComponent(0.82).setStroke()
        bodyPath.lineWidth = 1.4
        bodyPath.stroke()

        let seamPath = NSBezierPath()
        seamPath.move(to: NSPoint(x: 12, y: 9.8))
        seamPath.line(to: NSPoint(x: 12, y: 18.2))
        seamPath.lineWidth = 1
        seamPath.stroke()

        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()
}
