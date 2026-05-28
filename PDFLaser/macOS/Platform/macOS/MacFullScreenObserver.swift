import AppKit
import SwiftUI

struct MacFullScreenObserver: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> FullScreenObserverNSView {
        let view = FullScreenObserverNSView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: FullScreenObserverNSView, context: Context) {
        nsView.onChange = onChange
    }
}

final class FullScreenObserverNSView: NSView {
    var onChange: ((Bool) -> Void)?

    private var observedWindow: NSWindow?
    private var enterToken: NSObjectProtocol?
    private var exitToken: NSObjectProtocol?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        unsubscribe()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        subscribe(to: window)
        if let window {
            onChange?(window.styleMask.contains(.fullScreen))
        }
    }

    private func subscribe(to window: NSWindow?) {
        observedWindow = window
        guard let window else { return }

        enterToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?(true)
            }
        }

        exitToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?(false)
            }
        }
    }

    private func unsubscribe() {
        if let enterToken {
            NotificationCenter.default.removeObserver(enterToken)
            self.enterToken = nil
        }
        if let exitToken {
            NotificationCenter.default.removeObserver(exitToken)
            self.exitToken = nil
        }
        observedWindow = nil
    }
}
