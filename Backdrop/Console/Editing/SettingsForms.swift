import AppKit
import BackdropCore
import BackdropStage
import SwiftUI

/// A field laid out in two rows: its name on the left and its reading, if it
/// has one, on the right; then its control across the whole width.
struct FieldRow<Control: View>: View {
    let label: String
    var value: String?
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer(minLength: 12)
                if let value {
                    Text(value)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // A grouped form reserves a label column beside any control that
            // might have a label, even an empty one; hiding labels gives that
            // width back, and text reads from the left rather than the right.
            control
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// One setting in a form: its name, its control, and how it reads.
struct SettingRowView: View {
    let key: SettingKey
    /// The kind of cue it sets, or nil for a show-wide setting.
    var kind: Cue.Kind?
    let value: SettingValue
    /// A second reading after the value, as a hold's length in seconds.
    var annotation: String?
    var isEnabled = true
    let onChange: (SettingValue, _ continuous: Bool) -> Void

    var body: some View {
        FieldRow(label: key.label, value: showsReading ? reading : nil) {
            control
        }
        .disabled(!isEnabled)
        .help(key.help)
    }

    /// A picker shows its own value, so it needs no reading beside it.
    private var showsReading: Bool {
        switch key.control {
        case .slider, .toggle: true
        case .choice, .font: false
        }
    }

    private var reading: String {
        let text = key.format(value, for: kind)
        return annotation.map { text + " \u{00B7} " + $0 } ?? text
    }

    @ViewBuilder
    private var control: some View {
        switch key.control {
        case .slider(let range, let step):
            Slider(value: number, in: Double(range.lowerBound)...Double(range.upperBound), step: Double(max(step, 1)))
                .focusable(false)
                .frame(maxWidth: .infinity)
        case .toggle:
            HStack {
                Toggle("", isOn: flag).labelsHidden().focusable(false)
                Spacer(minLength: 0)
            }
        case .choice:
            HStack {
                Picker("", selection: choice) {
                    ForEach(Array(key.choices(for: kind).enumerated()), id: \.offset) { i, option in
                        Text(option.label).tag(i)
                    }
                }
                .labelsHidden()
                .focusable(false)
            }
        case .font:
            HStack {
                Picker("", selection: family) {
                    Text(SettingKey.stageFont).tag("")
                    Divider()
                    ForEach(Self.families, id: \.self) { name in
                        Text(name).font(.custom(name, size: 13)).tag(name)
                    }
                    if case .font(let chosen) = value, !chosen.isEmpty, !Self.families.contains(chosen) {
                        Divider()
                        Text("\(chosen) (not on this Mac)").tag(chosen)
                    }
                }
                .labelsHidden()
                .focusable(false)
            }
        }
    }

    // MARK: Bindings

    private var number: Binding<Double> {
        Binding(get: { if case .number(let n) = value { Double(n) } else { 0 } },
                set: { onChange(key.snapped(.number(Int($0.rounded()))), true) })
    }

    private var flag: Binding<Bool> {
        Binding(get: { if case .flag(let on) = value { on } else { false } },
                set: { onChange(.flag($0), false) })
    }

    private var choice: Binding<Int> {
        Binding(get: { key.choiceIndex(of: value, for: kind) ?? 0 },
                set: { i in
                    let options = key.choices(for: kind)
                    guard options.indices.contains(i) else { return }
                    onChange(options[i].value, false)
                })
    }

    private var family: Binding<String> {
        Binding(get: { if case .font(let f) = value { f } else { "" } },
                set: { onChange(.font($0), false) })
    }

    /// Every font family on this Mac, each named in its own type where it has
    /// letters to show, so a hand can be picked by eye.
    @MainActor
    static let families: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted()
}

/// How a setting reads and whether it has any effect.
enum SettingState {
    /// What an image cue's order does where it isn't plain: a flip has no
    /// quarters, so quarters flips in a random order.
    private static func imageNote(reveal: TileReveal, order: TileOrder, key: SettingKey) -> String? {
        guard key == .order, order == .quarters, reveal == .flip else { return nil }
        return "random, as a flip has no quarters"
    }

    /// For the cue standing by.
    static func of(_ key: SettingKey, in cue: Cue) -> (enabled: Bool, annotation: String?) {
        let timing = cue.timing
        switch key {
        case .fade:
            return (cue.transition.hasLength, nil)
        case .wipeFrom:
            return (cue.transition.style == .wipe, nil)
        case .grid, .flip, .order, .wave:
            // Wave is shared with decryption and anagram cues, which always use it.
            guard case .image(let c) = cue.content else { return (true, nil) }
            return (c.settings.reveal != .show, imageNote(reveal: c.settings.reveal, order: c.settings.order, key: key))
        case .bars:
            if case .title(let c) = cue.content { return (c.settings.histogram, nil) }
            return (true, nil)
        case .hold:
            return (true, SettingKey.holdLength(holdTicks: timing.holdTicks, clockMs: timing.clockMs))
        case .pause:
            // A step, stage or stop on GO leaves nothing to pause between.
            switch cue.content {
            case .anagram(let c):
                let s = c.settings
                return (s.advance != .eachStep, SettingKey.holdLength(holdTicks: s.pauseTicks, clockMs: s.clockMs))
            case .map(let c):
                let s = c.settings
                return (!s.eachStopOnGO, SettingKey.holdLength(holdTicks: s.pauseTicks, clockMs: s.clockMs))
            case .morph(let c):
                let s = c.settings
                return (!s.eachStageOnGO, SettingKey.holdLength(holdTicks: s.pauseTicks, clockMs: s.clockMs))
            case .layered(let c):
                let s = c.settings
                return (!s.eachStepOnGO, SettingKey.holdLength(holdTicks: s.pauseTicks, clockMs: s.clockMs))
            default:
                return (true, nil)
            }
        default:
            return (true, nil)
        }
    }
}

/// A heading and the settings under it, as the panels list them.
struct SettingGroup: Identifiable {
    let id: String
    let keys: [SettingKey]

    /// Every group of settings a cue can have.
    static let all = SettingKey.groups.map { SettingGroup(id: $0.name, keys: $0.keys) }

    /// The same groups, keeping only what this kind of cue can set.
    static func applying(to kind: Cue.Kind) -> [SettingGroup] {
        all.compactMap { group in
            var keys = group.keys.filter { $0.applies(to: kind) }
            // Zoom is the map's key, shared: a layered cue's sits with its own.
            if kind == .layered {
                if group.id == "Map cues" { keys = [] }
                if group.id == "Layered image cues" { keys.insert(.zoom, at: keys.firstIndex(of: .push).map { $0 + 1 } ?? keys.endIndex) }
            }
            return keys.isEmpty ? nil : SettingGroup(id: group.id, keys: keys)
        }
    }
}

/// The Show Settings the Inspector holds: the title printed on the cue sheet,
/// the size of text, and the projection area.
struct ShowSettingsView: View {
    let title: String
    /// What prints when the title is empty: the document's name.
    let fallback: String
    let settings: ShowSettings
    let geometry: Geometry
    let guidesOn: Bool
    let outputAspect: Double
    let onTitle: (String) -> Void
    let onTextScale: (Int, _ continuous: Bool) -> Void
    let onFinishedEditing: () -> Void
    let onGeometry: (Geometry) -> Void
    let onGuides: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                FieldRow(label: "Title") {
                    TextField("Title", text: Binding(get: { title }, set: { onTitle($0) }),
                              prompt: Text("\(fallback) (the file\u{2019}s name)"))
                        .textFieldStyle(.roundedBorder)
                        // Return and Escape both hand the keyboard back to the
                        // show keys. The title is already saved as it is typed.
                        .onSubmit(onFinishedEditing)
                        .onExitCommand(perform: onFinishedEditing)
                }
            } footer: {
                Text("Printed at the head of every page of the cue sheet.")
            }

            Section {
                SettingRowView(key: .textScale, value: .number(settings.textScale),
                               onChange: { value, continuous in
                                   if case .number(let n) = value { onTextScale(n, continuous) }
                               })
            } footer: {
                Text("Changes show on the cue on stage at once.")
            }

            ProjectionAreaView(geometry: geometry, guidesOn: guidesOn, outputAspect: outputAspect,
                               onChange: onGeometry, onGuides: onGuides).sections
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // A grouped form insets its cards by about 20pt and the panel pads again;
        // pull the form out by half that.
        .padding(.horizontal, -15)
        .padding(.top, -12)
    }
}

