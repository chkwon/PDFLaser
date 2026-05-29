import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PDFLaser

@MainActor
final class PDFPresentationStateTests: XCTestCase {
    func testDefaultToolIsTrailLaser() {
        let state = PDFPresentationState()

        XCTAssertEqual(state.selectedTool, .laserTrail)
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

    func testTabsReusePristineUntitledTabWhenOpeningImage() throws {
        let url = try makeTemporaryImage(fileExtension: "png", contentType: .png)
        let tabsModel = PDFTabsModel()
        let initialTabID = tabsModel.activeTabID

        let openedTab = tabsModel.openDocument(url: url)

        XCTAssertEqual(tabsModel.tabs.count, 1)
        XCTAssertEqual(openedTab.id, initialTabID)
        XCTAssertEqual(tabsModel.activeTab.sourceURL, url)
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

    func testOpeningCommonImageTypesCreatesOnePageDocuments() throws {
        let imageTypes: [(fileExtension: String, contentType: UTType)] = [
            ("png", .png),
            ("jpg", .jpeg),
            ("tiff", .tiff)
        ]

        for imageType in imageTypes {
            let url = try makeTemporaryImage(
                fileExtension: imageType.fileExtension,
                contentType: imageType.contentType,
                width: 64,
                height: 32
            )
            let state = PDFPresentationState()

            state.openDocument(url: url)

            XCTAssertNil(state.errorMessage)
            XCTAssertEqual(state.pageCount, 1)
            XCTAssertEqual(state.currentPageIndex, 0)
            XCTAssertEqual(state.currentPageAspectRatio, 2, accuracy: 0.001)
            XCTAssertEqual(state.sourceURL, url)

            guard case .image(let source)? = state.sourceDocument else {
                XCTFail("Expected image source for \(imageType.fileExtension)")
                continue
            }

            XCTAssertEqual(source.contentType, imageType.contentType)
            XCTAssertEqual(source.fileExtension, imageType.fileExtension)
            XCTAssertEqual(source.pixelWidth, 64)
            XCTAssertEqual(source.pixelHeight, 32)
        }
    }

    func testOpeningImageKeepsDisplayOrientation() throws {
        let url = try makeTemporaryTopBottomImage(
            fileExtension: "png",
            contentType: .png,
            width: 20,
            height: 20,
            topRGBA: (255, 0, 0, 255),
            bottomRGBA: (0, 0, 255, 255)
        )
        let state = PDFPresentationState()

        state.openDocument(url: url)

        guard let page = state.currentPage else {
            XCTFail("Expected image page")
            return
        }

        let renderedImage = try renderPageAsDisplayed(page, width: 20, height: 20)
        let topPixel = try rgbaPixel(in: renderedImage, x: 10, y: 17)
        let bottomPixel = try rgbaPixel(in: renderedImage, x: 10, y: 2)

        XCTAssertGreaterThan(topPixel.red, 200)
        XCTAssertLessThan(topPixel.blue, 80)
        XCTAssertGreaterThan(bottomPixel.blue, 200)
        XCTAssertLessThan(bottomPixel.red, 80)
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

    func testMarkedDocumentExportKeepsPDFContentTypeAndFilename() throws {
        let url = try makeTemporaryPDF(pageCount: 2)
        let state = PDFPresentationState()
        state.openPDF(url: url)

        let export = try MarkedDocumentExporter.exportMarkedDocument(from: state)
        let exportedDocument = PDFDocument(data: export.data)

        XCTAssertEqual(export.contentType, .pdf)
        XCTAssertEqual(
            export.filename,
            "\(url.deletingPathExtension().lastPathComponent) Marked.pdf"
        )
        XCTAssertEqual(exportedDocument?.pageCount, 2)
    }

    func testMarkedImageExportKeepsSourceFormatFilenameAndPixelSize() throws {
        let url = try makeTemporaryImage(
            fileExtension: "png",
            contentType: .png,
            width: 64,
            height: 64
        )
        let state = PDFPresentationState()
        state.openDocument(url: url)
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.1, y: 0.5),
                    CGPoint(x: 0.9, y: 0.5)
                ],
                color: .defaultPenColor,
                width: 16
            )
        )

        let export = try MarkedDocumentExporter.exportMarkedDocument(from: state)
        let exportedImage = try decodeImage(from: export.data)
        let centerPixel = try rgbaPixel(in: exportedImage, x: 32, y: 32)

