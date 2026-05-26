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

        return ZStack {
            #if os(macOS)
            MacPDFViewRepresentable(page: state.currentPage)
            #else
            IOSPDFViewRepresentable(page: state.currentPage)
            #endif

            PresentationCanvasView(state: state)

            #if os(macOS)
            MacPointerInputView(state: state)
            #else
            TouchInputView(
                state: state,
                onNext: { state.nextPage() },
                onPrevious: { state.previousPage() }
            )
            #endif
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .background(Color.white)
        .clipShape(Rectangle())
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
