import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var tabsModel = PDFTabsModel()
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportDocument = ExportedPDFDocument()
    @State private var sharedPDFItem: SharedPDFItem?
    @State private var isPDFDropTargeted = false
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
    @State private var sharePicker: NSSharingServicePicker?

    private let toolbarHideDelay: TimeInterval = 1.0
    #endif

    var body: some View {
        platformContent
            .pdfDropTarget(isTargeted: $isPDFDropTargeted) { urls in
                tabsModel.openPDFs(urls: urls)
            }
            .overlay {
                if isPDFDropTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: 3)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .focusedSceneObject(tabsModel)
            .onOpenURL { url in
                tabsModel.openPDFs(urls: [url])
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
            .platformPDFShareSheet(item: $sharedPDFItem)
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
            shareAction: {
                prepareMarkedPDFShare()
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
            },
            shareAction: {
                prepareMarkedPDFShare()
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

    private func prepareMarkedPDFShare() {
        do {
            let url = try TemporaryPDFShareFile.write(
                data: try PDFMarkupExporter.exportPDFData(from: state),
                filename: state.exportDefaultFilename
            )
            presentMarkedPDFShare(url: url)
        } catch {
            alertTitle = "Could not share PDF"
            state.errorMessage = error.localizedDescription
        }
    }

    private func presentMarkedPDFShare(url: URL) {
        #if os(macOS)
        guard let contentView = NSApp.keyWindow?.contentView else {
            alertTitle = "Could not share PDF"
            state.errorMessage = "Could not find a window to present the share menu."
            return
        }

        let fallbackPoint = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY)
        let eventPoint = NSApp.currentEvent.map {
            contentView.convert($0.locationInWindow, from: nil)
        }

        sharePicker = NSSharingServicePicker(items: [url])
        sharePicker?.show(
            relativeTo: CGRect(origin: eventPoint ?? fallbackPoint, size: .zero),
            of: contentView,
            preferredEdge: .minY
        )
        #else
        sharedPDFItem = SharedPDFItem(url: url)
        #endif
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

private struct SharedPDFItem: Identifiable {
    let id = UUID()
    let url: URL
}

private enum TemporaryPDFShareFile {
    static func write(data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFLaserSharedPDFs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let sanitizedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareFilename = sanitizedFilename.isEmpty ? "PDF Laser Marked.pdf" : sanitizedFilename
        let url = directory.appendingPathComponent(shareFilename)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private enum PDFDropURLLoader {
    static func loadPDFURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard !fileProviders.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let collector = PDFDropURLCollector()

        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = pdfURL(from: item) {
                    collector.append(url, at: index)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(collector.urls)
        }
    }

    private static func pdfURL(from item: NSSecureCoding?) -> URL? {
        let candidateURL: URL?

        switch item {
        case let url as URL:
            candidateURL = url
        case let url as NSURL:
            candidateURL = url as URL
        case let data as Data:
            candidateURL = url(from: data)
        case let string as String:
            candidateURL = url(from: string)
        default:
            candidateURL = nil
        }

        guard let candidateURL,
              candidateURL.isFileURL,
              candidateURL.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else {
            return nil
        }

        return candidateURL
    }

    private static func url(from data: Data) -> URL? {
        if let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }

        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return url(from: string)
    }

    private static func url(from string: String) -> URL? {
        let trimmedString = string.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))
        )
        return URL(string: trimmedString)
    }
}

private final class PDFDropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var indexedURLs: [(index: Int, url: URL)] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return indexedURLs
            .sorted { $0.index < $1.index }
            .map { $0.url }
    }

    func append(_ url: URL, at index: Int) {
        lock.lock()
        indexedURLs.append((index, url))
        lock.unlock()
    }
}

#if os(iOS)
private struct PDFActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
    }
}
#endif

private extension View {
    func pdfDropTarget(
        isTargeted: Binding<Bool>,
        onDropPDFs: @escaping ([URL]) -> Void
    ) -> some View {
        onDrop(of: [UTType.fileURL.identifier], isTargeted: isTargeted) { providers in
            PDFDropURLLoader.loadPDFURLs(from: providers) { urls in
                guard !urls.isEmpty else { return }
                onDropPDFs(urls)
            }
            return providers.contains {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            }
        }
    }

    @ViewBuilder
    func platformPDFShareSheet(item: Binding<SharedPDFItem?>) -> some View {
        #if os(iOS)
        sheet(item: item) { item in
            PDFActivityView(activityItems: [item.url])
        }
        #else
        let _ = item
        self
        #endif
    }
}
