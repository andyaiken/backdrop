import AppKit
import BackdropCore
import QuartzCore

/// Text message cues: one bubble with the sender above it, on a dark or light
/// screen. The bubble arrives by zooming in from small, growing a little
/// past its size and settling, or by fading up, or at once.
///
/// Everything is drawn from how far into the arrival the clock is, so every
/// surface agrees.
@MainActor
public final class SMSRenderer: PaintsBetweenFrames, WaitsForGO {
    public let isInstant = true

    private var content: SMSContent?
    private var textScale = 100
    private var timeline = GoTimeline(parts: [0])
    /// Frames into the cue, as last painted; a refit repaints at it.
    private var lastPosition = Double(SMSRenderer.settledFrame)
    private var trees: [ObjectIdentifier: Tree] = [:]

    static let settledFrame = 1_000_000
    /// How large the bubble starts, against its size.
    static let startScale: CGFloat = 0.35
    /// Frames a change of status takes: it fades out and the new one fades in.
    static let statusFrames = 8.0

    final class QuietText: CATextLayer {
        override func action(forKey event: String) -> (any CAAction)? { nil }
    }

    final class QuietShape: CAShapeLayer {
        override func action(forKey event: String) -> (any CAAction)? { nil }
    }

    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        let group = StillLayer()
        let bubble = QuietShape()
        let body = QuietText()
        let from = QuietText()
        let status = QuietText()
        let ticks = QuietShape()
        var tick = CGSize.zero
        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
            group.addSublayer(bubble)
            group.addSublayer(body)
            group.addSublayer(from)
            group.addSublayer(status)
            group.addSublayer(ticks)
            root.addSublayer(group)
            ticks.fillColor = nil
            ticks.lineCap = .round
            ticks.lineJoin = .round
            for text in [body, from, status] {
                text.isWrapped = true
                text.truncationMode = .none
            }
        }
    }

    public init() {}

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let tree = Tree(surface: surface)
        trees[ObjectIdentifier(surface)] = tree
        surface.inset.addSublayer(tree.root)
        fit(surface)
    }

    public func unmount(from surface: SurfaceLayer) {
        trees.removeValue(forKey: ObjectIdentifier(surface))?.root.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        trees[ObjectIdentifier(surface)]?.root.isHidden = !visible
    }

    public func clear(_ surface: SurfaceLayer) {
        content = nil
        timeline = GoTimeline(parts: [0])
        lastPosition = Double(Self.settledFrame)
        guard let tree = trees[ObjectIdentifier(surface)] else { return }
        tree.body.string = nil
        tree.from.string = nil
        tree.status.string = nil
        tree.ticks.path = nil
        tree.bubble.path = nil
        tree.root.backgroundColor = RGB.black.cgColor
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .sms(let content) = cue.content else { return }
        self.content = content
        textScale = show.textScale
        let s = content.settings
        let arrival = s.entrance == .cut ? 0 : Int((Double(s.entranceMs) / Double(CueTiming.standardClockMs)).rounded(.up))
        timeline = GoTimeline(parts: [arrival] + s.goStatuses.map { _ in Int(Self.statusFrames) })
        lastPosition = 0
        for tree in trees.values { fit(tree.surface) }
    }

    public func settingsChanged(_ show: ShowSettings) {
        guard show.textScale != textScale else { return }
        textScale = show.textScale
        for tree in trees.values { fit(tree.surface) }
    }

    public func frame(_ f: Int) -> Bool {
        paint(at: Double(f))
    }

    // MARK: PaintsBetweenFrames

    public func paint(at position: Double) -> Bool {
        lastPosition = position
        guard let content else { return true }
        let p = progress(at: position, content.settings)
        let (status, alpha) = statusState(at: position, content.settings)
        for tree in trees.values {
            apply(p, content.settings, to: tree)
            applyStatus(status, alpha: alpha, content.settings, to: tree)
        }
        return p >= 1 && timeline.isFinished(at: Int(position))
    }

    // MARK: WaitsForGO

    public func isWaiting(at f: Int) -> Bool { content != nil && timeline.isWaiting(at: f) }
    public func carryOn(at f: Int) { timeline.carryOn(at: f) }
    public func carryOnToEnd() { timeline.carryOnToEnd() }

    /// GO point k brings on the status after k steps; part 0 is the arrival.
    public func goTo(_ point: Int, at f: Int) { timeline.jump(toPart: point + 1, at: f) }

    /// The status showing at `position`, and how strongly: a change fades the
    /// old one out and the new one in.
    private func statusState(at position: Double, _ s: SMSSettings) -> (SMSStatus, Float) {
        var current = s.shownStatus
        var alpha: Float = 1
        let steps = s.goStatuses
        for (i, next) in steps.enumerated() {
            guard let start = timeline.start(part: i + 1, offset: 0).map(Double.init), position >= start else { break }
            let q = min(1, (position - start) / Self.statusFrames)
            if q < 0.5 {
                current = i == 0 ? s.shownStatus : steps[i - 1]
                alpha = Float(1 - 2 * q)
            } else {
                current = next
                alpha = Float(2 * q - 1)
            }
        }
        return (current, alpha)
    }

    private func applyStatus(_ status: SMSStatus, alpha: Float, _ s: SMSSettings, to tree: Tree) {
        let palette = MessageLook.palette(style: s.style, dark: s.dark, sent: s.sent)
        tree.status.string = status.line
        tree.status.opacity = alpha
        tree.ticks.path = Self.statusPath(status, width: tree.tick.width, height: tree.tick.height)
        tree.ticks.strokeColor = (status == .read ? RGB(0x53, 0xBD, 0xEB) : palette.quiet).cgColor
        tree.ticks.opacity = alpha
    }

    /// How far through the arrival the cue is, from 0 to 1.
    private func progress(at position: Double, _ s: SMSSettings) -> Double {
        guard s.entrance != .cut else { return 1 }
        let frames = max(1, Double(s.entranceMs) / Double(CueTiming.standardClockMs))
        return min(1, max(0, position / frames))
    }

    // MARK: Look

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = trees[ObjectIdentifier(surface)] else { return }
        let size = surface.inset.bounds.size
        tree.root.frame = CGRect(origin: .zero, size: size)
        guard let content, size.width > 0, size.height > 0 else { return }
        let s = content.settings
        let palette = MessageLook.palette(style: s.style, dark: s.dark, sent: s.sent)
        let contents = max(surface.contentsScale, 1)
        tree.root.backgroundColor = palette.screen.cgColor

        let fontSize = max(10, size.height * 0.055 * CGFloat(textScale) / 100)
        let bodyFont = MessageLook.font(s.style, size: fontSize)
        let fromFont = MessageLook.font(s.style, size: fontSize * 0.6)
        let padX = fontSize * 0.85
        let padY = fontSize * 0.5
        let maxBubble = size.width * 0.72
        let margin = size.width * 0.08

        let attributes: [NSAttributedString.Key: Any] = [.font: bodyFont as NSFont]
        let free = NSAttributedString(string: content.text, attributes: attributes)
            .boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textWidth = min(ceil(free.width) + 2, maxBubble - 2 * padX)
        let wrapped = NSAttributedString(string: content.text, attributes: attributes)
            .boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textHeight = ceil(wrapped.height)
        let shown = s.shownStatus
        // WhatsApp keeps its status inside the bubble, at the bottom right.
        let ticked = shown != .none && s.style == .whatsapp
        let tickW = fontSize * 0.5
        let tickSpace = ticked ? tickW * 1.9 : 0
        let bubbleW = textWidth + 2 * padX + tickSpace
        let bubbleH = max(textHeight + 2 * padY, fontSize * 2)

        let hasFrom = !content.sub.trimmingCharacters(in: .whitespaces).isEmpty
        let fromH = hasFrom ? ceil(MessageLook.lineHeight(fromFont)) : 0
        let fromGap = hasFrom ? fontSize * 0.25 : 0
        // The other styles write it beneath the bubble.
        let lined = shown != .none && !ticked
        let statusH = lined ? ceil(MessageLook.lineHeight(fromFont)) : 0
        let statusGap = lined ? fontSize * 0.25 : 0
        let lift = statusH + statusGap
        let groupW = max(bubbleW, hasFrom ? min(ceil(fromWidth(content.sub, fromFont)) + 2, maxBubble) : 0,
                         lined ? ([shown] + s.goStatuses).map { ceil(fromWidth($0.line, fromFont)) + 2 }.max() ?? 0 : 0)
        let groupH = lift + bubbleH + fromGap + fromH

        // Layers count up from the bottom. The group sits at the picture's
        // middle, at the left for a message received and the right for one sent.
        let groupX = s.sent ? size.width - margin - groupW : margin
        let groupY = (size.height - groupH) / 2
        // Bounds and position, not frame: the frame of a layer that is zoomed
        // means something else, and a refit can come mid-arrival.
        tree.group.bounds = CGRect(x: 0, y: 0, width: groupW, height: groupH)
        tree.group.position = CGPoint(x: groupX.rounded() + groupW / 2, y: groupY.rounded() + groupH / 2)

        let bubbleX = s.sent ? groupW - bubbleW : 0
        let bubbleRect = CGRect(x: bubbleX, y: 0, width: bubbleW, height: bubbleH)
        tree.bubble.frame = CGRect(x: 0, y: lift, width: groupW, height: bubbleH)
        tree.bubble.path = MessageLook.bubblePath(bubbleRect, style: s.style, sent: s.sent, fontSize: fontSize)
        tree.bubble.fillColor = palette.bubble.cgColor

        configure(tree.body, text: content.text, font: bodyFont, size: fontSize, colour: palette.text, scale: contents)
        tree.body.alignmentMode = .left
        tree.body.frame = CGRect(x: bubbleX + padX, y: lift + (bubbleH - textHeight) / 2, width: textWidth, height: textHeight)

        configure(tree.from, text: content.sub, font: fromFont, size: fontSize * 0.6, colour: palette.quiet, scale: contents)
        tree.from.alignmentMode = s.sent ? .right : .left
        tree.from.isHidden = !hasFrom
        let fromInset = s.style == .imessage ? fontSize * 0.6 : 0
        tree.from.frame = CGRect(x: s.sent ? 0 : fromInset, y: lift + bubbleH + fromGap, width: groupW - fromInset, height: fromH)

        configure(tree.status, text: shown.line, font: fromFont, size: fontSize * 0.6, colour: palette.quiet, scale: contents)
        tree.status.alignmentMode = .right
        tree.status.isHidden = !lined
        tree.status.frame = CGRect(x: 0, y: 0, width: groupW - fontSize * 0.3, height: statusH)

        tree.ticks.isHidden = !ticked
        if ticked {
            let height = tickW * 0.9
            let origin = CGPoint(x: bubbleX + bubbleW - padX * 0.55 - tickW * 1.9, y: lift + padY * 0.7)
            tree.ticks.frame = CGRect(origin: origin, size: CGSize(width: tickW * 1.9, height: height))
            tree.tick = CGSize(width: tickW, height: height)
            tree.ticks.lineWidth = max(1, fontSize * 0.085)
        }

        _ = paint(at: lastPosition)
    }

    /// WhatsApp's status marks, drawn in a box of `width` by `height` (one
    /// tick wide): a clock while sending, a tick when sent, and two once
    /// delivered or read.
    static func statusPath(_ status: SMSStatus, width w: CGFloat, height h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func tick(at dx: CGFloat) {
            path.move(to: CGPoint(x: dx, y: h * 0.45))
            path.addLine(to: CGPoint(x: dx + w * 0.32, y: h * 0.08))
            path.addLine(to: CGPoint(x: dx + w, y: h * 0.95))
        }
        switch status {
        case .none:
            break
        case .sending:
            let d = h * 0.95
            let centre = CGPoint(x: w / 2 + d * 0.05, y: h / 2)
            path.addEllipse(in: CGRect(x: centre.x - d / 2, y: centre.y - d / 2, width: d, height: d))
            path.move(to: CGPoint(x: centre.x, y: centre.y + d * 0.28))
            path.addLine(to: centre)
            path.addLine(to: CGPoint(x: centre.x + d * 0.2, y: centre.y - d * 0.1))
        case .sent:
            tick(at: w * 0.9)
        case .delivered, .read:
            tick(at: 0)
            tick(at: w * 0.9)
        }
        return path
    }

    private func fromWidth(_ text: String, _ font: CTFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font as NSFont]).size().width
    }

    private func configure(_ layer: QuietText, text: String, font: CTFont, size: CGFloat, colour: RGB, scale: CGFloat) {
        layer.string = text
        layer.font = font
        layer.fontSize = size
        layer.foregroundColor = colour.cgColor
        layer.contentsScale = scale
    }

    // MARK: Arrival

    private func apply(_ p: Double, _ s: SMSSettings, to tree: Tree) {
        let opacity: Float
        var scale: CGFloat = 1
        switch s.entrance {
        case .cut:
            opacity = 1
        case .fade:
            opacity = Float(StageRunner.ease(p))
        case .pop:
            opacity = Float(min(1, p / 0.25))
            if p < 1 {
                // A spring that overshoots once, from small through a little
                // over full size, and settles.
                let spring = 1 - exp(-4.5 * p) * cos(2 * .pi * 0.9 * p)
                scale = Self.startScale + (1 - Self.startScale) * CGFloat(spring)
            }
        }
        tree.group.opacity = opacity
        tree.group.transform = CATransform3DMakeScale(scale, scale, 1)
    }
}
