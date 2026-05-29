import AppKit
import PDFKit
import SwiftUI

struct MacPDFViewRepresentable: NSViewRepresentable {
    var page: PDFPage?

    func makeNSView(context: Context) -> MacPDFPageView {
        let view = MacPDFPageView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        return view
    }

    func updateNSView(_ nsView: MacPDFPageView, context: Context) {
        nsView.page = page
    }
}

final class MacPDFPageView: NSView {
    var page: PDFPage? {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        guard let page, let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let pageBounds = page.bounds(for: .cropBox)
        let scale = min(bounds.width / pageBounds.width, bounds.height / pageBounds.height)
        let scaledSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        let origin = CGPoint(
            x: (bounds.width - scaledSize.width) / 2,
            y: (bounds.height - scaledSize.height) / 2
        )

        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }
}
