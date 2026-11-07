import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// A field of the cue editor. The order they stand in is stated once here:
/// Tab walks it, and the document check reads it.
enum CueField: String, Hashable, CaseIterable {
    case number, line, seconds, text, sub, key, anagrams, script

    /// Which of the Inspector's tabs a form is: the fields every cue has, or
    /// the ones this kind of cue adds to them.
    enum Scope { case common, kind }

    static func order(for kind: Cue.Kind, continues: Bool, scope: Scope) -> [CueField] {
        if scope == .common {
            var fields: [CueField] = [.number, .line]
            if continues { fields.append(.seconds) }
            return fields
        }
        var fields: [CueField] = []
        switch kind {
        case .title: fields += [.text, .sub, .key]
        case .anagram: fields += [.anagrams]
        case .video: fields += [.text, .sub]
        case .image, .text, .morph, .map, .layered: fields += [.text]
        case .keypad: fields += [.text, .script]
        case .blank: break
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
    /// Words that run to several lines: Return starts a new one rather than
    /// finishing, and Escape or Tab leaves the box.
    var multiline = false
    /// What the cue says now.
    let value: String
    let commit: (String) -> Void
    let onFinished: () -> Void

    @State private var draft = ""
    @State private var ready = false

    private var editing: Bool { focus.wrappedValue == field }

    @ViewBuilder
    private var input: some View {
        if multiline {
            TextEditor(text: $draft)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
        } else {
            TextField("", text: $draft, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .font(mono ? .system(size: 12.5, design: .monospaced) : nil)
        }
    }

    var body: some View {
        input
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

/// Edit mode's Cue tab and its kind's tab. The Cue tab holds what every cue
/// has: its number, cue point and continue. The kind's tab holds what only
/// this kind has (its text, pictures and the like), then the settings it
/// runs with. Every change goes through the show controller as one
/// undoable edit.
struct CueEditorView: View {
    let scope: CueField.Scope
    let cue: Cue?
    /// The GO of the cue that stands by, if one does: its cue point is the
    /// one the Cue point field edits.
    let goPoint: ShowController.StandingByGoPoint?
    let morphPictures: MorphPicturesState
    let layeredStrip: LayeredStripState
    let edit: (String, @escaping (inout Cue) -> Void) -> Void
    /// A change made as it is typed: coalesced, so a run of keystrokes is one
    /// undo step rather than one each.
    let typing: (String, @escaping (inout Cue) -> Void) -> Void
    let onFinished: () -> Void
    let onChooseMedia: () -> Void
    let onRemoveMedia: () -> Void
    let onDropMedia: (URL) -> Void
    let onEditRoute: () -> Void
    let onSetting: (SettingKey, SettingValue, Bool) -> Void

    @FocusState private var focus: CueField?

    /// The fields this cue shows, in the order Tab walks them.
    private var fieldOrder: [CueField] {
        guard let cue else { return [] }
        return CueField.order(for: cue.kind, continues: cue.continueMode.continues, scope: scope)
    }

    var body: some View {
        Form {
            if let cue {
                if scope == .common {
                  Section {
                    FieldRow(label: "Number") {
                        CommittingField(field: .number, focus: $focus, order: fieldOrder, prompt: "", mono: true, value: cue.number,
                                        commit: { v in typing("Change Cue Number") { $0.number = v.trimmingCharacters(in: .whitespaces) } },
                                        onFinished: onFinished)
                    }
                    FieldRow(label: goPoint.map { "GO \($0.number)" } ?? "Cue point") {
                        CommittingField(field: .line, focus: $focus, order: fieldOrder, prompt: cuePointPrompt, value: cuePoint(cue),
                                        commit: commitCuePoint(cue), onFinished: onFinished)
                    }
                    continueRow(cue)
                  }
                } else {
                    content(cue)
                    CueSettingsSections(transitions: false, cue: cue, onChange: onSetting)
                }
            } else {
                Section {
                    Text(scope == .common
                         ? "Nothing is standing by. Add a cue with Add Cue at the top, or click one in the list to edit it."
                         : "Nothing is standing by. Click a cue in the list to see what it holds.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // A grouped form insets its cards by about 20pt and the panel pads again;
        // pull the form out by half that.
        .padding(.horizontal, -15)
        .padding(.top, -12)
        .id(cue?.id)
    }

    // MARK: The cue itself

    private var cuePointPrompt: String {
        goPoint.map { "The line or action GO \($0.number) waits for" } ?? "The line or action to wait for"
    }

    private func cuePoint(_ cue: Cue) -> String {
        goPoint?.point.cuePoint ?? cue.line
    }

    private func commitCuePoint(_ cue: Cue) -> (String) -> Void {
        { value in
            if let step = goPoint?.number.advanced(by: -1) {
                typing("Change GO Cue Point") { $0.setCuePoint(value, ofGoPoint: step) }
            } else {
                typing("Change Cue Point") { $0.line = value }
            }
        }
    }

    @ViewBuilder
    private func continueRow(_ cue: Cue) -> some View {
        FieldRow(label: "Continue") {
            Picker("", selection: Binding(get: { continueChoice(cue) }, set: { setContinue($0, on: cue) })) {
                Text("When cued").tag(0)
                Text("After a wait").tag(1)
                Text("When finished").tag(2).disabled(!cue.finishes)
            }
            .labelsHidden()
            .focusable(false)
        }
        if cue.continueMode.continues {
            FieldRow(label: "Seconds") {
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
                FieldRow(label: "Key") {
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
        case .text(let c):
            Section {
                textRow("Text", cue, name: "Change Text", multiline: true)
                FieldRow(label: "Font") {
                    Picker("", selection: Binding(get: { c.font }, set: { family in
                        edit("Change Font") { cue in
                            if case .text(var t) = cue.content { t.font = family; cue.content = .text(t) }
                        }
                    })) {
                        Text(SettingKey.stageFont).tag("")
                        Divider()
                        ForEach(SettingRowView.families, id: \.self) { name in
                            Text(name).font(.custom(name, size: 13)).tag(name)
                        }
                        if !c.font.isEmpty, !SettingRowView.families.contains(c.font) {
                            Divider()
                            Text("\(c.font) (not on this Mac)").tag(c.font)
                        }
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                FieldRow(label: "Colour") {
                    ColorPicker("", selection: colourBinding(c.colour, name: "Change Colour") { rgb, cue in
                        if case .text(var t) = cue.content { t.colour = rgb; cue.content = .text(t) }
                    })
                        .labelsHidden()
                        .focusable(false)
                }
                FieldRow(label: "Background") {
                    ColorPicker("", selection: colourBinding(c.background, name: "Change Background") { rgb, cue in
                        if case .text(var t) = cue.content { t.background = rgb; cue.content = .text(t) }
                    })
                        .labelsHidden()
                        .focusable(false)
                }
                FieldRow(label: "Vertical") {
                    Picker("", selection: Binding(get: { c.vertical }, set: { v in
                        edit("Change Vertical Alignment") { cue in
                            if case .text(var t) = cue.content { t.vertical = v; cue.content = .text(t) }
                        }
                    })) {
                        ForEach(TextVertical.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .focusable(false)
                }
                FieldRow(label: "Alignment") {
                    Picker("", selection: Binding(get: { c.alignment }, set: { align in
                        edit("Change Alignment") { cue in
                            if case .text(var t) = cue.content { t.alignment = align; cue.content = .text(t) }
                        }
                    })) {
                        ForEach(TextAlign.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .focusable(false)
                }
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
                FieldRow(label: "Route") {
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
                FieldRow(label: "At the end") {
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
                }
            }
        case .layered(let c):
            Section {
                textRow("Label", cue, name: "Change Label")
                mediaRow("Base", path: c.base, kind: .image, empty: "No base \u{2014} black", cue: cue)
            }
            Section("Layers") {
                LayeredStripView(state: layeredStrip)
                Text("\(c.layers.count) layer\(c.layers.count == 1 ? "" : "s"), \(c.steps.count) step\(c.steps.count == 1 ? "" : "s"). Every layer is a full-frame picture at the base\u{2019}s size, with transparency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .keypad(let c):
            Section {
                textRow("Label", cue, name: "Change Label")
                FieldRow(label: "Keys") {
                    CommittingField(field: .script, focus: $focus, order: fieldOrder, prompt: "a stage per line, e.g. 1332, <<<<, 1123, GOOD", mono: true, multiline: true, value: c.script,
                                    commit: { v in edit("Change Keys") { cue in
                                        if case .keypad(var k) = cue.content { k.script = v; cue.content = .keypad(k) }
                                    } }, onFinished: onFinished)
                }
                Text("Typed a stage at a time, a GO for each after the first: digits, * and # press that key, \u{003C} deletes, and each new line starts the next stage. A stage with GOOD or BAD presses OK after its keys, then flashes the boxes green or red. The boxes are as many as the script ever holds at once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .blank(let c):
            Section {
                FieldRow(label: "Colour") {
                    ColorPicker("", selection: colourBinding(c.colour, name: "Change Colour") { rgb, cue in
                        if case .blank(var b) = cue.content { b.colour = rgb; cue.content = .blank(b) }
                    })
                        .labelsHidden()
                        .focusable(false)
                }
            }
        }
    }

    @ViewBuilder
    private func textRow(_ label: String, _ cue: Cue, name: String, multiline: Bool = false) -> some View {
        FieldRow(label: label) {
            CommittingField(field: .text, focus: $focus, order: fieldOrder, prompt: "", mono: true, multiline: multiline, value: cue.text,
                            commit: { v in typing(name) { $0.text = v } }, onFinished: onFinished)
        }
    }

    @ViewBuilder
    private func subRow(_ label: String, _ cue: Cue, name: String) -> some View {
        FieldRow(label: label) {
            CommittingField(field: .sub, focus: $focus, order: fieldOrder, prompt: "", mono: true, value: cue.sub,
                            commit: { v in typing(name) { $0.sub = v } }, onFinished: onFinished)
        }
    }

    @ViewBuilder
    private func mediaRow(_ label: String, path: String, kind: Cue.Kind, empty: String, cue: Cue) -> some View {
        FieldRow(label: label) {
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
    private func colourBinding(_ colour: RGB, name: String, set: @escaping (RGB, inout Cue) -> Void) -> Binding<Color> {
        Binding(get: { Self.swiftUI(colour) }, set: { setColour($0, name: name, set: set) })
    }

    private static func swiftUI(_ colour: RGB) -> Color {
        Color(red: Double(colour.r) / 255, green: Double(colour.g) / 255, blue: Double(colour.b) / 255)
    }

    private func setColour(_ colour: Color, name: String, set: @escaping (RGB, inout Cue) -> Void) {
        guard let srgb = NSColor(colour).usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        let rgb = RGB(UInt8(clamping: r), UInt8(clamping: g), UInt8(clamping: b))
        edit(name) { cue in set(rgb, &cue) }
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
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
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
