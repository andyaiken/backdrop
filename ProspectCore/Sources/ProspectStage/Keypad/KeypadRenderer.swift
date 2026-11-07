import AppKit
import ProspectCore
import QuartzCore

/// Keypad cues: a row of empty boxes and a phone-style numpad beneath. The
/// numbers are keyed in a stage on each GO; each key lights as it is pressed
/// and its digit lands in the next free box, and a delete empties the last. A
/// stage that says GOOD or BAD presses OK and flashes the boxes green or red.
///
/// Everything is drawn from the state at the clock's frame (`KeypadCuePlan`),
/// so every surface agrees.
@MainActor
public final class KeypadRenderer: CueRenderer, WaitsForGO {
    public let isInstant = false

    private var plan: KeypadCuePlan?
    private var timeline = GoTimeline(parts: [0])
    private var lastFrame: Int?
    private var textScale = 100
    private var trees: [ObjectIdentifier: Tree] = [:]

    static let green = RGB(0x3C, 0xC8, 0x6E)
    static let red = RGB(0xE0, 0x45, 0x45)
    /// The keys, row by row: * 0 # beneath them, and delete and OK down a fourth column.
    static let layout: [[KeypadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.digit("*"), .digit("0"), .digit("#")],
    ]
    /// The fourth column: delete beside the top two rows, OK beside the bottom two.
    static let side: [(key: KeypadKey, rows: ClosedRange<Int>)] = [(.delete, 0...1), (.ok, 2...3)]

