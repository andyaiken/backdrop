import AppKit
import BackdropCore
import QuartzCore

/// Text conversation cues: a thread of bubbles on a dark or light screen,
/// with the contact's name across the top. A received message shows the
/// typing dots and then grows into its text; a sent one is typed into the
/// compose bar and then lifts into the thread. The thread sits at the
/// bottom, so each new bubble pushes the older ones up, and the ones that
/// reach the top go off it.
///
/// Everything is drawn from the plan's state at the clock's position, so
/// every surface agrees, and GO, stepping back and putting the cue up
/// finished all come out right.
@MainActor
public final class ConversationRenderer: PaintsBetweenFrames, WaitsForGO {
    public let isInstant = true

    private var plan: ConversationCuePlan?
    private var timeline = GoTimeline(parts: [0])
    private var lastPosition = Double(ConversationRenderer.settledFrame)
    private var textScale = 100
    private var trees: [ObjectIdentifier: Tree] = [:]

    static let settledFrame = 1_000_000

    final class QuietText: CATextLayer {
        override func action(forKey event: String) -> (any CAAction)? { nil }
    }

    final class QuietShape: CAShapeLayer {
        override func action(forKey event: String) -> (any CAAction)? { nil }
    }

    /// The layers of one message.
    struct Bubble {
        let shape = QuietShape()
        let text = QuietText()
        let dots = (0..<3).map { _ in StillLayer() }
    }

    /// What one message measures, at this surface's size.
    struct Size {
        var textW: CGFloat
        var textH: CGFloat
        var bubbleW: CGFloat
        var bubbleH: CGFloat
    }

