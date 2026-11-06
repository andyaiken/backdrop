import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// What the header shows, and what its controls do. Held apart from the view
/// so the wordmark can animate without the console rebuilding it.
@MainActor
final class HeaderState: ObservableObject {
    static let name = "PROSPECT"

    @Published var editing = false
    @Published var lamp = ""
    @Published var live = false
    @Published var warn = false
    @Published var projectorOpen = false
    @Published var goEnabled = true
    @Published var goTip = ""
    /// The wordmark's glyphs, and how far home each one is.
    @Published var wordmark: [(glyph: Character, progress: Double)] = HeaderState.name.map { ($0, 1) }

    var onGo: () -> Void = {}
    var onMode: (Bool) -> Void = { _ in }
    var onAddCue: (Cue.Kind) -> Void = { _ in }
    var onShowSettings: () -> Void = {}
    var onOpenProjector: () -> Void = {}
}

/// The console's header: the wordmark and the mode switch, then the cue sheet's
/// own controls, then the projector's lamp and button, with GO at the right.
///
/// Nothing here takes the keyboard. Space fires the standby cue through the
/// show keys, and a focused GO button would fire it twice.
@MainActor
final class HeaderView: PanelHost<HeaderBar> {
    let state: HeaderState

    init() {
        let state = HeaderState()
        self.state = state
        super.init(rootView: HeaderBar(state: state))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(mode editing: Bool, lamp text: String, live: Bool, warn: Bool, projectorOpen: Bool, goEnabled: Bool, goTip: String) {
        state.editing = editing
        state.lamp = text
        state.live = live
        state.warn = warn
        state.projectorOpen = projectorOpen
        state.goEnabled = goEnabled
        state.goTip = goTip
    }

    // MARK: The wordmark

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
        reveal = TravelPlan(text: HeaderState.name, key: "FIBONACCI", wave: 3, random: &revealRandom)
        showReveal(at: frame)
    }

    /// Frames up to 0 are the ciphertext; from the plan's duration on, the
    /// name itself, and the reveal is over.
    private func showReveal(at frame: Int) {
        guard let plan = reveal else { return }
        revealFrame = frame
        state.wordmark = plan.frame(max(0, frame), random: &revealRandom).map { ($0.glyph, $0.progress) }
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

struct HeaderBar: View {
    @ObservedObject var state: HeaderState

    var body: some View {
        HStack(spacing: 14) {
            Text(wordmark)
                .font(.system(size: 18, design: .monospaced))
                .accessibilityLabel(HeaderState.name)

            Picker("Mode", selection: Binding(get: { state.editing }, set: { state.onMode($0) })) {
                Text("Show").tag(false)
                Text("Edit").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .focusable(false)
            .help("Show mode locks the cue sheet; edit mode unlocks it")

            rule

            if state.editing {
                Menu("Add Cue") {
                    ForEach(Cue.Kind.common, id: \.self) { kind in
                        Button { state.onAddCue(kind) } label: { Label(kind.heading, systemImage: kind.symbol) }
                    }
                    Divider()
                    ForEach(Cue.Kind.others, id: \.self) { kind in
                        Button { state.onAddCue(kind) } label: { Label(kind.heading, systemImage: kind.symbol) }
                    }
                }
                .fixedSize()
                .focusable(false)
                .help("Adds a cue after the one standing by")
            }

            Button("Show Settings\u{2026}") { state.onShowSettings() }
                .fixedSize()
                .focusable(false)
                .help("Opens the show's defaults and its projection area")

            rule

            Circle()
                .fill(lampColour)
                .frame(width: 7, height: 7)
            Text(state.lamp)
                .font(.system(size: 12.5))
                .foregroundStyle(state.live || state.warn ? AnyShapeStyle(lampColour) : AnyShapeStyle(.secondary))

            if !state.projectorOpen {
                Button("Open Projector") { state.onOpenProjector() }
                    .focusable(false)
            }

            Spacer(minLength: 16)

            Button("GO") { state.onGo() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!state.goEnabled)
                .focusable(false)
                .help(state.goTip)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// The rule between one group of controls and the next.
    private var rule: some View {
        Divider().frame(height: 26)
    }

    private var lampColour: Color {
        state.live ? .green : (state.warn ? .orange : .secondary)
    }

    /// The glyphs in the wordmark's own case, each warming from the
    /// ciphertext's quiet to full as it finds its way home.
    private var wordmark: AttributedString {
        var out = AttributedString()
        for (glyph, letter) in zip(state.wordmark, HeaderState.name) {
            let p = min(max(glyph.progress, 0), 1), eased = p * p * (3 - 2 * p)
            var piece = AttributedString(letter.isLowercase ? String(glyph.glyph).lowercased() : String(glyph.glyph))
            piece.foregroundColor = Color.primary.opacity(0.3 + 0.7 * eased)
            piece.kern = 1.4
            out += piece
        }
        return out
    }
}
