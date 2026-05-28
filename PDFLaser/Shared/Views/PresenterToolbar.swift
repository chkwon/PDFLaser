import SwiftUI

#if os(macOS)
import AppKit
#endif

struct PresenterToolbar: View {
    @ObservedObject var state: PDFPresentationState
    var openAction: () -> Void
    var saveAction: () -> Void
    #if os(macOS)
    var isFullScreen: Bool = false
    var toggleFullScreenAction: () -> Void = {
        NSApp.sendAction(#selector(NSWindow.toggleFullScreen(_:)), to: nil, from: nil)
    }
    #endif

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
            .keyboardShortcut("z", modifiers: .command)

            Button(action: { state.redoLastUndoOnCurrentPage() }) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!state.currentPageCanRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Button(action: { state.clearMarkupOnCurrentPage() }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(!state.currentPageHasMarkup)

            #if os(macOS)
            Divider()
                .frame(height: 22)

            Button(action: toggleFullScreenAction) {
                Label(
                    isFullScreen ? "Exit Full Screen" : "Enter Full Screen",
                    systemImage: isFullScreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
            }
            .labelStyle(.iconOnly)
            #endif
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
