import SwiftUI

struct PresenterToolbar: View {
    @ObservedObject var state: PDFPresentationState
    var openAction: () -> Void
    var saveAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openAction) {
                Label("Open PDF", systemImage: "folder")
            }

            Button(action: saveAction) {
                Label("Save Marked PDF", systemImage: "square.and.arrow.down")
            }
            .disabled(state.document == nil)

            Divider()
                .frame(height: 22)

            Button(action: { state.previousPage() }) {
                Label("Previous", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .disabled(!state.canGoPrevious)

            Button(action: { state.nextPage() }) {
                Label("Next", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .disabled(!state.canGoNext)

            Text("\(state.currentPageDisplayNumber) / \(state.pageCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 58, alignment: .leading)

            Divider()
                .frame(height: 22)

            Picker("Tool", selection: $state.selectedTool) {
                ForEach(PresentationTool.allCases) { tool in
                    Text(tool.title)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Spacer(minLength: 8)

            Button(action: { state.undoLastStrokeOnCurrentPage() }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!state.currentPageCanUndo)

            Button(action: { state.clearMarkupOnCurrentPage() }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(!state.currentPageHasMarkup)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
