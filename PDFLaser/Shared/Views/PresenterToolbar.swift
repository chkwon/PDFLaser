import SwiftUI

#if os(macOS)
import AppKit
#endif

struct PresenterToolbar: View {
    @ObservedObject var state: PDFPresentationState
    var openAction: () -> Void
    var saveAction: () -> Void
    var shareAction: () -> Void
    #if os(macOS)
    var isFullScreen: Bool = false
    var toggleFullScreenAction: () -> Void = {
        NSApp.sendAction(#selector(NSWindow.toggleFullScreen(_:)), to: nil, from: nil)
    }
    #endif

    var body: some View {
        HStack(spacing: 10) {
            toolbarButton("Open PDF", systemImage: "folder", action: openAction)

            toolbarButton("Save Marked PDF", systemImage: "square.and.arrow.down", action: saveAction)
            .disabled(state.document == nil)

            toolbarButton("Share Marked PDF", systemImage: "square.and.arrow.up", action: shareAction)
            .disabled(state.document == nil)

            Divider()
                .frame(height: 22)

            toolbarButton("Previous", systemImage: "chevron.left") {
                state.previousPage()
            }
            .disabled(!state.canGoPrevious)

            toolbarButton("Next", systemImage: "chevron.right") {
                state.nextPage()
            }
            .disabled(!state.canGoNext)

            Text("\(state.currentPageDisplayNumber) / \(state.pageCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 58, alignment: .leading)

            Divider()
                .frame(height: 22)

            Picker("Tool", selection: $state.selectedTool) {
                ForEach(PresentationTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImageName)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(Text(tool.title))
                        .presenterToolbarHelp(tool.title)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            .accessibilityLabel(Text("Tool"))
            .presenterToolbarHelp("Tool")

            Spacer(minLength: 8)

            toolbarButton("Undo", systemImage: "arrow.uturn.backward") {
                state.undoLastStrokeOnCurrentPage()
            }
            .disabled(!state.currentPageCanUndo)
            .keyboardShortcut("z", modifiers: .command)

            toolbarButton("Redo", systemImage: "arrow.uturn.forward") {
                state.redoLastUndoOnCurrentPage()
            }
            .disabled(!state.currentPageCanRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            toolbarButton("Clear", systemImage: "trash") {
                state.clearMarkupOnCurrentPage()
            }
            .disabled(!state.currentPageHasMarkup)

            #if os(macOS)
            Divider()
                .frame(height: 22)

            toolbarButton(
                isFullScreen ? "Exit Full Screen" : "Enter Full Screen",
                systemImage: isFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                action: toggleFullScreenAction
            )
            #endif
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func toolbarButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(minWidth: 20)
        }
        .accessibilityLabel(Text(title))
        .presenterToolbarHelp(title)
    }
}

private extension View {
    @ViewBuilder
    func presenterToolbarHelp(_ title: String) -> some View {
        #if os(macOS)
        help(title)
        #else
        self
        #endif
    }
}
