import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// One setting in a form: its name, its control, how it reads, and in a cue's
/// settings a Reset that puts it back on the show's default.
struct SettingRowView: View {
    let key: SettingKey
    /// The kind of cue it sets, or nil for a show default.
    var kind: Cue.Kind?
    let value: SettingValue
    /// Whether the cue sets this itself. Nil for a show default, which has
    /// nothing to override.
    var overridden: Bool?
    /// A second reading after the value, as a hold's length in seconds.
    var annotation: String?
    var isEnabled = true
    let onChange: (SettingValue, _ continuous: Bool) -> Void
    var onReset: () -> Void = {}

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                control
                if showsReading {
                    Text(reading)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 88, alignment: .trailing)
                }
                if overridden == true {
                    Button("Reset", action: onReset)
                        .controlSize(.small)
                        .focusable(false)
                        .help("Use the show\u{2019}s default")
                }
            }
        } label: {
            Text(key.label)
                .foregroundStyle(overridden == true ? Color.accentColor : Color.primary)
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
                .fixedSize()
                Spacer(minLength: 0)
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
                .fixedSize()
                Spacer(minLength: 0)
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

/// How a setting reads and whether it has any effect, worked out once for
/// both panels so the show's defaults and a cue's settings never disagree.
enum SettingState {
    /// For a show default.
    static func of(_ key: SettingKey, in s: ShowSettings) -> (enabled: Bool, annotation: String?) {
        switch key {
        case .fade: (s.transition != .snap, nil)
        // Nothing to time or order when the picture is just shown.
        case .grid, .flip, .order: (s.reveal != .show, imageNote(reveal: s.reveal, order: s.order, key: key))
        case .bars: (s.histogram, nil)
        case .hold: (true, SettingKey.holdLength(holdTicks: s.holdTicks, clockMs: s.clockMs))
        case .pause: (s.advance != .eachStep, SettingKey.holdLength(holdTicks: s.pauseTicks, clockMs: s.clockMs))
        default: (true, nil)
        }
    }

    /// What an image cue's order does where it isn't plain: a flip has no
    /// quarters, so quarters flips in a random order.
    private static func imageNote(reveal: TileReveal, order: TileOrder, key: SettingKey) -> String? {
        guard key == .order, order == .quarters, reveal == .flip else { return nil }
        return "random, as a flip has no quarters"
    }

    /// For the cue standing by, which may set its own values.
    static func of(_ key: SettingKey, in cue: Cue, defaults: ShowSettings) -> (enabled: Bool, annotation: String?) {
        let timing = cue.timing(defaults: defaults)
        switch key {
        case .fade:
            return (cue.transitionIn(defaults: defaults).hasLength, nil)
        case .grid, .flip, .order, .wave:
            // Wave is shared with decryption and anagram cues, which always use it.
            guard cue.kind == .image else { return (true, nil) }
            let reveal = SettingKey.reveal.effective(for: cue, defaults: defaults).value
            let order = SettingKey.order.effective(for: cue, defaults: defaults).value
            guard case .reveal(let r) = reveal, case .order(let o) = order else { return (true, nil) }
            return (r != .show, imageNote(reveal: r, order: o, key: key))
        case .bars:
            return (SettingKey.histogram.effective(for: cue, defaults: defaults).value == .flag(true), nil)
        case .hold:
            return (true, SettingKey.holdLength(holdTicks: timing.holdTicks, clockMs: timing.clockMs))
        case .pause:
            // A step, stage or stop on GO leaves nothing to pause between.
            switch cue.content {
            case .anagram(let c):
                let s = defaults.resolved(c.overrides)
                return (s.advance != .eachStep, SettingKey.holdLength(holdTicks: s.pauseTicks, clockMs: s.clockMs))
            case .map(let c):
                let s = defaults.resolved(c.overrides)
                return (!s.eachStopOnGO, SettingKey.holdLength(holdTicks: s.pauseTicks, clockMs: s.clockMs))
            case .morph(let c):
                let s = defaults.resolved(c.overrides)
                return (!s.eachStageOnGO, SettingKey.holdLength(holdTicks: s.pauseTicks, clockMs: s.clockMs))
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

    /// Every group the show holds defaults for.
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

/// Edit mode's Show tab: the title printed on the cue sheet, then the show's
/// defaults. Every cue that doesn't set its own value runs with these.
struct ShowDefaultsView: View {
    let title: String
    /// What prints when the title is empty: the document's name.
    let fallback: String
    let settings: ShowSettings
    let onTitle: (String) -> Void
    let onChange: (SettingKey, SettingValue, Bool) -> Void
    let onFinishedEditing: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Title", text: Binding(get: { title }, set: { onTitle($0) }),
                          prompt: Text("\(fallback) (the file\u{2019}s name)"))
                    // Return and Escape both hand the keyboard back to the
                    // show keys. The title is already saved as it is typed.
                    .onSubmit(onFinishedEditing)
                    .onExitCommand(perform: onFinishedEditing)
            } footer: {
                Text("Printed at the head of every page of the cue sheet.")
            }

            ForEach(SettingGroup.all) { group in
                Section(group.id) {
                    ForEach(group.keys, id: \.self) { key in
                        let state = SettingState.of(key, in: settings)
                        SettingRowView(key: key, kind: nil, value: key.value(in: settings), overridden: nil,
                                       annotation: state.annotation, isEnabled: state.enabled,
                                       onChange: { value, continuous in onChange(key, value, continuous) })
                    }
                }
            }

            Section("How timing works") {
                Text(SettingKey.timingExplanation)
            }
            Section {
                Text("Every cue runs with these unless it sets its own, in Cue Settings. Changes show on the cue on "
                     + "stage at once, finished, except transitions, which take effect when the stage next changes "
                     + "cue; R runs it again.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Edit mode's Cue Settings tab: what the cue standing by runs with, the
/// values it sets itself marked, and a Reset for each of those.
struct CueSettingsView: View {
    /// The Settings tab, or the Transitions tab beside it.
    enum Scope { case settings, transitions }

    let scope: Scope
    let cue: Cue?
    let defaults: ShowSettings
    let onChange: (SettingKey, SettingValue?, Bool) -> Void

    var body: some View {
        Form {
            if let cue {
                ForEach(SettingGroup.applying(to: cue.kind).filter { (scope == .transitions) == ($0.id == "Transitions") }) { group in
                    Section(scope == .transitions ? "Transition in" : group.id) {
                        ForEach(group.keys, id: \.self) { key in
                            let (value, overridden) = key.effective(for: cue, defaults: defaults)
                            let state = SettingState.of(key, in: cue, defaults: defaults)
                            SettingRowView(key: key, kind: cue.kind, value: value, overridden: overridden,
                                           annotation: state.annotation, isEnabled: state.enabled,
                                           onChange: { value, continuous in onChange(key, value, continuous) },
                                           onReset: { onChange(key, nil, false) })
                        }
                    }
                }
                Section { Text(scope == .transitions ? Self.transitionNote : note(for: cue)) }
            } else {
                Section {
                    Text("Nothing is standing by. Click a cue in the list to see the settings it runs with.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let transitionNote = "How the stage changes to this cue, when it fires. A crossfade dissolves from the cue before; "
        + "a fade goes through black; a snap cuts. A value in the accent colour is set for this cue; the rest come from the Show tab. "
        + "A cue with its own transition shows a row above it in the cue list."

    private func note(for cue: Cue) -> String {
        switch cue.kind {
        case .video:
            "A video plays on its own clock from GO, so it has no settings of its own beyond how the stage changes to it, in the Transitions tab. Its end behaviour is in the Cue tab."
        case .blank:
            "A blank is instant, so it has no settings of its own beyond how the stage changes to it, in the Transitions tab. Its colour is in the Cue tab."
        case .title, .anagram, .image, .morph, .map, .layered:
            SettingKey.timingExplanation
                + " Values in the accent colour are set for this cue; the rest come from the Show tab. Reset puts a value back on the default."
        }
    }
}
