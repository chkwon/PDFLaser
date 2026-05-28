import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var tabsModel = PDFTabsModel()
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportDocument = ExportedPDFDocument()
    @State private var alertTitle = "PDF Laser"

    private var state: PDFPresentationState {
        tabsModel.activeTab
    }

    #if os(macOS)
    @State private var isFullScreen = false
    @State private var isToolbarVisible = true
    @State private var isToolbarHovered = false
    @State private var toolbarHeight: CGFloat = 0
    @State private var hideWorkItem: DispatchWorkItem?

    private let toolbarHideDelay: TimeInterval = 1.0
    #endif

    var body: some View {
        platformContent
            .focusedSceneObject(tabsModel)
            .onOpenURL { url in
                tabsModel.openPDF(url: url)
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

                    tabsModel.openPDF(url: url)
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
    }

    private var presenterToolbar: PresenterToolbar {
        #if os(macOS)
        PresenterToolbar(
            state: state,
            openAction: {
                alertTitle = "Could not open PDF"
                isImporterPresented = true
            },
            saveAction: {
                prepareMarkedPDFExport()
            },
            isFullScreen: isFullScreen
        )
        #else
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
        #endif
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        macContent
        #else
        stackedContent
        #endif
    }

    private var stackedContent: some View {
        VStack(spacing: 0) {
            PDFTabBarView(tabsModel: tabsModel)
            presenterToolbar
            PDFSlideView(state: state)
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var macContent: some View {
        Group {
            if isFullScreen {
                ZStack(alignment: .top) {
                    PDFSlideView(state: state)

                    MacMouseActivityView(onMove: handleMouseMove)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 0) {
                        PDFTabBarView(tabsModel: tabsModel)
                        presenterToolbar
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ToolbarHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                    .offset(y: isToolbarVisible ? 0 : -toolbarHeight)
                    .opacity(isToolbarVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isToolbarVisible)
                    .onHover(perform: handleToolbarHover)
                }
                .onPreferenceChange(ToolbarHeightPreferenceKey.self) { value in
                    toolbarHeight = value
                }
            } else {
                stackedContent
            }
        }
        .background(
            MacKeyboardHandlingView(
                onNext: { state.nextPage() },
                onPrevious: { state.previousPage() }
            )
            .frame(width: 0, height: 0)
        )
        .background(
            MacFullScreenObserver(onChange: handleFullScreenChange)
                .frame(width: 0, height: 0)
        )
        .frame(minWidth: 900, minHeight: 620)
    }

    private func handleFullScreenChange(_ value: Bool) {
        guard isFullScreen != value else { return }
        isFullScreen = value
        cancelHideTimer()
        if value {
            isToolbarHovered = false
            isToolbarVisible = false
        } else {
            isToolbarVisible = true
        }
    }

    private func handleMouseMove(at point: CGPoint) {
        guard isFullScreen else { return }
        let hotZoneHeight = max(toolbarHeight, 60)
        guard point.y <= hotZoneHeight else { return }
        if !isToolbarVisible {
            isToolbarVisible = true
        }
        if !isToolbarHovered {
            scheduleHide()
        }
    }

    private func handleToolbarHover(_ hovering: Bool) {
        isToolbarHovered = hovering
        if hovering {
            cancelHideTimer()
            if !isToolbarVisible {
                isToolbarVisible = true
            }
        } else if isFullScreen {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        cancelHideTimer()
        let item = DispatchWorkItem { [self] in
            guard isFullScreen, !isToolbarHovered else { return }
            isToolbarVisible = false
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + toolbarHideDelay, execute: item)
    }

    private func cancelHideTimer() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }
    #endif

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

#if os(macOS)
private struct ToolbarHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
#endif
