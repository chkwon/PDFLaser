import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum PresentationDocumentLoaderError: LocalizedError {
    case unsupportedFileType
    case emptyOrUnreadablePDF
    case emptyOrUnreadableImage
    case couldNotCreatePresentationPDF

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "The selected file is not a supported PDF or image."
        case .emptyOrUnreadablePDF:
            return "The selected file could not be opened as a PDF."
        case .emptyOrUnreadableImage:
            return "The selected file could not be opened as an image."
        case .couldNotCreatePresentationPDF:
            return "Could not prepare the image for presentation."
        }
    }
}

enum PresentationDocumentLoader {
    private static let maximumImagePresentationLongEdge: CGFloat = 1280

    static func loadDocument(from url: URL) throws -> LoadedPresentationDocument {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)

        if PresentationSupportedFileTypes.isPDFFileURL(url) {
            let document = try loadPDF(from: data)
            return LoadedPresentationDocument(document: document, source: .pdf(url: url))
        }

        if let imageContentType = PresentationSupportedFileTypes.imageContentType(for: url) {
            return try loadImageDocument(
                from: data,
                url: url,
                contentType: imageContentType
            )
        }

        throw PresentationDocumentLoaderError.unsupportedFileType
    }

    static func loadPDFDocument(from url: URL) throws -> PDFDocument {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try loadPDF(from: Data(contentsOf: url))
    }

    private static func loadPDF(from data: Data) throws -> PDFDocument {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw PresentationDocumentLoaderError.emptyOrUnreadablePDF
        }

        return document
    }

    private static func loadImageDocument(
        from data: Data,
        url: URL,
        contentType: UTType
    ) throws -> LoadedPresentationDocument {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let rawImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw PresentationDocumentLoaderError.emptyOrUnreadableImage
        }

        let cgImage = try orientedImage(rawImage, from: imageSource)
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let presentationSize = presentationSize(for: pixelSize)
        let document = try makePresentationPDF(from: cgImage, pageSize: presentationSize)
        let fileExtension = url.pathExtension.isEmpty ? (contentType.preferredFilenameExtension ?? "png") : url.pathExtension
        let presentationSource = ImagePresentationSource(
            url: url,
            cgImage: cgImage,
            contentType: contentType,
            fileExtension: fileExtension,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            presentationSize: presentationSize
        )

        return LoadedPresentationDocument(document: document, source: .image(presentationSource))
    }

    private static func orientedImage(
        _ image: CGImage,
        from imageSource: CGImageSource
    ) throws -> CGImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1

        guard orientation != 1 else {
            return image
        }

        let orientedImage = CIImage(cgImage: image)
            .oriented(forExifOrientation: Int32(orientation))
        let extent = orientedImage.extent.integral
        let normalizedImage = orientedImage.transformed(
            by: CGAffineTransform(
                translationX: -extent.origin.x,
                y: -extent.origin.y
            )
        )
        let normalizedExtent = CGRect(origin: .zero, size: extent.size)
        let context = CIContext(options: nil)

        guard let cgImage = context.createCGImage(normalizedImage, from: normalizedExtent) else {
            throw PresentationDocumentLoaderError.emptyOrUnreadableImage
        }

        return cgImage
    }

    private static func presentationSize(for pixelSize: CGSize) -> CGSize {
        let longEdge = max(pixelSize.width, pixelSize.height)
        guard longEdge > maximumImagePresentationLongEdge else {
            return pixelSize
        }

        let scale = maximumImagePresentationLongEdge / longEdge
        return CGSize(
            width: max(pixelSize.width * scale, 1),
            height: max(pixelSize.height * scale, 1)
        )
    }

    private static func makePresentationPDF(from image: CGImage, pageSize: CGSize) throws -> PDFDocument {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PresentationDocumentLoaderError.couldNotCreatePresentationPDF
        }

        context.beginPDFPage(PDFMarkupExporter.pageInfo(for: mediaBox))
        drawImageInPDFPage(image, in: context, rect: mediaBox)
        context.endPDFPage()
        context.closePDF()

        guard let document = PDFDocument(data: data as Data), document.pageCount > 0 else {
            throw PresentationDocumentLoaderError.couldNotCreatePresentationPDF
        }

        return document
    }

    private static func drawImageInPDFPage(_ image: CGImage, in context: CGContext, rect: CGRect) {
        context.draw(
            image,
            in: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: rect.height
            )
        )
    }

    static func drawImageInBitmapContext(_ image: CGImage, in context: CGContext, rect: CGRect) {
        context.draw(
            image,
            in: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: rect.height
            )
        )
    }
}

enum PDFDocumentLoader {
    static func loadPDF(from url: URL) throws -> PDFDocument {
        try PresentationDocumentLoader.loadPDFDocument(from: url)
    }
}
