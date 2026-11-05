import AppKit
import ProspectCore
import ProspectStage

// MARK: - Header

/// GO. Brass, and the biggest thing in the window. It never takes keyboard
/// focus, so Space can't press it as well as firing through the show keys.
final class GoButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = "GO"
        refusesFirstResponder = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        if isEnabled {
            (isHighlighted ? Desk.rgb(0xD6, 0xB0, 0x58) : Desk.brass).setFill()
            path.fill()
        } else {
            Desk.line.setStroke()
            path.stroke()
        }
        let text = NSAttributedString(string: "GO", attributes: [
            .font: Desk.sans(14, .semibold),
            .foregroundColor: isEnabled ? Desk.rgb(0x15, 0x12, 0x0B) : Desk.dim,
            .kern: 2.2,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2 + 1.1, y: (bounds.height - size.height) / 2))
    }
}

/// Show or edit: two segments in the desk's own colours, with whichever is
/// on in brass. Clicked, never keyed: it doesn't take the keyboard, so Space
/// can't flip it.
final class ModeSwitch: NSControl {
    var isEditing = false {
        didSet { if isEditing != oldValue { needsDisplay = true } }
    }

    private static let labels = ["SHOW", "EDIT"]
    private static let font = Desk.sans(10.5, .semibold)

    override init(frame: NSRect) {
        super.init(frame: frame)
        refusesFirstResponder = true
        focusRingType = .none
        toolTip = "Show mode locks the cue sheet; edit mode unlocks it"
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Mode")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 104, height: 22) }
    override var fittingSize: NSSize { intrinsicContentSize }

    override func mouseDown(with event: NSEvent) {
        let editing = convert(event.locationInWindow, from: nil).x >= bounds.midX
        guard editing != isEditing else { return }
        isEditing = editing
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outline = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        Desk.sunk.setFill()
        outline.fill()
        Desk.line.setStroke()
        outline.stroke()

        let half = box.width / 2
        let selected = NSRect(x: box.minX + (isEditing ? half : 0), y: box.minY, width: half, height: box.height).insetBy(dx: 2, dy: 2)
        Desk.brass.setFill()
        NSBezierPath(roundedRect: selected, xRadius: 3, yRadius: 3).fill()

        for (i, label) in Self.labels.enumerated() {
            let on = (i == 1) == isEditing
            let colour = on ? Desk.rgb(0x15, 0x12, 0x0B) : Desk.dim
            let text = NSAttributedString(string: label, attributes: [.font: Self.font, .foregroundColor: colour, .kern: 0.8])
            let size = text.size()
            text.draw(at: NSPoint(x: box.minX + CGFloat(i) * half + (half - size.width) / 2 + 0.4, y: (bounds.height - size.height) / 2))
        }
    }
}

final class HeaderView: PanelView {
    let wordmark = Desk.label("Prospect", font: Desk.mono(14), colour: Desk.text)
    /// Show or edit, chosen here or from the Show menu. Never by a key: a
    /// key that unlocked the sheet mid-performance would be a liability.
    let mode = ModeSwitch(frame: .zero)
    /// Edit mode only: a new cue of any kind, after the one standing by.
    let addCue = NSPopUpButton(frame: .zero, pullsDown: true)
    let lampDot = PanelView(radius: 3.5)
    let lamp = Desk.label("", font: Desk.sans(12.5), colour: Desk.dim)
    let openProjector = NSButton(title: "Open Projector", target: nil, action: nil)
    let separator = PanelView(fill: Desk.line)
    let go = GoButton(frame: .zero)

