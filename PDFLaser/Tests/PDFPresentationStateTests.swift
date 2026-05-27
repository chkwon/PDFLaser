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
