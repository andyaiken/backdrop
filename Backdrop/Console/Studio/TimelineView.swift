import AppKit
import BackdropCore
import BackdropStage
import SwiftUI

/// The selected cue laid out in time, under the stage. A ruler in seconds
/// from GO, then a row for each part: the transition in, the hold, the
/// kind's own tracks, where it waits for GO partway, and what happens after.
///
/// A bar's end drags to change the setting it shows, a whole step of the
/// clock at a time, within the setting's range, and a drag is one undo step.
/// A click without a drag opens that setting's exact control. While Run
/// again plays, a red playhead sweeps the ruler.
@MainActor
final class TimelineView: NSView {
    private(set) var timeline: CueTimeline?
    private var cue: Cue?
    /// The transition in is selected, so the In bar is lit.
    var transitionSelected = false { didSet { needsDisplay = true } }
    /// Where Run again has got to, in the cue's frames from GO.
    var playhead: () -> Double? = { nil }

    /// A setting changed: coalescing while a drag goes on.
    var onSetting: (SettingKey, SettingValue, _ coalescing: Bool) -> Void = { _, _, _ in }
    /// The continue's wait, in milliseconds, from the Then bar.
    var onContinue: (Int, _ coalescing: Bool) -> Void = { _, _ in }
    /// A drag or a popover finished: the keyboard goes back to the show.
    var onFinished: () -> Void = {}

    static let header: CGFloat = 30
    static let ruler: CGFloat = 26
    static let row: CGFloat = 38
    static let labels: CGFloat = 96

    private let clockMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let title = NSTextField(labelWithString: "Timeline")
    private let hint = NSTextField(labelWithString: "Drag a bar\u{2019}s end to change it. Click a bar for its exact value.")
    private var popover: NSPopover?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        title.font = Desk.sans(13, .semibold)
        hint.font = Desk.sans(12)
        hint.textColor = Desk.dim
        hint.lineBreakMode = .byTruncatingTail
        clockMenu.controlSize = .small
        clockMenu.font = Desk.mono(11.5)
        clockMenu.target = self
        clockMenu.action = #selector(clockChosen(_:))
        (clockMenu.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        clockMenu.focusRingType = .none
        clockMenu.refusesFirstResponder = true
        for view in [title, clockMenu, hint] as [NSView] { addSubview(view) }
        setAccessibilityElement(false)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Timeline")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// The rows it draws, for a cue laid out.
    static func rows(_ timeline: CueTimeline) -> [Row] {
        var rows: [Row] = []
        if timeline.transitionIn != nil { rows.append(Row(name: "In", part: .transition)) }
        if timeline.holdTicks > 0 { rows.append(Row(name: "Hold", part: .hold)) }
        for (i, track) in timeline.tracks.enumerated() { rows.append(Row(name: track.name, part: .track(i))) }
        if !timeline.goes.isEmpty { rows.append(Row(name: "GO steps", part: .goes)) }
        rows.append(Row(name: "Then", part: .then))
        return rows
    }

    struct Row: Equatable {
        enum Part: Equatable { case transition, hold, track(Int), goes, then }
        let name: String
        let part: Part
    }

    private var rows: [Row] = []

    func show(_ timeline: CueTimeline?, cue: Cue?) {
        guard timeline != self.timeline || cue != self.cue else { return }
        self.timeline = timeline
        self.cue = cue
        rows = timeline.map(Self.rows) ?? []
        rebuildClockMenu()
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    private func rebuildClockMenu() {
        clockMenu.removeAllItems()
        guard let cue, SettingKey.clock.applies(to: cue.kind), case .slider(let range, let step) = SettingKey.clock.control,
              case .number(let ms)? = SettingKey.clock.value(in: cue) else {
            clockMenu.isHidden = true
            return
        }
        clockMenu.isHidden = false
        for value in stride(from: range.lowerBound, through: range.upperBound, by: max(step * 2, 4)) {
            clockMenu.addItem(withTitle: "Clock \(value) ms")
            clockMenu.lastItem?.tag = value
        }
        if clockMenu.itemArray.contains(where: { $0.tag == ms }) == false {
            clockMenu.addItem(withTitle: "Clock \(ms) ms")
            clockMenu.lastItem?.tag = ms
        }
        clockMenu.selectItem(withTag: ms)
    }

    @objc private func clockChosen(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        onSetting(.clock, .number(item.tag), false)
        onFinished()
    }

    // MARK: Geometry

    private var plot: NSRect {
        NSRect(x: Self.labels, y: Self.header + Self.ruler, width: max(40, bounds.width - Self.labels - 20),
               height: CGFloat(rows.count) * Self.row)
    }

    /// The frames the ruler spans: the whole of the cue, and a little after.
    private var span: Int {
        guard let timeline else { return 1 }
        var last = max(timeline.endFrame, timeline.transitionIn?.end ?? 0, timeline.holdTicks)
        if case .after(let ms) = timeline.then { last = max(last, ms / timeline.clockMs) }
        if case .whenFinished(let ms) = timeline.then { last = timeline.endFrame + ms / timeline.clockMs }
        let second = 1000 / Double(timeline.clockMs)
        // To the next whole second, and at least two.
        return Int((ceil(Double(last + 4) / second) * second).rounded(.up)).clamped(min: Int(2 * second))
    }

    private func x(_ frame: Double) -> CGFloat { plot.minX + CGFloat(frame / Double(span)) * plot.width }
    private func frame(atX x: CGFloat) -> Double { Double((x - plot.minX) / plot.width) * Double(span) }
    private func rowRect(_ i: Int) -> NSRect { NSRect(x: 0, y: plot.minY + CGFloat(i) * Self.row, width: bounds.width, height: Self.row) }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 14, y: 8, width: 70, height: 18)
        let menu = clockMenu.fittingSize
        clockMenu.frame = NSRect(x: 86, y: 5, width: menu.width, height: 22)
        let hintX = (clockMenu.isHidden ? 86 : clockMenu.frame.maxX + 14)
        hint.frame = NSRect(x: hintX, y: 9, width: max(0, bounds.width - hintX - 12), height: 16)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let room = Room.studio
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        room.line.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).stroke()
        guard let timeline else { return }

