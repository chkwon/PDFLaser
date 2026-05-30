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
            toolbarButton("Open File", systemImage: "folder", action: openAction)

            toolbarButton("Save Marked Copy", systemImage: "square.and.arrow.down", action: saveAction)
            .disabled(state.document == nil)

            toolbarButton("Share Marked Copy", systemImage: "square.and.arrow.up", action: shareAction)
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

            toolColorControls

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
        .frame(minHeight: ToolbarLayout.contentHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var toolColorControls: some View {
        switch state.selectedTool {
        case .laserDot, .laserTrail:
            colorSwatchRow(
                title: "Laser Color",
                presets: LaserColorPreset.allCases,
                selectedPreset: state.laserSettings.colorPreset
            ) { preset in
                state.laserSettings.colorPreset = preset
            }
        case .pen:
            colorSwatchRow(
                title: "Pen Color",
                presets: PenColorPreset.allCases,
                selectedPreset: state.penColorPreset
            ) { preset in
                state.penColorPreset = preset
            }
        case .none, .erase:
            EmptyView()
        }
    }

    private func colorSwatchRow<P: ToolbarColorPreset>(
        title: String,
        presets: [P],
        selectedPreset: P,
        select: @escaping (P) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            ForEach(presets) { preset in
                let isSelected = preset == selectedPreset

                Button {
                    select(preset)
                } label: {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: ToolbarLayout.swatchSelectionCornerRadius, style: .continuous)
                                .fill(Color.secondary.opacity(0.18))
                                .frame(
                                    width: ToolbarLayout.swatchSelectionSize,
                                    height: ToolbarLayout.swatchSelectionSize
                                )
                        }

                        Circle()
                            .fill(Color(platformColor: preset.swatchColor))
                            .frame(
                                width: ToolbarLayout.swatchCircleDiameter,
                                height: ToolbarLayout.swatchCircleDiameter
                            )
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(isSelected ? 0.32 : 0.16), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                    }
                    .frame(width: ToolbarLayout.swatchButtonWidth, height: ToolbarLayout.contentHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(preset.title) \(title)"))
                .presenterToolbarHelp("\(preset.title) \(title)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
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

private enum ToolbarLayout {
    static let contentHeight: CGFloat = 28
    static let swatchButtonWidth: CGFloat = 26
    static let swatchSelectionSize: CGFloat = 20
    static let swatchSelectionCornerRadius: CGFloat = 6
    static let swatchCircleDiameter: CGFloat = 12
}

private protocol ToolbarColorPreset: Hashable, Identifiable {
    var title: String { get }
    var swatchColor: PlatformColor { get }
}

extension LaserColorPreset: ToolbarColorPreset {
    var swatchColor: PlatformColor {
        mainColor
    }
}

extension PenColorPreset: ToolbarColorPreset {
    var swatchColor: PlatformColor {
        color
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
