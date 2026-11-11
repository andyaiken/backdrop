import Foundation

/// Keeps the displays awake while a show is open, and tells macOS that
/// Backdrop's timing matters: no App Nap, and no timers held back to save
/// energy.
final class DisplaySleepGuard {
    private var activity: NSObjectProtocol?

    func hold(reason: String) {
        guard activity == nil else { return }
        // User-initiated also keeps the Mac itself from idle sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled, .latencyCritical], reason: reason)
    }

    func release() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