        // The ruler: a tick each quarter second, a number each second.
        let perSecond = 1000 / Double(timeline.clockMs)
        let rulerY = Self.header + Self.ruler - 4
        var second = 0.0
        while second * perSecond <= Double(span) {
            for quarter in 0..<4 {
                let f = (second + Double(quarter) / 4) * perSecond
                guard f <= Double(span) else { break }
                let tickX = x(f)
                room.line.setFill()
                NSRect(x: tickX, y: rulerY - (quarter == 0 ? 6 : 3), width: 1, height: quarter == 0 ? 6 : 3).fill()
                if quarter == 0 {
                    let label = NSAttributedString(string: "\(Int(second)) s", attributes: [.font: Desk.mono(10.5), .foregroundColor: room.dim])
                    label.draw(at: NSPoint(x: tickX + 2, y: rulerY - 18))
                    room.line.withAlphaComponent(0.35).setFill()
                    NSRect(x: tickX, y: plot.minY, width: 1, height: plot.height).fill()
                }
            }
            second += 1
        }

        for (i, row) in rows.enumerated() {
            let r = rowRect(i)
            let name = NSAttributedString(string: row.name, attributes: [.font: Desk.sans(12), .foregroundColor: room.dim])
            name.draw(at: NSPoint(x: 14, y: r.midY - 8))
            switch row.part {
            case .transition:
                if let span = timeline.transitionIn { drawBar(span, in: r, label: transitionLabel, lit: transitionSelected) }
            case .hold:
                let hold = CueTimeline.Span(start: 0, end: timeline.holdTicks, label: nil, key: .hold, handle: .end)
                drawBar(hold, in: r, label: "Hold \u{00B7} \(timeline.holdTicks) steps \u{00B7} \(seconds(timeline.holdTicks))")
            case .track(let t):
                drawTrack(timeline.tracks[t], in: r)
            case .goes:
                for go in timeline.goes {
                    // Everything after a GO waits for the operator.
                    drawHatch(from: x(Double(go)), in: r)
                    drawDiamond(at: NSPoint(x: x(Double(go)), y: r.midY), filled: true)
                }
            case .then:
                drawThen(timeline, in: r)
            }
        }

