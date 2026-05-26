import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var state = PDFPresentationState()
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportDocument = ExportedPDFDocument()
    @State private var alertTitle = "PDF Laser"

    var body: some View {
        VStack(spacing: 0) {
            PresenterToolbar(
                state: state,
                openAction: {
                    alertTitle = "Could not open PDF"
                    isImporterPresented = true
                },
                saveAction: {
                    prepareMarkedPDFExport()
                }
            )

            PDFSlideView(state: state)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                state.openPDF(url: url)
            case .failure(let error):
                alertTitle = "Could not open PDF"
                state.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: state.exportDefaultFilename
        ) { result in
            if case .failure(let error) = result {
                alertTitle = "Could not save PDF"
                state.errorMessage = error.localizedDescription
            }
        }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        state.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                state.errorMessage = nil
            }
        } message: {
            Text(state.errorMessage ?? "")
        }
        #if os(macOS)
        .background(
            MacKeyboardHandlingView(
                onNext: { state.nextPage() },
                onPrevious: { state.previousPage() }
            )
            .frame(width: 0, height: 0)
        )
        .frame(minWidth: 900, minHeight: 620)
        #endif
    }

    private func prepareMarkedPDFExport() {
        do {
            exportDocument = ExportedPDFDocument(
                data: try PDFMarkupExporter.exportPDFData(from: state)
            )
            isExporterPresented = true
        } catch {
            alertTitle = "Could not save PDF"
            state.errorMessage = error.localizedDescription
        }
    }
}
