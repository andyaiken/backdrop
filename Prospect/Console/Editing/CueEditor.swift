import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// Edit mode's cue editor. It edits the cue standing by: click a cue in the
/// list to edit it. Every change goes through the show controller as one
/// undoable edit.
final class CueEditorPanel: PanelView, NSTextFieldDelegate, NSTextViewDelegate {
    weak var controller: ShowController?
    var importMedia: (URL, UUID, ShowDocument.MediaSlot?) -> Void = { _, _, _ in }
    var chooseMedia: (UUID, ShowDocument.MediaSlot?) -> Void = { _, _ in }
    /// Opens a morph's points, on one of its stages.
    var editPoints: (UUID, Int) -> Void = { _, _ in }
    /// Opens a map's route.
    var editRoute: (UUID) -> Void = { _ in }
    /// Where a file in the show is on disk, for the morph's thumbnails.
    var mediaURL: (String) -> URL? = { _ in nil } {
        didSet { morphPictures.thumbnails.mediaURL = mediaURL }
    }
    /// Return or Escape in a field gives the keyboard back to the show keys.
    var finishedEditing: () -> Void = {}

    private(set) var cue: Cue?
    /// The GO of the cue that stands by, if one does: its cue point is the
    /// one the Cue point field edits.
    private var goPoint: ShowController.StandingByGoPoint?

    private let heading = Desk.label("", font: Desk.sans(12.5, .semibold), colour: Desk.text)
    private let empty = Desk.label("Nothing is standing by. Add a cue with Add Cue at the top, or click one in the list to edit it.",
                                   font: Desk.sans(12.5), colour: Desk.dim, wraps: true)

    private let numberLabel = Desk.label("Number", font: Desk.sans(12.5), colour: Desk.dim)
    private let number = CueEditorPanel.field(mono: true)
    private let lineLabel = Desk.label("Cue point", font: Desk.sans(12.5), colour: Desk.dim)
    private let line = CueEditorPanel.field(placeholder: "The line or action to wait for")
    private let continueLabel = Desk.label("Continue", font: Desk.sans(12.5), colour: Desk.dim)
    private let continueMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let continueSeconds = CueEditorPanel.field(mono: true)
    private let secondsLabel = Desk.label("seconds", font: Desk.sans(12.5), colour: Desk.dim)

    private let textLabel = Desk.label("", font: Desk.sans(12.5), colour: Desk.dim)
    private let text = CueEditorPanel.field(mono: true)
    private let subLabel = Desk.label("", font: Desk.sans(12.5), colour: Desk.dim)
    private let sub = CueEditorPanel.field(mono: true)
    private let keyLabel = Desk.label("Key", font: Desk.sans(12.5), colour: Desk.dim)
    private let key = CueEditorPanel.field(mono: true)
    /// An anagram cue's anagrams, a paragraph each.
    private let anagramsLabel = Desk.label("Anagrams", font: Desk.sans(12.5), colour: Desk.dim)
    private let anagrams = ParagraphsView()
    /// The anagram cue the text box is being edited for, so a change lands on
    /// it even if another cue stands by before editing ends.
    private var anagramsCue: UUID?
    /// Escape puts the text back, and nothing is saved as editing ends.
    private var revertingAnagrams = false

    private let mediaLabel = Desk.label("", font: Desk.sans(12.5), colour: Desk.dim)
    private let well = MediaWell()
    private let choose = CueEditorPanel.button("Choose\u{2026}")
    private let removeMedia = CueEditorPanel.button("Remove")
    // A morph's pictures in turn, and the stages between them.
    private let picturesLabel = Desk.label("Pictures", font: Desk.sans(12.5), colour: Desk.dim)
    private let morphPictures = MorphPicturesState()
    private lazy var picturesView = NSHostingView(rootView: MorphPicturesView(state: morphPictures))
    // A map's route.
    private let routeLabel = Desk.label("Route", font: Desk.sans(12.5), colour: Desk.dim)
    private let routeSummary = Desk.label("", font: Desk.sans(12.5), colour: Desk.text)
    private let editRouteButton = CueEditorPanel.button("Edit Route\u{2026}")
    private let atEndLabel = Desk.label("At the end", font: Desk.sans(12.5), colour: Desk.dim)
    private let atEnd = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colourLabel = Desk.label("Colour", font: Desk.sans(12.5), colour: Desk.dim)
    private let colour = NSColorWell(style: .default)

