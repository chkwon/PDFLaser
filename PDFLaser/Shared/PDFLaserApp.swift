import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct PDFLaserApp: App {
    #if os(macOS)
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .windowList) {
                TabNavigationCommands()
            }
            CommandGroup(after: .toolbar) {
                ZoomCommands()
            }
        }
        #endif
    }
}

#if os(macOS)
private struct TabNavigationCommands: View {
    @FocusedObject private var tabsModel: PDFTabsModel?

    var body: some View {
        Button("Show Previous Tab") {
            tabsModel?.selectPreviousTab()
        }
        .keyboardShortcut(.tab, modifiers: [.control, .shift])
        .disabled((tabsModel?.tabs.count ?? 0) <= 1)

        Button("Show Next Tab") {
            tabsModel?.selectNextTab()
        }
        .keyboardShortcut(.tab, modifiers: .control)
        .disabled((tabsModel?.tabs.count ?? 0) <= 1)
    }
}

private struct ZoomCommands: View {
    @FocusedObject private var tabsModel: PDFTabsModel?

    var body: some View {
        Button("Zoom In") {
            tabsModel?.activeTab.zoomIn()
        }
        .keyboardShortcut("=", modifiers: .command)
        .disabled(tabsModel?.activeTab.document == nil)

        Button("Zoom Out") {
            tabsModel?.activeTab.zoomOut()
        }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(tabsModel?.activeTab.document == nil)

        Button("Reset Zoom") {
            tabsModel?.activeTab.resetZoom()
        }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(tabsModel?.activeTab.document == nil)
    }
}
#endif
