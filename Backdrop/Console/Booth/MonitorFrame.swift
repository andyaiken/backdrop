import AppKit
import BackdropStage
import QuartzCore
import SwiftUI

/// A monitor in the Booth: a picture of the stage in a frame whose border is
/// its tally, as on a vision mixer. On stage is red, Next brass; Next pulses
/// amber while its clip or camera arms, and stays amber if that fails.
///
/// A slate can cover the picture: blackout over On stage, the end of the
/// sheet over Next.
@MainActor
final class MonitorFrame: NSView {
    enum Tally: Equatable {
        case onStage, next, arming, failed
    }

    struct Slate: Equatable {
        var title: String
        var detail: String?
    }

    var tally: Tally = .next {
        didSet { if tally != oldValue { applyTally() } }
    }

    var slate: Slate? {
        didSet {
            guard slate != oldValue else { return }
            slateView.slate = slate
            slateView.isHidden = slate == nil
        }
    }

    private let slateView = SlateView()
    static let border: CGFloat = 2
    static let radius: CGFloat = 10

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = Self.radius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = Self.border
        slateView.isHidden = true
        addSubview(slateView)
        applyTally()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// The picture goes inside the border, under the slate.
    func hold(_ picture: NSView) {
        addSubview(picture, positioned: .below, relativeTo: slateView)
        needsLayout = true
    }

    /// Where the picture sits: inside the border.
    var pictureFrame: NSRect { bounds.insetClamped(dx: Self.border, dy: Self.border) }

    override func layout() {
        super.layout()
        for view in subviews where view !== slateView { view.frame = pictureFrame }
        slateView.frame = pictureFrame
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTally()
    }

    private func applyTally() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "pulse")
        let colour: NSColor = switch tally {
        case .onStage: Booth.tally
        case .next: Booth.brass
        case .arming, .failed: Booth.amber
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.borderColor = colour.cgColor
        }
        // Arming pulses, unless motion is reduced; then it holds amber.
        guard tally == .arming, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "borderColor")
        effectiveAppearance.performAsCurrentDrawingAppearance {
            pulse.fromValue = colour.cgColor
            pulse.toValue = colour.withAlphaComponent(0.25).cgColor
        }
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        layer.add(pulse, forKey: "pulse")
    }
}

/// What covers a monitor's picture: dimmed, with a word across it.
private final class SlateView: NSView {
    var slate: MonitorFrame.Slate? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let slate else { return }
        NSColor.black.withAlphaComponent(0.72).setFill()
        bounds.fill()
        let title = NSAttributedString(string: slate.title, attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .black).withWidth(.compressed),
            .foregroundColor: Booth.ink, .kern: 3,
        ])
        let detail = slate.detail.map {
            NSAttributedString(string: $0, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Booth.dim])
        }
        let t = title.size(), d = detail?.size() ?? .zero
        let total = t.height + (detail == nil ? 0 : 4 + d.height)
        var y = (bounds.height - total) / 2
        title.draw(at: NSPoint(x: (bounds.width - t.width) / 2, y: y))
        y += t.height + 4
        detail?.draw(at: NSPoint(x: (bounds.width - d.width) / 2, y: y))
    }
}

extension NSFont {
    /// The same font at another width, such as compressed.
    func withWidth(_ width: NSFont.Width) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.width: width.rawValue]])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

/// A monitor's label, above it: its tag, then the cue's number and name.
struct MonitorLabel: View {
    let tag: String
    let tagColour: NSColor
    /// The tag filled, as Next's is, or outlined.
    let filled: Bool
    let cue: String
    var runAgain: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Text(tag)
                .font(.system(size: 11, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(filled ? Color(nsColor: Booth.background) : .white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: tagColour)))
                .fixedSize()
            Text(cue)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Color(nsColor: Booth.ink))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let runAgain {
                Button(action: runAgain) {
                    // The words go first when the monitor is narrow; the key stays.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            Keycap("R")
                            Text("Run again")
                        }
                        Keycap("R")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: Booth.dim))
                    .contentShape(Rectangle())
                }
                .layoutPriority(1)
                .buttonStyle(.plain)
                .focusable(false)
                .help("Runs the cue on stage again from its start")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Between the monitors: the transition GO will run, as an arrow from On
/// stage to Next, or "carries on" where GO takes the live cue on.
struct TransitionArrow: View {
    let note: String

    var body: some View {
        VStack(spacing: 6) {
            Text(words.first ?? "")
            HStack(spacing: 0) {
                Rectangle().fill(Color(nsColor: Booth.tally)).frame(height: 2)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: Booth.brass))
            }
            .frame(width: 80)
            Text(words.dropFirst().joined(separator: " "))
        }
        .font(.system(size: 12.5, design: .monospaced))
        .foregroundStyle(Color(nsColor: Booth.dim))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GO runs \(note)")
    }

    /// The style over the arrow, the length under it: "fade" and "0.5 s".
    private var words: [String] {
        let parts = note.split(separator: " ")
        guard parts.count > 2 else { return [note] }
        return [parts.dropLast(2).joined(separator: " "), parts.suffix(2).joined(separator: " ")]
    }
}