    init() {
        super.init(border: Desk.line, radius: 4)
        for field in [number, line, text, sub, key, continueSeconds] { field.delegate = self }
        // Tab goes down what the cue shows, then where it comes in the book,
        // and round again. AppKit skips hidden fields, so one chain serves
        // every kind of cue.
        let order: [NSView] = [text, sub, key, anagrams.text, number, line, continueSeconds]
        for (field, next) in zip(order, order.dropFirst() + [order[0]]) { field.nextKeyView = next }
        anagrams.text.delegate = self
        anagrams.text.hint = "The phrase on the first line, the answer on the last, and any working between. A blank line starts another anagram, solved after this one. One line alone is solved already; ~ before a phrase leaves it unsolved."
        anagrams.text.toolTip = "Each anagram is a paragraph: its phrase, then any working, a step to a line, then its answer. Working may be partial or wrong; the letters a step doesn\u{2019}t use dim beneath it. A paragraph of one line stands solved from the start, and one whose phrase starts with ~ stands unsolved; the cue skips both. Return starts a new line; Tab moves on, and Escape puts it back as it was."

        for (button, action) in [(choose, #selector(choosePressed)), (removeMedia, #selector(removePressed)),
                                 (editRouteButton, #selector(editRoutePressed))] {
            button.target = self
            button.action = action
        }
        continueMode.addItems(withTitles: ["When cued", "After", "When finished, after"])
        // When finished is offered only to a cue that takes time.
        continueMode.autoenablesItems = false
        continueMode.target = self
        continueMode.action = #selector(continueChosen)
        continueMode.refusesFirstResponder = true
        continueMode.toolTip = "When the show moves on to the next cue: on GO, a number of seconds after this cue fires, or a number of seconds after it finishes"
        continueSeconds.alignment = .right
        atEnd.addItems(withTitles: ["Hold the last frame", "Cut to black", "Loop"])
        atEnd.target = self
        atEnd.action = #selector(atEndChosen)
        atEnd.refusesFirstResponder = true
        colour.target = self
        colour.action = #selector(colourChosen)
        well.onDrop = { [weak self] url in
            guard let self, let cue else { return }
            importMedia(url, cue.id, nil)
        }
        wireMorphPictures()
        let views: [NSView] = [heading, empty, numberLabel, number, lineLabel, line,
                               continueLabel, continueMode, continueSeconds, secondsLabel,
                               textLabel, text, subLabel, sub, keyLabel, key, anagramsLabel, anagrams, mediaLabel, well, choose, removeMedia,
                               picturesLabel, picturesView, routeLabel, routeSummary, editRouteButton,
                               atEndLabel, atEnd, colourLabel, colour]
        views.forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Dim and italic, plainly a hint, so an empty field never passes for a
    /// filled one.
    private static func hint(_ field: NSTextField, _ text: String) {
        field.placeholderAttributedString = NSAttributedString(string: text, attributes: [
            .foregroundColor: Desk.dim.withAlphaComponent(0.7),
            .font: NSFontManager.shared.convert(field.font ?? Desk.sans(12.5), toHaveTrait: .italicFontMask),
        ])
    }

    private static func field(mono: Bool = false, placeholder: String? = nil) -> NSTextField {
        let field = NSTextField(string: "")
        field.font = mono ? Desk.mono(12.5) : Desk.sans(12.5)
        field.bezelStyle = .roundedBezel
        if let placeholder { hint(field, placeholder) }
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        // Only whole edits go on the undo stack, not keystrokes.
        field.cell?.allowsUndo = false
        return field
    }

    private static func button(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = Desk.sans(11.5)
        button.refusesFirstResponder = true
        return button
    }

    // MARK: Showing a cue

    func update(cue: Cue?, goPoint: ShowController.StandingByGoPoint? = nil) {
        self.cue = cue
        self.goPoint = cue != nil && goPoint?.cue.id == cue?.id ? goPoint : nil
        let kind = cue?.kind
        empty.isHidden = cue != nil
        for view in [numberLabel, number, lineLabel, line, continueLabel, continueMode] as [NSView] {
            view.isHidden = cue == nil
        }
        textLabel.isHidden = kind == nil || kind == .anagram
        text.isHidden = textLabel.isHidden
        anagramsLabel.isHidden = kind != .anagram
        anagrams.isHidden = anagramsLabel.isHidden
        subLabel.isHidden = kind == nil || kind == .blank || kind == .image || kind == .anagram || kind == .morph || kind == .map
        sub.isHidden = subLabel.isHidden
        keyLabel.isHidden = kind != .title
        key.isHidden = keyLabel.isHidden
        for view in [mediaLabel, well, choose, removeMedia] as [NSView] { view.isHidden = ![.image, .video, .map].contains(kind) }
        for view in [routeLabel, routeSummary, editRouteButton] as [NSView] { view.isHidden = kind != .map }
        picturesLabel.isHidden = kind != .morph
        picturesView.isHidden = picturesLabel.isHidden
        atEndLabel.isHidden = kind != .video
        atEnd.isHidden = atEndLabel.isHidden
        colourLabel.isHidden = kind != .blank
        colour.isHidden = colourLabel.isHidden
        // Seconds after firing, or after finishing; none for when cued.
        continueSeconds.isHidden = !(cue?.continueMode.continues ?? false)
        secondsLabel.isHidden = continueSeconds.isHidden
        guard let cue else {
            heading.stringValue = "Cue"
            needsLayout = true
            return
        }

        heading.stringValue = "Cue \(cue.number.isEmpty ? "(no number)" : cue.number) \u{2014} \(cue.kind.name)"
            + (self.goPoint.map { " \u{00B7} GO \($0.number) of \($0.count): \($0.point.text)" } ?? "")
        set(number, cue.number)
        // With one of its GOs standing by, the cue point is that GO's.
        if let goPoint = self.goPoint {
            lineLabel.stringValue = "GO \(goPoint.number)"
            if line.currentEditor() == nil { Self.hint(line, "The line or action GO \(goPoint.number) waits for") }
            set(line, goPoint.point.cuePoint)
        } else {
            lineLabel.stringValue = "Cue point"
            if line.currentEditor() == nil { Self.hint(line, "The line or action to wait for") }
            set(line, cue.line)
        }
        var continuesWhenFinished = false
        switch cue.continueMode {
        case .whenCued: continueMode.selectItem(at: 0)
        case .after(let ms):
            continueMode.selectItem(at: 1)
            set(continueSeconds, ContinueMode.seconds(ms))
        case .whenFinished(let ms):
            continueMode.selectItem(at: 2)
            set(continueSeconds, ContinueMode.seconds(ms))
            continuesWhenFinished = true
        }
        continueMode.item(at: 2)?.isEnabled = cue.finishes || continuesWhenFinished
        set(text, cue.text)
        set(sub, cue.sub)
        switch cue.content {
        case .title(let c):
            textLabel.stringValue = "Text"
            subLabel.stringValue = "Subtext"
            set(key, c.key)
        case .anagram(let c):
            if anagrams.text.window?.firstResponder !== anagrams.text {
                let paragraphs = Anagram.paragraphs(c.anagrams)
                if anagrams.text.string != paragraphs { anagrams.text.string = paragraphs }
            }
        case .image(let c):
            textLabel.stringValue = "Label"
            mediaLabel.stringValue = "Picture"
            well.show(path: c.src, kind: .image, empty: "No picture \u{2014} drop one here")
            removeMedia.isEnabled = !c.src.isEmpty
        case .morph(let c):
            textLabel.stringValue = "Label"
            if morphPictures.pictures != c.pictures { morphPictures.pictures = c.pictures }
            let morphMs = (controller?.show.settings ?? ShowSettings()).resolved(c.overrides).morphMs
            if morphPictures.cueMorphMs != morphMs { morphPictures.cueMorphMs = morphMs }
        case .map(let c):
            textLabel.stringValue = "Header"
            mediaLabel.stringValue = "Map"
            well.show(path: c.src, kind: .map, empty: "No map \u{2014} drop one here")
            removeMedia.isEnabled = !c.src.isEmpty
            let stops = c.stops.count - 1, jumps = c.stops.dropFirst().filter { c.stop(at: $0).arrival == .jump }.count
            routeSummary.stringValue = c.route.isEmpty ? "None yet: set it in the route window"
                : stops < 1 ? "A start, and no stops yet"
                : "\(stops) stop\(stops == 1 ? "" : "s")" + (jumps > 0 ? ", \(jumps) by a jump" : "")
                    + (c.reference == nil ? "" : ", with coordinates")
        case .video(let c):
            textLabel.stringValue = "Label"
            subLabel.stringValue = "Caption"
            mediaLabel.stringValue = "Clip"
            well.show(path: c.src, kind: .video, empty: "No clip \u{2014} drop one here")
            removeMedia.isEnabled = !c.src.isEmpty
            atEnd.selectItem(at: VideoEnd.allCases.firstIndex(of: c.atEnd) ?? 0)
        case .blank(let c):
            textLabel.stringValue = "Label"
            colour.color = NSColor(srgbRed: CGFloat(c.colour.r) / 255, green: CGFloat(c.colour.g) / 255, blue: CGFloat(c.colour.b) / 255, alpha: 1)
        }
        needsLayout = true
    }

    /// Doesn't touch a field while someone is typing in it.
    private func set(_ field: NSTextField, _ value: String) {
        if field.currentEditor() == nil, field.stringValue != value { field.stringValue = value }
    }

    // MARK: Editing

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let cue, let controller else { return }
        let value = field.stringValue
        switch field {
        case number:
            controller.updateCue(cue.id, "Change Cue Number") { $0.number = value.trimmingCharacters(in: .whitespaces) }
        case line:
            if let step = goPoint?.number.advanced(by: -1) {
                let defaults = controller.show.settings
                controller.updateCue(cue.id, "Change GO Cue Point") { $0.setCuePoint(value, ofGoPoint: step, defaults: defaults) }
            } else {
                controller.updateCue(cue.id, "Change Cue Point") { $0.line = value }
            }
        case text:
            controller.updateCue(cue.id, cue.kind == .title ? "Change Text" : "Change Label") { $0.text = value }
        case sub:
            let name = switch cue.kind {
            case .title: "Change Subtext"
            default: "Change Caption"
            }
            controller.updateCue(cue.id, name) { $0.sub = value }
        case key:
            controller.updateCue(cue.id, "Change Key") { cue in
                if case .title(var c) = cue.content { c.key = value; cue.content = .title(c) }
            }
        case continueSeconds:
            // To a tenth of a second, up to an hour. Anything unreadable is
            // put back as it was.
            guard let seconds = Double(value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)),
                  seconds.isFinite else {
                update(cue: cue)
                return
            }
            let ms = min(max(0, Int((seconds * 10).rounded()) * 100), ContinueMode.longest)
            controller.updateCue(cue.id, "Change Continue Wait") { cue in
                switch cue.continueMode {
                case .whenFinished: cue.continueMode = .whenFinished(waitMs: ms)
                default: cue.continueMode = .after(ms: ms)
                }
            }
        default:
            break
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            finishedEditing()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Put the field back as it was, then leave it.
            if let field = control as? NSTextField { field.abortEditing() }
            update(cue: cue)
            finishedEditing()
            return true
        default:
            return false
        }
    }

    // MARK: Anagrams

    func textDidBeginEditing(_ notification: Notification) {
        anagramsCue = cue?.id
    }

    /// The text box read back into anagrams, as one edit.
    func textDidEndEditing(_ notification: Notification) {
        defer {
            anagramsCue = nil
            revertingAnagrams = false
        }
        guard !revertingAnagrams, let id = anagramsCue ?? cue?.id else { return }
        let read = Anagram.anagrams(fromParagraphs: anagrams.text.string)
        controller?.updateCue(id, "Change Anagrams") { cue in
            // Each GO's cue point stays with the step it moves to.
            if case .anagram(var c) = cue.content {
                c.anagrams = Anagram.carryingCuePoints(from: c.anagrams, into: read)
                cue.content = .anagram(c)
            }
        }
    }

    /// Return starts a new line, as a paragraph needs. Tab moves on, and
    /// Escape puts the text back and gives the keyboard to the show keys.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            window?.selectKeyView(following: textView)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            window?.selectKeyView(preceding: textView)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            revertingAnagrams = true
            if case .anagram(let c) = cue?.content { textView.string = Anagram.paragraphs(c.anagrams) }
            finishedEditing()
            return true
        default:
            return false
        }
    }

    /// A wait after firing starts at five seconds, a wait after finishing
    /// at none; choosing the one already set changes nothing.
    @objc private func continueChosen() {
        guard let cue else { return }
        let mode: ContinueMode
        switch (continueMode.indexOfSelectedItem, cue.continueMode) {
        case (1, .after), (2, .whenFinished), (0, .whenCued): return
        case (1, _): mode = .after(ms: 5000)
        case (2, _): mode = .whenFinished(waitMs: 0)
        default: mode = .whenCued
        }
        controller?.updateCue(cue.id, "Change Continue") { $0.continueMode = mode }
    }

    @objc private func atEndChosen() {
        guard let cue else { return }
        let end = VideoEnd.allCases[atEnd.indexOfSelectedItem]
        controller?.updateCue(cue.id, "Change End Behaviour") { cue in
            if case .video(var c) = cue.content { c.atEnd = end; cue.content = .video(c) }
        }
    }

    @objc private func colourChosen() {
        guard let cue, let srgb = colour.color.usingColorSpace(.sRGB) else { return }
        func byte(_ v: CGFloat) -> UInt8 { UInt8(clamping: Int((v * 255).rounded())) }
        let rgb = RGB(byte(srgb.redComponent), byte(srgb.greenComponent), byte(srgb.blueComponent))
        controller?.updateCue(cue.id, "Change Colour") { cue in
            if case .blank(var c) = cue.content { c.colour = rgb; cue.content = .blank(c) }
        }
    }

    @objc private func choosePressed() { if let cue { chooseMedia(cue.id, nil) } }
    @objc private func editRoutePressed() { if let cue { editRoute(cue.id) } }

    // MARK: A morph's pictures

    /// Every change to the list is one undoable edit, to the cue the strip
    /// shows.
    private func wireMorphPictures() {
        func change(_ name: String, _ body: @escaping (inout MorphContent) -> Void) {
            guard let id = cue?.id else { return }
            controller?.updateCue(id, name) { cue in
                if case .morph(var c) = cue.content { body(&c); cue.content = .morph(c) }
            }
        }
        morphPictures.onAdd = { [weak self] urls in
            guard let self, let id = cue?.id else { return }
            for url in urls { importMedia(url, id, .add) }
        }
        morphPictures.onChoose = { [weak self] index in
            guard let self, let id = cue?.id else { return }
            chooseMedia(id, index.map(ShowDocument.MediaSlot.picture) ?? .add)
        }
        morphPictures.onRemove = { index in change("Remove Picture") { $0.removePicture(at: index) } }
        morphPictures.onMove = { from, to in change("Move Picture") { $0.movePicture(from: from, to: to) } }
        morphPictures.onTime = { index, ms in
            change("Change Stage Time") { c in
                guard c.pictures.indices.contains(index) else { return }
                c.pictures[index].morphMs = ms.map { min(max($0, SettingRange.morphMs.lowerBound), SettingRange.morphMs.upperBound) }
            }
        }
        morphPictures.onPoints = { [weak self] stage in
            guard let self, let id = cue?.id else { return }
            editPoints(id, stage)
        }
    }

    /// Leaves the file in the show, where an undo expects it.
    @objc private func removePressed() {
        guard let cue else { return }
        controller?.updateCue(cue.id, cue.kind == .video ? "Remove Clip" : "Remove Picture") { cue in
            switch cue.content {
            case .image(var c): c.src = ""; cue.content = .image(c)
            case .map(var c): c.src = ""; cue.content = .map(c)
            case .video(var c): c.src = ""; cue.content = .video(c)
            default: break
            }
        }
    }

    #if DEBUG
    /// The fields Tab visits from the first, in order, for checking the
    /// key view loop without a keyboard.
    var tabStops: [String] {
        let names: [NSView: String] = [text: "text", sub: "sub", key: "key", anagrams.text: "anagrams", number: "number", line: "line",
                                       continueSeconds: "seconds"]
        let first: NSView = text.isHidden ? anagrams.text : text
        var stops = [names[first] ?? "?"]
        var view: NSView? = first.nextValidKeyView
        while let v = view, v !== first, stops.count < 10 {
            stops.append(names[v] ?? "?")
            view = v.nextValidKeyView
        }
        return stops
    }
    #endif

    // MARK: Layout

    /// The header and the taller column: a video cue's four rows.
    var preferredHeight: CGFloat { 15 + 36 + 4 * 32 + 15 }

    override func layout() {
        super.layout()
        let x: CGFloat = 16, inner = bounds.width - 32, labelWidth: CGFloat = 76
        var y: CGFloat = 15
        heading.frame = NSRect(x: x, y: y + 3, width: inner, height: 18)
        y += 36
        empty.frame = NSRect(x: x, y: y, width: inner, height: 40)

        let gap: CGFloat = 24
        let leftWidth = ((inner - gap) * 0.55).rounded()
        let rightX = x + leftWidth + gap, rightWidth = inner - leftWidth - gap
        func row(_ label: NSTextField, _ control: NSView, x rowX: CGFloat, y rowY: CGFloat, width: CGFloat, controlWidth: CGFloat? = nil) {
            label.frame = NSRect(x: rowX, y: rowY + 3, width: labelWidth - 6, height: 18)
            control.frame = NSRect(x: rowX + labelWidth, y: rowY, width: controlWidth ?? width - labelWidth, height: 24)
        }

        // Left: what the cue shows.
        var ly = y
        func left(_ label: NSTextField, _ control: NSView, controlWidth: CGFloat? = nil) {
            row(label, control, x: x, y: ly, width: leftWidth, controlWidth: controlWidth)
            ly += 32
        }
        if !text.isHidden { left(textLabel, text) }
        if !anagrams.isHidden {
            // The whole column: four rows' room for the paragraphs.
            anagramsLabel.frame = NSRect(x: x, y: ly + 3, width: labelWidth - 6, height: 18)
            anagrams.frame = NSRect(x: x + labelWidth, y: ly, width: leftWidth - labelWidth, height: 4 * 32 - 8)
            ly += 4 * 32
        }
        if !sub.isHidden { left(subLabel, sub) }
        if !key.isHidden { left(keyLabel, key) }
        func media(_ label: NSTextField, _ well: MediaWell, _ choose: NSButton, _ remove: NSButton) {
            label.frame = NSRect(x: x, y: ly + 3, width: labelWidth - 6, height: 18)
            let buttons = choose.fittingSize.width + remove.fittingSize.width + 12
            well.frame = NSRect(x: x + labelWidth, y: ly, width: leftWidth - labelWidth - buttons - 8, height: 24)
            choose.frame = NSRect(x: well.frame.maxX + 8, y: ly, width: choose.fittingSize.width, height: 24)
            remove.frame = NSRect(x: choose.frame.maxX + 4, y: ly, width: remove.fittingSize.width, height: 24)
            ly += 32
        }
        if !well.isHidden { media(mediaLabel, well, choose, removeMedia) }
        if !routeSummary.isHidden {
            routeLabel.frame = NSRect(x: x, y: ly + 3, width: labelWidth - 6, height: 18)
            let buttonWidth = editRouteButton.fittingSize.width
            routeSummary.frame = NSRect(x: x + labelWidth, y: ly + 3, width: leftWidth - labelWidth - buttonWidth - 8, height: 18)
            editRouteButton.frame = NSRect(x: x + leftWidth - buttonWidth, y: ly, width: buttonWidth, height: 24)
            ly += 32
        }
        if !picturesView.isHidden {
            // The rest of the column: three rows' room for the strip.
            picturesLabel.frame = NSRect(x: x, y: ly + 3, width: labelWidth - 6, height: 18)
            picturesView.frame = NSRect(x: x + labelWidth, y: ly, width: leftWidth - labelWidth, height: 3 * 32 - 8)
            ly += 3 * 32
        }
        if !atEnd.isHidden { left(atEndLabel, atEnd, controlWidth: min(220, leftWidth - labelWidth)) }
        if !colour.isHidden { left(colourLabel, colour, controlWidth: 60) }

        // Right: where it comes in the book.
        row(numberLabel, number, x: rightX, y: y, width: rightWidth, controlWidth: min(140, rightWidth - labelWidth))
        row(lineLabel, line, x: rightX, y: y + 32, width: rightWidth)
        let continueY = y + 64
        continueLabel.frame = NSRect(x: rightX, y: continueY + 3, width: labelWidth - 6, height: 18)
        let popupWidth = max(110, min(170, rightWidth - labelWidth - 124))
        continueMode.frame = NSRect(x: rightX + labelWidth, y: continueY, width: popupWidth, height: 24)
        continueSeconds.frame = NSRect(x: continueMode.frame.maxX + 8, y: continueY, width: 56, height: 24)
        secondsLabel.frame = NSRect(x: continueSeconds.frame.maxX + 6, y: continueY + 3, width: 70, height: 18)
    }
}
