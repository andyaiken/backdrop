import AppIntents
import AppKit
import BackdropCore
import BackdropStage
import CoreSpotlight

/// The show open in Backdrop, for intents. Backdrop has one at a time.
@MainActor
enum OpenShow {
    static var document: ShowDocument? {
        (NSDocumentController.shared as? DocumentController)?.current
    }

    static var controller: ShowController? { document?.controller }
}

// MARK: Shows

/// A show on disk, as Shortcuts and Spotlight see it. Spotlight finds it by
/// its title and by the words on its cues, and choosing it opens it.
struct ShowEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let defaultQuery = ShowQuery()

    /// The show's file, as a path: the same show however it was found.
    let id: String
    let title: String
    /// Its cues' words, for Spotlight. Known only for a show that is open.
    let words: String?
    let cueCount: Int?

    var url: URL { URL(fileURLWithPath: id) }

    var displayRepresentation: DisplayRepresentation {
        let cues = cueCount.map { "\($0) cue\($0 == 1 ? "" : "s")" }
        return DisplayRepresentation(title: "\(title)", subtitle: cues.map { "\($0)" })
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.displayName = title
        attributes.contentDescription = cueCount.map { "A Backdrop show of \($0) cue\($0 == 1 ? "" : "s")" }
        attributes.textContent = words
        attributes.contentURL = url
        return attributes
    }

    /// A show known only by its file: its name stands for its title.
    init(url: URL) {
        id = url.standardizedFileURL.path
        title = url.deletingPathExtension().lastPathComponent
        words = nil
        cueCount = nil
    }

    /// The show open, with everything Spotlight finds it by.
    init(url: URL, show: Show) {
        id = url.standardizedFileURL.path
        let named = show.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = named.isEmpty ? url.deletingPathExtension().lastPathComponent : named
        words = show.searchableText
        cueCount = show.cues.count
    }

    /// The open show if this is it, which knows its title; otherwise the file.
    @MainActor
    static func current(or url: URL) -> ShowEntity {
        if let document = OpenShow.document, document.fileURL?.standardizedFileURL == url.standardizedFileURL {
            return ShowEntity(url: url, show: document.show)
        }
        return ShowEntity(url: url)
    }
}

/// Shows Backdrop knows: the one open, and those it can open again, which it
/// has kept bookmarks to (see `ShowBookmarks`), most recent first.
struct ShowQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ShowEntity] {
        await MainActor.run {
            let known = Self.known()
            return identifiers.compactMap { id in known.first { $0.id == URL(fileURLWithPath: id).standardizedFileURL.path } }
        }
    }

    func suggestedEntities() async throws -> [ShowEntity] {
        await MainActor.run { Self.known() }
    }

    func entities(matching string: String) async throws -> [ShowEntity] {
        await MainActor.run { Self.known().filter { $0.title.localizedCaseInsensitiveContains(string) } }
    }

    @MainActor
    private static func known() -> [ShowEntity] {
        var urls = ShowBookmarks.known()
        if let open = OpenShow.document?.fileURL {
            urls.removeAll { $0.standardizedFileURL == open.standardizedFileURL }
            urls.insert(open, at: 0)
        }
        return urls.map(ShowEntity.current(or:))
    }
}

// MARK: Cues

/// A cue in the show open, known by its number, as the stage manager calls
/// it: a shortcut for cue 12 stands by cue 12 of whichever show is open.
struct CueEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cue"
    static let defaultQuery = CueQuery()

    /// The cue's number.
    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(_ cue: Cue) {
        id = cue.number.trimmingCharacters(in: .whitespacesAndNewlines)
        title = cue.title
    }
}

/// The numbered cues of the show open, in sheet order.
struct CueQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CueEntity] {
        await MainActor.run {
            guard let show = OpenShow.controller?.show else { return [] }
            return identifiers.compactMap { number in show.index(ofNumber: number).map { CueEntity(show.cues[$0]) } }
        }
    }

    func suggestedEntities() async throws -> [CueEntity] {
        await MainActor.run { Self.cues() }
    }

    /// By number, exactly, or by the words on the cue.
    func entities(matching string: String) async throws -> [CueEntity] {
        await MainActor.run {
            let wanted = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.cues().filter { $0.id.caseInsensitiveCompare(wanted) == .orderedSame || $0.title.localizedCaseInsensitiveContains(wanted) }
        }
    }

    @MainActor
    private static func cues() -> [CueEntity] {
        (OpenShow.controller?.show.cues ?? []).map(CueEntity.init).filter { !$0.id.isEmpty }
    }
}

// MARK: Spotlight

/// Shows go into Spotlight as they are opened and saved, so searching for a
/// line on a cue finds the show.
@MainActor
enum ShowSpotlight {
    static func index(_ document: ShowDocument) {
        guard let url = document.fileURL else { return }
        let entity = ShowEntity(url: url, show: document.show)
        Task {
            try? await CSSearchableIndex.default().indexAppEntities([entity])
            // Shortcuts' and Siri's phrases name the cues of the show open.
            BackdropShortcuts.updateAppShortcutParameters()
        }
    }
}
