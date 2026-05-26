import PDFKit
import SwiftUI
import UIKit

struct IOSPDFViewRepresentable: UIViewRepresentable {
    var page: PDFPage?

    func makeUIView(context: Context) -> IOSPDFPageView {
        let view = IOSPDFPageView()
        view.backgroundColor = .white
        view.isOpaque = true
        return view
    }

    func updateUIView(_ uiView: IOSPDFPageView, context: Context) {
        uiView.page = page
    }
}

final class IOSPDFPageView: UIView {
    var page: PDFPage? {
        didSet {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        UIColor.white.setFill()
        UIRectFill(bounds)

        guard let page, let context = UIGraphicsGetCurrentContext() else {
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
