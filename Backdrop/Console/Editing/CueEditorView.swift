import AppKit
import BackdropCore
import BackdropStage
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
        case .video, .feed, .sms: fields += [.text, .sub]
        case .image, .text, .morph, .map, .layered: fields += [.text]
        case .keypad: fields += [.text, .script]
        case .conversation: fields += [.text, .sub, .script]
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
/// The cameras there are now, to choose one from. A camera the cue names
/// that isn't there is listed too, so the cue says what it was waiting for.
struct FeedDevicePicker: View {
    let settings: FeedSettings
    let choose: (FeedDevice?) -> Void
    @ObservedObject private var cameras = Cameras.shared

    private var missing: FeedDevice? {
        guard !settings.device.isEmpty, !cameras.devices.contains(where: { $0.id == settings.device }) else { return nil }
        // The same camera under another ID, as on another Mac, is found by name.
        guard !cameras.devices.contains(where: { $0.name == settings.deviceName }) else { return nil }
        return FeedDevice(id: settings.device, name: settings.deviceName.isEmpty ? settings.device : settings.deviceName)
    }

    /// The listed camera the cue means: by ID, or failing that by name.
    private var selection: String {
        if cameras.devices.contains(where: { $0.id == settings.device }) { return settings.device }
        return cameras.devices.first { !settings.deviceName.isEmpty && $0.name == settings.deviceName }?.id ?? settings.device
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(
                get: { selection },
                set: { id in
                    cameras.requestAccess()
                    choose(([missing].compactMap { $0 } + cameras.devices).first { $0.id == id })
                }
            )) {
                Text("None").tag("")
                ForEach(cameras.devices) { Text($0.name).tag($0.id) }
                if let missing { Text("\(missing.name) \u{2014} not connected").tag(missing.id) }
            }
            .labelsHidden()
            .focusable(false)
            if cameras.devices.isEmpty {
                Text("No camera found. A wireless camera must first be connected to this Mac: an iPhone through Continuity Camera, or another computer through an app that offers it as a camera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // After the view has been built: publishing during an update is not allowed.
        .onAppear { DispatchQueue.main.async { cameras.refresh() } }
    }
}

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
        case .feed(let c):
            Section {
                textRow("Label", cue, name: "Change Label")
                subRow("Caption", cue, name: "Change Caption")
                FieldRow(label: "Camera") {
                    FeedDevicePicker(settings: c.settings) { device in
                        edit("Change Camera") { cue in
                            guard case .feed(var f) = cue.content else { return }
                            f.settings.device = device?.id ?? ""
                            f.settings.deviceName = device?.name ?? ""
                            cue.content = .feed(f)
                        }
                    }
                }
                FieldRow(label: "Mirror") {
                    Toggle("", isOn: Binding(
                        get: { c.settings.mirror },
                        set: { on in edit("Change Mirror") { cue in
                            if case .feed(var f) = cue.content { f.settings.mirror = on; cue.content = .feed(f) }
                        } }
                    ))
                    .labelsHidden()
                    .focusable(false)
                    .help("Flip the picture left to right, as a mirror does: for a camera that faces the person it films")
                }
                FieldRow(label: "Turn") {
                    Picker("", selection: Binding(
                        get: { c.settings.rotation },
                        set: { turn in edit("Change Turn") { cue in
                            if case .feed(var f) = cue.content { f.settings.rotation = turn; cue.content = .feed(f) }
                        } }
                    )) {
                        ForEach(FeedRotation.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                FieldRow(label: "Picture") {
                    Picker("", selection: Binding(
                        get: { c.settings.fit },
                        set: { fit in edit("Change Fit") { cue in
                            if case .feed(var f) = cue.content { f.settings.fit = fit; cue.content = .feed(f) }
                        } }
                    )) {
                        Text("Fit \u{2014} all of it").tag(FeedFit.fit)
                        Text("Fill \u{2014} crop the edges").tag(FeedFit.fill)
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                FieldRow(label: "If the feed is lost") {
                    Picker("", selection: Binding(
                        get: { c.settings.onLoss },
                        set: { loss in edit("Change If Lost") { cue in
                            if case .feed(var f) = cue.content { f.settings.onLoss = loss; cue.content = .feed(f) }
                        } }
                    )) {
                        Text("Cut to black").tag(FeedLoss.black)
                        Text("Hold the last picture").tag(FeedLoss.hold)
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
        case .conversation(let c):
            Section {
                textRow("Label", cue, name: "Change Label")
                subRow("Contact", cue, name: "Change Contact")
                FieldRow(label: "Script") {
                    CommittingField(field: .script, focus: $focus, order: fieldOrder, prompt: "< Are you coming tonight?   > Yes, leaving now   GO", mono: true, multiline: true, value: c.script,
                                    commit: { v in edit("Change Script") { cue in
                                        if case .conversation(var k) = cue.content { k.script = v; cue.content = .conversation(k) }
                                    } }, onFinished: onFinished)
                }
                Text("A line to each message: \u{003C} starts one received, on the left, and \u{003E} one sent, on the right. A line of GO makes the cue wait for GO before the messages after it, and anything written after GO is the line it waits for. Other lines are ignored. Everything before the first GO plays when the cue fires.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FieldRow(label: "Style") {
                    Picker("", selection: Binding(
                        get: { c.settings.style },
                        set: { style in edit("Change Style") { cue in
                            if case .conversation(var m) = cue.content { m.settings.style = style; cue.content = .conversation(m) }
                        } }
                    )) {
                        ForEach(SMSStyle.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                FieldRow(label: "Screen") {
                    Picker("", selection: Binding(
                        get: { c.settings.dark },
                        set: { dark in edit("Change Screen") { cue in
                            if case .conversation(var m) = cue.content { m.settings.dark = dark; cue.content = .conversation(m) }
                        } }
                    )) {
                        Text("Dark").tag(true)
                        Text("Light").tag(false)
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                FieldRow(label: "Typing") {
                    Toggle("", isOn: Binding(
                        get: { c.settings.showTyping },
                        set: { on in edit("Change Typing") { cue in
                            if case .conversation(var m) = cue.content { m.settings.showTyping = on; cue.content = .conversation(m) }
                        } }
                    ))
                    .labelsHidden()
                    .focusable(false)
                    .help("Show the dots while a message is on its way, and the compose bar while one is typed. Off, each bubble just arrives.")
                }
                FieldRow(label: "Between messages", value: ContinueMode.seconds(c.settings.pauseTicks * CueTiming.standardClockMs) + " s") {
                    Slider(value: Binding(
                        get: { Double(c.settings.pauseTicks) },
                        set: { ticks in edit("Change Pause") { cue in
                            if case .conversation(var m) = cue.content { m.settings.pauseTicks = min(max(Int(ticks), SettingRange.pauseTicks.lowerBound), SettingRange.pauseTicks.upperBound); cue.content = .conversation(m) }
                        } }
                    ), in: Double(SettingRange.pauseTicks.lowerBound)...Double(SettingRange.pauseTicks.upperBound), step: 1)
                        .focusable(false)
                }
            }
        case .sms(let c):
            Section {
                FieldRow(label: "Message") {
                    CommittingField(field: .text, focus: $focus, order: fieldOrder, prompt: "", mono: true, multiline: true, value: cue.text,
                                    commit: { v in typing("Change Message") { $0.text = v } }, onFinished: onFinished)
                }
                subRow("From", cue, name: "Change From")
                FieldRow(label: "Style") {
                    Picker("", selection: Binding(
                        get: { c.settings.style },
                        set: { style in edit("Change Style") { cue in
                            if case .sms(var m) = cue.content { m.settings.style = style; cue.content = .sms(m) }
                        } }
                    )) {
                        ForEach(SMSStyle.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                FieldRow(label: "Screen") {
                    Picker("", selection: Binding(
                        get: { c.settings.dark },
                        set: { dark in edit("Change Screen") { cue in
                            if case .sms(var m) = cue.content { m.settings.dark = dark; cue.content = .sms(m) }
                        } }
                    )) {
                        Text("Dark").tag(true)
                        Text("Light").tag(false)
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                FieldRow(label: "Bubble") {
                    Picker("", selection: Binding(
                        get: { c.settings.sent },
                        set: { sent in edit("Change Bubble") { cue in
                            if case .sms(var m) = cue.content { m.settings.sent = sent; cue.content = .sms(m) }
                        } }
                    )) {
                        Text("Received \u{2014} left").tag(false)
                        Text("Sent \u{2014} right").tag(true)
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                if c.settings.sent {
                    FieldRow(label: "Status") {
                        Picker("", selection: Binding(
                            get: { c.settings.status },
                            set: { status in edit("Change Status") { cue in
                                if case .sms(var m) = cue.content { m.settings.status = status; cue.content = .sms(m) }
                            } }
                        )) {
                            ForEach(SMSStatus.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                        .labelsHidden()
                        .focusable(false)
                        .help("How far the sent message has got: written beneath the bubble, or as ticks inside it in the Green rectangles style")
                    }
                    if c.settings.status != .none, c.settings.status != .read {
                        FieldRow(label: "Moves on with GO") {
                            Toggle("", isOn: Binding(
                                get: { c.settings.advances },
                                set: { on in edit("Change Status On GO") { cue in
                                    if case .sms(var m) = cue.content { m.settings.advances = on; cue.content = .sms(m) }
                                } }
                            ))
                            .labelsHidden()
                            .focusable(false)
                            .help("Each GO moves the status on a step, towards read")
                        }
                    }
                }
                FieldRow(label: "Arrives") {
                    Picker("", selection: Binding(
                        get: { c.settings.entrance },
                        set: { entrance in edit("Change Arrival") { cue in
                            if case .sms(var m) = cue.content { m.settings.entrance = entrance; cue.content = .sms(m) }
                        } }
                    )) {
                        ForEach(SMSEntrance.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .focusable(false)
                }
                if c.settings.entrance != .cut {
                    FieldRow(label: "Arrival time", value: ContinueMode.seconds(c.settings.entranceMs) + " s") {
                        Slider(value: Binding(
                            get: { Double(c.settings.entranceMs) },
                            set: { ms in edit("Change Arrival Time") { cue in
                                if case .sms(var m) = cue.content { m.settings.entranceMs = min(max(Int(ms), SettingRange.smsEntranceMs.lowerBound), SettingRange.smsEntranceMs.upperBound); cue.content = .sms(m) }
                            } }
                        ), in: Double(SettingRange.smsEntranceMs.lowerBound)...Double(SettingRange.smsEntranceMs.upperBound), step: 50)
                            .focusable(false)
                    }
                }
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