    final class QuietText: CATextLayer {
        override func action(forKey event: String) -> (any CAAction)? { nil }
    }

    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        var boxes: [StillLayer] = []
        var digits: [QuietText] = []
        var keys: [(key: KeypadKey, cap: StillLayer, label: QuietText)] = []
        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
        }

        /// Takes every box, digit, key and label off the surface.
        func removeAll() {
            boxes.forEach { $0.removeFromSuperlayer() }
            digits.forEach { $0.removeFromSuperlayer() }
            keys.forEach { $0.cap.removeFromSuperlayer(); $0.label.removeFromSuperlayer() }
            boxes = []
            digits = []
            keys = []
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
        lastFrame = nil
        guard let tree = trees[ObjectIdentifier(surface)] else { return }
        tree.removeAll()
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .keypad(let content) = cue.content else { return }
        let plan = KeypadCuePlan(content)
        self.plan = plan
        timeline = GoTimeline(parts: plan.parts)
        textScale = show.textScale
        lastFrame = nil
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
        lastFrame = f
        guard let plan else { return true }
        paint(plan.state(at: f, timeline: timeline))
        return timeline.isFinished(at: f)
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = trees[ObjectIdentifier(surface)] else { return }
        let size = surface.inset.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        tree.root.frame = CGRect(origin: .zero, size: size)
        guard let plan else { return }
        let scale = CGFloat(textScale) / 100
        let n = plan.content.boxCount
        let contents = max(surface.contentsScale, 1)

        // Keys first, as they set the width the boxes sit within.
        let keyH = size.height * 0.09 * min(scale, 1.2)
        let keyW = keyH * 1.7
        let gap = keyH * 0.22
        let padH = 4 * keyH + 3 * gap
        let padW = 4 * keyW + 3 * gap

        let gapBox = size.width * 0.012
        let boxSide = min(size.height * 0.15 * min(scale, 1.2), (size.width * 0.84 - CGFloat(n - 1) * gapBox) / CGFloat(n))
        let rowW = CGFloat(n) * boxSide + CGFloat(n - 1) * gapBox
        let between = size.height * 0.07
        let total = boxSide + between + padH
        let top = (size.height + total) / 2   // Layers count up from the bottom.

        for (i, box) in tree.boxes.enumerated() {
            let x = (size.width - rowW) / 2 + CGFloat(i) * (boxSide + gapBox)
            box.frame = CGRect(x: x.rounded(), y: (top - boxSide).rounded(), width: boxSide.rounded(), height: boxSide.rounded())
            box.cornerRadius = boxSide * 0.14
            box.borderWidth = max(2, boxSide * 0.04)
            place(tree.digits[i], in: box.frame, fontSize: boxSide * 0.6, scale: contents)
        }
        let padTop = top - boxSide - between
        for entry in tree.keys {
            guard let (rows, col) = position(of: entry.key) else { continue }
            let x = (size.width - padW) / 2 + CGFloat(col) * (keyW + gap)
            let span = CGFloat(rows.count)
            let h = span * keyH + (span - 1) * gap
            let y = padTop - h - CGFloat(rows.lowerBound) * (keyH + gap)
            entry.cap.frame = CGRect(x: x.rounded(), y: y.rounded(), width: keyW.rounded(), height: h.rounded())
            entry.cap.cornerRadius = keyH * 0.28
            place(entry.label, in: entry.cap.frame, fontSize: keyH * 0.5, scale: contents)
        }
        paint(plan.state(at: lastFrame ?? -1_000_000, timeline: timeline))
    }

    // MARK: WaitsForGO

    public func isWaiting(at f: Int) -> Bool { plan != nil && timeline.isWaiting(at: f) }
    public func carryOn(at f: Int) { timeline.carryOn(at: f) }
    public func carryOnToEnd() { timeline.carryOnToEnd() }

    /// GO point k lets go part k + 1; part 0 runs from the cue's start.
    public func goTo(_ point: Int, at f: Int) { timeline.jump(toPart: point + 1, at: f) }

    // MARK: Layers

    /// The rows a key covers and its column.
    private func position(of key: KeypadKey) -> (ClosedRange<Int>, Int)? {
        for (r, row) in Self.layout.enumerated() {
            if let c = row.firstIndex(of: key) { return (r...r, c) }
        }
        return Self.side.first { $0.key == key }.map { ($0.rows, 3) }
    }

    private func build(_ tree: Tree) {
        tree.removeAll()
        guard let plan else { return }
        for _ in 0..<plan.content.boxCount {
            let box = StillLayer()
            box.borderColor = Palette.slate.cgColor
            let digit = textLayer()
            digit.foregroundColor = Palette.bone.cgColor
            box.masksToBounds = false
            tree.root.addSublayer(box)
            tree.root.addSublayer(digit)
            tree.boxes.append(box)
            tree.digits.append(digit)
        }
        for key in Self.layout.flatMap({ $0 }) + Self.side.map(\.key) {
            let cap = StillLayer()
            cap.borderWidth = 2
            let label = textLayer()
            switch key {
            case .digit(let c): label.string = String(c)
            case .delete: label.string = "\u{232B}"
            case .ok: label.string = "OK"
            }
            tree.root.addSublayer(cap)
            tree.root.addSublayer(label)
            tree.keys.append((key, cap, label))
        }
    }

    private func textLayer() -> QuietText {
        let layer = QuietText()
        layer.alignmentMode = .center
        layer.truncationMode = .none
        return layer
    }

    private func place(_ layer: QuietText, in frame: CGRect, fontSize: CGFloat, scale: CGFloat) {
        let font = StageFont.title(size: fontSize)
        layer.font = font
        layer.fontSize = fontSize
        layer.contentsScale = scale
        let h = ceil(fontSize * 1.25)
        layer.frame = CGRect(x: frame.minX, y: (frame.midY - h / 2).rounded(), width: frame.width, height: h)
    }

    private func paint(_ state: KeypadCuePlan.State) {
        for tree in trees.values {
            for (i, box) in tree.boxes.enumerated() {
                let filled = i < state.entry.count
                tree.digits[i].string = filled ? String(state.entry[i]) : ""
                let tint: RGB? = state.lit ? (state.verdict == .bad ? Self.red : Self.green) : nil
                box.borderColor = (tint ?? (filled ? Palette.bone : Palette.slate)).cgColor
                box.backgroundColor = tint.map { $0.cgColor(alpha: 0.35) } ?? RGB.black.cgColor(alpha: 0)
                tree.digits[i].foregroundColor = (tint ?? Palette.bone).cgColor
            }
            for entry in tree.keys {
                let down = state.pressed == entry.key
                entry.cap.backgroundColor = down ? Palette.brass.cgColor : Palette.slate.cgColor(alpha: 0.18)
                entry.cap.borderColor = (down ? Palette.brass : Palette.slate).cgColor
                entry.label.foregroundColor = (down ? RGB.black : Palette.bone).cgColor
            }
        }
    }
}
