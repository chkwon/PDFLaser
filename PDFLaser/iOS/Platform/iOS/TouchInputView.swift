import SwiftUI
import UIKit

struct TouchInputView: UIViewRepresentable {
    @ObservedObject var state: PDFPresentationState
    var onNext: () -> Void
    var onPrevious: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onNext: onNext, onPrevious: onPrevious)
    }

    func makeUIView(context: Context) -> TouchInputUIView {
        let view = TouchInputUIView()
        view.coordinator = context.coordinator
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: TouchInputUIView, context: Context) {
        context.coordinator.state = state
        context.coordinator.onNext = onNext
        context.coordinator.onPrevious = onPrevious
        uiView.coordinator = context.coordinator
    }

    @MainActor
    final class Coordinator {
        var state: PDFPresentationState
        var onNext: () -> Void
        var onPrevious: () -> Void

        init(state: PDFPresentationState, onNext: @escaping () -> Void, onPrevious: @escaping () -> Void) {
            self.state = state
            self.onNext = onNext
            self.onPrevious = onPrevious
        }

        func handleTouchBegan(at viewportPoint: CGPoint, viewportSize: CGSize) {
            guard let normalizedPoint = state.normalizedPagePoint(
                from: viewportPoint,
                viewportSize: viewportSize
            ) else {
                return
            }

            switch state.selectedTool {
            case .pen:
                state.beginPenStroke(at: normalizedPoint)
            case .erase:
                state.beginErase(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint, isPressed: true, persistsUntilCleared: false)
            case .laserTrail:
                state.beginLaserTrail(at: normalizedPoint)
            case .none:
                break
            }
        }

        func handleTouchMoved(at viewportPoint: CGPoint, viewportSize: CGSize) {
            guard let normalizedPoint = state.normalizedPagePoint(
                from: viewportPoint,
                viewportSize: viewportSize
            ) else {
                return
            }

            switch state.selectedTool {
            case .pen:
                state.appendPenStroke(at: normalizedPoint)
            case .erase:
                state.continueErase(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint, isPressed: true, persistsUntilCleared: false)
            case .laserTrail:
                state.appendLaserTrail(at: normalizedPoint)
            case .none:
                break
            }
        }

        func handleTouchEnded(at viewportPoint: CGPoint, viewportSize: CGSize) {
            guard let normalizedPoint = state.normalizedPagePoint(
                from: viewportPoint,
                viewportSize: viewportSize
            ) else {
                return
            }

            switch state.selectedTool {
            case .pen:
                state.endPenStroke(at: normalizedPoint)
            case .erase:
                state.endErase(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint, isPressed: false, persistsUntilCleared: false)
            case .laserTrail:
                state.endLaserTrail(at: normalizedPoint)
            case .none:
                break
            }
        }

        func cancelTouch() {
            state.cancelPenStroke()
            state.cancelErase()
            state.cancelLaserTrail()
            state.clearLaserDot()
        }

        func zoom(by factor: CGFloat, around anchor: CGPoint, viewportSize: CGSize) {
            cancelTouch()
            state.zoom(by: factor, around: anchor, viewportSize: viewportSize)
        }

        func pan(by translation: CGSize, viewportSize: CGSize) {
            cancelTouch()
            state.pan(by: translation, viewportSize: viewportSize)
        }
    }
}