/// Edit mode's Cue Settings tab: what the cue standing by runs with.
struct CueSettingsView: View {
    /// The Settings tab, or the transition selected in the cue list.
    enum Scope { case settings, transitions }

    let scope: Scope
    let cue: Cue?
    let onChange: (SettingKey, SettingValue, Bool) -> Void

    var body: some View {
        Form {
            if let cue {
                CueSettingsSections(transitions: scope == .transitions, cue: cue, onChange: onChange)
            } else {
                Section {
                    Text("Nothing is standing by. Click a cue in the list to see the settings it runs with.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // A grouped form insets its cards by about 20pt and the panel pads again;
        // pull the form out by half that.
        .padding(.horizontal, -15)
        .padding(.top, -12)
    }
}

/// The sections of a cue's settings, for a Form to hold: the Settings groups
/// that apply to its kind, or its transition, and a note on what they mean.
struct CueSettingsSections: View {
    let transitions: Bool
    let cue: Cue
    let onChange: (SettingKey, SettingValue, Bool) -> Void

    var body: some View {
        ForEach(SettingGroup.applying(to: cue.kind).filter { transitions == ($0.id == "Transitions") }) { group in
            Section {
                ForEach(group.keys, id: \.self) { key in
                    if let value = key.value(in: cue) {
                        let state = SettingState.of(key, in: cue)
                        SettingRowView(key: key, kind: cue.kind, value: value,
                                       annotation: state.annotation, isEnabled: state.enabled,
                                       onChange: { value, continuous in onChange(key, value, continuous) })
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text(transitions ? "Transition in" : group.id)
                    // What timing means, on hover, rather than as text in the form.
                    if group.id == "Timing" {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .help(SettingKey.timingExplanation)
                    }
                }
            }
        }
        if let text = transitions ? Self.transitionNote : note(for: cue) {
            Section { Text(text) }
        }
    }

    private static let transitionNote = "How the stage changes to this cue, when it fires."

    private func note(for cue: Cue) -> String? {
        switch cue.kind {
        case .video:
            "A video plays on its own clock from GO, so it has no settings of its own beyond how the stage changes to it, in the transition row above it in the cue list. Its end behaviour is above."
        case .feed:
            "A live feed shows the camera as it arrives, so it has no settings of its own beyond how the stage changes to it, in the transition row above it in the cue list. Its camera, mirror, turn, fit and what happens if the feed is lost are above."
        case .blank:
            "A blank is instant, so it has no settings of its own beyond how the stage changes to it, in the transition row above it in the cue list. Its colour is above."
        case .text:
            "A text cue is instant, so it has no settings of its own beyond how the stage changes to it, in the transition row above it in the cue list. Its words, font, colour and alignment are above."
        case .title, .anagram, .image, .morph, .map, .layered, .keypad:
            nil
        }
    }
}
