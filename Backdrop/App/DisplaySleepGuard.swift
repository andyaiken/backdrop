import Foundation
import IOKit.pwr_mgt

/// Keeps the displays awake.
final class DisplaySleepGuard {
    private var assertion = IOPMAssertionID(0)
    private var held = false

    func hold(reason: String) {
        guard !held else { return }
        held = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertion
        ) == kIOReturnSuccess
    }

    func release() {
        guard held else { return }
        IOPMAssertionRelease(assertion)
        held = false
    }
}