        // Run again's playhead.
        if let position = playhead() {
            let px = x(position)
            if px >= plot.minX, px <= plot.maxX {
                room.tally.setFill()
                NSRect(x: px - 1, y: Self.header + 6, width: 2, height: plot.maxY - Self.header - 6).fill()
                let head = NSBezierPath()
                head.move(to: NSPoint(x: px - 6, y: Self.header + 4))
                head.line(to: NSPoint(x: px + 6, y: Self.header + 4))
                head.line(to: NSPoint(x: px, y: Self.header + 12))
                head.close()
                head.fill()
            }
        }
    }

    private var transitionLabel: String {
        guard let cue else { return "" }
        return CueText.transitionNote(cue)
    }

    private func seconds(_ frames: Int) -> String {
        guard let timeline else { return "" }
        return CueText.seconds(frames * timeline.clockMs)
    }

    private func barRect(_ span: CueTimeline.Span, in row: NSRect, inset: CGFloat = 8) -> NSRect {
        let x0 = x(Double(span.start)), x1 = max(x0 + 2, x(Double(span.end)))
        return NSRect(x: x0, y: row.minY + inset, width: x1 - x0, height: row.height - 2 * inset)
    }

    private func drawBar(_ span: CueTimeline.Span, in row: NSRect, label: String?, lit: Bool = false) {
        let room = Room.studio
        let rect = barRect(span, in: row)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        room.brass.withAlphaComponent(lit ? 0.35 : 0.16).setFill()
        path.fill()
        room.brass.setStroke()
        path.lineWidth = lit ? 2 : 1
        path.stroke()
        if span.handle == .end {
            room.brass.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.maxX - 5, y: rect.minY + 4, width: 3, height: rect.height - 8),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
        if let label, rect.width > 40 {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: label, attributes: [.font: Desk.mono(11), .foregroundColor: room.ink, .paragraphStyle: style])
                .draw(in: NSRect(x: rect.minX + 8, y: rect.midY - 7, width: rect.width - 16, height: 16))
        }
    }

    /// A track: a bar for each span. Many spans, as a decryption's letters,
    /// fan down the row, each a little lower than the last.
    private func drawTrack(_ track: CueTimeline.Track, in row: NSRect) {
        let room = Room.studio
        if track.spans.count > 4, track.spans.contains(where: { $0.handle == .slope }) {
            let usable = row.height - 14
            for (i, span) in track.spans.enumerated() {
                let y = row.minY + 7 + usable * CGFloat(i) / CGFloat(max(1, track.spans.count - 1)) - 2
                let x0 = x(Double(span.start)), x1 = max(x0 + 2, x(Double(span.end)))
                room.brass.setFill()
                NSRect(x: x0, y: y, width: x1 - x0, height: 4).fill()
            }
            return
        }
        for span in track.spans {
            if span.end - span.start <= 1 {
                // A moment, as a key press: a tick.
                room.brass.setFill()
                NSRect(x: x(Double(span.start)) - 1, y: row.minY + 10, width: 2, height: row.height - 20).fill()
            } else {
                drawBar(span, in: row, label: span.label)
            }
        }
    }

    private func drawThen(_ timeline: CueTimeline, in row: NSRect) {
        let room = Room.studio
        switch timeline.then {
        case .waits:
            let at = NSPoint(x: x(Double(timeline.endFrame)) + 10, y: row.midY)
            drawDiamond(at: at, filled: true)
            let words = NSAttributedString(string: "waits for GO", attributes: [.font: Desk.mono(11), .foregroundColor: room.dim])
            words.draw(at: NSPoint(x: at.x - words.size().width - 12, y: row.midY - 7))
        case .after(let ms), .whenFinished(let ms):
            drawBar(thenSpan(timeline, ms: ms), in: row, label: "runs on \(CueText.seconds(ms))")
        }
    }

    private func thenSpan(_ timeline: CueTimeline, ms: Int) -> CueTimeline.Span {
        let from: Int = if case .whenFinished = timeline.then { timeline.endFrame } else { 0 }
        return CueTimeline.Span(start: from, end: from + max(1, ms / timeline.clockMs), label: nil, key: nil, handle: .end)
    }

    private func drawDiamond(at point: NSPoint, filled: Bool) {
        let room = Room.studio
        let d = NSBezierPath()
        d.move(to: NSPoint(x: point.x, y: point.y - 7))
        d.line(to: NSPoint(x: point.x + 7, y: point.y))
        d.line(to: NSPoint(x: point.x, y: point.y + 7))
        d.line(to: NSPoint(x: point.x - 7, y: point.y))
        d.close()
        room.brass.setFill()
        d.fill()
    }

    private func drawHatch(from x0: CGFloat, in row: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: x0, y: row.minY + 4, width: plot.maxX - x0, height: row.height - 8).clip()
        Room.studio.dim.withAlphaComponent(0.25).setStroke()
        let lines = NSBezierPath()
        var x = x0 - row.height
        while x < plot.maxX {
            lines.move(to: NSPoint(x: x, y: row.maxY))
            lines.line(to: NSPoint(x: x + row.height, y: row.minY))
            x += 8
        }
        lines.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Dragging and clicking

    /// What is under the pointer: a row, a span in it, and its index.
    private struct Hit {
        var row: Row
        var span: CueTimeline.Span
        var index: Int
    }

    private func hit(at point: NSPoint) -> Hit? {
        guard let timeline, plot.contains(point) else { return nil }
        let i = Int((point.y - plot.minY) / Self.row)
        guard rows.indices.contains(i) else { return nil }
        let row = rows[i]
        let frame = frame(atX: point.x)
        switch row.part {
        case .transition:
            return timeline.transitionIn.map { Hit(row: row, span: $0, index: 0) }
        case .hold:
            return Hit(row: row, span: CueTimeline.Span(start: 0, end: timeline.holdTicks, key: .hold, handle: .end), index: 0)
        case .track(let t):
            let spans = timeline.tracks[t].spans
            // The nearest span to the pointer, by its end.
            guard let best = spans.indices.min(by: { abs(Double(spans[$0].end) - frame) < abs(Double(spans[$1].end) - frame) })
            else { return nil }
            return Hit(row: row, span: spans[best], index: best)
        case .goes:
            return nil
        case .then:
            switch timeline.then {
            case .waits: return nil
            case .after(let ms), .whenFinished(let ms): return Hit(row: row, span: thenSpan(timeline, ms: ms), index: 0)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let cue, let timeline, let window else { return }
        let start = convert(event.locationInWindow, from: nil)
        guard let target = hit(at: start) else { return }
        let draggable = target.span.handle != nil
        var dragged = false
        let original = target.span.key.flatMap { $0.value(in: cue) }
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event, event.type == .leftMouseDragged else {
                stop.pointee = true
                return
            }
            guard draggable else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard abs(point.x - start.x) > 2 || dragged else { return }
            dragged = true
            drag(target, by: frame(atX: point.x) - frame(atX: start.x), original: original, timeline: timeline)
        }
        let rect = barRect(target.span, in: rowRect(rows.firstIndex(of: target.row) ?? 0))
        if dragged {
            onFinished()
        } else if let key = target.span.key {
            showPopover(for: key, at: rect)
        } else if target.row.part == .then {
            showContinuePopover(at: rect)
        }
    }

    /// A drag of `delta` frames from where it started, turned into the
    /// setting's value, snapped to its step and kept in its range.
    private func drag(_ target: Hit, by delta: Double, original: SettingValue?, timeline: CueTimeline) {
        let frames = Int(delta.rounded())
        let clock = timeline.clockMs
        if target.row.part == .then {
            let length = max(0, target.span.end - target.span.start + frames)
            onContinue(min(length * clock, ContinueMode.longest), true)
            return
        }
        guard let key = target.span.key, case .number(let was)? = original else { return }
        let value: Int
        switch (key, target.span.handle) {
        case (.wave, .slope?):
            // The fan's slope: the change at this letter, spread over the
            // letters before it.
            value = was + Int((Double(frames) / Double(max(1, target.index))).rounded())
        case (.hold, _), (.pause, _):
            value = was + frames
        default:
            // A length in milliseconds.
            value = was + frames * clock
        }
        onSetting(key, Self.clamp(key, value), true)
    }

    static func clamp(_ key: SettingKey, _ value: Int) -> SettingValue {
        guard case .slider(let range, _) = key.control else { return .number(value) }
        return key.snapped(.number(min(max(value, range.lowerBound), range.upperBound)))
    }

    /// A bar clicked: its setting's exact control, and the cue's other
    /// timing settings under it, each with its help.
    private func showPopover(for key: SettingKey, at rect: NSRect) {
        guard let cue else { return }
        let others = SettingKey.allCases.filter { $0.isTiming && $0 != key && $0 != .clock && $0 != .fade && $0.applies(to: cue.kind) }
        let view = TimelinePopover(cue: cue, key: key, others: others,
                                   onChange: { [weak self] key, value, continuous in self?.onSetting(key, value, continuous) })
        present(NSHostingController(rootView: view), at: rect)
    }

    private func showContinuePopover(at rect: NSRect) {
        guard let cue else { return }
        let view = ContinuePopover(cue: cue, onChange: { [weak self] ms in self?.onContinue(ms, false) })
        present(NSHostingController(rootView: view), at: rect)
    }

    private func present(_ controller: NSViewController, at rect: NSRect) {
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.delegate = self
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        self.popover = popover
    }

    // MARK: Accessibility

    override func accessibilityChildren() -> [Any]? {
        guard let timeline, let cue else { return [] }
        var handles: [Any] = []
        for (i, row) in rows.enumerated() {
            let key: SettingKey?
            switch row.part {
            case .transition: key = .fade
            case .hold: key = .hold
            case .track(let t): key = timeline.tracks[t].spans.first(where: { $0.handle != nil })?.key
            case .goes, .then: key = nil
            }
            guard let key, case .number? = key.value(in: cue) else { continue }
            handles.append(TimelineHandle(parent: self, key: key, cue: cue, clockMs: timeline.clockMs,
                                          frame: NSAccessibility.screenRect(fromView: self, rect: rowRect(i))))
        }
        return handles
    }

    fileprivate func step(_ key: SettingKey, by direction: Int) {
        guard let cue, case .number(let was)? = key.value(in: cue), case .slider(_, let step) = key.control else { return }
        onSetting(key, Self.clamp(key, was + direction * max(step, 1)), false)
    }
}

