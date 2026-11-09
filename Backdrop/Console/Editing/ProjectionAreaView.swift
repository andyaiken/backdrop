import AppKit
import BackdropCore
import SwiftUI

/// Edit mode's projection area controls: width, height and offsets as
/// percentages of the projector output, alignment guides, and a reset.
///
/// AppKit on the outside so the console's layout places it like any other
/// panel; SwiftUI within, in the Mac's own controls.
@MainActor
final class GeometryPanel: PanelHost<ProjectionAreaView> {
    var onChange: (Geometry) -> Void = { _ in }
    var onGuides: (Bool) -> Void = { _ in }

    init() {
        super.init(rootView: ProjectionAreaView(geometry: Geometry(), guidesOn: false, outputAspect: 16.0 / 9,
                                                onChange: { _ in }, onGuides: { _ in }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameter outputAspect: The projector output's width over its
    ///   height, so a shape can be worked back into percentages of it.
    func update(geometry: Geometry, guidesOn: Bool, outputAspect: Double) {
        rootView = ProjectionAreaView(
            geometry: geometry,
            guidesOn: guidesOn,
            outputAspect: outputAspect,
            onChange: { [weak self] in self?.onChange($0) },
            onGuides: { [weak self] in self?.onGuides($0) }
        )
    }
}

struct ProjectionAreaView: View {
    let geometry: Geometry
    let guidesOn: Bool
    let outputAspect: Double
    let onChange: (Geometry) -> Void
    let onGuides: (Bool) -> Void

    var body: some View {
        Form { sections }
            .formStyle(.grouped)
    }

    /// The sections themselves, for a form that holds more than this.
    @ViewBuilder
    var sections: some View {
            Section {
                FieldRow(label: "Shape") {
                    HStack {
                        Picker("", selection: Binding(get: { shape }, set: { use($0) })) {
                            ForEach(StageShape.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .focusable(false)
                        .fixedSize()
                        Spacer(minLength: 0)
                    }
                }
                row("Width", \.width, SettingRange.geometrySize)
                row("Height", \.height, SettingRange.geometrySize)
                row("Across", \.across, SettingRange.geometryOffset, signed: true)
                row("Down", \.down, SettingRange.geometryOffset, signed: true)
            } header: {
                Text("Projection area")
            } footer: {
                Text("Percentages of the projector output, so they hold if the resolution changes. "
                     + "Guides switch themselves off in show mode.")
            }

            Section {
                FieldRow(label: "Alignment guides") {
                    HStack {
                        Toggle("", isOn: Binding(get: { guidesOn }, set: { onGuides($0) }))
                            .labelsHidden()
                            .focusable(false)
                        Spacer(minLength: 0)
                    }
                }
                Button("Fill the Output") { onChange(Geometry()) }
                    .focusable(false)
            }
    }

    /// The shape the picture lands in, as the audience sees it: the stage's
    /// own width over its height, whatever shape the output is.
    private var shape: StageShape {
        let stage = Double(geometry.width) / Double(max(geometry.height, 1)) * outputAspect
        return StageShape.allCases.first { $0.ratio.map { abs($0 - stage) < 0.02 } ?? false } ?? .custom
    }

    /// The largest area of that shape the output will hold, as percentages
    /// of it. A portrait shape on a landscape projector is a tall slice of
    /// the middle; the offsets then move it where it is wanted.
    private func use(_ shape: StageShape) {
        guard let ratio = shape.ratio else { return }
        let most = SettingRange.geometrySize.upperBound, least = SettingRange.geometrySize.lowerBound
        func fit(_ value: Double) -> Int { min(most, max(least, Int(value.rounded()))) }
        var changed = geometry
        if ratio >= outputAspect {
            changed.width = most
            changed.height = fit(Double(most) * outputAspect / ratio)
        } else {
            changed.height = most
            changed.width = fit(Double(most) * ratio / outputAspect)
        }
        onChange(changed)
    }

    /// A labelled slider and its reading. Offsets read with their sign, so
    /// which way the picture has moved is plain.
    @ViewBuilder
    private func row(_ name: String, _ key: WritableKeyPath<Geometry, Int>, _ range: ClosedRange<Int>,
                     signed: Bool = false) -> some View {
        let value = geometry[keyPath: key]
        FieldRow(label: name, value: signed ? value.signedPercentage : "\(value)%") {
            Slider(value: Binding(
                get: { Double(value) },
                set: { new in
                    var changed = geometry
                    changed[keyPath: key] = Int(new.rounded())
                    onChange(changed)
                }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .focusable(false)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The shapes a projection area is usually asked for, as width : height of
/// the picture itself.
enum StageShape: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case widescreen = "16:9"
    case sixteenTen = "16:10"
    case classic = "4:3"
    case square = "1:1"
    case portrait = "3:4"
    case tall = "9:16"

    var id: String { rawValue }

    /// Width over height. Nil where the percentages say something else.
    var ratio: Double? {
        switch self {
        case .custom: nil
        case .widescreen: 16.0 / 9
        case .sixteenTen: 16.0 / 10
        case .classic: 4.0 / 3
        case .square: 1
        case .portrait: 3.0 / 4
        case .tall: 9.0 / 16
        }
    }
}

private extension Int {
    /// `+6%`, `-6%`, and plain `0%` for no offset at all.
    var signedPercentage: String {
        self == 0 ? "0%" : String(format: "%+d%%", self)
    }
}
