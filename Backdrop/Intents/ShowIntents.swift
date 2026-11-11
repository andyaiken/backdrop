import AppIntents
import AppKit
import BackdropCore
import BackdropStage

/// Why an intent couldn't do what it was asked.
enum ShowIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noShow
    case editMode

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noShow: "Backdrop has no show open."
        case .editMode: "Backdrop is in edit mode. Shortcuts only act on the show in show mode, so nothing in the booth changes while it is being edited."
        }
    }
}

/// The show open, in show mode, for an intent that acts on it, as show
/// control does: whatever the status line says, the shortcut says too.
@MainActor
private func showInShowMode() throws -> ShowController {
    guard let controller = OpenShow.controller else { throw ShowIntentError.noShow }
    guard controller.mode == .show else { throw ShowIntentError.editMode }
    return controller
}

/// What the status line says the intent did.
private let byShortcut = "a shortcut"

// MARK: Open Show

/// Opens a show, in show mode, ready for GO. Spotlight runs it when a show
/// it found is chosen.
struct OpenShowIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Show"
    static let description = IntentDescription("Opens a show in Backdrop, in show mode, ready for GO.")

    @Parameter(title: "Show")
    var target: ShowEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        // Through the bookmark kept when the show was last open: sandboxed,
        // Backdrop may only open a show it has been given. Opening may first
        // ask about a live projector on the console, so the shortcut doesn't
        // wait for it.
        let url = ShowBookmarks.access(target.url) ?? target.url
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        return .result()
    }
}

// MARK: Stand By Cue

/// Stands a cue by, ready for GO. It fires nothing: GO stays with the
/// operator, or with show control.
struct StandByCueIntent: AppIntent {
    static let title: LocalizedStringResource = "Stand By Cue"
    static let description = IntentDescription("Stands a cue by in the show open in Backdrop, ready for GO. It fires nothing, and only acts in show mode.")

    @Parameter(title: "Cue")
    var cue: CueEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Stand by \(\.$cue)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = try showInShowMode()
        controller.perform(.standBy(cue: cue.id), from: byShortcut)
        return .result(dialog: "\(controller.message ?? "Cue \(cue.id) is standing by.")")
    }
}

// MARK: Blackout

enum BlackoutChange: String, AppEnum {
    case on, off, toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Blackout"
    static let caseDisplayRepresentations: [BlackoutChange: DisplayRepresentation] = [
        .on: "On", .off: "Off", .toggle: "On or Off, Whichever It Isn\u{2019}t",
    ]
}

/// Blacks out the projector, or brings the picture back.
struct BlackoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Blackout"
    static let description = IntentDescription("Blacks out Backdrop\u{2019}s projector, or brings the picture back. Only acts in show mode.")

    @Parameter(title: "Blackout", default: .on)
    var change: BlackoutChange

    static var parameterSummary: some ParameterSummary {
        Summary("Turn blackout \(\.$change)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = try showInShowMode()
        let on = switch change {
        case .on: true
        case .off: false
        case .toggle: !controller.playhead.blackout
        }
        controller.perform(.blackout(on), from: byShortcut)
        return .result(dialog: "\(controller.message ?? (on ? "Blacked out." : "Picture back."))")
    }
}

// MARK: Phrases

/// What Spotlight, Siri and the Shortcuts app offer without a shortcut
/// being made first.
struct BackdropShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenShowIntent(), phrases: [
            "Open \(\.$target) in \(.applicationName)",
            "Open a show in \(.applicationName)",
        ], shortTitle: "Open Show", systemImageName: "theatermasks")
        AppShortcut(intent: StandByCueIntent(), phrases: [
            "Stand by \(\.$cue) in \(.applicationName)",
            "Stand by a cue in \(.applicationName)",
        ], shortTitle: "Stand By Cue", systemImageName: "forward.end")
        AppShortcut(intent: BlackoutIntent(), phrases: [
            "Blackout in \(.applicationName)",
            "Black out the projector in \(.applicationName)",
        ], shortTitle: "Blackout", systemImageName: "moon")
    }
}
