import AppKit

/// Go To: a cue number typed on flaps, then Return to stand that cue by.
/// G opens it, in either room, from the console or the projector window.
///
/// It sits over the console, inside its window, so the console stays the
/// key window and nothing else can take the keyboard meanwhile. While it is
/// open its flaps take every plain key; Space still fires GO, and closes it.
/// Escape, a click anywhere outside it, or the console losing focus closes
/// it with no change, and the keyboard goes back to the show keys.
final class GoToPanel: NSView {
    let field = FlapField()
    private let heading = GoToPanel.label("GO TO CUE", font: .systemFont(ofSize: 11, weight: .semibold), colour: Booth.brass, kern: 2)
    private let message = GoToPanel.label("", font: .systemFont(ofSize: 13), colour: Booth.amber)
    private let hints = GoToPanel.label("\u{21A9} make it next      esc close", font: .monospacedSystemFont(ofSize: 11.5, weight: .regular),
                                        colour: Booth.dim)

    static let padding: CGFloat = 20

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 24
            s.shadowColor = NSColor.black.withAlphaComponent(0.5)
            s.shadowOffset = NSSize(width: 0, height: -6)
            return s
        }()
        for view in [heading, field, message, hints] as [NSView] { addSubview(view) }
        field.onChange = { [weak self] _ in self?.show(message: nil) }
        applyColours()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private static func label(_ text: String, font: NSFont, colour: NSColor, kern: CGFloat = 0) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = colour
        if kern > 0 {
            field.attributedStringValue = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: colour, .kern: kern])
        }
        return field
    }

    /// The Booth's own colours in both rooms: the flaps are a departures
    /// board, dark whatever the Mac is.
    private func applyColours() {
        layer?.backgroundColor = Booth.raised.cgColor
        layer?.borderColor = Booth.line.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColours()
    }

    /// Under the flaps: why Return didn't stand a cue by. Nil clears it.
    func show(message text: String?) {
        message.stringValue = text ?? ""
        if let text {
            NSAccessibility.post(element: field, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        needsLayout = true
        superview?.needsLayout = true
    }

    /// The size it takes for what is typed so far.
    var fittingPanelSize: NSSize {
        let flaps = field.intrinsicContentSize
        // A few points' slack: a label's own measure can fall just short of
        // what it draws.
        let width = max(flaps.width, hints.intrinsicContentSize.width + 8, message.intrinsicContentSize.width + 8) + 2 * Self.padding
        let messageHeight: CGFloat = message.stringValue.isEmpty ? 0 : 26
        return NSSize(width: width, height: Self.padding + 16 + 12 + flaps.height + 14 + messageHeight + 16 + Self.padding)
    }

    override func layout() {
        super.layout()
        let p = Self.padding
        heading.frame = NSRect(x: p, y: p, width: bounds.width - 2 * p, height: 16)
        let flaps = field.intrinsicContentSize
        field.frame = NSRect(x: p, y: heading.frame.maxY + 12, width: flaps.width, height: flaps.height)
        var y = field.frame.maxY + 14
        message.isHidden = message.stringValue.isEmpty
        if !message.isHidden {
            message.frame = NSRect(x: p, y: y, width: bounds.width - 2 * p, height: 18)
            y += 26
        }
        hints.frame = NSRect(x: p, y: y, width: bounds.width - 2 * p, height: 16)
    }

    /// Clicks on it go nowhere else.
    override func mouseDown(with event: NSEvent) {}
}