        XCTAssertEqual(export.contentType, .png)
        XCTAssertEqual(
            export.filename,
            "\(url.deletingPathExtension().lastPathComponent) Marked.png"
        )
        XCTAssertEqual(exportedImage.width, 64)
        XCTAssertEqual(exportedImage.height, 64)
        XCTAssertGreaterThan(centerPixel.red, 180)
        XCTAssertLessThan(centerPixel.green, 140)
        XCTAssertLessThan(centerPixel.blue, 140)
    }

    func testMarkedImageExportUsesOriginalJPEGExtensionAndContentType() throws {
        let url = try makeTemporaryImage(
            fileExtension: "jpg",
            contentType: .jpeg,
            width: 40,
            height: 24
        )
        let state = PDFPresentationState()
        state.openDocument(url: url)

        let export = try MarkedDocumentExporter.exportMarkedDocument(from: state)
        let exportedImage = try decodeImage(from: export.data)

        XCTAssertEqual(export.contentType, .jpeg)
        XCTAssertEqual(
            export.filename,
            "\(url.deletingPathExtension().lastPathComponent) Marked.jpg"
        )
        XCTAssertEqual(exportedImage.width, 40)
        XCTAssertEqual(exportedImage.height, 24)
    }

    func testMarkedImageExportKeepsImageOrientation() throws {
        let url = try makeTemporaryTopBottomImage(
            fileExtension: "png",
            contentType: .png,
            width: 20,
            height: 20,
            topRGBA: (255, 0, 0, 255),
            bottomRGBA: (0, 0, 255, 255)
        )
        let state = PDFPresentationState()
        state.openDocument(url: url)
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.2, y: 0.5),
                    CGPoint(x: 0.8, y: 0.5)
                ],
                color: .defaultPenColor,
                width: 2
            )
        )

        let export = try MarkedDocumentExporter.exportMarkedDocument(from: state)
        let exportedImage = try decodeImage(from: export.data)
        let topPixel = try rgbaPixel(in: exportedImage, x: 10, y: 2)
        let bottomPixel = try rgbaPixel(in: exportedImage, x: 10, y: 17)

        XCTAssertGreaterThan(topPixel.red, 200)
        XCTAssertLessThan(topPixel.blue, 80)
        XCTAssertGreaterThan(bottomPixel.blue, 200)
        XCTAssertLessThan(bottomPixel.red, 80)
    }

    func testMarkedImageExportKeepsPenWritingOrientation() throws {
        let url = try makeTemporaryTopBottomImage(
            fileExtension: "png",
            contentType: .png,
            width: 20,
            height: 20,
            topRGBA: (255, 255, 255, 255),
            bottomRGBA: (255, 255, 255, 255)
        )
        let state = PDFPresentationState()
        state.openDocument(url: url)
        state.addPenStroke(
            PenStroke(
                normalizedPoints: [
                    CGPoint(x: 0.2, y: 0.15),
                    CGPoint(x: 0.8, y: 0.15)
                ],
                color: .defaultPenColor,
                width: 4
            )
        )

        let export = try MarkedDocumentExporter.exportMarkedDocument(from: state)
        let exportedImage = try decodeImage(from: export.data)
        let writtenTopPixel = try rgbaPixel(in: exportedImage, x: 10, y: 3)
        let emptyBottomPixel = try rgbaPixel(in: exportedImage, x: 10, y: 17)

        XCTAssertGreaterThan(writtenTopPixel.red, 180)
        XCTAssertLessThan(writtenTopPixel.green, 140)
        XCTAssertLessThan(writtenTopPixel.blue, 140)
        XCTAssertGreaterThan(emptyBottomPixel.red, 220)
        XCTAssertGreaterThan(emptyBottomPixel.green, 220)
        XCTAssertGreaterThan(emptyBottomPixel.blue, 220)
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

    private func makeTemporaryImage(
        fileExtension: String,
        contentType: UTType,
        width: Int = 64,
        height: Int = 32
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Could not create temporary image context")
        }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.setFillColor(CGColor(red: 0.82, green: 0.88, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                contentType.identifier as CFString,
                1,
                nil
              ) else {
            throw XCTSkip("Could not create temporary image")
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("Could not write temporary image")
        }

        return url
    }

    private func makeTemporaryTopBottomImage(
        fileExtension: String,
        contentType: UTType,
        width: Int,
        height: Int,
        topRGBA: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
        bottomRGBA: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            let color = y < height / 2 ? topRGBA : bottomRGBA
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = color.alpha
            }
        }

        let imageData = Data(pixels) as CFData
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: imageData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                contentType.identifier as CFString,
                1,
                nil
              ) else {
            throw XCTSkip("Could not create temporary orientation image")
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("Could not write temporary orientation image")
        }

        return url
    }

    private func decodeImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw XCTSkip("Could not decode exported image")
        }

        return image
    }

    private func renderPageAsDisplayed(
        _ page: PDFPage,
        width: Int,
        height: Int
    ) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw XCTSkip("Could not create page render context")
        }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let pageBounds = page.bounds(for: .cropBox)
        let scale = min(bounds.width / pageBounds.width, bounds.height / pageBounds.height)
        let scaledSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        let origin = CGPoint(
            x: (bounds.width - scaledSize.width) / 2,
            y: (bounds.height - scaledSize.height) / 2
        )

        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw XCTSkip("Could not render page")
        }

        return image
    }

    private func rgbaPixel(
        in image: CGImage,
        x: Int,
        y: Int
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        guard let croppedImage = image.cropping(
            to: CGRect(x: x, y: y, width: 1, height: 1)
        ) else {
            throw XCTSkip("Could not crop exported image")
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        try pixel.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                throw XCTSkip("Could not inspect exported image pixel")
            }

            context.interpolationQuality = .none
            context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}
