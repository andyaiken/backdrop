import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// A field of the cue editor. The order they stand in is stated once here:
/// Tab walks it, and the document check reads it.
enum CueField: String, Hashable, CaseIterable {
    case number, line, seconds, text, sub, key, anagrams

    static func order(for kind: Cue.Kind, continues: Bool) -> [CueField] {
        var fields: [CueField] = [.number, .line]
        if continues { fields.append(.seconds) }
        switch kind {
        case .title: fields += [.text, .sub, .key]
        case .anagram: fields += [.anagrams]
        case .video: fields += [.text, .sub]
        case .image, .morph, .map, .blank: fields += [.text]
        }
        return fields
    }
}

/// Moves the keyboard on from `field`, wrapping at either end. SwiftUI in a
/// hosted view doesn't inherit the window's key view loop, so Tab is walked
/// here rather than left to AppKit.
@MainActor
func moveFocus(from field: CueField, by delta: Int, in order: [CueField], to focus: FocusState<CueField?>.Binding) {
    guard let i = order.firstIndex(of: field), !order.isEmpty else { return }
    focus.wrappedValue = order[(i + delta + order.count) % order.count]
}

/// A text field that edits a draft and commits once it is left, so a change
/// is one undoable edit rather than one per keystroke. Return commits and
/// hands the keyboard back; Escape puts the field as it was and does the same.
struct CommittingField: View {
    let field: CueField
    let focus: FocusState<CueField?>.Binding
    let order: [CueField]
    let prompt: String
    var mono = false
    /// What the cue says now.
    let value: String
    let commit: (String) -> Void
    let onFinished: () -> Void

    @State private var draft = ""
    @State private var ready = false

    private var editing: Bool { focus.wrappedValue == field }

    var body: some View {
        TextField("", text: $draft, prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .font(mono ? .system(size: 12.5, design: .monospaced) : nil)
            .focused(focus, equals: field)
            .onKeyPress(keys: [.tab]) { press in
                moveFocus(from: field, by: press.modifiers.contains(.shift) ? -1 : 1, in: order, to: focus)
                return .handled
            }
            .onAppear { draft = value; ready = true }
            // Changed elsewhere, as by an undo: take it, unless it is being
            // typed in right now.
            .onChange(of: value) { _, new in if !editing { draft = new } }
            // Committed as it is typed. Waiting for the field to be left lost
            // the edit outright, and a run of keystrokes coalesces into one
            // undo step anyway.
            .onChange(of: draft) { _, new in if ready, new != value { commit(new) } }
            .onSubmit { onFinished() }
            .onExitCommand {
                draft = value
                onFinished()
            }
    }
}

/// The picture, clip or map a cue plays, as a well a file can be dropped on.
struct MediaWellView: NSViewRepresentable {
    let path: String
    let kind: Cue.Kind
    let empty: String
    let onDrop: (URL) -> Void

    func makeNSView(context: Context) -> MediaWell { MediaWell() }

    func updateNSView(_ well: MediaWell, context: Context) {
        well.onDrop = onDrop
        well.show(path: path, kind: kind, empty: empty)
    }
}

/// Edit mode's Cue tab: the cue standing by, and everything about it that
/// isn't a setting. Every change goes through the show controller as one
/// undoable edit.
struct CueEditorView: View {
    let cue: Cue?
    /// The GO of the cue that stands by, if one does: its cue point is the
    /// one the Cue point field edits.
    let goPoint: ShowController.StandingByGoPoint?
    /// The show's defaults, for setting a GO's cue point.
    let defaults: ShowSettings
    let morphPictures: MorphPicturesState
    let edit: (String, @escaping (inout Cue) -> Void) -> Void
    /// A change made as it is typed: coalesced, so a run of keystrokes is one
    /// undo step rather than one each.
    let typing: (String, @escaping (inout Cue) -> Void) -> Void
    let onFinished: () -> Void
    let onChooseMedia: () -> Void
    let onRemoveMedia: () -> Void
    let onDropMedia: (URL) -> Void
    let onEditRoute: () -> Void

    @FocusState private var focus: CueField?

    /// The fields this cue shows, in the order Tab walks them.
    private var fieldOrder: [CueField] {
        guard let cue else { return [] }
        return CueField.order(for: cue.kind, continues: cue.continueMode.continues)
    }

    var body: some View {
        Form {
            if let cue {
                Section {
                    Text(heading(cue)).font(.headline)
                }
                Section {
                    LabeledContent("Number") {
                        CommittingField(field: .number, focus: $focus, order: fieldOrder, prompt: "", mono: true, value: cue.number,
                                        commit: { v in typing("Change Cue Number") { $0.number = v.trimmingCharacters(in: .whitespaces) } },
                                        onFinished: onFinished)
                    }
                    LabeledContent(goPoint.map { "GO \($0.number)" } ?? "Cue point") {
                        CommittingField(field: .line, focus: $focus, order: fieldOrder, prompt: cuePointPrompt, value: cuePoint(cue),
                                        commit: commitCuePoint(cue), onFinished: onFinished)
                    }
                    continueRow(cue)
                }
                content(cue)
            } else {
                Section {
                    Text("Nothing is standing by. Add a cue with Add Cue at the top, or click one in the list to edit it.")
                }
            }
        }
        .formStyle(.grouped)
        .id(cue?.id)
    }