    init() {
        super.init(fill: Desk.raised)
        wordmark.attributedStringValue = Self.wordmarkText(Self.name.map { ($0, 1) })
        wordmark.setAccessibilityLabel(Self.name)
        openProjector.bezelStyle = .rounded
        openProjector.refusesFirstResponder = true
        // A pull-down's first item is its title; the kinds follow.
        addCue.addItems(withTitles: ["Add Cue"] + Cue.Kind.allCases.map(\.heading))
        addCue.controlSize = .small
        addCue.font = Desk.sans(11.5)
        addCue.refusesFirstResponder = true
        addCue.toolTip = "Adds a cue after the one standing by"
        for view in [wordmark, mode, addCue, lampDot, lamp, openProjector, separator, go] as [NSView] { addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(mode editing: Bool, lamp text: String, live: Bool, warn: Bool, projectorOpen: Bool, goEnabled: Bool, goTip: String) {
        mode.isEditing = editing
        addCue.isHidden = !editing
        lamp.stringValue = text
        lamp.textColor = live ? Desk.live : (warn ? Desk.brass : Desk.dim)
        lampDot.layer?.backgroundColor = (live ? Desk.live : (warn ? Desk.brass : Desk.lineBright)).cgColor
        lampDot.layer?.shadowColor = Desk.live.cgColor
        lampDot.layer?.shadowOpacity = live ? 0.9 : 0
        lampDot.layer?.shadowRadius = 3.5
        lampDot.layer?.shadowOffset = .zero
        openProjector.isHidden = projectorOpen
        go.isEnabled = goEnabled
        go.toolTip = goTip
        go.needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        func centre(_ v: NSView, x: CGFloat, width: CGFloat? = nil) {
            let size = v.fittingSize
            v.frame = NSRect(x: x, y: ((h - size.height) / 2).rounded(), width: width ?? size.width, height: size.height)
        }
        centre(wordmark, x: 16)
        centre(mode, x: wordmark.frame.maxX + 16)
        if !addCue.isHidden { centre(addCue, x: mode.frame.maxX + 12) }

        go.frame = NSRect(x: bounds.width - 16 - 104, y: (h - 36) / 2, width: 104, height: 36)
        separator.frame = NSRect(x: go.frame.minX - 15, y: (h - 26) / 2, width: 1, height: 26)
        var right = separator.frame.minX - 14
        if !openProjector.isHidden {
            let width = openProjector.fittingSize.width
            centre(openProjector, x: right - width)
            right = openProjector.frame.minX - 14
        }
        let lampWidth = lamp.fittingSize.width
        centre(lamp, x: right - lampWidth)
        lampDot.frame = NSRect(x: lamp.frame.minX - 14, y: (h - 7) / 2, width: 7, height: 7)
    }

    // MARK: The wordmark

    private static let name = "PROSPECT"
    /// Frames of ciphertext before any letter moves, and how long a frame is.
    private static let hold = 20
    private static let frameSeconds: TimeInterval = 0.05

    private var reveal: TravelPlan?
    private var revealFrame = 0
    private var revealRandom = SystemUnitRandom()
    private var revealTimer: Timer?

    /// Decrypts the wordmark the way a title cue decrypts on stage: a moment
    /// of ciphertext, then each letter cycling home, warming as it goes.
    /// Not at all under reduced motion.
    func decryptWordmark() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        startReveal(at: -Self.hold)
        let timer = Timer(timeInterval: Self.frameSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.showReveal(at: (self?.revealFrame ?? 0) + 1) }
        }
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
    }

    private func startReveal(at frame: Int) {
        revealTimer?.invalidate()
        revealTimer = nil
        // The key never shows, on stage or here. Its shifts, 5, 8, 1, 13, 13,
        // 0, 2, 2, 8, are mostly Fibonacci numbers, for anyone who looks.
        reveal = TravelPlan(text: Self.name, key: "FIBONACCI", wave: 3, random: &revealRandom)
        showReveal(at: frame)
    }

    /// Frames up to 0 are the ciphertext; from the plan's duration on, the
    /// name itself, and the reveal is over.
    private func showReveal(at frame: Int) {
        guard let plan = reveal else { return }
        revealFrame = frame
        wordmark.attributedStringValue = Self.wordmarkText(plan.frame(max(0, frame), random: &revealRandom).map { ($0.glyph, $0.progress) })
        if frame >= plan.duration {
            revealTimer?.invalidate()
            revealTimer = nil
            reveal = nil
        }
    }

    /// The glyphs in the wordmark's own case, each coloured by how far home
    /// it is: from the ciphertext's slate to the desk's text colour, eased as
    /// the stage's warming is.
    private static func wordmarkText(_ glyphs: [(glyph: Character, progress: Double)]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (glyph, letter) in zip(glyphs, name) {
            let p = min(max(glyph.progress, 0), 1), e = p * p * (3 - 2 * p)
            func mix(_ cold: UInt8, _ warm: Int) -> Int { Int((Double(cold) + (Double(warm) - Double(cold)) * e).rounded()) }
            let colour = Desk.rgb(mix(Palette.slate.r, 0xCF), mix(Palette.slate.g, 0xD4), mix(Palette.slate.b, 0xDE))
            let shown = letter.isLowercase ? String(glyph.glyph).lowercased() : String(glyph.glyph)
            text.append(NSAttributedString(string: shown, attributes: [.font: Desk.mono(14), .foregroundColor: colour, .kern: 1.4]))
        }
        return text
    }

    #if DEBUG
    /// The wordmark held on one frame of a fresh reveal, for snapshots.
    func holdWordmark(atFrame frame: Int) {
        startReveal(at: frame)
    }
    #endif
}
