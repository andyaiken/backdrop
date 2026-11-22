import AppKit
import QuartzCore

/// Where a cue number is typed for Go To: each character on a flap, as on a
/// departures board, with a blinking cursor flap after them.
///
/// It is the one view in the console that takes the keyboard, and only
/// while Go To is open. It handles every plain key itself so none of them
/// beeps, and Space still fires GO from here.
final class FlapField: NSView {
    /// The characters typed, as typed.
    private(set) var text = "" {
        didSet {
            guard text != oldValue else { return }
            onChange(text)
            invalidateIntrinsicContentSize()
            needsDisplay = true
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    static let limit = 12
    static let flap = NSSize(width: 40, height: 52)
    static let spacing: CGFloat = 4

    /// Return: stand by the cue typed. True if one stood by, and Go To closes.
    var onCommit: (String) -> Bool = { _ in false }
    /// Space: Go To closes, then GO.
    var onGo: () -> Void = {}
    /// Escape: Go To closes with no change.
    var onCancel: () -> Void = {}
    /// The text changed, so a message about the last Return goes.
    var onChange: (String) -> Void = { _ in }

    private var cursorShown = true
    private var blink: Timer?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Wide enough for what is typed and the cursor, and no narrower than
    /// four flaps, so the panel doesn't jump about as the first are typed.
    override var intrinsicContentSize: NSSize {
        let count = CGFloat(max(4, min(text.count + 1, Self.limit)))
        return NSSize(width: count * Self.flap.width + (count - 1) * Self.spacing, height: Self.flap.height)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        blink?.invalidate()
        blink = nil
        cursorShown = true
        // A cursor that blinks is motion; under Reduce Motion it holds still.
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        blink = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cursorShown.toggle()
                self.needsDisplay = true
            }
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        // Command-key combinations belong to the menus.
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            super.keyDown(with: event)
            return
        }
        // Holding a key fires nothing more than once, and types nothing more.
        if event.isARepeat { return }
        switch Int(event.keyCode) {
        case 49: onGo()                                     // space
        case 36, 76: _ = onCommit(text)                      // Return, Enter
        case 53: onCancel()                                  // Escape
        case 51, 117: if !text.isEmpty { text.removeLast() } // Delete, forward delete
        case 123, 124, 125, 126, 115, 116, 119, 121: break   // arrows, Home, Page Up, End, Page Down
        default:
            guard let typed = event.characters else { return }
            for c in typed where Self.takes(c) && text.count < Self.limit {
                text.append(c)
            }
        }
    }

    /// A printable character, but not a space.
    private static func takes(_ c: Character) -> Bool {
        guard !c.isWhitespace, !c.isNewline else { return false }
        return c.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: 32, weight: .medium)
        let characters = Array(text.uppercased())
        var x: CGFloat = 0
        for i in 0..<(characters.count + (characters.count < Self.limit ? 1 : 0)) {
            let box = NSRect(x: x, y: 0, width: Self.flap.width, height: Self.flap.height)
            x += Self.flap.width + Self.spacing
            let isCursor = i == characters.count
            if isCursor && !cursorShown { continue }
            drawFlap(in: box, faint: isCursor)
            guard !isCursor else { continue }
            let string = NSAttributedString(string: String(characters[i]),
                                            attributes: [.font: font, .foregroundColor: Booth.brass])
            let size = string.size()
            string.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
        }
    }

    /// A flap: a lighter top half and a darker bottom, split by a line.
    private func drawFlap(in box: NSRect, faint: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let shape = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        shape.addClip()
        (faint ? Booth.panel : Booth.raised).setFill()
        NSRect(x: box.minX, y: box.minY, width: box.width, height: box.height / 2).fill()
        Booth.panel.blended(withFraction: 0.35, of: .black)?.setFill()
        NSRect(x: box.minX, y: box.midY, width: box.width, height: box.height / 2).fill()
        Booth.background.setFill()
        NSRect(x: box.minX, y: box.midY - 0.5, width: box.width, height: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        if faint {
            // The cursor: an outline, where the next character goes.
            Booth.brass.withAlphaComponent(0.7).setStroke()
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textField }
    override func accessibilityLabel() -> String? { "Go to cue" }
    override func accessibilityValue() -> Any? { text }
}
