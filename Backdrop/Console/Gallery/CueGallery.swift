import BackdropCore
import SwiftUI

/// Adding a cue: every kind as a card with its sample running, in groups,
/// narrowed as the user types. Return adds the first match, which is
/// outlined; Escape cancels. It replaces the Add Cue sheet.
struct CueGallery: View {
    /// Where the cue will go, as the top right says it: the words, and the
    /// cue in bold, if there is one.
    let place: GalleryPlace
    let done: (Cue.Kind?) -> Void

    @State private var query: String
    @FocusState private var searching: Bool
    @StateObject private var clock: GalleryClock

    /// - Parameter query: What the search starts with; snapshots fill it in.
    init(place: GalleryPlace, query: String = "", clock: GalleryClock = GalleryClock(), done: @escaping (Cue.Kind?) -> Void) {
        self.place = place
        self.done = done
        _query = State(initialValue: query)
        _clock = StateObject(wrappedValue: clock)
    }

    /// The groups an empty search shows. They are presentation, so they live
    /// here rather than in the model, whose own order is for the menus.
    static let groups: [(title: String, kinds: [Cue.Kind])] = [
        ("Pictures", [.image, .layered, .morph, .map]),
        ("Words", [.text, .title, .anagram, .cascade]),
        ("Phones and devices", [.sms, .conversation, .keypad]),
        ("Moving pictures, and nothing", [.video, .feed, .blank]),
    ]

    private var matches: [Cue.Kind] { Cue.Kind.matching(query) }
    private var searchingNow: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// What Return adds: the first card shown.
    private var first: Cue.Kind? { searchingNow ? matches.first : Self.groups.first?.kinds.first }

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                TextField("Search cue types. Try \u{201C}safe\u{201D} or \u{201C}hacker\u{201D}.", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($searching)
                    .onSubmit { if let first { done(first) } }
                place.text
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(16)
            Divider()
            ScrollView {
                if searchingNow {
                    if matches.isEmpty {
                        Text("No cue types match \u{201C}\(query)\u{201D}.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else {
                        grid(matches).padding(16)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Self.groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .kerning(1.6)
                                    .foregroundStyle(.secondary)
                                grid(group.kinds)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            Divider()
            HStack {
                Text("Return adds the first match \u{00B7} Escape cancels")
                Spacer()
                Text("Or drop pictures and clips anywhere on the rail")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 760, height: 600)
        .onAppear { searching = true }
        .onDisappear { clock.stop() }
        .onExitCommand { done(nil) }
        .background(
            // Escape, wherever the keyboard is in the sheet.
            Button("") { done(nil) }.keyboardShortcut(.cancelAction).hidden()
        )
    }

    private func grid(_ kinds: [Cue.Kind]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(kinds, id: \.self) { kind in
                GalleryCard(kind: kind, isFirst: kind == first, clock: clock) { done(kind) }
            }
        }
    }
}

/// Where the new cue will land.
struct GalleryPlace: Equatable {
    var lead: String
    var cue: String?

    static let atEnd = GalleryPlace(lead: "Adds at the end")
    static let atStart = GalleryPlace(lead: "Starts the sheet")
    static func after(_ cue: Cue) -> GalleryPlace {
        GalleryPlace(lead: "Adds after ", cue: "\(cue.number) \u{00B7} \(CueText.name(cue))")
    }

    var text: Text {
        cue.map { Text("\(lead)\(Text($0).bold())") } ?? Text(lead)
    }
}

/// A kind: its sample running at 16:9, its heading and today's blurb.
struct GalleryCard: View {
    let kind: Cue.Kind
    let isFirst: Bool
    let clock: GalleryClock
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 8) {
                GalleryPreviewView(kind: kind, clock: clock)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.quaternary))
                Text(kind.heading).font(.system(size: 13, weight: .semibold))
                Text(kind.blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3, reservesSpace: true)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(hovering ? 0.10 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: isFirst ? 2 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(kind.heading): \(kind.blurb)")
    }
}
