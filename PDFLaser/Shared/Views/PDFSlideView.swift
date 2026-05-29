import PDFKit
import SwiftUI

struct PDFSlideView: View {
    @ObservedObject var state: PDFPresentationState

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.105, green: 0.11, blue: 0.115)
                    .ignoresSafeArea()

                if state.document == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.secondary)

                        Text("Open a PDF to present")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    slideStack(in: proxy.size)
                }
            }
        }
    }

    private func slideStack(in containerSize: CGSize) -> some View {
        let pageSize = fittedPageSize(in: containerSize, aspectRatio: state.currentPageAspectRatio)
        let contentSize = CGSize(
            width: pageSize.width * state.zoomScale,
            height: pageSize.height * state.zoomScale
        )

        return ZStack {
            ZStack {
                #if os(macOS)
                MacPDFViewRepresentable(page: state.currentPage)
                #else
                IOSPDFViewRepresentable(page: state.currentPage)
                #endif

                PresentationCanvasView(state: state, zoomScale: state.zoomScale)
            }
            .frame(width: contentSize.width, height: contentSize.height)
            .offset(x: state.panOffset.width, y: state.panOffset.height)
            .allowsHitTesting(false)

            #if os(macOS)
            MacPointerInputView(state: state)
                .frame(width: pageSize.width, height: pageSize.height)
            #else
            TouchInputView(
                state: state,
                onNext: { state.nextPage() },
                onPrevious: { state.previousPage() }
            )
            .frame(width: pageSize.width, height: pageSize.height)
            #endif
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .background(Color.white)
        .clipShape(Rectangle())
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            state.updateZoomViewportSize(pageSize)
        }
        .onChange(of: pageSize) { _, newValue in
            state.updateZoomViewportSize(newValue)
        }
        .onChange(of: state.zoomScale) { _, _ in
            state.clampPan(viewportSize: pageSize)
        }
    }

    private func fittedPageSize(in containerSize: CGSize, aspectRatio: CGFloat) -> CGSize {
        let availableWidth = max(containerSize.width - 32, 1)
        let availableHeight = max(containerSize.height - 32, 1)
        let safeAspectRatio = max(aspectRatio, 0.01)
        let availableAspectRatio = availableWidth / availableHeight

        if availableAspectRatio > safeAspectRatio {
            let height = availableHeight
            return CGSize(width: height * safeAspectRatio, height: height)
        } else {
            let width = availableWidth
            return CGSize(width: width, height: width / safeAspectRatio)
        }
    }
}
