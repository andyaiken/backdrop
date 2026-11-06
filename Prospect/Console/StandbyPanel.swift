import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// What GO fires next, large; what is on screen, small.
@MainActor
final class StandbyPanel: PanelHost<StandbyPanelView> {
    init() {
        super.init(rootView: StandbyPanelView(standby: nil, live: nil, goPoint: nil, entry: "", arm: nil), fills: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameter arm: For a video cue standing by: whether it is armed,
    ///   said plainly. While the live cue waits partway, its GO point stands
    ///   by in the cue's place.
    func update(standby: Cue?, live: Cue?, goPoint: ShowController.StandingByGoPoint?, entry: String, arm: ArmState?) {
        rootView = StandbyPanelView(standby: standby, live: live, goPoint: goPoint, entry: entry, arm: arm)
    }
}

struct StandbyPanelView: View {
    let standby: Cue?
    let live: Cue?
    let goPoint: ShowController.StandingByGoPoint?
    /// A cue number being typed into Go to cue.
    let entry: String
    let arm: ArmState?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(number)
                    .font(.system(size: 30, design: .monospaced))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Text(name)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, 2)

            if let armed {
                Text(armed.text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(armed.colour)
                    .padding(.top, 8)
            }

            cuePointBox.padding(.top, 10)

            Divider().padding(.vertical, 12)

            Text("On screen")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(live?.number ?? "\u{2014}")
                    .font(.system(size: 17, design: .monospaced))
                Spacer(minLength: 0)
                Text(live.map { $0.text.isEmpty ? "\u{2014}" : $0.text } ?? "\u{2014}")
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The cue point, in a box with a bar down its edge: lit where one is
    /// set, quiet where none is.
    private var cuePointBox: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(hasCuePoint ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 2)
            Text(cuePoint)
                .font(.system(size: 13))
                .italic(!hasCuePoint)
                .foregroundStyle(hasCuePoint ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: What it says

    private var heading: String {
        if !entry.isEmpty { return "Go to \u{2014} Return stands it by, Escape clears" }
        if let goPoint { return "Standing by \u{2014} \(goPoint.point.unit.rawValue) \(goPoint.number) of \(goPoint.count)" }
        return "Standing by"
    }

    private var number: String {
        if !entry.isEmpty { return entry + "\u{2581}" }
        if let goPoint { return goPoint.cue.number }
        return standby?.number ?? "\u{2014}"
    }

    private var name: String {
        if !entry.isEmpty { return "" }
        if let goPoint { return goPoint.point.text }
        return standby.map { $0.text.isEmpty ? "\u{2014}" : $0.text } ?? "end of sheet"
    }

    /// A GO of a cue waits for its own cue point, if it has one.
    private var line: String {
        (goPoint?.point.cuePoint ?? standby?.line ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasCuePoint: Bool { !line.isEmpty }

    private var cuePoint: String {
        if hasCuePoint { return line }
        // No cue point of its own: what GO does here.
        if let goPoint {
            return goPoint.cue.id == live?.id
                ? "GO carries cue \(goPoint.cue.number) on to this step."
                : "GO fires cue \(goPoint.cue.number) straight to this step, the steps before it already done."
        }
        return standby == nil ? "Nothing to stand by for" : "No cue point set"
    }

    private var armed: (text: String, colour: Color)? {
        switch arm {
        case .armed: ("Video armed", .green)
        case .arming: ("Video loading \u{2014} not armed yet", .orange)
        case .failed: ("No clip \u{2014} this cue goes to black", .orange)
        case nil: nil
        }
    }
}
