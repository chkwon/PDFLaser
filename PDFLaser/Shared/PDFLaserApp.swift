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
#endif