@MainActor
final class TouchInputUIView: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: TouchInputView.Coordinator?
    private var lastPinchScale: CGFloat = 1

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(rightArrowCommand)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(downArrowCommand)),
            UIKeyCommand(input: " ", modifierFlags: [], action: #selector(nextCommand)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(leftArrowCommand)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(upArrowCommand)),
            UIKeyCommand(input: "\u{8}", modifierFlags: [], action: #selector(previousCommand)),
            UIKeyCommand(input: "=", modifierFlags: .command, action: #selector(zoomInCommand)),
            UIKeyCommand(input: "+", modifierFlags: [.command, .shift], action: #selector(zoomInCommand)),
            UIKeyCommand(input: "-", modifierFlags: .command, action: #selector(zoomOutCommand)),
            UIKeyCommand(input: "0", modifierFlags: .command, action: #selector(resetZoomCommand))
        ]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
        installGestureRecognizersIfNeeded()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isSingleTouch(touches, event: event), let point = localPoint(from: touches.first) else {
            coordinator?.cancelTouch()
            return
        }

        coordinator?.handleTouchBegan(at: point, viewportSize: bounds.size)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isSingleTouch(touches, event: event), let point = localPoint(from: touches.first) else {
            coordinator?.cancelTouch()
            return
        }

        coordinator?.handleTouchMoved(at: point, viewportSize: bounds.size)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = localPoint(from: touches.first) else {
            return
        }

        coordinator?.handleTouchEnded(at: point, viewportSize: bounds.size)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.cancelTouch()
    }

    @objc private func nextCommand() {
        guard coordinator?.state.isZoomed != true else {
            return
        }

        coordinator?.onNext()
    }

    @objc private func previousCommand() {
        guard coordinator?.state.isZoomed != true else {
            return
        }

        coordinator?.onPrevious()
    }

    @objc private func rightArrowCommand() {
        panOrNavigate(
            zoomedTranslation: CGSize(width: -bounds.width * 0.1, height: 0),
            navigate: coordinator?.onNext
        )
    }

    @objc private func downArrowCommand() {
        panOrNavigate(
            zoomedTranslation: CGSize(width: 0, height: -bounds.height * 0.1),
            navigate: coordinator?.onNext
        )
    }

    @objc private func leftArrowCommand() {
        panOrNavigate(
            zoomedTranslation: CGSize(width: bounds.width * 0.1, height: 0),
            navigate: coordinator?.onPrevious
        )
    }

    @objc private func upArrowCommand() {
        panOrNavigate(
            zoomedTranslation: CGSize(width: 0, height: bounds.height * 0.1),
            navigate: coordinator?.onPrevious
        )
    }

    @objc private func zoomInCommand() {
        coordinator?.state.zoomIn()
    }

    @objc private func zoomOutCommand() {
        coordinator?.state.zoomOut()
    }

    @objc private func resetZoomCommand() {
        coordinator?.state.resetZoom()
    }

    @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        guard let selectedTool = coordinator?.state.selectedTool, selectedTool == PresentationTool.none else {
            return
        }

        switch recognizer.direction {
        case .left:
            coordinator?.onNext()
        case .right:
            coordinator?.onPrevious()
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            lastPinchScale = 1
            coordinator?.cancelTouch()
        case .changed:
            let factor = recognizer.scale / lastPinchScale
            coordinator?.zoom(
                by: factor,
                around: recognizer.location(in: self),
                viewportSize: bounds.size
            )
            lastPinchScale = recognizer.scale
        case .ended, .cancelled, .failed:
            lastPinchScale = 1
        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            coordinator?.cancelTouch()
            recognizer.setTranslation(.zero, in: self)
        case .changed:
            let translation = recognizer.translation(in: self)
            coordinator?.pan(
                by: CGSize(width: translation.x, height: translation.y),
                viewportSize: bounds.size
            )
            recognizer.setTranslation(.zero, in: self)
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer {
            return coordinator?.state.isZoomed == true
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer ||
            otherGestureRecognizer is UIPinchGestureRecognizer
    }

    private func installGestureRecognizersIfNeeded() {
        guard gestureRecognizers?.isEmpty ?? true else {
            return
        }

        let leftSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        leftSwipe.direction = .left
        leftSwipe.numberOfTouchesRequired = 1
        addGestureRecognizer(leftSwipe)

        let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        rightSwipe.direction = .right
        rightSwipe.numberOfTouchesRequired = 1
        addGestureRecognizer(rightSwipe)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        pinch.cancelsTouchesInView = true
        addGestureRecognizer(pinch)

        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = self
        twoFingerPan.cancelsTouchesInView = true
        addGestureRecognizer(twoFingerPan)
    }

    private func isSingleTouch(_ touches: Set<UITouch>, event: UIEvent?) -> Bool {
        let touchCount = event?.allTouches?.count ?? touches.count
        return touchCount == 1
    }

    private func panOrNavigate(zoomedTranslation: CGSize, navigate: (() -> Void)?) {
        guard coordinator?.state.isZoomed == true else {
            navigate?()
            return
        }

        coordinator?.pan(by: zoomedTranslation, viewportSize: bounds.size)
    }

    private func localPoint(from touch: UITouch?) -> CGPoint? {
        guard let touch else {
            return nil
        }

        return touch.location(in: self)
    }
}
