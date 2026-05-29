import CoreGraphics
import PDFKit
import XCTest
@testable import PDFLaser

@MainActor
final class PDFPresentationStateTests: XCTestCase {
    func testDefaultToolIsNone() {
        let state = PDFPresentationState()

        XCTAssertEqual(state.selectedTool, .none)
    }

    func testTabsReusePristineUntitledTabWhenOpeningPDF() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let tabsModel = PDFTabsModel()
        let initialTabID = tabsModel.activeTabID

        let openedTab = tabsModel.openPDF(url: url)

        XCTAssertEqual(tabsModel.tabs.count, 1)
        XCTAssertEqual(openedTab.id, initialTabID)
        XCTAssertEqual(tabsModel.activeTab.sourcePDFURL, url)
    }

    func testTabsPreserveUntitledTabWithCommittedPenMarkupWhenOpeningPDF() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let tabsModel = PDFTabsModel()
        let initialTab = tabsModel.activeTab
        initialTab.addPenStroke(
            PenStroke(
                normalizedPoints: [CGPoint(x: 0.1, y: 0.1)],
                color: .defaultPenColor,
                width: 3
            )
        )

        let openedTab = tabsModel.openPDF(url: url)

        XCTAssertEqual(tabsModel.tabs.count, 2)
        XCTAssertEqual(tabsModel.tabs[0].id, initialTab.id)
        XCTAssertNil(tabsModel.tabs[0].sourcePDFURL)
        XCTAssertEqual(openedTab.sourcePDFURL, url)
        XCTAssertEqual(tabsModel.activeTabID, openedTab.id)
    }

    func testTabsPreserveUntitledTabWithActivePenMarkupWhenOpeningPDF() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let tabsModel = PDFTabsModel()
        let initialTab = tabsModel.activeTab
        initialTab.beginPenStroke(at: CGPoint(x: 0.1, y: 0.1))

        let openedTab = tabsModel.openPDF(url: url)

        XCTAssertEqual(tabsModel.tabs.count, 2)
        XCTAssertEqual(tabsModel.tabs[0].id, initialTab.id)
        XCTAssertNil(tabsModel.tabs[0].sourcePDFURL)
        XCTAssertEqual(openedTab.sourcePDFURL, url)
        XCTAssertEqual(tabsModel.activeTabID, openedTab.id)
    }

    func testOpeningMultiplePDFsCreatesTabsInOrder() throws {
        let firstURL = try makeTemporaryPDF(pageCount: 1)
        let secondURL = try makeTemporaryPDF(pageCount: 2)
        let tabsModel = PDFTabsModel()

        let openedTabs = tabsModel.openPDFs(urls: [firstURL, secondURL])

        XCTAssertEqual(openedTabs.count, 2)
        XCTAssertEqual(openedTabs[0].sourcePDFURL, firstURL)
        XCTAssertEqual(openedTabs[1].sourcePDFURL, secondURL)
        XCTAssertEqual(tabsModel.tabs.count, 2)
        XCTAssertEqual(tabsModel.tabs[0].sourcePDFURL, firstURL)
        XCTAssertEqual(tabsModel.tabs[1].sourcePDFURL, secondURL)
        XCTAssertEqual(tabsModel.activeTab.sourcePDFURL, secondURL)
    }

    func testOpeningPDFResetsNavigationAndMarkup() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        state.penStrokesByPage[0] = [
            PenStroke(normalizedPoints: [CGPoint(x: 0.5, y: 0.5)], color: .defaultPenColor, width: 3)
        ]

        state.openPDF(url: url)

        XCTAssertEqual(state.pageCount, 2)
        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertTrue(state.penStrokesByPage.isEmpty)
        XCTAssertNil(state.errorMessage)
    }

    func testNavigationClampsToDocumentBounds() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        state.openPDF(url: url)

        state.previousPage()
        XCTAssertEqual(state.currentPageIndex, 0)

        state.nextPage()
        XCTAssertEqual(state.currentPageIndex, 1)

        state.nextPage()
        XCTAssertEqual(state.currentPageIndex, 1)
    }

    func testDefaultZoomIsFittedPage() {
        let state = PDFPresentationState()

        XCTAssertEqual(state.zoomScale, 1)
        XCTAssertEqual(state.panOffset, .zero)
        XCTAssertFalse(state.isZoomed)
    }

    func testZoomOutCannotGoBelowDefault() {
        let state = PDFPresentationState()
        let viewportSize = CGSize(width: 100, height: 80)

        state.updateZoomViewportSize(viewportSize)
        state.zoomOut()

        XCTAssertEqual(state.zoomScale, 1)
        XCTAssertEqual(state.panOffset, .zero)

        state.zoom(by: 0.1, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)

        XCTAssertEqual(state.zoomScale, 1)
        XCTAssertEqual(state.panOffset, .zero)
    }

    func testResetZoomReturnsToDefault() {
        let state = PDFPresentationState()
        let viewportSize = CGSize(width: 100, height: 80)

        state.updateZoomViewportSize(viewportSize)
        state.zoomIn()
        state.pan(by: CGSize(width: 20, height: -10), viewportSize: viewportSize)
        state.resetZoom()

        XCTAssertEqual(state.zoomScale, 1)
        XCTAssertEqual(state.panOffset, .zero)
    }

    func testPanClampsToZoomedContentBounds() {
        let state = PDFPresentationState()
        let viewportSize = CGSize(width: 100, height: 80)

        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)
        state.pan(by: CGSize(width: 1_000, height: -1_000), viewportSize: viewportSize)

        XCTAssertEqual(state.panOffset.width, 50)
        XCTAssertEqual(state.panOffset.height, -40)
    }

    func testOpeningPDFResetsZoomAndPan() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        let viewportSize = CGSize(width: 100, height: 80)

        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)
        state.pan(by: CGSize(width: 20, height: -10), viewportSize: viewportSize)
        state.openPDF(url: url)

        XCTAssertEqual(state.zoomScale, 1)
        XCTAssertEqual(state.panOffset, .zero)
    }

    func testZoomPersistsAcrossPageNavigation() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)

        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)
        state.pan(by: CGSize(width: 20, height: -10), viewportSize: viewportSize)
        state.nextPage()

        XCTAssertEqual(state.currentPageIndex, 1)
        XCTAssertEqual(state.zoomScale, 2)
        XCTAssertEqual(state.panOffset.width, 20)
        XCTAssertEqual(state.panOffset.height, -10)
    }

    func testAnchorBasedZoomKeepsAnchorStable() {
        let state = PDFPresentationState()
        let viewportSize = CGSize(width: 100, height: 80)
        let anchor = CGPoint(x: 75, y: 20)

        let pointBefore = state.normalizedPagePoint(from: anchor, viewportSize: viewportSize)
        state.zoom(by: 2, around: anchor, viewportSize: viewportSize)
        let pointAfter = state.normalizedPagePoint(from: anchor, viewportSize: viewportSize)

        XCTAssertEqual(pointBefore?.x ?? 0, pointAfter?.x ?? 1, accuracy: 0.0001)
        XCTAssertEqual(pointBefore?.y ?? 0, pointAfter?.y ?? 1, accuracy: 0.0001)
    }

    func testMacScrollPansWhenZoomed() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)
        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)

        coordinator.handleScroll(
            deltaX: 12,
            deltaY: -24,
            hasPreciseDeltas: true,
            timestamp: 1,
            viewportSize: viewportSize
        )

        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertEqual(state.panOffset.width, 12)
        XCTAssertEqual(state.panOffset.height, -24)
    }

    func testMacScrollAtZoomedEdgeClampsWithoutChangingPage() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)
        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)

        coordinator.handleScroll(
            deltaX: 1_000,
            deltaY: -1_000,
            hasPreciseDeltas: true,
            timestamp: 1,
            viewportSize: viewportSize
        )
        coordinator.handleScroll(
            deltaX: 1_000,
            deltaY: -1_000,
            hasPreciseDeltas: true,
            timestamp: 2,
            viewportSize: viewportSize
        )

        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertEqual(state.panOffset.width, 50)
        XCTAssertEqual(state.panOffset.height, -40)
    }

    func testMacScrollNavigatesPagesAtDefaultZoom() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)

        coordinator.handleScroll(
            deltaX: 0,
            deltaY: -31,
            hasPreciseDeltas: true,
            timestamp: 1,
            viewportSize: viewportSize
        )

        XCTAssertEqual(state.currentPageIndex, 1)

        coordinator.handleScroll(
            deltaX: 0,
            deltaY: 31,
            hasPreciseDeltas: true,
            timestamp: 1.3,
            viewportSize: viewportSize
        )

        XCTAssertEqual(state.currentPageIndex, 0)
    }

    func testMacZoomedScrollClearsPendingPageScrollAccumulator() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)

        coordinator.handleScroll(
            deltaX: 0,
            deltaY: -20,
            hasPreciseDeltas: true,
            timestamp: 1,
            viewportSize: viewportSize
        )
        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)
        coordinator.handleScroll(
            deltaX: 0,
            deltaY: -5,
            hasPreciseDeltas: true,
            timestamp: 1.1,
            viewportSize: viewportSize
        )
        state.resetZoom()
        coordinator.handleScroll(
            deltaX: 0,
            deltaY: -11,
            hasPreciseDeltas: true,
            timestamp: 1.4,
            viewportSize: viewportSize
        )

        XCTAssertEqual(state.currentPageIndex, 0)
    }

    func testMacKeyboardNavigationWorksAtDefaultZoom() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)

        let didHandleNext = coordinator.handlePageNavigationShortcut(
            keyCode: 124,
            modifierFlags: [],
            viewportSize: viewportSize
        )

        XCTAssertTrue(didHandleNext)
        XCTAssertEqual(state.currentPageIndex, 1)

        let didHandlePrevious = coordinator.handlePageNavigationShortcut(
            keyCode: 123,
            modifierFlags: [],
            viewportSize: viewportSize
        )

        XCTAssertTrue(didHandlePrevious)
        XCTAssertEqual(state.currentPageIndex, 0)
    }

    func testMacRightAndDownArrowsPanWhileZoomed() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)
        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)

        let didHandleRight = coordinator.handlePageNavigationShortcut(
            keyCode: 124,
            modifierFlags: [],
            viewportSize: viewportSize
        )
        let didHandleDown = coordinator.handlePageNavigationShortcut(
            keyCode: 125,
            modifierFlags: [],
            viewportSize: viewportSize
        )

        XCTAssertTrue(didHandleRight)
        XCTAssertTrue(didHandleDown)
        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertEqual(state.panOffset.width, -10)
        XCTAssertEqual(state.panOffset.height, -8)
    }

    func testMacLeftAndUpArrowsPanWhileZoomed() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)
        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)

        let didHandleLeft = coordinator.handlePageNavigationShortcut(
            keyCode: 123,
            modifierFlags: [],
            viewportSize: viewportSize
        )
        let didHandleUp = coordinator.handlePageNavigationShortcut(
            keyCode: 126,
            modifierFlags: [],
            viewportSize: viewportSize
        )

        XCTAssertTrue(didHandleLeft)
        XCTAssertTrue(didHandleUp)
        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertEqual(state.panOffset.width, 10)
        XCTAssertEqual(state.panOffset.height, 8)
    }

    func testMacArrowKeyPanClampsWhileZoomed() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)
        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)

        for _ in 0..<20 {
            _ = coordinator.handlePageNavigationShortcut(
                keyCode: 124,
                modifierFlags: [],
                viewportSize: viewportSize
            )
            _ = coordinator.handlePageNavigationShortcut(
                keyCode: 125,
                modifierFlags: [],
                viewportSize: viewportSize
            )
        }

        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertEqual(state.panOffset.width, -50)
        XCTAssertEqual(state.panOffset.height, -40)
    }

    func testMacSpacebarNavigationIsIgnoredWhileZoomed() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        let coordinator = MacPointerInputView.Coordinator(state: state)
        let viewportSize = CGSize(width: 100, height: 80)
        state.openPDF(url: url)
        state.zoom(by: 2, around: CGPoint(x: 50, y: 40), viewportSize: viewportSize)

        let didHandleSpace = coordinator.handlePageNavigationShortcut(
            keyCode: 49,
            modifierFlags: [],
            viewportSize: viewportSize
        )

        XCTAssertTrue(didHandleSpace)
        XCTAssertEqual(state.currentPageIndex, 0)
    }

    func testClearAndUndoCurrentPageMarkup() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)

        state.addPenStroke(PenStroke(normalizedPoints: [CGPoint(x: 0.1, y: 0.1)], color: .defaultPenColor, width: 3))
        state.addPenStroke(PenStroke(normalizedPoints: [CGPoint(x: 0.2, y: 0.2)], color: .defaultPenColor, width: 3))

        XCTAssertTrue(state.currentPageCanUndo)

        state.undoLastStrokeOnCurrentPage()
        XCTAssertEqual(state.penStrokesByPage[0]?.count, 1)
        XCTAssertTrue(state.currentPageCanUndo)

        state.clearMarkupOnCurrentPage()
        XCTAssertEqual(state.penStrokesByPage[0]?.count, 0)
        XCTAssertFalse(state.currentPageCanUndo)
    }

    func testPenStrokeIsActiveBeforeCommit() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)

        state.beginPenStroke(at: CGPoint(x: 0.1, y: 0.1))
        state.appendPenStroke(at: CGPoint(x: 0.2, y: 0.2))

        XCTAssertEqual(state.activePenStroke?.normalizedPoints.count, 2)
        XCTAssertNil(state.penStrokesByPage[0])

        state.endPenStroke(at: CGPoint(x: 0.3, y: 0.3))

        XCTAssertNil(state.activePenStroke)
        XCTAssertEqual(state.penStrokesByPage[0]?.count, 1)
        XCTAssertEqual(state.penStrokesByPage[0]?.first?.normalizedPoints.count, 3)
    }

    func testTrailLaserRetainsPointsWhileHeldAndFadesAfterRelease() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        state.laserSettings.trailDuration = 1.0
        state.laserSettings.trailFadeDelay = 0.5

        state.beginLaserTrail(at: CGPoint(x: 0.1, y: 0.1), timestamp: 100)
        state.appendLaserTrail(at: CGPoint(x: 0.2, y: 0.2), timestamp: 100.2)
        state.pruneLaserPoints(now: 101.8)

        XCTAssertTrue(state.isLaserTrailActive)
        XCTAssertEqual(state.laserTrailSegments.count, 1)
        XCTAssertEqual(state.laserTrailSegments.first?.count, 2)

        state.endLaserTrail(at: CGPoint(x: 0.3, y: 0.3), timestamp: 102)
        state.pruneLaserPoints(now: 102.5)

        XCTAssertFalse(state.isLaserTrailActive)
        XCTAssertNotNil(state.laserTrailFadeStartedAt)
        XCTAssertEqual(state.laserTrailSegments.count, 1)
        XCTAssertEqual(state.laserTrailSegments.first?.count, 3)

        state.pruneLaserPoints(now: 103.2)

        XCTAssertFalse(state.isLaserTrailActive)
        XCTAssertNotNil(state.laserTrailFadeStartedAt)
        XCTAssertEqual(state.laserTrailSegments.count, 1)
        XCTAssertEqual(state.laserTrailSegments.first?.count, 3)

        state.pruneLaserPoints(now: 103.6)

        XCTAssertFalse(state.isLaserTrailActive)
        XCTAssertNil(state.laserTrailFadeStartedAt)
        XCTAssertTrue(state.laserTrailSegments.isEmpty)
    }

    func testTrailLaserRepressDuringFadeDelayKeepsExistingBucketHeld() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        state.laserSettings.trailDuration = 1.0
        state.laserSettings.trailFadeDelay = 0.5

        state.beginLaserTrail(at: CGPoint(x: 0.1, y: 0.1), timestamp: 100)
        state.appendLaserTrail(at: CGPoint(x: 0.2, y: 0.1), timestamp: 100.1)
        state.endLaserTrail(at: CGPoint(x: 0.3, y: 0.1), timestamp: 100.2)

        state.beginLaserTrail(at: CGPoint(x: 0.6, y: 0.6), timestamp: 100.6)

        XCTAssertTrue(state.isLaserTrailActive)
        XCTAssertNil(state.laserTrailFadeStartedAt)
        XCTAssertEqual(state.laserTrailSegments.count, 2)
        XCTAssertEqual(state.laserTrailSegments[0].count, 3)
        XCTAssertEqual(state.laserTrailSegments[1].count, 1)

        state.appendLaserTrail(at: CGPoint(x: 0.7, y: 0.6), timestamp: 100.7)

        XCTAssertEqual(state.laserTrailSegments[0].count, 3)
        XCTAssertEqual(state.laserTrailSegments[1].count, 2)
    }

    func testTrailLaserRepressAfterFadeBeginsStartsFreshBucket() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        state.laserSettings.trailDuration = 1.0
        state.laserSettings.trailFadeDelay = 0.5

        state.beginLaserTrail(at: CGPoint(x: 0.1, y: 0.1), timestamp: 100)
        state.appendLaserTrail(at: CGPoint(x: 0.2, y: 0.1), timestamp: 100.1)
        state.endLaserTrail(at: CGPoint(x: 0.3, y: 0.1), timestamp: 100.2)

        state.beginLaserTrail(at: CGPoint(x: 0.7, y: 0.7), timestamp: 100.8)

        XCTAssertTrue(state.isLaserTrailActive)
        XCTAssertNil(state.laserTrailFadeStartedAt)
        XCTAssertEqual(state.laserTrailSegments.count, 1)
        XCTAssertEqual(state.laserTrailSegments.first?.count, 1)
        XCTAssertEqual(state.laserTrailSegments.first?.first?.normalizedPosition, CGPoint(x: 0.7, y: 0.7))
    }

    func testTrailLaserAppendWithoutActiveDragDoesNothing() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)

        state.appendLaserTrail(at: CGPoint(x: 0.5, y: 0.5), timestamp: 100)

        XCTAssertFalse(state.isLaserTrailActive)
        XCTAssertTrue(state.laserTrailSegments.isEmpty)
    }

    func testLaserDotTracksPressedAndHoverState() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)

        state.updateLaserDot(
            at: CGPoint(x: 0.2, y: 0.3),
            isPressed: false,
            persistsUntilCleared: true,
            timestamp: 100
        )

        XCTAssertNotNil(state.currentLaserPoint)
        XCTAssertFalse(state.isLaserDotPressed)

        state.pruneLaserPoints(now: 101)

        XCTAssertNotNil(state.currentLaserPoint)

        state.updateLaserDot(
            at: CGPoint(x: 0.4, y: 0.5),
            isPressed: true,
            persistsUntilCleared: true,
            timestamp: 102
        )

        XCTAssertTrue(state.isLaserDotPressed)

        state.clearLaserDot()

        XCTAssertNil(state.currentLaserPoint)
        XCTAssertFalse(state.isLaserDotPressed)
    }

    func testTransientLaserDotFadesAfterRelease() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)

        state.updateLaserDot(
            at: CGPoint(x: 0.2, y: 0.3),
            isPressed: true,
            persistsUntilCleared: false,
            timestamp: 100
        )
        state.updateLaserDot(
            at: CGPoint(x: 0.2, y: 0.3),
            isPressed: false,
            persistsUntilCleared: false,
            timestamp: 100.1
        )

        state.pruneLaserPoints(now: 100.5)

        XCTAssertNil(state.currentLaserPoint)
        XCTAssertFalse(state.isLaserDotPressed)
    }

    func testEraseRemovesWholeStrokeAtPoint() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.1, y: 0.1),
                    CGPoint(x: 0.2, y: 0.2)
                ],
                color: .defaultPenColor,
                width: 3
            )
        )

        let didErase = state.eraseStroke(at: CGPoint(x: 0.1, y: 0.1))

        XCTAssertTrue(didErase)
        XCTAssertEqual(state.penStrokesByPage[0]?.count, 0)
    }

    func testEraseUsesSegmentHitTestingBetweenRecordedPoints() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.1, y: 0.1),
                    CGPoint(x: 0.9, y: 0.1)
                ],
                color: .defaultPenColor,
                width: 3
            )
        )

        let didErase = state.eraseStroke(at: CGPoint(x: 0.5, y: 0.11))

        XCTAssertTrue(didErase)
        XCTAssertEqual(state.penStrokesByPage[0]?.count, 0)
    }

    func testEraseOutsideRadiusLeavesStroke() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.1, y: 0.1),
                    CGPoint(x: 0.2, y: 0.2)
                ],
                color: .defaultPenColor,
                width: 3
            )
        )

        let didErase = state.eraseStroke(at: CGPoint(x: 0.8, y: 0.8))

        XCTAssertFalse(didErase)
        XCTAssertEqual(state.penStrokesByPage[0]?.count, 1)
    }

    func testEraseOnlyAffectsCurrentPage() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.1, y: 0.1),
                    CGPoint(x: 0.2, y: 0.2)
                ],
                color: .defaultPenColor,
                width: 3
            )
        )

        state.nextPage()
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.1, y: 0.1),
                    CGPoint(x: 0.2, y: 0.2)
                ],
                color: .defaultPenColor,
                width: 3
            )
        )

        let didErase = state.eraseStroke(at: CGPoint(x: 0.1, y: 0.1))

        XCTAssertTrue(didErase)
        XCTAssertEqual(state.penStrokesByPage[0]?.count, 1)
        XCTAssertEqual(state.penStrokesByPage[1]?.count, 0)
    }

    func testUndoRestoresErasedStroke() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        let firstStroke = PenStroke(
            normalizedPoints: [
                CGPoint(x: 0.1, y: 0.1),
                CGPoint(x: 0.2, y: 0.2)
            ],
            color: .defaultPenColor,
            width: 3
        )
        let secondStroke = PenStroke(
            normalizedPoints: [
                CGPoint(x: 0.7, y: 0.7),
                CGPoint(x: 0.8, y: 0.8)
            ],
            color: .defaultPenColor,
            width: 3
        )
        state.addPenStroke(firstStroke)
        state.addPenStroke(secondStroke)

        let didErase = state.eraseStroke(at: CGPoint(x: 0.1, y: 0.1))

        XCTAssertTrue(didErase)
        XCTAssertTrue(state.currentPageCanUndo)
        XCTAssertEqual(state.penStrokesByPage[0]?.map(\.id), [secondStroke.id])

        state.undoLastStrokeOnCurrentPage()

        XCTAssertEqual(state.penStrokesByPage[0]?.map(\.id), [firstStroke.id, secondStroke.id])
    }

    func testUndoRestoresMultipleStrokesErasedInOneGesture() throws {
        let url = try makeTemporaryPDF(pageCount: 1)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        let firstStroke = PenStroke(
            normalizedPoints: [
                CGPoint(x: 0.1, y: 0.1),
                CGPoint(x: 0.2, y: 0.2)
            ],
            color: .defaultPenColor,
            width: 3
        )
        let secondStroke = PenStroke(
            normalizedPoints: [
                CGPoint(x: 0.4, y: 0.4),
                CGPoint(x: 0.5, y: 0.5)
            ],
            color: .defaultPenColor,
            width: 3
        )
        let thirdStroke = PenStroke(
            normalizedPoints: [
                CGPoint(x: 0.8, y: 0.8),
                CGPoint(x: 0.9, y: 0.9)
            ],
            color: .defaultPenColor,
            width: 3
        )
        state.addPenStroke(firstStroke)
        state.addPenStroke(secondStroke)
        state.addPenStroke(thirdStroke)

        state.beginErase(at: CGPoint(x: 0.1, y: 0.1))
        state.continueErase(at: CGPoint(x: 0.4, y: 0.4))
        state.endErase(at: CGPoint(x: 0.9, y: 0.9))

        XCTAssertEqual(state.penStrokesByPage[0]?.count, 0)
        XCTAssertTrue(state.currentPageCanUndo)

        state.undoLastStrokeOnCurrentPage()

        XCTAssertEqual(state.penStrokesByPage[0]?.map(\.id), [firstStroke.id, secondStroke.id, thirdStroke.id])
    }

    func testMarkedPDFExportIncludesAllPages() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        state.openPDF(url: url)
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.1, y: 0.1),
                    CGPoint(x: 0.9, y: 0.9)
                ],
                color: .defaultPenColor,
                width: 3
            )
        )

        let data = try PDFMarkupExporter.exportPDFData(from: state)
        let exportedDocument = PDFDocument(data: data)

        XCTAssertEqual(exportedDocument?.pageCount, 2)
    }

    func testMarkedPDFExportRequiresDocument() {
        XCTAssertThrowsError(
            try PDFMarkupExporter.exportPDFData(
                document: nil,
                penStrokesByPage: [:],
                activePenStroke: nil,
                activePenPageIndex: 0
            )
        )
    }

    private func makeTemporaryPDF(pageCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        var mediaBox = CGRect(x: 0, y: 0, width: 320, height: 180)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw XCTSkip("Could not create temporary PDF")
        }

        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.endPDFPage()
        }

        context.closePDF()
        return url
    }
}
