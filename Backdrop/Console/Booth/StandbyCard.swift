import AppKit
import BackdropCore
import BackdropStage
import SwiftUI

/// What GO will act on, as large as the room allows: the cue's number,
/// name and cue point, and what one GO runs after it. It replaces the
/// standby panel.
struct StandbyCard: View {
    var standby: Cue?
    var live: Cue?
    var goPoint: ShowController.StandingByGoPoint?
    /// The steps the live cue has taken, for the diamonds.
    var stepsTaken = 0
    var arm: ArmState?
    var reach: [Reach] = []
    var numberSize: CGFloat = 104
    var onGoTo: () -> Void = {}

    /// The cue the card is about: the one standing by, or the one whose
    /// step stands by.
    private var cue: Cue? { goPoint?.cue ?? standby }
    private var steps: [GoPoint] { cue?.goPoints() ?? [] }

    /// The name and cue point grow and shrink with the number, so a small
    /// card keeps its proportions: 30 and 33 points beside a number of 104.
    private var scale: CGFloat { min(1, max(0.6, numberSize / 104)) }

    var body: some View {
        // Never taller than the room it has: on a small window what doesn't
        // fit is cut off at the foot, not pushed over the monitors.
        GeometryReader { room in
            content
                .frame(width: room.size.width, height: room.size.height, alignment: .topLeading)
                .clipped()
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: Booth.panel)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(nsColor: Booth.line)))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            identity.padding(.top, 6 * scale)
            cuePoint.padding(.top, 14 * scale)
            if let after = afterIt {
                after.padding(.top, 14)
            }
            if let armed {
                armChip(armed).padding(.top, 12)
            }
        }
        .padding(.horizontal, 28 * scale)
        .padding(.vertical, 22 * scale)
    }

    // MARK: Parts

    private var eyebrow: some View {
        HStack(spacing: 10) {
            Text("STAND BY")
                .font(.system(size: 13, weight: .semibold))
                .kerning(3)
                .foregroundStyle(Color(nsColor: Booth.brass))
            Spacer(minLength: 8)
            if !steps.isEmpty {
                Text(CueText.partway(steps.count))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: Booth.dim))
                HStack(spacing: 5) {
                    ForEach(steps.indices, id: \.self) { i in diamond(i) }
                }
            }
        }
    }

    /// A step: filled when taken, solid brass when it is what stands by,
    /// an outline when still to come.
    private func diamond(_ i: Int) -> some View {
        let standingBy = goPoint.map { $0.number - 1 == i } ?? false
        let taken = cue?.id == live?.id && i < stepsTaken
        let brass = Color(nsColor: Booth.brass)
        return Rectangle()
            .fill(standingBy ? brass : (taken ? Color(nsColor: Booth.dim) : .clear))
            .overlay(Rectangle().strokeBorder(standingBy ? brass : Color(nsColor: Booth.dim), lineWidth: 1.5))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(45))
            .frame(width: 15, height: 15)
    }

    private var identity: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Button(action: onGoTo) {
                Text(cue?.number ?? "\u{2014}")
                    .font(.system(size: numberSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Booth.brass))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Go to a cue (G)")
            .accessibilityLabel("Cue \(cue?.number ?? "none") stands by. Go to another cue")
            VStack(alignment: .leading, spacing: 6) {
                if case .blank(let blank)? = cue?.content, goPoint == nil {
                    BlankSwatch(colour: blank.colour, size: CGSize(width: 64, height: 24))
                } else {
                    Text(name)
                        .font(.system(size: 30 * scale, design: .monospaced))
                        .foregroundStyle(Color(nsColor: Booth.ink))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let kind = kindLine {
                    Text(kind)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: Booth.dim))
                        .lineLimit(1)
                }
            }
        }
    }

    private var name: String {
        cue.map(CueText.name) ?? "End of the cue sheet"
    }

    /// "Keypad · 4 boxes", or the step standing by.
    private var kindLine: String? {
        guard let cue else { return nil }
        if let goPoint { return "GO \(goPoint.number) \u{00B7} \(goPoint.point.text)" }
        return [cue.kind.heading, CueText.summary(cue)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    // MARK: Cue point

    /// A GO of a cue waits for its own cue point, if it has one.
    private var line: String {
        (goPoint?.point.cuePoint ?? standby?.line ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cuePoint: some View {
        HStack(alignment: .top, spacing: 18) {
            Rectangle()
                .fill(Color(nsColor: line.isEmpty ? Booth.line : Booth.brass))
                .frame(width: 3)
            Text(line.isEmpty ? fallback : line)
                .font(Font(Desk.script(33 * scale, italic: line.isEmpty)))
                .foregroundStyle(Color(nsColor: line.isEmpty ? Booth.dim : Booth.ink))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .help(line)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// With no cue point of its own: what GO does here.
    private var fallback: String {
        if let goPoint {
            return goPoint.cue.id == live?.id
                ? "GO carries cue \(goPoint.cue.number) on to this step."
                : "GO fires cue \(goPoint.cue.number) straight to this step, the steps before it already done."
        }
        return standby == nil ? "Nothing up next" : "No cue point set"
    }

    // MARK: After it

    /// Only when there is something to say: the step the next GO goes to,
    /// or the cues this GO runs on into.
    private var afterIt: AnyView? {
        if goPoint == nil, let cue, let first = steps.first {
            return AnyView(HStack(spacing: 12) {
                Text("After it").foregroundStyle(Color(nsColor: Booth.dim))
                HStack(spacing: 6) {
                    Image(systemName: "diamond.fill").font(.system(size: 10)).foregroundStyle(Color(nsColor: Booth.brass))
                    Text("GO 1 \u{00B7} \(first.text)").font(.system(size: 14, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: Booth.line)))
                .foregroundStyle(Color(nsColor: Booth.ink))
                Text("the next GO carries cue \(cue.number) on to this step")
                    .foregroundStyle(Color(nsColor: Booth.dim))
                    .lineLimit(1)
            }
            .font(.system(size: 15)))
        }
        if let reach = CueText.reach(reach) {
            return AnyView(HStack(spacing: 12) {
                Text("After it").foregroundStyle(Color(nsColor: Booth.dim))
                Text(reach).foregroundStyle(Color(nsColor: Booth.ink)).lineLimit(1)
            }
            .font(.system(size: 15)))
        }
        return nil
    }

    // MARK: Arming

    private var armed: (text: String, colour: NSColor)? {
        guard let arm else { return nil }
        let colour: NSColor = arm == .armed ? Booth.ok : Booth.amber
        return (arm.text(isFeed: standby?.kind == .feed), colour)
    }

    private func armChip(_ armed: (text: String, colour: NSColor)) -> some View {
        HStack(spacing: 7) {
            Circle().fill(Color(nsColor: armed.colour)).frame(width: 7, height: 7)
            Text(armed.text)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color(nsColor: armed.colour))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(nsColor: armed.colour).opacity(0.12)))
    }
}

/// A blank cue's colour, as a bordered swatch.
struct BlankSwatch: View {
    let colour: RGB
    var size = CGSize(width: 34, height: 13)

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: Double(colour.r) / 255, green: Double(colour.g) / 255, blue: Double(colour.b) / 255))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: Booth.line), lineWidth: 1))
            .frame(width: size.width, height: size.height)
    }
}
