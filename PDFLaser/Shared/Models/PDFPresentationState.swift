import Combine
import CoreGraphics
import Foundation
import PDFKit

@MainActor
final class PDFPresentationState: ObservableObject, Identifiable {
    let id = UUID()

    @Published var document: PDFDocument?
    @Published var currentPageIndex: Int = 0
    @Published var selectedTool: PresentationTool = .none {
        didSet {
            guard oldValue != selectedTool else {
                return
            }

            if selectedTool != .laserDot {
                clearLaserDot()
            }

            if selectedTool != .laserTrail {
                clearLaserTrail()
            }

            if selectedTool != .pen {
                activePenStroke = nil
            }

            if selectedTool != .erase {
                cancelErase()
            }
        }
    }
    @Published var laserSettings: LaserSettings = .default
    @Published var penStrokesByPage: [Int: [PenStroke]] = [:]
    @Published var laserTrailSegments: [[LaserPoint]] = []
    @Published var currentLaserPoint: LaserPoint?
    @Published var isLaserDotPressed = false
    @Published var isLaserTrailActive = false
    @Published var laserTrailFadeStartedAt: TimeInterval?
    @Published var activePenStroke: PenStroke?
    @Published var errorMessage: String?
    @Published private(set) var sourcePDFURL: URL?
    @Published private(set) var laserDotPersistsUntilCleared = false
    @Published private var markupUndoActionsByPage: [Int: [MarkupUndoAction]] = [:]
    @Published private var markupRedoActionsByPage: [Int: [MarkupUndoAction]] = [:]

    var penColor: PlatformColor = .defaultPenColor
    var penWidth: CGFloat = 3
    var eraserRadius: CGFloat = 0.025
    private var activeEraseSnapshot: [PenStroke]?
    private var activeErasePageIndex: Int?

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var currentPage: PDFPage? {
        guard let document, currentPageIndex >= 0, currentPageIndex < document.pageCount else {
            return nil
        }

        return document.page(at: currentPageIndex)
    }

    var currentPageAspectRatio: CGFloat {
        guard let page = currentPage else {
            return 16.0 / 9.0
        }

        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else {
            return 16.0 / 9.0
        }

        return bounds.width / bounds.height
    }

    var currentPageDisplayNumber: Int {
        guard pageCount > 0 else {
            return 0
        }

        return currentPageIndex + 1
    }

    var canGoPrevious: Bool {
        currentPageIndex > 0
    }

    var canGoNext: Bool {
        currentPageIndex + 1 < pageCount
    }

    var currentPageHasMarkup: Bool {
        !(penStrokesByPage[currentPageIndex] ?? []).isEmpty
    }

    var hasPenMarkup: Bool {
        penStrokesByPage.values.contains { !$0.isEmpty } ||
            activePenStroke?.normalizedPoints.isEmpty == false
    }

    var currentPageCanUndo: Bool {
        !(markupUndoActionsByPage[currentPageIndex] ?? []).isEmpty
    }

    var currentPageCanRedo: Bool {
        !(markupRedoActionsByPage[currentPageIndex] ?? []).isEmpty
    }

    init() {
        document = Self.makeBlankPresentationDocument()
    }

