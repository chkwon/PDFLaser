import Foundation
import PDFKit

enum PDFDocumentLoaderError: LocalizedError {
    case emptyOrUnreadablePDF

    var errorDescription: String? {
        switch self {
        case .emptyOrUnreadablePDF:
            return "The selected file could not be opened as a PDF."
        }
    }
}

enum PDFDocumentLoader {
    static func loadPDF(from url: URL) throws -> PDFDocument {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw PDFDocumentLoaderError.emptyOrUnreadablePDF
        }

        return document
    }
}
