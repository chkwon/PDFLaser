import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MarkedDocumentExport {
    var data: Data
    var contentType: UTType
    var filename: String
}

enum MarkedDocumentExporter {
    @MainActor
    static func exportMarkedDocument(from state: PDFPresentationState) throws -> MarkedDocumentExport {
        let source = state.sourceDocument

        switch source {
        case .image(let imageSource):
            let data = try ImageMarkupExporter.exportImageData(
                source: imageSource,
                penStrokesByPage: state.penStrokesByPage,
                activePenStroke: state.activePenStroke,
                activePenPageIndex: state.currentPageIndex
            )
            return MarkedDocumentExport(
                data: data,
                contentType: imageSource.contentType,
                filename: imageSource.markedFilename
            )

        case .pdf, .none:
            return MarkedDocumentExport(
                data: try PDFMarkupExporter.exportPDFData(from: state),
                contentType: .pdf,
                filename: source?.markedFilename ?? "PDF Laser Marked.pdf"
            )
        }
    }
}

enum ImageMarkupExportError: LocalizedError {
    case couldNotCreateBitmapContext
    case couldNotCreateMarkedImage
    case couldNotEncodeImage

    var errorDescription: String? {
        switch self {
        case .couldNotCreateBitmapContext:
            return "Could not create an image canvas for the marked copy."
        case .couldNotCreateMarkedImage:
            return "Could not render the marked image."
        case .couldNotEncodeImage:
            return "Could not save the marked image in the original format."
        }
    }
}

enum ImageMarkupExporter {
    static func exportImageData(
        source: ImagePresentationSource,
        penStrokesByPage: [Int: [PenStroke]],
        activePenStroke: PenStroke?,
        activePenPageIndex: Int
    ) throws -> Data {
        let pageSize = source.pixelSize
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: source.pixelWidth,
            height: source.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageMarkupExportError.couldNotCreateBitmapContext
        }

        context.interpolationQuality = .high
        PresentationDocumentLoader.drawImageInBitmapContext(
            source.cgImage,
            in: context,
            rect: CGRect(origin: .zero, size: pageSize)
        )

        var strokes = penStrokesByPage[0] ?? []
        if activePenPageIndex == 0, let activePenStroke {
            strokes.append(activePenStroke)
        }

        PDFMarkupExporter.drawPenStrokes(
            scaledStrokes(strokes, from: source.presentationSize, to: pageSize),
            in: context,
            pageSize: pageSize
        )

        guard let markedImage = context.makeImage() else {
            throw ImageMarkupExportError.couldNotCreateMarkedImage
        }

        return try encode(markedImage, as: source.contentType)
    }

    private static func scaledStrokes(
        _ strokes: [PenStroke],
        from presentationSize: CGSize,
        to pixelSize: CGSize
    ) -> [PenStroke] {
        guard presentationSize.width > 0, presentationSize.height > 0 else {
            return strokes
        }

        let widthScale = max(
            pixelSize.width / presentationSize.width,
            pixelSize.height / presentationSize.height
        )

        return strokes.map { stroke in
            PenStroke(
                normalizedPoints: stroke.normalizedPoints,
                color: stroke.color,
                width: stroke.width * widthScale
            )
        }
    }

    private static func encode(_ image: CGImage, as contentType: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageMarkupExportError.couldNotEncodeImage
        }

        CGImageDestinationAddImage(
            destination,
            image,
            encodeProperties(for: contentType)
        )

        guard CGImageDestinationFinalize(destination) else {
            throw ImageMarkupExportError.couldNotEncodeImage
        }

        return data as Data
    }

    private static func encodeProperties(for contentType: UTType) -> CFDictionary? {
        guard contentType == .jpeg || contentType == .heic || contentType == .heif else {
            return nil
        }

        return [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ] as CFDictionary
    }
}

private extension ImagePresentationSource {
    var markedFilename: String {
        let baseName = url.deletingPathExtension().lastPathComponent
        return "\(baseName) Marked.\(fileExtension)"
    }
}
