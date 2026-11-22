import CoreGraphics

/// Where everything goes in the console's two rooms, worked out from the
/// window's size alone, so every rule can be tested without a window; the
/// console only assigns the frames.
///
/// Rectangles run top down, as the console's views are flipped: y is the
/// distance from the top of the window.
public enum ConsoleGeometry {
    /// The header in the Booth, and the toolbar in the Studio.
    public static let headerHeight: CGFloat = 56
    /// The rail's width as the operator may drag it, in both rooms.
    public static let railRange: ClosedRange<CGFloat> = 260...520
    /// The Inspector's width as the operator may drag it.
    public static let inspectorRange: ClosedRange<CGFloat> = 300...640
    /// The line between the rail and what is beside it.
    public static let divider: CGFloat = 1

    // MARK: The Booth

    /// The Booth's main column is inset this far from the rail and the window.
    public static let boothInset: CGFloat = 24
    public static let keyRowHeight: CGFloat = 24
    public static let goPlateHeight: CGFloat = 94
    /// Between the GO plate and the key row under it.
    public static let goPlateGap: CGFloat = 12
    /// Between the monitors, the card and the GO plate.
    public static let boothGap: CGFloat = 20
    /// The label row above each monitor: its tag, number and name.
    public static let monitorLabelHeight: CGFloat = 28
    /// The space between the two monitors, where the transition arrow goes.
    public static let monitorGap: CGFloat = 132
    public static let monitorMinWidth: CGFloat = 200
    public static let cardMinHeight: CGFloat = 220
    /// The standby card's number: as large as the card allows, between these.
    public static let cardNumberRange: ClosedRange<CGFloat> = 72...104
    /// The card height at which the number reaches its largest size.
    public static let cardHeightForLargestNumber: CGFloat = 320

    /// The Booth's frames.
    public struct BoothFrames: Equatable, Sendable {
        public var header: CGRect
        /// The stop bands under the header, empty when there are none.
        public var stopBands: CGRect
        public var rail: CGRect
        /// Everything right of the rail, inset.
        public var column: CGRect
        public var onStageLabel: CGRect
        public var onStage: CGRect
        public var nextLabel: CGRect
        public var next: CGRect
        /// Between the monitors, for the transition arrow.
        public var arrow: CGRect
        public var card: CGRect
        public var goPlate: CGRect
        public var keyRow: CGRect
        /// The standby card's number size, for the card's height.
        public var cardNumberSize: CGFloat
    }

    /// - Parameters:
    ///   - bounds: The console's content, top down.
    ///   - railWidth: As the operator left it; clamped to `railRange`.
    ///   - outputAspect: The projector's width over its height.
    ///   - stopBands: The height of the stop bands showing, or zero.
    public static func booth(in bounds: CGRect, railWidth: CGFloat, outputAspect: CGFloat,
                             stopBands: CGFloat = 0) -> BoothFrames {
        let aspect = outputAspect > 0 ? outputAspect : 16 / 9
        let header = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: headerHeight)
        let bands = CGRect(x: bounds.minX, y: header.maxY, width: bounds.width, height: max(0, stopBands))
        let top = bands.maxY
        let rail = CGRect(x: bounds.minX, y: top, width: clampedRail(railWidth, in: bounds.width),
                          height: max(0, bounds.maxY - top))

        let columnX = rail.maxX + divider + boothInset
        let column = CGRect(x: columnX, y: top + boothInset,
                            width: max(0, bounds.maxX - boothInset - columnX),
                            height: max(0, bounds.maxY - boothInset - (top + boothInset)))
        let keyRow = CGRect(x: column.minX, y: column.maxY - keyRowHeight, width: column.width, height: keyRowHeight)
        let goPlate = CGRect(x: column.minX, y: keyRow.minY - goPlateGap - goPlateHeight,
                             width: column.width, height: goPlateHeight)

        // The monitors and the card share what is above the GO plate. The
        // monitors take what the card leaves, as wide as the column lets
        // them; if that leaves them narrower than their least, the card gives
        // up room first.
        let available = max(0, goPlate.minY - boothGap - column.minY)
        let widest = max(0, (column.width - monitorGap) / 2)
        func width(leavingCard card: CGFloat) -> CGFloat {
            let height = available - card - boothGap - monitorLabelHeight
            return min(widest, max(0, height * aspect))
        }
        var monitorWidth = width(leavingCard: cardMinHeight)
        if monitorWidth < min(monitorMinWidth, widest) {
            // As much as the monitors' least, or what is there.
            let least = min(monitorMinWidth, widest)
            let room = max(0, available - boothGap - monitorLabelHeight)
            monitorWidth = min(least, room * aspect)
        }
        monitorWidth = monitorWidth.rounded(.down)
        let monitorHeight = (monitorWidth / aspect).rounded(.down)

        let onStageLabel = CGRect(x: column.minX, y: column.minY, width: monitorWidth, height: monitorLabelHeight)
        let onStage = CGRect(x: column.minX, y: onStageLabel.maxY, width: monitorWidth, height: monitorHeight)
        let nextX = column.maxX - monitorWidth
        let nextLabel = CGRect(x: nextX, y: column.minY, width: monitorWidth, height: monitorLabelHeight)
        let next = CGRect(x: nextX, y: onStageLabel.maxY, width: monitorWidth, height: monitorHeight)
        let arrow = CGRect(x: onStage.maxX, y: onStage.minY, width: max(0, next.minX - onStage.maxX), height: monitorHeight)

        let cardTop = onStage.maxY + boothGap
        let card = CGRect(x: column.minX, y: cardTop, width: column.width,
                          height: max(0, goPlate.minY - boothGap - cardTop))

