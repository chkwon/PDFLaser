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
        view.isMultipleTouchEnabled = false
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

        func handleTouchBegan(at normalizedPoint: CGPoint) {
            switch state.selectedTool {
            case .pen:
                state.beginPenStroke(at: normalizedPoint)
            case .erase:
                state.beginErase(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint)
            case .laserTrail:
                state.beginLaserTrail(at: normalizedPoint)
            case .none:
                break
            }
        }

        func handleTouchMoved(at normalizedPoint: CGPoint) {
            switch state.selectedTool {
            case .pen:
                state.appendPenStroke(at: normalizedPoint)
            case .erase:
                state.continueErase(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint)
            case .laserTrail:
                state.appendLaserTrail(at: normalizedPoint)
            case .none:
                break
            }
        }

        func handleTouchEnded(at normalizedPoint: CGPoint) {
            switch state.selectedTool {
            case .pen:
                state.endPenStroke(at: normalizedPoint)
            case .erase:
                state.endErase(at: normalizedPoint)
            case .laserDot:
                state.updateLaserDot(at: normalizedPoint)
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
        }
    }
}

@MainActor
final class TouchInputUIView: UIView {
    weak var coordinator: TouchInputView.Coordinator?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(nextCommand)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(nextCommand)),
            UIKeyCommand(input: " ", modifierFlags: [], action: #selector(nextCommand)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(previousCommand)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(previousCommand)),
            UIKeyCommand(input: "\u{8}", modifierFlags: [], action: #selector(previousCommand))
        ]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
        installSwipeRecognizersIfNeeded()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = normalizedPoint(from: touches.first) else {
            return
        }

        coordinator?.handleTouchBegan(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = normalizedPoint(from: touches.first) else {
            return
        }

        coordinator?.handleTouchMoved(at: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = normalizedPoint(from: touches.first) else {
            return
        }

        coordinator?.handleTouchEnded(at: point)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.cancelTouch()
    }

    @objc private func nextCommand() {
        coordinator?.onNext()
    }

    @objc private func previousCommand() {
        coordinator?.onPrevious()
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

    private func installSwipeRecognizersIfNeeded() {
        guard gestureRecognizers?.isEmpty ?? true else {
            return
        }

        let leftSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        leftSwipe.direction = .left
        addGestureRecognizer(leftSwipe)

        let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        rightSwipe.direction = .right
        addGestureRecognizer(rightSwipe)
    }

    private func normalizedPoint(from touch: UITouch?) -> CGPoint? {
        guard let touch else {
            return nil
        }

        return CGPoint.normalized(from: touch.location(in: self), in: bounds.size)
    }
}
