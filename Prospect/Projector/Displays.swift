import AppKit
import ProspectCore
import ProspectStage

/// Connected displays, described for projector placement.
enum Displays {
    static func info(for screen: NSScreen) -> DisplayInfo {
        let id = screen.displayID
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        return DisplayInfo(
            identity: DisplayIdentity(uuid: uuid, name: screen.localizedName,
                                      vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id)),
            frame: screen.frame,
            // The first screen is the one with the menu bar.
            isMain: screen == NSScreen.screens.first
        )
    }

    static func current() -> [DisplayInfo] {
        NSScreen.screens.map(info(for:))
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