        return BoothFrames(header: header, stopBands: bands, rail: rail, column: column,
                           onStageLabel: onStageLabel, onStage: onStage, nextLabel: nextLabel, next: next,
                           arrow: arrow, card: card, goPlate: goPlate, keyRow: keyRow,
                           cardNumberSize: cardNumberSize(forCardHeight: card.height))
    }

    /// From the smallest number on a card of the least height, to the largest
    /// on a tall one.
    public static func cardNumberSize(forCardHeight height: CGFloat) -> CGFloat {
        let span = cardHeightForLargestNumber - cardMinHeight
        let t = min(1, max(0, (height - cardMinHeight) / span))
        return (cardNumberRange.lowerBound + t * (cardNumberRange.upperBound - cardNumberRange.lowerBound)).rounded()
    }

    // MARK: The Studio

    /// Space around the Studio's middle column.
    public static let studioInset: CGFloat = 24
    public static let canvasHeaderHeight: CGFloat = 24
    /// Between the canvas and the timeline.
    public static let timelineGap: CGFloat = 16
    /// The line under the timeline, into the next cue.
    public static let joinLineHeight: CGFloat = 20
    /// The least the canvas shrinks to on a short window.
    public static let canvasMinWidth: CGFloat = 240
    /// The least the middle column keeps, whatever the Inspector asks.
    public static let middleMinWidth: CGFloat = 260

    /// The timeline's height for a number of tracks.
    public static func timelineHeight(tracks: Int) -> CGFloat {
        64 + 38 * CGFloat(max(0, tracks))
    }

    /// The Studio's frames.
    public struct StudioFrames: Equatable, Sendable {
        public var toolbar: CGRect
        public var stopBands: CGRect
        public var rail: CGRect
        /// Between the rail and the Inspector, inset.
        public var middle: CGRect
        public var canvasHeader: CGRect
        public var canvas: CGRect
        /// Empty when there is no timeline.
        public var timeline: CGRect
        /// Empty when there is no timeline.
        public var joinLine: CGRect
        /// The full-height column on the right.
        public var inspector: CGRect
    }

    /// - Parameters:
    ///   - timelineTracks: The tracks the timeline shows, or nil for no
    ///     timeline and no join line under it.
    public static func studio(in bounds: CGRect, railWidth: CGFloat, inspectorWidth: CGFloat, outputAspect: CGFloat,
                              timelineTracks: Int? = nil, stopBands: CGFloat = 0) -> StudioFrames {
        let aspect = outputAspect > 0 ? outputAspect : 16 / 9
        let toolbar = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: headerHeight)
        let bands = CGRect(x: bounds.minX, y: toolbar.maxY, width: bounds.width, height: max(0, stopBands))
        let top = bands.maxY, height = max(0, bounds.maxY - top)
        let rail = CGRect(x: bounds.minX, y: top, width: clampedRail(railWidth, in: bounds.width), height: height)

        // The Inspector gives way so the middle keeps its least, and the
        // rail and middle never cross it.
        let roomForInspector = bounds.maxX - (rail.maxX + divider + 2 * studioInset + middleMinWidth + divider)
        let inspectorW = min(inspectorWidth.clamped(to: inspectorRange), max(0, roomForInspector))
        let inspector = CGRect(x: bounds.maxX - inspectorW, y: top, width: inspectorW, height: height)

        let middleX = rail.maxX + divider + studioInset
        let middle = CGRect(x: middleX, y: top + studioInset,
                            width: max(0, inspector.minX - divider - studioInset - middleX),
                            height: max(0, height - 2 * studioInset))
        let canvasHeader = CGRect(x: middle.minX, y: middle.minY, width: middle.width, height: canvasHeaderHeight)

        // What the canvas leaves below it.
        let below: CGFloat = timelineTracks.map { timelineGap + timelineHeight(tracks: $0) + joinLineHeight } ?? 0
        let roomForCanvas = max(0, middle.height - canvasHeaderHeight - below)
        // As large as fits; on a short window it shrinks, but not past its least.
        var canvasWidth = min(middle.width, roomForCanvas * aspect)
        canvasWidth = max(canvasWidth, min(canvasMinWidth, middle.width)).rounded(.down)
        let canvasHeight = (canvasWidth / aspect).rounded(.down)
        let canvas = CGRect(x: middle.minX + ((middle.width - canvasWidth) / 2).rounded(), y: canvasHeader.maxY,
                            width: canvasWidth, height: canvasHeight)

        var timeline = CGRect.zero, joinLine = CGRect.zero
        if let tracks = timelineTracks {
            // The timeline gives up height when the canvas can't shrink more.
            let joinY = min(middle.maxY - joinLineHeight, canvas.maxY + timelineGap + timelineHeight(tracks: tracks))
            let timelineY = canvas.maxY + timelineGap
            timeline = CGRect(x: middle.minX, y: timelineY, width: middle.width, height: max(0, joinY - timelineY))
            joinLine = CGRect(x: middle.minX, y: max(timeline.maxY, joinY), width: middle.width, height: joinLineHeight)
        }
        return StudioFrames(toolbar: toolbar, stopBands: bands, rail: rail, middle: middle, canvasHeader: canvasHeader,
                            canvas: canvas, timeline: timeline, joinLine: joinLine, inspector: inspector)
    }

    // MARK: Both

    /// The rail as wide as asked, within its range, and never so wide it
    /// leaves nothing beside it.
    private static func clampedRail(_ width: CGFloat, in total: CGFloat) -> CGFloat {
        min(width.clamped(to: railRange), max(0, total / 2))
    }
}

extension CGFloat {
    fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
