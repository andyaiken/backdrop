import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// What the header shows, and what its controls do. Held apart from the view
/// so the console needn't rebuild it.
@MainActor
final class HeaderState: ObservableObject {
    @Published var editing = false
    @Published var lamp = ""
    @Published var live = false
    @Published var warn = false
    @Published var projectorOpen = false
    /// The Inspector is showing the Show Settings.
    @Published var showSettingsOn = false
    @Published var goEnabled = true
    @Published var goTip = ""

    var onGo: () -> Void = {}
    var onMode: (Bool) -> Void = { _ in }
    var onAddCue: (Cue.Kind) -> Void = { _ in }
    var onShowSettings: (Bool) -> Void = { _ in }
    var onOpenProjector: () -> Void = {}
    var onCloseProjector: () -> Void = {}
}

/// The console's header: the mode switch, then the cue sheet's
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
}

struct HeaderBar: View {
    @State private var showingAddCue = false
    @ObservedObject var state: HeaderState

    var body: some View {
        HStack(spacing: 14) {
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

            if state.projectorOpen {
                Button("Close Projector") { state.onCloseProjector() }
                    .focusable(false)
            } else {
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
