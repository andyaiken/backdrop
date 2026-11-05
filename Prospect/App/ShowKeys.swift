import AppKit
import ProspectStage

/// The show keys, the same in every window. Returns false only for keys
/// that belong to the menus.
enum ShowKeys {
    @MainActor
    static func handle(_ event: NSEvent, controller: ShowController) -> Bool {
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
        case 36, 76: controller.commitEntry()                   // Return, Enter
        case 53: controller.clearEntry()                        // Escape
        case 51, 117: controller.deleteBackward()               // Delete, forward delete
        default:
            guard let c = event.charactersIgnoringModifiers?.lowercased().first else { return true }
            switch c {
            case "0"..."9", ".": controller.type(c)
            case "r": controller.rerun()
            case "b": controller.toggleBlackout()
            default: break
            }
        }
        return true
    }
}