    struct Metrics {
        var size: CGSize
        var fontSize: CGFloat
        var padX: CGFloat
        var margin: CGFloat
        var dotsW: CGFloat
        var dotsH: CGFloat
        var messages: [Size]
    }

    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        let thread = StillLayer()
        let header = QuietText()
        let bar = StillLayer()
        let barText = QuietText()
        let barSend = StillLayer()
        var bubbles: [Bubble] = []
        var metrics: Metrics?
        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
            thread.masksToBounds = true
            header.alignmentMode = .center
            barText.truncationMode = .start
            root.addSublayer(thread)
            root.addSublayer(header)
            root.addSublayer(bar)
            bar.addSublayer(barText)
            bar.addSublayer(barSend)
        }

        func removeBubbles() {
            for b in bubbles {
                b.shape.removeFromSuperlayer()
                b.text.removeFromSuperlayer()
                b.dots.forEach { $0.removeFromSuperlayer() }
            }
            bubbles = []
        }
    }

    public init() {}

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let tree = Tree(surface: surface)
        trees[ObjectIdentifier(surface)] = tree
        surface.inset.addSublayer(tree.root)
        build(tree)
        fit(surface)
    }

    public func unmount(from surface: SurfaceLayer) {
        trees.removeValue(forKey: ObjectIdentifier(surface))?.root.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        trees[ObjectIdentifier(surface)]?.root.isHidden = !visible
    }

    public func clear(_ surface: SurfaceLayer) {
        plan = nil
        timeline = GoTimeline(parts: [0])
        lastPosition = Double(Self.settledFrame)
        guard let tree = trees[ObjectIdentifier(surface)] else { return }
        tree.removeBubbles()
        tree.metrics = nil
        tree.header.string = nil
        tree.barText.string = nil
        tree.root.backgroundColor = RGB.black.cgColor
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .conversation(let content) = cue.content else { return }
        let plan = ConversationCuePlan(content)
        self.plan = plan
        timeline = GoTimeline(parts: plan.parts)
        textScale = show.textScale
        lastPosition = 0
        for tree in trees.values {
            build(tree)
            fit(tree.surface)
        }
    }

    public func settingsChanged(_ show: ShowSettings) {
        guard show.textScale != textScale else { return }
        textScale = show.textScale
        for tree in trees.values { fit(tree.surface) }
    }

    public func frame(_ f: Int) -> Bool {
        paint(at: Double(f))
    }

    // MARK: WaitsForGO

    public func isWaiting(at f: Int) -> Bool { plan != nil && timeline.isWaiting(at: f) }
    public func carryOn(at f: Int) { timeline.carryOn(at: f) }
    public func carryOnToEnd() { timeline.carryOnToEnd() }

    /// GO point k lets go stage k + 1; stage 0 runs from the cue's start.
    public func goTo(_ point: Int, at f: Int) { timeline.jump(toPart: point + 1, at: f) }

    // MARK: PaintsBetweenFrames

    public func paint(at position: Double) -> Bool {
        lastPosition = position
        guard let plan else { return true }
        let state = plan.state(at: position, timeline: timeline)
        for tree in trees.values { render(state, plan: plan, in: tree) }
        return timeline.isFinished(at: Int(position))
    }

    // MARK: Layout

    private func build(_ tree: Tree) {
        tree.removeBubbles()
        guard let plan else { return }
        for _ in plan.content.messages {
            let bubble = Bubble()
            bubble.text.isWrapped = true
            bubble.text.truncationMode = .none
            tree.thread.addSublayer(bubble.shape)
            tree.thread.addSublayer(bubble.text)
            for dot in bubble.dots {
                dot.isHidden = true
                tree.thread.addSublayer(dot)
            }
            tree.bubbles.append(bubble)
        }
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = trees[ObjectIdentifier(surface)] else { return }
        let size = surface.inset.bounds.size
        tree.root.frame = CGRect(origin: .zero, size: size)
        guard let plan, size.width > 0, size.height > 0 else { return }
        let s = plan.content.settings
        let palette = MessageLook.palette(style: s.style, dark: s.dark, sent: false)
        let contents = max(surface.contentsScale, 1)
        tree.root.backgroundColor = palette.screen.cgColor

        let f = max(10, size.height * 0.05 * CGFloat(textScale) / 100)
        let font = MessageLook.font(s.style, size: f)
        let padX = f * 0.85, padY = f * 0.5
        let margin = size.width * 0.06
        let maxBubble = size.width * 0.72
        let edge = size.height * 0.04

        // The name across the top.
        let name = plan.content.sub.trimmingCharacters(in: .whitespaces)
        var top = size.height - edge
        tree.header.isHidden = name.isEmpty
        if !name.isEmpty {
            let headFont = MessageLook.font(s.style, size: f * 0.8)
            let h = ceil(MessageLook.lineHeight(headFont))
            style(tree.header, text: name, font: headFont, size: f * 0.8, colour: palette.text, scale: contents)
            tree.header.frame = CGRect(x: 0, y: top - h, width: size.width, height: h)
            top -= h + f * 0.6
        }

        // The compose bar, where there is anything to type into it.
        var bottom = edge
        let hasBar = s.showTyping && plan.content.hasSent
        tree.bar.isHidden = !hasBar
        if hasBar {
            let barH = f * 2.1
            tree.bar.frame = CGRect(x: margin, y: bottom, width: size.width - 2 * margin, height: barH)
            tree.bar.cornerRadius = barH / 2
            tree.bar.borderWidth = max(1, f * 0.06)
            tree.bar.borderColor = palette.quiet.cgColor
            let send = barH * 0.72
            tree.barSend.frame = CGRect(x: tree.bar.bounds.width - send - (barH - send) / 2, y: (barH - send) / 2, width: send, height: send)
            tree.barSend.cornerRadius = send / 2
            tree.barSend.backgroundColor = MessageLook.palette(style: s.style, dark: s.dark, sent: true).bubble.cgColor
            let textH = ceil(MessageLook.lineHeight(font))
            style(tree.barText, text: "", font: font, size: f, colour: palette.text, scale: contents)
            tree.barText.alignmentMode = .left
            tree.barText.frame = CGRect(x: padX, y: (barH - textH) / 2, width: tree.bar.bounds.width - padX - send - barH * 0.3, height: textH)
            bottom += barH + f * 0.8
        }
        tree.thread.frame = CGRect(x: 0, y: bottom, width: size.width, height: max(0, top - bottom))

        // Each message at this size.
        let attributes: [NSAttributedString.Key: Any] = [.font: font as NSFont]
        let infinite = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let singleH = max(ceil(MessageLook.lineHeight(font)) + 2 * padY, f * 2)
        let sizes = plan.content.messages.map { m -> Size in
            let text = NSAttributedString(string: m.text, attributes: attributes)
            let free = text.boundingRect(with: infinite, options: [.usesLineFragmentOrigin, .usesFontLeading])
            let textW = min(ceil(free.width) + 2, maxBubble - 2 * padX)
            let wrapped = text.boundingRect(with: CGSize(width: textW, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
            let textH = ceil(wrapped.height)
            return Size(textW: textW, textH: textH, bubbleW: textW + 2 * padX, bubbleH: max(textH + 2 * padY, f * 2))
        }
        tree.metrics = Metrics(size: size, fontSize: f, padX: padX, margin: margin, dotsW: f * 3.1, dotsH: singleH, messages: sizes)
        for (i, bubble) in tree.bubbles.enumerated() where sizes.indices.contains(i) {
            style(bubble.text, text: plan.content.messages[i].text, font: font, size: f, colour: palette.text, scale: contents)
            bubble.text.alignmentMode = .left
        }
        _ = paint(at: lastPosition)
    }

    private func style(_ layer: QuietText, text: String, font: CTFont, size: CGFloat, colour: RGB, scale: CGFloat) {
        layer.string = text
        layer.font = font
        layer.fontSize = size
        layer.foregroundColor = colour.cgColor
        layer.contentsScale = scale
    }

    // MARK: Painting

    private func render(_ state: ConversationCuePlan.State, plan: ConversationCuePlan, in tree: Tree) {
        guard let m = tree.metrics else { return }
        let s = plan.content.settings
        let f = m.fontSize
        let thread = tree.thread.bounds

        for b in tree.bubbles {
            b.shape.isHidden = true
            b.text.isHidden = true
            b.dots.forEach { $0.isHidden = true }
        }

        var cursor: CGFloat = 0
        for item in state.items.reversed() where tree.bubbles.indices.contains(item.index) {
            let bubble = tree.bubbles[item.index]
            let full = m.messages[item.index]
            var w = full.bubbleW, h = full.bubbleH
            var textAlpha: Float = 1, dotsAlpha: Float = 0, alpha: Float = 1
            var room: CGFloat = 1
            var pulse = 0.0
            switch item.phase {
            case .settled:
                break
            case .typing(let t):
                let open = CGFloat(StageRunner.ease(min(1, t / ConversationCuePlan.dotsOpenFrames)))
                w = m.dotsW
                h = m.dotsH * open
                room = open
                alpha = Float(open)
                textAlpha = 0
                dotsAlpha = Float(open)
                pulse = t
            case .arriving(let g, let fromDots):
                let e = CGFloat(1 - pow(1 - g, 3))
                if fromDots {
                    w = m.dotsW + (full.bubbleW - m.dotsW) * e
                    h = m.dotsH + (full.bubbleH - m.dotsH) * e
                    dotsAlpha = Float(max(0, 1 - g * 3))
                } else {
                    w = full.bubbleW * (0.5 + 0.5 * e)
                    h = full.bubbleH * e
                    room = e
                    alpha = Float(e)
                }
                textAlpha = Float(max(0, (g - 0.35) / 0.65))
            }

            let sent = item.side == .sent
            let palette = MessageLook.palette(style: s.style, dark: s.dark, sent: sent)
            let x = sent ? thread.width - m.margin - w : m.margin
            let frame = CGRect(x: x, y: cursor, width: w, height: h)
            bubble.shape.frame = frame
            bubble.shape.path = MessageLook.bubblePath(CGRect(origin: .zero, size: frame.size), style: s.style, sent: sent, fontSize: f, tail: s.style == .greenRectangles ? !item.joinsPrevious : item.hasTail)
            bubble.shape.fillColor = palette.bubble.cgColor
            bubble.shape.opacity = alpha
            bubble.shape.isHidden = false

            bubble.text.frame = CGRect(x: x + m.padX, y: cursor + (h - full.textH) / 2, width: full.textW, height: full.textH)
            bubble.text.opacity = textAlpha
            bubble.text.isHidden = textAlpha <= 0

            if dotsAlpha > 0 {
                let d = f * 0.42
                for (i, dot) in bubble.dots.enumerated() {
                    let cx = x + w / 2 + (CGFloat(i) - 1) * d * 1.55
                    dot.frame = CGRect(x: cx - d / 2, y: cursor + (h - d) / 2, width: d, height: d)
                    dot.cornerRadius = d / 2
                    dot.backgroundColor = palette.quiet.cgColor
                    let wave = 0.5 + 0.5 * sin(2 * .pi * (pulse / 14 - Double(i) * 0.18))
                    dot.opacity = dotsAlpha * Float(0.3 + 0.7 * wave)
                    dot.isHidden = false
                }
            }

            let gap = (item.joinsPrevious ? 0.14 : 0.55) * f
            cursor += h + gap * room
        }

        let typed = state.composing ?? ""
        tree.barText.string = typed
        tree.barSend.isHidden = typed.isEmpty
    }
}
