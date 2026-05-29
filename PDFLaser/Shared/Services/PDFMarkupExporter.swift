import CoreGraphics
import Foundation
import PDFKit

enum PDFMarkupExportError: LocalizedError {
    case noDocument
    case couldNotCreateContext

    var errorDescription: String? {
        switch self {
        case .noDocument:
            return "Open a document before saving a marked copy."
        case .couldNotCreateContext:
            return "Could not create the exported PDF."
        }
    }
}

enum PDFMarkupExporter {
    @MainActor
    static func exportPDFData(from state: PDFPresentationState) throws -> Data {
        try exportPDFData(
            document: state.document,
            penStrokesByPage: state.penStrokesByPage,
            activePenStroke: state.activePenStroke,
            activePenPageIndex: state.currentPageIndex
        )
    }

    static func exportPDFData(
        document: PDFDocument?,
        penStrokesByPage: [Int: [PenStroke]],
        activePenStroke: PenStroke?,
        activePenPageIndex: Int
    ) throws -> Data {
        guard let document else {
            throw PDFMarkupExportError.noDocument
        }

        let outputData = NSMutableData()
        guard let consumer = CGDataConsumer(data: outputData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw PDFMarkupExportError.couldNotCreateContext
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            let pageBounds = page.bounds(for: .cropBox)
            guard pageBounds.width > 0, pageBounds.height > 0 else {
                continue
            }

            let mediaBox = CGRect(origin: .zero, size: pageBounds.size)
            context.beginPDFPage(pageInfo(for: mediaBox))
            draw(page: page, in: context, pageBounds: pageBounds)

            var strokes = penStrokesByPage[pageIndex] ?? []
            if pageIndex == activePenPageIndex, let activePenStroke {
                strokes.append(activePenStroke)
            }

            drawPenStrokes(strokes, in: context, pageSize: mediaBox.size)
            context.endPDFPage()
        }

        context.closePDF()
        return outputData as Data
    }

    static func pageInfo(for mediaBox: CGRect) -> CFDictionary {
        var mediaBox = mediaBox
        let mediaBoxData = NSData(
            bytes: &mediaBox,
            length: MemoryLayout<CGRect>.size
        )

        return [
            kCGPDFContextMediaBox as String: mediaBoxData
        ] as CFDictionary
    }

    private static func draw(page: PDFPage, in context: CGContext, pageBounds: CGRect) {
        context.saveGState()
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }

    static func drawPenStrokes(_ strokes: [PenStroke], in context: CGContext, pageSize: CGSize) {
        for stroke in strokes where !stroke.normalizedPoints.isEmpty {
            context.saveGState()
            context.setStrokeColor(stroke.color.cgColor)
            context.setFillColor(stroke.color.cgColor)
            context.setLineWidth(stroke.width)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            if stroke.normalizedPoints.count == 1, let point = stroke.normalizedPoints.first {
                let pdfPoint = pdfPoint(from: point, pageSize: pageSize)
                let radius = stroke.width / 2
                context.fillEllipse(
                    in: CGRect(
                        x: pdfPoint.x - radius,
                        y: pdfPoint.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            } else {
                let path = CGMutablePath()
                if let firstPoint = stroke.normalizedPoints.first {
                    path.move(to: pdfPoint(from: firstPoint, pageSize: pageSize))

                    for point in stroke.normalizedPoints.dropFirst() {
                        path.addLine(to: pdfPoint(from: point, pageSize: pageSize))
                    }
                }

                context.addPath(path)
                context.strokePath()
            }

            context.restoreGState()
        }
    }

    private static func pdfPoint(from normalizedPoint: CGPoint, pageSize: CGSize) -> CGPoint {
        let normalizedPoint = normalizedPoint.clampedToUnitSquare
        return CGPoint(
            x: normalizedPoint.x * pageSize.width,
            y: (1 - normalizedPoint.y) * pageSize.height
        )
    }
}
