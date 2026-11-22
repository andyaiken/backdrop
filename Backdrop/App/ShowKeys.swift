import AppKit
import BackdropStage

/// What the show keys ask of the console, wherever they are pressed.
@MainActor
protocol ConsoleKeys: AnyObject {
    /// G: the Go To panel, with the console brought forward if it isn't.
    func showGoTo()
    /// ?: every key, over the console, or away again.
    func toggleKeyHelp()
    /// Escape: closes the key help. False if it wasn't showing.
    func closeKeyHelp() -> Bool
}

/// The show keys, the same in every window. Returns false only for keys
/// that belong to the menus.
///
/// Space is the only key that fires a cue. The number keys do nothing on
/// their own: a cue number is typed into Go To, which G opens.
enum ShowKeys {
    @MainActor
    static func handle(_ event: NSEvent, controller: ShowController, console: ConsoleKeys?) -> Bool {
        // Command-key combinations belong to the menus.
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        // Holding a key down must never fire a run of cues. Every other plain
        // key is swallowed, handled or not: an unhandled key makes the Mac
        // beep, and the beep is heard in the room.
        if event.isARepeat { return true }

        switch Int(event.keyCode) {
        case 49: controller.go()                                // space
        case 124, 125, 121: controller.standByNext()            // → ↓ PageDown
        case 123, 126, 116: controller.standByPrevious()        // ← ↑ PageUp
        case 53: _ = console?.closeKeyHelp()                    // Escape
        default:
            // Shift is allowed, so ? can be typed.
            guard let c = event.charactersIgnoringModifiers?.lowercased().first else { return true }
            switch c {
            case "g": console?.showGoTo()
            case "r": controller.rerun()
            case "b": controller.toggleBlackout()
            case "?": console?.toggleKeyHelp()
            default: break
            }
        }
        return true
    }
}
