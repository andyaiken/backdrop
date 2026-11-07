import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// The wordmark's glyphs, and how far home each one is.
@MainActor
final class WordmarkState: ObservableObject {
    static let name = "PROSPECT"

    @Published var glyphs: [(glyph: Character, progress: Double)] = WordmarkState.name.map { ($0, 1) }
}

/// The animated PROSPECT wordmark, sized to fit whatever space it is given.
/// Edit mode shows it in the preview's place when no cue is selected.
@MainActor
final class WordmarkView: PanelHost<WordmarkBar> {
    let state: WordmarkState

    init() {
        let state = WordmarkState()
        self.state = state
        super.init(rootView: WordmarkBar(state: state))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Frames of ciphertext before any letter moves, and how long a frame is.
    private static let hold = 20
    private static let frameSeconds: TimeInterval = 0.05

    private var reveal: TravelPlan?
    private var revealFrame = 0
    private var revealRandom = SystemUnitRandom()
    private var revealTimer: Timer?

    /// Decrypts the wordmark the way a title cue decrypts on stage: a moment
    /// of ciphertext, then each letter cycling home, warming as it goes.
    /// Not at all under reduced motion.
    func decryptWordmark() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        startReveal(at: -Self.hold)
        let timer = Timer(timeInterval: Self.frameSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.showReveal(at: (self?.revealFrame ?? 0) + 1) }
        }
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
    }

    private func startReveal(at frame: Int) {
        revealTimer?.invalidate()
        revealTimer = nil
        // The key never shows, on stage or here. Its shifts, 5, 8, 1, 13, 13,
        // 0, 2, 2, 8, are mostly Fibonacci numbers, for anyone who looks.
        reveal = TravelPlan(text: WordmarkState.name, key: "FIBONACCI", wave: 3, random: &revealRandom)
        showReveal(at: frame)
    }

    /// Frames up to 0 are the ciphertext; from the plan's duration on, the
    /// name itself, and the reveal is over.
    private func showReveal(at frame: Int) {
        guard let plan = reveal else { return }
        revealFrame = frame
        state.glyphs = plan.frame(max(0, frame), random: &revealRandom).map { ($0.glyph, $0.progress) }
        if frame >= plan.duration {
            revealTimer?.invalidate()
            revealTimer = nil
            reveal = nil
        }
    }

    #if DEBUG
    /// The wordmark held on one frame of a fresh reveal, for snapshots.
    func holdWordmark(atFrame frame: Int) {
        startReveal(at: frame)
    }
    #endif
}

struct WordmarkBar: View {
    @ObservedObject var state: WordmarkState

    var body: some View {
        GeometryReader { proxy in
            // A monospaced glyph is about 0.6 of its size wide, plus the kern.
            let count = CGFloat(WordmarkState.name.count)
            let size = max(8, min(proxy.size.width / (count * 0.7), proxy.size.height)).rounded(.down)
            Text(wordmark(size: size))
                .font(.system(size: size, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityLabel(WordmarkState.name)
        }
    }

    /// The glyphs in the wordmark's own case, each warming from the
    /// ciphertext's quiet to full as it finds its way home.
    private func wordmark(size: CGFloat) -> AttributedString {
        var out = AttributedString()
        for (glyph, letter) in zip(state.glyphs, WordmarkState.name) {
            let p = min(max(glyph.progress, 0), 1), eased = p * p * (3 - 2 * p)
            var piece = AttributedString(letter.isLowercase ? String(glyph.glyph).lowercased() : String(glyph.glyph))
            piece.foregroundColor = Color.primary.opacity(0.3 + 0.7 * eased)
            piece.kern = size * 0.08
            out += piece
        }
        return out
    }
}