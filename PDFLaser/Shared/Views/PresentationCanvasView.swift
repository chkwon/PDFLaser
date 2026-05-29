import SwiftUI

struct PresentationCanvasView: View {
    @ObservedObject var state: PDFPresentationState
    var zoomScale: CGFloat = 1
    private let cleanupTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                drawPenMarkup(in: &context, size: size)
                drawLaserTrail(in: &context, size: size, now: now)
                drawLaserDot(in: &context, size: size, now: now)
            }
        }
        .allowsHitTesting(false)
        .onReceive(cleanupTimer) { date in
            state.pruneLaserPoints(now: date.timeIntervalSinceReferenceDate)
        }
    }

    private func drawPenMarkup(in context: inout GraphicsContext, size: CGSize) {
        let strokes = state.penStrokesByPage[state.currentPageIndex] ?? []

        for stroke in strokes {
            drawStroke(
                points: stroke.normalizedPoints,
                color: Color(platformColor: stroke.color),
                width: stroke.width * zoomScale,
                opacity: 1,
                in: &context,
                size: size
            )
        }

        if let activePenStroke = state.activePenStroke {
            drawStroke(
                points: activePenStroke.normalizedPoints,
                color: Color(platformColor: activePenStroke.color),
                width: activePenStroke.width * zoomScale,
                opacity: 1,
                in: &context,
                size: size
            )
        }
    }

    private func drawLaserTrail(in context: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        guard !state.laserTrailSegments.isEmpty else {
            return
        }

        let colors = LaserDrawColors(settings: state.laserSettings)
        let duration = max(state.laserSettings.trailDuration, 0.1)
        let fadeDelay = max(state.laserSettings.trailFadeDelay, 0)
        let segments = state.laserTrailSegments
        let opacity: Double

        if state.isLaserTrailActive {
            opacity = 1
        } else if let fadeStartedAt = state.laserTrailFadeStartedAt {
            let elapsedSinceRelease = now - fadeStartedAt
            if elapsedSinceRelease <= fadeDelay {
                opacity = 1
            } else {
                let fadeProgress = (elapsedSinceRelease - fadeDelay) / duration
                guard fadeProgress <= 1 else {
                    return
                }

                opacity = max(0, 1 - fadeProgress)
            }
        } else {
            return
        }

        drawLaserTrail(segments: segments, colors: colors, opacity: opacity, in: &context, size: size)
    }

    private func drawLaserTrail(
        segments: [[LaserPoint]],
        colors: LaserDrawColors,
        opacity: Double,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        for segment in segments where !segment.isEmpty {
            drawLaserTrailSegment(points: segment, colors: colors, opacity: opacity, in: &context, size: size)
        }
    }

    private func drawLaserTrailSegment(
        points: [LaserPoint],
        colors: LaserDrawColors,
        opacity: Double,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        if points.count == 1 {
            let center = points[0].normalizedPosition.denormalized(in: size)
            drawHighlightedLaserDot(
                center: center,
                radius: max(state.laserSettings.width * zoomScale, 5),
                colors: colors,
                opacity: opacity,
                in: &context
            )
            return
        }

        let path = smoothPath(
            points: points.map { $0.normalizedPosition },
            in: size
        )

        drawGoodNotesLaserPath(
            path,
            colors: colors,
            baseWidth: state.laserSettings.width * zoomScale,
            opacity: opacity,
            in: &context
        )
    }

    private func drawGoodNotesLaserPath(
        _ path: Path,
        colors: LaserDrawColors,
        baseWidth: CGFloat,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        let width = max(baseWidth, 1)

        var shadowContext = context
        shadowContext.addFilter(.blur(radius: width * 1.25))
        shadowContext.stroke(
            path,
            with: .color(colors.shadow.opacity(opacity * 0.18)),
            style: laserStrokeStyle(width: width * 3.4)
        )

        var haloContext = context
        haloContext.addFilter(.blur(radius: width * 0.9))
        haloContext.stroke(
            path,
            with: .color(colors.halo.opacity(opacity * 0.32)),
            style: laserStrokeStyle(width: width * 2.7)
        )

        context.stroke(
            path,
            with: .color(colors.main.opacity(opacity)),
            style: laserStrokeStyle(width: width)
        )
        context.stroke(
            path,
            with: .color(.white.opacity(opacity * 0.94)),
            style: laserStrokeStyle(width: max(width * 0.30, 1.5))
        )
    }

    private func laserStrokeStyle(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    private func drawLaserDot(in context: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        guard state.selectedTool == .laserDot, let point = state.currentLaserPoint else {
            return
        }

        let age = point.age(at: now)
        let shouldFade = !state.isLaserDotPressed && !state.laserDotPersistsUntilCleared
        guard !shouldFade || age <= 0.35 else {
            return
        }

        let center = point.normalizedPosition.denormalized(in: size)
        let colors = LaserDrawColors(settings: state.laserSettings)

        if state.isLaserDotPressed {
            drawHighlightedLaserDot(
                center: center,
                radius: state.laserSettings.dotRadius * zoomScale,
                colors: colors,
                opacity: 1,
                in: &context
            )
        } else {
            let radius = max(state.laserSettings.dotRadius * zoomScale * 0.42, 3)
            context.fill(
                Path(ellipseIn: circleRect(center: center, radius: radius)),
                with: .color(colors.main)
            )
        }
    }

    private func drawHighlightedLaserDot(
        center: CGPoint,
        radius: CGFloat,
        colors: LaserDrawColors,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        let coreRadius = max(radius, 4)
        let haloRadius = coreRadius * 2.1

        context.fill(
            Path(ellipseIn: circleRect(center: center, radius: haloRadius)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: colors.halo.opacity(opacity * 0.34), location: 0),
                    .init(color: colors.shadow.opacity(opacity * 0.18), location: 0.68),
                    .init(color: colors.shadow.opacity(0), location: 1)
                ]),
                center: center,
                startRadius: coreRadius,
                endRadius: haloRadius
            )
        )
        context.fill(
            Path(ellipseIn: circleRect(center: center, radius: coreRadius)),
            with: .color(colors.main.opacity(opacity))
        )
        context.fill(
            Path(ellipseIn: circleRect(center: center, radius: coreRadius * 0.36)),
            with: .color(.white.opacity(opacity * 0.96))
        )
    }

    private func circleRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }

    private func drawStroke(
        points: [CGPoint],
        color: Color,
        width: CGFloat,
        opacity: Double,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard let firstPoint = points.first else {
            return
        }

        if points.count == 1 {
            let point = firstPoint.denormalized(in: size)
            let rect = CGRect(
                x: point.x - width / 2,
                y: point.y - width / 2,
                width: width,
                height: width
            )
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
            return
        }

        var path = Path()
        path.move(to: firstPoint.denormalized(in: size))

        for point in points.dropFirst() {
            path.addLine(to: point.denormalized(in: size))
        }

        context.stroke(
            path,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private func smoothPath(points: [CGPoint], in size: CGSize) -> Path {
        var path = Path()
        guard let firstPoint = points.first else {
            return path
        }

        path.move(to: firstPoint.denormalized(in: size))

        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: point.denormalized(in: size))
            }
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1].denormalized(in: size)
            let current = points[index].denormalized(in: size)
            let midPoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )

            path.addQuadCurve(to: midPoint, control: previous)
        }

        if let lastPoint = points.last {
            path.addLine(to: lastPoint.denormalized(in: size))
        }

        return path
    }
}

private struct LaserDrawColors {
    let main: Color
    let halo: Color
    let shadow: Color

    init(settings: LaserSettings) {
        main = Color(platformColor: settings.color)
        halo = Color(platformColor: settings.haloColor)
        shadow = Color(platformColor: settings.shadowColor)
    }
}