    private static func makeBlankPresentationDocument() -> PDFDocument {
        var mediaBox = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            return PDFDocument()
        }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return PDFDocument(data: data as Data) ?? PDFDocument()
    }

    func openPDF(url: URL) {
        do {
            document = try PDFDocumentLoader.loadPDF(from: url)
            sourcePDFURL = url
            currentPageIndex = 0
            penStrokesByPage.removeAll()
            markupUndoActionsByPage.removeAll()
            markupRedoActionsByPage.removeAll()
            activePenStroke = nil
            activeEraseSnapshot = nil
            activeErasePageIndex = nil
            clearLaser()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var exportDefaultFilename: String {
        let baseName = sourcePDFURL?.deletingPathExtension().lastPathComponent ?? "PDF Laser"
        return "\(baseName) Marked.pdf"
    }

    func nextPage() {
        guard canGoNext else {
            return
        }

        cancelErase()
        currentPageIndex += 1
        activePenStroke = nil
        activeEraseSnapshot = nil
        activeErasePageIndex = nil
        clearLaser()
    }

    func previousPage() {
        guard canGoPrevious else {
            return
        }

        cancelErase()
        currentPageIndex -= 1
        activePenStroke = nil
        activeEraseSnapshot = nil
        activeErasePageIndex = nil
        clearLaser()
    }

    func clearMarkupOnCurrentPage() {
        penStrokesByPage[currentPageIndex] = []
        markupUndoActionsByPage[currentPageIndex] = []
        markupRedoActionsByPage[currentPageIndex] = []
        activeEraseSnapshot = nil
        activeErasePageIndex = nil
    }

    func undoLastStrokeOnCurrentPage() {
        guard var actions = markupUndoActionsByPage[currentPageIndex], let action = actions.popLast() else {
            return
        }

        let snapshotBefore = penStrokesByPage[currentPageIndex] ?? []
        markupUndoActionsByPage[currentPageIndex] = actions
        undo(action)
        markupRedoActionsByPage[currentPageIndex, default: []].append(.restoredPageStrokes(snapshotBefore))
    }

    func redoLastUndoOnCurrentPage() {
        guard var redoActions = markupRedoActionsByPage[currentPageIndex], let action = redoActions.popLast() else {
            return
        }

        let snapshotBefore = penStrokesByPage[currentPageIndex] ?? []
        markupRedoActionsByPage[currentPageIndex] = redoActions
        undo(action)
        pushUndoAction(.restoredPageStrokes(snapshotBefore), on: currentPageIndex, clearingRedo: false)
    }

    func addPenStroke(_ stroke: PenStroke) {
        guard !stroke.normalizedPoints.isEmpty, pageCount > 0 else {
            return
        }

        penStrokesByPage[currentPageIndex, default: []].append(stroke)
        pushUndoAction(.addedStroke(stroke.id), on: currentPageIndex)
    }

    func beginPenStroke(at normalizedPosition: CGPoint) {
        guard pageCount > 0 else {
            return
        }

        activePenStroke = PenStroke(
            normalizedPoints: [normalizedPosition.clampedToUnitSquare],
            color: penColor,
            width: penWidth
        )
    }

    func appendPenStroke(at normalizedPosition: CGPoint) {
        guard var stroke = activePenStroke else {
            return
        }

        stroke.normalizedPoints.append(normalizedPosition.clampedToUnitSquare)
        activePenStroke = stroke
    }

    func endPenStroke(at normalizedPosition: CGPoint) {
        guard var stroke = activePenStroke else {
            return
        }

        stroke.normalizedPoints.append(normalizedPosition.clampedToUnitSquare)
        activePenStroke = nil
        addPenStroke(stroke)
    }

    func cancelPenStroke() {
        activePenStroke = nil
    }

    @discardableResult
    func eraseStroke(at normalizedPosition: CGPoint, radius: CGFloat? = nil) -> Bool {
        let snapshot = penStrokesByPage[currentPageIndex] ?? []
        let didErase = eraseStrokeWithoutUndo(at: normalizedPosition, radius: radius)

        if didErase {
            pushUndoAction(.restoredPageStrokes(snapshot), on: currentPageIndex)
        }

        return didErase
    }

    func beginErase(at normalizedPosition: CGPoint) {
        guard pageCount > 0 else {
            return
        }

        activeErasePageIndex = currentPageIndex
        activeEraseSnapshot = penStrokesByPage[currentPageIndex] ?? []
        eraseStrokeWithoutUndo(at: normalizedPosition)
    }

    func continueErase(at normalizedPosition: CGPoint) {
        guard activeErasePageIndex == currentPageIndex else {
            return
        }

        eraseStrokeWithoutUndo(at: normalizedPosition)
    }

    func endErase(at normalizedPosition: CGPoint? = nil) {
        guard let activeErasePageIndex,
              activeErasePageIndex == currentPageIndex,
              let activeEraseSnapshot else {
            self.activeErasePageIndex = nil
            self.activeEraseSnapshot = nil
            return
        }

        if let normalizedPosition {
            eraseStrokeWithoutUndo(at: normalizedPosition)
        }

        let currentStrokes = penStrokesByPage[currentPageIndex] ?? []
        if currentStrokes.map(\.id) != activeEraseSnapshot.map(\.id) {
            pushUndoAction(.restoredPageStrokes(activeEraseSnapshot), on: currentPageIndex)
        }

        self.activeErasePageIndex = nil
        self.activeEraseSnapshot = nil
    }

    func cancelErase() {
        endErase()
    }

    @discardableResult
    private func eraseStrokeWithoutUndo(at normalizedPosition: CGPoint, radius: CGFloat? = nil) -> Bool {
        guard pageCount > 0,
              var strokes = penStrokesByPage[currentPageIndex],
              !strokes.isEmpty else {
            return false
        }

        let erasePoint = normalizedPosition.clampedToUnitSquare
        let eraseRadius = max(radius ?? eraserRadius, 0)
        let originalCount = strokes.count

        strokes.removeAll { stroke in
            stroke.intersects(point: erasePoint, radius: eraseRadius)
        }
        penStrokesByPage[currentPageIndex] = strokes

        return strokes.count != originalCount
    }

    func updateLaserDot(
        at normalizedPosition: CGPoint,
        isPressed: Bool = false,
        persistsUntilCleared: Bool = true,
        timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        guard pageCount > 0 else {
            return
        }

        let point = LaserPoint(normalizedPosition: normalizedPosition.clampedToUnitSquare, timestamp: timestamp)
        currentLaserPoint = point
        isLaserDotPressed = isPressed
        laserDotPersistsUntilCleared = persistsUntilCleared
        clearLaserTrail()
    }

    func clearLaserDot() {
        currentLaserPoint = nil
        isLaserDotPressed = false
        laserDotPersistsUntilCleared = false
    }

    func beginLaserTrail(at normalizedPosition: CGPoint, timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard pageCount > 0 else {
            return
        }

        let point = LaserPoint(normalizedPosition: normalizedPosition.clampedToUnitSquare, timestamp: timestamp)
        let fadeDelay = max(laserSettings.trailFadeDelay, 0)
        let shouldContinueExistingBucket: Bool

        if let laserTrailFadeStartedAt, !laserTrailSegments.isEmpty {
            shouldContinueExistingBucket = max(timestamp - laserTrailFadeStartedAt, 0) <= fadeDelay
        } else {
            shouldContinueExistingBucket = false
        }

        clearLaserDot()
        isLaserTrailActive = true
        laserTrailFadeStartedAt = nil

        if shouldContinueExistingBucket {
            laserTrailSegments.append([point])
        } else {
            laserTrailSegments = [[point]]
        }
    }

    func appendLaserTrail(at normalizedPosition: CGPoint, timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard pageCount > 0, isLaserTrailActive, !laserTrailSegments.isEmpty else {
            return
        }

        var segments = laserTrailSegments
        segments[segments.count - 1].append(
            LaserPoint(normalizedPosition: normalizedPosition.clampedToUnitSquare, timestamp: timestamp)
        )
        laserTrailSegments = segments
    }

    func endLaserTrail(at normalizedPosition: CGPoint? = nil, timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard isLaserTrailActive else {
            return
        }

        if let normalizedPosition, !laserTrailSegments.isEmpty {
            let normalizedPosition = normalizedPosition.clampedToUnitSquare
            var segments = laserTrailSegments
            let lastSegmentIndex = segments.count - 1

            if segments[lastSegmentIndex].last?.normalizedPosition != normalizedPosition {
                segments[lastSegmentIndex].append(
                    LaserPoint(normalizedPosition: normalizedPosition, timestamp: timestamp)
                )
                laserTrailSegments = segments
            }
        }

        isLaserTrailActive = false
        laserTrailFadeStartedAt = timestamp
    }

    func cancelLaserTrail(timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard isLaserTrailActive else {
            return
        }

        isLaserTrailActive = false
        laserTrailFadeStartedAt = timestamp
    }

    func pruneLaserPoints(now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        if let currentLaserPoint,
           !isLaserDotPressed,
           !laserDotPersistsUntilCleared,
           currentLaserPoint.age(at: now) > 0.35 {
            clearLaserDot()
        }

        guard !isLaserTrailActive, let laserTrailFadeStartedAt else {
            return
        }

        let trailLifetimeAfterRelease = max(laserSettings.trailFadeDelay, 0) + max(laserSettings.trailDuration, 0.1)
        if now - laserTrailFadeStartedAt > trailLifetimeAfterRelease {
            clearLaserTrail()
        }
    }

    func clearLaser() {
        clearLaserTrail()
        clearLaserDot()
    }

    private func clearLaserTrail() {
        laserTrailSegments.removeAll()
        isLaserTrailActive = false
        laserTrailFadeStartedAt = nil
    }

    private func pushUndoAction(_ action: MarkupUndoAction, on pageIndex: Int, clearingRedo: Bool = true) {
        markupUndoActionsByPage[pageIndex, default: []].append(action)
        if clearingRedo {
            markupRedoActionsByPage[pageIndex] = []
        }
    }

    private func undo(_ action: MarkupUndoAction) {
        switch action {
        case .addedStroke(let strokeID):
            guard var strokes = penStrokesByPage[currentPageIndex] else {
                return
            }

            strokes.removeAll { $0.id == strokeID }
            penStrokesByPage[currentPageIndex] = strokes

        case .restoredPageStrokes(let strokes):
            penStrokesByPage[currentPageIndex] = strokes
        }
    }
}

private enum MarkupUndoAction {
    case addedStroke(UUID)
    case restoredPageStrokes([PenStroke])
}

private extension PenStroke {
    func intersects(point: CGPoint, radius: CGFloat) -> Bool {
        guard let firstPoint = normalizedPoints.first else {
            return false
        }

        guard normalizedPoints.count > 1 else {
            return firstPoint.distance(to: point) <= radius
        }

        for index in 1..<normalizedPoints.count {
            let start = normalizedPoints[index - 1]
            let end = normalizedPoints[index]

            if point.distance(toSegmentStart: start, end: end) <= radius {
                return true
            }
        }

        return false
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distance(toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let lengthSquared = segmentX * segmentX + segmentY * segmentY

        guard lengthSquared > 0 else {
            return distance(to: start)
        }

        let rawProjection = ((x - start.x) * segmentX + (y - start.y) * segmentY) / lengthSquared
        let projection = min(max(rawProjection, 0), 1)
        let closestPoint = CGPoint(
            x: start.x + projection * segmentX,
            y: start.y + projection * segmentY
        )

        return distance(to: closestPoint)
    }
}
