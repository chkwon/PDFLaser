import AppKit
import SwiftUI

struct MacKeyboardHandlingView: NSViewRepresentable {
    var onNext: () -> Void
    var onPrevious: () -> Void

    func makeNSView(context: Context) -> KeyboardView {
        let view = KeyboardView()
        view.onNext = onNext
        view.onPrevious = onPrevious
        return view
    }

    func updateNSView(_ nsView: KeyboardView, context: Context) {
        nsView.onNext = onNext
        nsView.onPrevious = onPrevious

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyboardView: NSView {
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 124, 125, 49:
            onNext?()
        case 123, 126, 51:
            onPrevious?()
        default:
            super.keyDown(with: event)
        }
    }
}
