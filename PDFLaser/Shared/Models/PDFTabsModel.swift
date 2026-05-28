import Combine
import Foundation

@MainActor
final class PDFTabsModel: ObservableObject {
    @Published private(set) var tabs: [PDFPresentationState]
    @Published var activeTabID: PDFPresentationState.ID

    init() {
        let first = PDFPresentationState()
        tabs = [first]
        activeTabID = first.id
    }

    var activeTab: PDFPresentationState {
        tabs.first { $0.id == activeTabID } ?? tabs[0]
    }

    var activeIndex: Int {
        tabs.firstIndex { $0.id == activeTabID } ?? 0
    }

    @discardableResult
    func newTab(activate: Bool = true) -> PDFPresentationState {
        let tab = PDFPresentationState()
        tabs.append(tab)
        if activate {
            activeTabID = tab.id
        }
        return tab
    }

    func selectTab(id: PDFPresentationState.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabID = tabs[index].id
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        let next = (activeIndex - 1 + tabs.count) % tabs.count
        activeTabID = tabs[next].id
    }

    func selectNextTab() {
        guard tabs.count > 1 else { return }
        let next = (activeIndex + 1) % tabs.count
        activeTabID = tabs[next].id
    }

    func openPDF(url: URL) {
        let target: PDFPresentationState
        if activeTab.sourcePDFURL == nil {
            target = activeTab
        } else {
            target = newTab(activate: true)
        }
        target.openPDF(url: url)
    }

    func closeTab(id: PDFPresentationState.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = (tabs[index].id == activeTabID)
        tabs.remove(at: index)

        if tabs.isEmpty {
            let fresh = PDFPresentationState()
            tabs = [fresh]
            activeTabID = fresh.id
            return
        }

        if wasActive {
            let nextIndex = min(index, tabs.count - 1)
            activeTabID = tabs[nextIndex].id
        }
    }

    func closeActiveTab() {
        closeTab(id: activeTabID)
    }
}
