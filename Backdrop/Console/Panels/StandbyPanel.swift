import AppKit
import BackdropCore
import BackdropStage
import SwiftUI

/// What is on screen, then what GO fires next: two halves with a rule
/// between them, each half centred down the panel where it is told, which in
/// show mode is level with the middle of its preview.
@MainActor
final class StandbyPanel: NSView {
    private let onScreen = PanelHost(rootView: StandbyPanelView(part: .onScreen), fills: false)
    private let upNext = PanelHost(rootView: StandbyPanelView(part: .upNext), fills: false)
    private let rule = PanelView(fill: Desk.line)

    /// Where down the panel the middle of each half, and the rule between
    /// them, should be.
    struct Marks: Equatable {
        var onScreen: CGFloat
        var rule: CGFloat
        var upNext: CGFloat
    }

    /// Nil stacks the halves from the top.
    var marks: Marks? {
        didSet { if marks != oldValue { needsLayout = true } }
    }

    /// The least room above and below the rule.
    private static let gap: CGFloat = 14

    init() {
        super.init(frame: .zero)
        for view in [onScreen, rule, upNext] as [NSView] { addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// - Parameter arm: For a video cue standing by: whether it is armed,
    ///   said plainly. While the live cue waits partway, its GO point stands
    ///   by in the cue's place.
    func update(standby: Cue?, live: Cue?, goPoint: ShowController.StandingByGoPoint?, entry: String, arm: ArmState?) {
        onScreen.rootView = StandbyPanelView(part: .onScreen, standby: standby, live: live, goPoint: goPoint, entry: entry, arm: arm)
        upNext.rootView = StandbyPanelView(part: .upNext, standby: standby, live: live, goPoint: goPoint, entry: entry, arm: arm)
        // Either half may have grown or shrunk, so it is centred again.
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width, inset = StandbyPanelView.padding
        let above = onScreen.height(width: w), below = upNext.height(width: w)
        let gap = Self.gap
        let top: CGFloat, ruleY: CGFloat, nextTop: CGFloat
        if let marks {
            // Each half centred on its mark, kept inside the panel, and Up
            // next kept clear of On screen with room for the rule between.
            top = max(0, min(marks.onScreen - above / 2, bounds.height - above))
            nextTop = max(top + above + 2 * gap, min(marks.upNext - below / 2, bounds.height - below))
            ruleY = max(top + above + gap, min(marks.rule, nextTop - gap))
        } else {
            top = inset
            ruleY = top + above + gap
            nextTop = ruleY + gap
        }
        onScreen.frame = NSRect(x: 0, y: top.rounded(), width: w, height: above)
        rule.frame = NSRect(x: inset, y: ruleY.rounded(), width: max(0, w - 2 * inset), height: 1)
        upNext.frame = NSRect(x: 0, y: nextTop.rounded(), width: w, height: below)
    }
}

struct StandbyPanelView: View {
    /// Which half of the panel this is.
    enum Part { case onScreen, upNext }

    let part: Part
    var standby: Cue? = nil
    var live: Cue? = nil
    var goPoint: ShowController.StandingByGoPoint? = nil
    /// A cue number being typed into Go to cue.
    var entry: String = ""
    var arm: ArmState? = nil

    /// Space either side of the panel's contents.
    static let padding: CGFloat = 16
    /// Both halves set their cue in the same sizes; On screen is told apart
    /// by its grey, Up next by the accent.
    static let numberSize: CGFloat = 40
    static let nameSize: CGFloat = 16

    var body: some View {
        Group {
            switch part {
            case .onScreen: onScreen
            case .upNext: upNext
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var onScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("On screen")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(live?.number ?? "\u{2014}")
                    .font(.system(size: Self.numberSize, design: .monospaced))
                Spacer(minLength: 0)
                if case .blank(let blank)? = live?.content {
                    BlankSwatch(colour: blank.colour)
                } else {
                    Text(live.map { $0.text.isEmpty ? "\u{2014}" : $0.text.replacingOccurrences(of: "\n", with: " \u{23CE} ") } ?? "\u{2014}")
                        .font(.system(size: Self.nameSize, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(number)
                    .font(.system(size: Self.numberSize, design: .monospaced))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                if let swatch = standbySwatch {
                    BlankSwatch(colour: swatch)
                } else {
                    Text(name)
                        .font(.system(size: Self.nameSize, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.top, 2)

            if let armed {
                Text(armed.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(armed.colour)
                    .padding(.top, 8)
            }

            cuePointBox.padding(.top, 12)
        }
    }

    /// The cue point, in a box with a bar down its edge: lit where one is
    /// set, quiet where none is.
    private var cuePointBox: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(hasCuePoint ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 2)
            Text(cuePoint)
                .font(.system(size: 15))
                .italic(!hasCuePoint)
                .foregroundStyle(hasCuePoint ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: What it says

    private var heading: String {
        if !entry.isEmpty { return "Go to \u{2014} Return makes it next, Escape clears" }
        if let goPoint { return "Up next \u{2014} \(goPoint.point.unit.rawValue) \(goPoint.number) of \(goPoint.count)" }
        return "Up next"
    }

    private var number: String {
        if !entry.isEmpty { return entry + "\u{2581}" }
        if let goPoint { return goPoint.cue.number }
        return standby?.number ?? "\u{2014}"
    }

    /// A blank has no words to name it, only its colour. Not while a step
    /// stands by in its place, or a number is being typed.
    private var standbySwatch: RGB? {
        guard entry.isEmpty, goPoint == nil, case .blank(let blank)? = standby?.content else { return nil }
        return blank.colour
    }

    private var name: String {
        if !entry.isEmpty { return "" }
        if let goPoint { return goPoint.point.text }
        return standby.map { $0.text.isEmpty ? "\u{2014}" : $0.text.replacingOccurrences(of: "\n", with: " \u{23CE} ") } ?? "end of sheet"
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
        return standby == nil ? "Nothing up next" : "No cue point set"
    }

    private var isFeed: Bool { standby?.kind == .feed }

    private var armed: (text: String, colour: Color)? {
        switch arm {
        case .armed: (isFeed ? "Camera ready" : "Video armed", .green)
        case .arming: (isFeed ? "Camera connecting \u{2014} not armed yet" : "Video loading \u{2014} not armed yet", .orange)
        case .failed(let message): (isFeed ? "No signal \u{2014} \(message)" : "No clip \u{2014} this cue goes to black", .orange)
        case nil: nil
        }
    }
}

/// A blank cue's colour, as a small bordered swatch.
struct BlankSwatch: View {
    let colour: RGB

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: Double(colour.r) / 255, green: Double(colour.g) / 255, blue: Double(colour.b) / 255))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.tertiary, lineWidth: 1))
            .frame(width: 34, height: 13)
    }
}
