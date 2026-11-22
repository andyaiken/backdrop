import AppKit
import BackdropCore
import BackdropStage

/// Choose Projector Display: one item per connected display, the show's
/// own ticked, and this Mac's display named but not choosable. The Show menu
/// and the console's projector chip both list these.
enum DisplayMenu {
    struct Item: Equatable {
        var title: String
        /// Nil for the console's own display, which the projector can't take.
        var display: DisplayIdentity?
        /// The show's chosen display.
        var chosen: Bool
    }

    /// The items, followed by a note when there is nothing to choose.
    @MainActor
    static func items(for document: ShowDocument?) -> (items: [Item], note: String?) {
        let console = document?.projector?.consoleDisplay
        let chosen = document?.show.settings.projector
        let displays = Displays.current()
        let items = displays.map { display in
            let isConsole = console.map { display.identity.bestMatch(in: [$0]) != nil } ?? false
            return Item(title: display.identity.name + (isConsole ? " \u{2014} this Mac\u{2019}s own display" : ""),
                        display: isConsole ? nil : display.identity,
                        chosen: chosen.map { $0.bestMatch(in: [display.identity]) != nil } ?? false)
        }
        return (items, displays.count < 2 ? "Connect the projector to choose it here" : nil)
    }
}
