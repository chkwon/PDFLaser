import SwiftUI

struct PDFTabBarView: View {
    @ObservedObject var tabsModel: PDFTabsModel

    #if os(iOS)
    private let tabHeight: CGFloat = 36
    private let tabHorizontalPadding: CGFloat = 12
    private let controlSize: CGFloat = 32
    #else
    private let tabHeight: CGFloat = 26
    private let tabHorizontalPadding: CGFloat = 10
    private let controlSize: CGFloat = 24
    #endif

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabsModel.tabs) { tab in
                        PDFTabCell(
                            tab: tab,
                            isActive: tab.id == tabsModel.activeTabID,
                            tabHeight: tabHeight,
                            horizontalPadding: tabHorizontalPadding,
                            onSelect: { tabsModel.selectTab(id: tab.id) },
                            onClose: { tabsModel.closeTab(id: tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Button(action: { tabsModel.newTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(.plain)
            .help("New Tab")
            .padding(.trailing, 8)

            shortcutButtons
        }
        .frame(height: tabHeight + 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        // Hidden buttons that carry keyboard shortcuts only.
        Group {
            Button(action: { tabsModel.newTab() }) { EmptyView() }
                .keyboardShortcut("t", modifiers: .command)

            Button(action: { tabsModel.closeActiveTab() }) { EmptyView() }
                .keyboardShortcut("w", modifiers: .command)

            ForEach(0..<min(tabsModel.tabs.count, 9), id: \.self) { index in
                Button(action: { tabsModel.selectTab(at: index) }) { EmptyView() }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")),
                        modifiers: .command
                    )
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

private struct PDFTabCell: View {
    @ObservedObject var tab: PDFPresentationState
    let isActive: Bool
    let tabHeight: CGFloat
    let horizontalPadding: CGFloat
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    private var title: String {
        tab.sourcePDFURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: 180, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: tabHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(isActive ? 0.12 : 0), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        #if os(macOS)
        .onHover { hovering in isHovering = hovering }
        #endif
    }

    private var backgroundFill: Color {
        if isActive {
            return Color.primary.opacity(0.12)
        }
        if isHovering {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
}