    // MARK: The cue itself

    private func heading(_ cue: Cue) -> String {
        "Cue \(cue.number.isEmpty ? "(no number)" : cue.number) \u{2014} \(cue.kind.name)"
            + (goPoint.map { " \u{00B7} GO \($0.number) of \($0.count): \($0.point.text)" } ?? "")
    }

    private var cuePointPrompt: String {
        goPoint.map { "The line or action GO \($0.number) waits for" } ?? "The line or action to wait for"
    }

    private func cuePoint(_ cue: Cue) -> String {
        goPoint?.point.cuePoint ?? cue.line
    }

    private func commitCuePoint(_ cue: Cue) -> (String) -> Void {
        { value in
            if let step = goPoint?.number.advanced(by: -1) {
                let defaults = self.defaults
                typing("Change GO Cue Point") { $0.setCuePoint(value, ofGoPoint: step, defaults: defaults) }
            } else {
                typing("Change Cue Point") { $0.line = value }
            }
        }
    }

    @ViewBuilder
    private func continueRow(_ cue: Cue) -> some View {
        LabeledContent("Continue") {
            Picker("", selection: Binding(get: { continueChoice(cue) }, set: { setContinue($0, on: cue) })) {
                Text("When cued").tag(0)
                Text("After a wait").tag(1)
                Text("When finished").tag(2).disabled(!cue.finishes)
            }
            .labelsHidden()
            .focusable(false)
            .fixedSize()
        }
        if cue.continueMode.continues {
            LabeledContent("Seconds") {
                CommittingField(field: .seconds, focus: $focus, order: fieldOrder, prompt: "", mono: true,
                                value: ContinueMode.seconds(waitMs(cue)),
                                commit: { commitSeconds($0, on: cue) }, onFinished: onFinished)
            }
        }
    }

    private func continueChoice(_ cue: Cue) -> Int {
        switch cue.continueMode {
        case .whenCued: 0
        case .after: 1
        case .whenFinished: 2
        }
    }

    private func waitMs(_ cue: Cue) -> Int {
        switch cue.continueMode {
        case .whenCued: 0
        case .after(let ms): ms
        case .whenFinished(let ms): ms
        }
    }

    /// A wait after firing starts at five seconds, a wait after finishing at
    /// none; choosing the one already set changes nothing.
    private func setContinue(_ choice: Int, on cue: Cue) {
        guard choice != continueChoice(cue) else { return }
        edit("Change Continue") { c in
            switch choice {
            case 0: c.continueMode = .whenCued
            case 1: c.continueMode = .after(ms: 5000)
            default: c.continueMode = .whenFinished(waitMs: 0)
            }
        }
    }

