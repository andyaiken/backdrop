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
    /// The Inspector is showing the Show Settings.
    @Published var showSettingsOn = false
    @Published var goEnabled = true
    @Published var goTip = ""
    /// The wordmark's glyphs, and how far home each one is.
    @Published var wordmark: [(glyph: Character, progress: Double)] = HeaderState.name.map { ($0, 1) }

    var onGo: () -> Void = {}
    var onMode: (Bool) -> Void = { _ in }
    var onAddCue: (Cue.Kind) -> Void = { _ in }
    var onShowSettings: (Bool) -> Void = { _ in }
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

    func update(mode editing: Bool, lamp text: String, live: Bool, warn: Bool, projectorOpen: Bool, showSettingsOn: Bool, goEnabled: Bool, goTip: String) {
        state.editing = editing
        state.lamp = text
        state.live = live
        state.warn = warn
        state.projectorOpen = projectorOpen
        state.showSettingsOn = showSettingsOn
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
    @State private var showingAddCue = false
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
                Button("Add Cue") { showingAddCue.toggle() }
                    .popover(isPresented: $showingAddCue, arrowEdge: .bottom) { addCueList }
                .fixedSize()
                .focusable(false)
                .help("Adds a cue after the one standing by")
            }

            if state.editing {
                Toggle("Show Settings", isOn: Binding(get: { state.showSettingsOn }, set: { state.onShowSettings($0) }))
                    .toggleStyle(.button)
                    .fixedSize()
                    .focusable(false)
                    .help("Shows the show's title, text size and projection area in the Inspector")
            }

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

    /// The Add Cue popover: each kind with its icon, name and a line on what it does.
    private var addCueList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Cue.Kind.common, id: \.self) { addCueRow($0) }
            Divider().padding(.vertical, 4)
            ForEach(Cue.Kind.others, id: \.self) { addCueRow($0) }
        }
        .padding(8)
        .frame(width: 320)
    }

    private func addCueRow(_ kind: Cue.Kind) -> some View {
        addCueButton(symbol: kind.symbol, title: kind.heading, blurb: kind.blurb) { state.onAddCue(kind) }
    }

    private func addCueButton(symbol: String, title: String, blurb: String, action: @escaping () -> Void) -> some View {
        Button {
            showingAddCue = false
            action()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.semibold)
                    Text(blurb).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(AddCueRowStyle())
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

/// A popover row that lights up under the pointer, as a menu item does.
private struct AddCueRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(configuration.isPressed ? 0.35 : (hovering ? 0.22 : 0)))
                )
                .onHover { hovering = $0 }
        }
    }
}