extension TimelineView: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        popover = nil
        onFinished()
    }
}

/// A timing handle, for VoiceOver: an adjustable element that reads its
/// name, its value and the seconds it stands for, and steps one at a time.
private final class TimelineHandle: NSAccessibilityElement {
    weak var parent: TimelineView?
    let key: SettingKey
    let cue: Cue
    let clockMs: Int

    init(parent: TimelineView, key: SettingKey, cue: Cue, clockMs: Int, frame: NSRect) {
        self.parent = parent
        self.key = key
        self.cue = cue
        self.clockMs = clockMs
        super.init()
        setAccessibilityParent(parent)
        setAccessibilityFrame(frame)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(key.label)
    }

    override func accessibilityValue() -> Any? {
        guard let value = key.value(in: cue) else { return nil }
        var words = key.format(value, for: cue.kind)
        if key == .hold, case .number(let ticks) = value { words += ", \(CueText.seconds(ticks * clockMs))" }
        return words
    }

    override func accessibilityPerformIncrement() -> Bool {
        let parent = parent, key = key
        MainActor.assumeIsolated { parent?.step(key, by: 1) }
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        let parent = parent, key = key
        MainActor.assumeIsolated { parent?.step(key, by: -1) }
        return true
    }
}

/// A bar's setting exactly, with its help, and the cue's other timing.
struct TimelinePopover: View {
    let cue: Cue
    let key: SettingKey
    let others: [SettingKey]
    let onChange: (SettingKey, SettingValue, Bool) -> Void