    /// To a tenth of a second, up to an hour. Anything unreadable is left as
    /// it was.
    private func commitSeconds(_ text: String, on cue: Cue) {
        guard let seconds = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)),
              seconds.isFinite else { return }
        let ms = min(max(0, Int((seconds * 10).rounded()) * 100), ContinueMode.longest)
        typing("Change Continue Wait") { c in
            switch c.continueMode {
            case .whenFinished: c.continueMode = .whenFinished(waitMs: ms)
            default: c.continueMode = .after(ms: ms)
            }
        }
    }

    // MARK: What the cue shows

    @ViewBuilder
    private func content(_ cue: Cue) -> some View {
        switch cue.content {
        case .title(let c):
            Section {
                textRow("Text", cue, name: "Change Text")
                subRow("Subtext", cue, name: "Change Subtext")
                LabeledContent("Key") {
                    CommittingField(field: .key, focus: $focus, order: fieldOrder, prompt: "", mono: true, value: c.key,
                                    commit: { v in typing("Change Key") { cue in
                                        if case .title(var t) = cue.content { t.key = v; cue.content = .title(t) }
                                    } },
                                    onFinished: onFinished)
                }
            }
        case .anagram(let c):
            Section("Anagrams") {
                AnagramsEditor(focus: $focus, order: fieldOrder, anagrams: c.anagrams, edit: edit, onFinished: onFinished)
            }
        case .image(let c):
            Section {
                textRow("Label", cue, name: "Change Label")
                mediaRow("Picture", path: c.src, kind: .image, empty: "No picture \u{2014} drop one here", cue: cue)
            }
        case .morph:
            Section {
                textRow("Label", cue, name: "Change Label")
            }
            Section("Pictures") {
                MorphPicturesView(state: morphPictures)
            }
        case .map(let c):
            Section {
                textRow("Header", cue, name: "Change Label")
                mediaRow("Map", path: c.src, kind: .map, empty: "No map \u{2014} drop one here", cue: cue)
                LabeledContent("Route") {
                    HStack {
                        Text(routeSummary(c)).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Button("Edit Route\u{2026}", action: onEditRoute).focusable(false)
                    }
                }
            }
        case .video(let c):
            Section {
                textRow("Label", cue, name: "Change Label")
                subRow("Caption", cue, name: "Change Caption")
                mediaRow("Clip", path: c.src, kind: .video, empty: "No clip \u{2014} drop one here", cue: cue)
                LabeledContent("At the end") {
                    Picker("", selection: Binding(
                        get: { c.atEnd },
                        set: { end in edit("Change At The End") { cue in
                            if case .video(var v) = cue.content { v.atEnd = end; cue.content = .video(v) }
                        } }
                    )) {
                        ForEach(VideoEnd.allCases, id: \.self) { end in
                            Text(end.rawValue.capitalized).tag(end)
                        }
                    }
                    .labelsHidden()
                    .focusable(false)
                    .fixedSize()
                }
            }
        case .blank(let c):
            Section {
                textRow("Label", cue, name: "Change Label")
                LabeledContent("Colour") {
                    ColorPicker("", selection: colourBinding(c.colour))
                        .labelsHidden()
                        .focusable(false)
                }
            }
        }
    }

    @ViewBuilder
    private func textRow(_ label: String, _ cue: Cue, name: String) -> some View {
        LabeledContent(label) {
            CommittingField(field: .text, focus: $focus, order: fieldOrder, prompt: "", mono: true, value: cue.text,
                            commit: { v in typing(name) { $0.text = v } }, onFinished: onFinished)
        }
    }

    @ViewBuilder
    private func subRow(_ label: String, _ cue: Cue, name: String) -> some View {
        LabeledContent(label) {
            CommittingField(field: .sub, focus: $focus, order: fieldOrder, prompt: "", mono: true, value: cue.sub,
                            commit: { v in typing(name) { $0.sub = v } }, onFinished: onFinished)
        }
    }

    @ViewBuilder
    private func mediaRow(_ label: String, path: String, kind: Cue.Kind, empty: String, cue: Cue) -> some View {
        LabeledContent(label) {
            VStack(alignment: .leading, spacing: 8) {
                MediaWellView(path: path, kind: kind, empty: empty, onDrop: onDropMedia)
                    .frame(height: 64)
                HStack {
                    Button("Choose\u{2026}", action: onChooseMedia).focusable(false)
                    Button("Remove", action: onRemoveMedia).focusable(false).disabled(path.isEmpty)
                }
            }
        }
    }

    /// A blank cue's colour, as the picker wants it and as the show keeps it.
    private func colourBinding(_ colour: RGB) -> Binding<Color> {
        Binding(get: { Self.swiftUI(colour) }, set: { setColour($0) })
    }

    private static func swiftUI(_ colour: RGB) -> Color {
        Color(red: Double(colour.r) / 255, green: Double(colour.g) / 255, blue: Double(colour.b) / 255)
    }

    private func setColour(_ colour: Color) {
        guard let srgb = NSColor(colour).usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        let rgb = RGB(UInt8(clamping: r), UInt8(clamping: g), UInt8(clamping: b))
        edit("Change Colour") { cue in
            if case .blank(var blank) = cue.content { blank.colour = rgb; cue.content = .blank(blank) }
        }
    }

    private func routeSummary(_ c: MapContent) -> String {
        let stops = c.stops.count - 1
        let jumps = c.stops.dropFirst().filter { c.stop(at: $0).arrival == .jump }.count
        if c.route.isEmpty { return "None yet: set it in the route window" }
        if stops < 1 { return "A start, and no stops yet" }
        return "\(stops) stop\(stops == 1 ? "" : "s")" + (jumps > 0 ? ", \(jumps) by a jump" : "")
            + (c.reference == nil ? "" : ", with coordinates")
    }
}

/// An anagram cue's anagrams, a paragraph each, read back as one edit when
/// the box is left.
struct AnagramsEditor: View {
    let focus: FocusState<CueField?>.Binding
    let order: [CueField]
    let anagrams: [Anagram]
    let edit: (String, @escaping (inout Cue) -> Void) -> Void
    let onFinished: () -> Void

    @State private var draft = ""
    @State private var ready = false

    private var editing: Bool { focus.wrappedValue == .anagrams }

    var body: some View {
        TextEditor(text: $draft)
            .font(.system(size: 12.5, design: .monospaced))
            .frame(minHeight: 96)
            .focused(focus, equals: .anagrams)
            .onKeyPress(keys: [.tab]) { press in
                moveFocus(from: .anagrams, by: press.modifiers.contains(.shift) ? -1 : 1, in: order, to: focus)
                return .handled
            }
            .onAppear { draft = Anagram.paragraphs(anagrams); ready = true }
            .onChange(of: Anagram.paragraphs(anagrams)) { _, new in if !editing { draft = new } }
            .onChange(of: draft) { _, new in
                guard ready else { return }
                let read = Anagram.anagrams(fromParagraphs: new)
                guard read != anagrams else { return }
                edit("Change Anagrams") { cue in
                    if case .anagram(var a) = cue.content { a.anagrams = read; cue.content = .anagram(a) }
                }
            }
            .onExitCommand {
                draft = Anagram.paragraphs(anagrams)
                onFinished()
            }
    }
}
