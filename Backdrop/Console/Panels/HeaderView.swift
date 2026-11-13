import AppKit
import BackdropCore
import BackdropStage
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
    /// The Add Cue sheet is open.
    @Published var showingAddCue = false

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
    @ObservedObject var state: HeaderState

    var body: some View {
        HStack(spacing: 14) {
            // The switch can write its choice while SwiftUI is still updating the
            // header, and changing the mode republishes every header value, which
            // isn't allowed mid-update. So the change is made just after.
            Picker("Mode", selection: Binding(get: { state.editing }, set: { editing in
                DispatchQueue.main.async { state.onMode(editing) }
            })) {
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
                Button("Add Cue") { state.showingAddCue.toggle() }
                    .sheet(isPresented: $state.showingAddCue) {
                        AddCueSheet { kind in
                            state.showingAddCue = false
                            if let kind { state.onAddCue(kind) }
                        }
                    }
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

    private var lampColour: Color {
        state.live ? .green : (state.warn ? .orange : .secondary)
    }
}

/// The Add Cue sheet: every kind with its icon, name and a line on what it
/// does, narrowed as the user types by name, blurb or keyword ("sms" finds
/// both text message kinds). Return picks the first match.
private struct AddCueSheet: View {
    let done: (Cue.Kind?) -> Void
    @State private var query = ""
    @FocusState private var searching: Bool

    private var matches: [Cue.Kind] { Cue.Kind.matching(query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search cue types", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searching)
                .onSubmit { if let first = matches.first { done(first) } }
                .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matches, id: \.self) { kind in
                        if query.isEmpty, kind == Cue.Kind.others.first { Divider().padding(.vertical, 4) }
                        row(kind)
                    }
                    if matches.isEmpty {
                        Text("No cue types match \u{201C}\(query)\u{201D}.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(8)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 480)
        .onAppear { searching = true }
    }

    private func row(_ kind: Cue.Kind) -> some View {
        Button { done(kind) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind.symbol)
                    .frame(width: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.heading).fontWeight(.semibold)
                    Text(kind.blurb).font(.callout).foregroundStyle(.secondary)
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
