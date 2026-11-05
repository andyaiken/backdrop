import AppKit

/// A box of several lines of text, for an anagram cue's paragraphs: dark,
/// monospaced, and scrolling once it is full.
final class ParagraphsView: NSScrollView {
    let text = HintTextView(frame: .zero)

    init() {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = true
        backgroundColor = Desk.sunk
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = Desk.lineBright.cgColor
        text.isRichText = false
        text.importsGraphics = false
        // Only whole edits go on the undo stack, not keystrokes.
        text.allowsUndo = false
        text.font = Desk.mono(12.5)
        text.textColor = Desk.text
        text.insertionPointColor = Desk.text
        text.backgroundColor = Desk.sunk
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.textContainerInset = NSSize(width: 4, height: 5)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        documentView = text
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        text.minSize = NSSize(width: contentSize.width, height: contentSize.height)
        text.frame.size.width = contentSize.width
    }
}

/// A text view that says what goes in it while it is empty, dim and italic,
/// as the editor's fields do.
final class HintTextView: NSTextView {
    var hint = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hint.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        NSAttributedString(string: hint, attributes: [
            .foregroundColor: Desk.dim.withAlphaComponent(0.7),
            .font: NSFontManager.shared.convert(Desk.sans(12.5), toHaveTrait: .italicFontMask),
        ]).draw(in: bounds.insetBy(dx: textContainerInset.width + padding, dy: textContainerInset.height))
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