    var body: some View {
        Form {
            row(key)
            if !others.isEmpty {
                Section("Other timing") {
                    ForEach(others, id: \.self) { row($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func row(_ key: SettingKey) -> some View {
        if let value = key.value(in: cue) {
            let state = SettingState.of(key, in: cue)
            SettingRowView(key: key, kind: cue.kind, value: value, annotation: state.annotation, isEnabled: state.enabled,
                           onChange: { value, continuous in onChange(key, value, continuous) })
        }
    }
}

/// The Then bar's wait, exactly.
struct ContinuePopover: View {
    let cue: Cue
    let onChange: (Int) -> Void

    private var ms: Int {
        switch cue.continueMode {
        case .whenCued: 0
        case .after(let ms), .whenFinished(let ms): ms
        }
    }

    var body: some View {
        Form {
            FieldRow(label: "Seconds", value: ContinueMode.seconds(ms)) {
                Stepper("", value: Binding(get: { Double(ms) / 1000 }, set: { onChange(Int(($0 * 10).rounded()) * 100) }),
                        in: 0...Double(ContinueMode.longest) / 1000, step: 0.1)
            }
        }
        .formStyle(.grouped)
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Int {
    fileprivate func clamped(min lower: Int) -> Int { Swift.max(self, lower) }
}
