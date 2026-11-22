import AppKit
import BackdropCore
import SwiftUI

/// A choice with a visible result, as picture chips: three across, each a
/// small picture of the option and its name, the chosen one outlined in
/// brass. An entrance's effects are toggle chips, any mix of them. Bars is
/// a segmented control.
struct LookChips: View {
    let key: SettingKey
    let cue: Cue
    let value: SettingValue
    var isEnabled = true
    let onChange: (SettingValue) -> Void
    @ObservedObject private var art = ChipArt.shared

    /// The settings shown this way.
    static func shows(_ key: SettingKey) -> Bool {
        [.letters, .order, .reveal, .camera, .context, .push, .entrance, .bars].contains(key)
    }

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        FieldRow(label: key.label, info: key.help, isEnabled: isEnabled) {
            switch key.control {
            case .effects(let names):
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                        let on = key.isOn(effect: i, in: value)
                        chip(name, option: i, value: key.turning(effect: i, on: true, in: .entrance(LayerEntrance())), selected: on) {
                            onChange(key.turning(effect: i, on: !on, in: value))
                        }
                    }
                }
            default:
                let options = key.choices(for: cue.kind)
                let chosen = key.choiceIndex(of: value, for: cue.kind)
                if key == .bars {
                    Picker("", selection: Binding(get: { chosen ?? 0 }, set: { onChange(options[$0].value) })) {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, option in Text(option.label).tag(i) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .focusable(false)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                            chip(option.label, option: i, value: option.value, selected: i == chosen) { onChange(option.value) }
                        }
                    }
                }
            }
        }
    }

    private func chip(_ label: String, option: Int, value: SettingValue, selected: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VStack(spacing: 5) {
                ZStack {
                    Color.black
                    if let image = art.image(key, kind: cue.kind, option: option, value: value) {
                        Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .frame(height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(label)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(selected ? 0.12 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25),
                                                                   lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
