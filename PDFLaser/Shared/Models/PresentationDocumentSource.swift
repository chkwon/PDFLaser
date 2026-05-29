import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers

struct LoadedPresentationDocument {
    var document: PDFDocument
    var source: PresentationDocumentSource
}

enum PresentationDocumentSource {
    case pdf(url: URL)
    case image(ImagePresentationSource)

    var url: URL {
        switch self {
        case .pdf(let url):
            return url
        case .image(let source):
            return source.url
        }
    }

    var exportContentType: UTType {
        switch self {
        case .pdf:
            return .pdf
        case .image(let source):
            return source.contentType
        }
    }

    var exportFileExtension: String {
        switch self {
        case .pdf:
            return "pdf"
        case .image(let source):
            return source.fileExtension
        }
    }

    var markedFilename: String {
        let baseName = url.deletingPathExtension().lastPathComponent
        return "\(baseName) Marked.\(exportFileExtension)"
    }

    var tabIconSystemName: String {
        switch self {
        case .pdf:
            return "doc.text"
        case .image:
            return "photo"
        }
    }
}

struct ImagePresentationSource {
    var url: URL
    var cgImage: CGImage
    var contentType: UTType
    var fileExtension: String
    var pixelWidth: Int
    var pixelHeight: Int
    var presentationSize: CGSize

    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }
}

enum PresentationSupportedFileTypes {
    static let imageContentTypes: [UTType] = [
        .png,
        .jpeg,
        .heic,
        .heif,
        .tiff
    ]

    static let importContentTypes: [UTType] = [.pdf] + imageContentTypes

    static func isSupportedFileURL(_ url: URL) -> Bool {
        isPDFFileURL(url) || imageContentType(for: url) != nil
    }

    static func isPDFFileURL(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
    }

    static func imageContentType(for url: URL) -> UTType? {
        switch url.pathExtension.lowercased() {
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        case "heic":
            return .heic
        case "heif":
            return .heif
        case "tif", "tiff":
            return .tiff
        default:
            return nil
        }
    }
}
