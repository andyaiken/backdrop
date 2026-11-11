import AppKit
import BackdropStage
import IOKit.ps
import notify

/// Watches the Mac for what could spoil a performance, and keeps
/// `conditions` up to date for the console's warnings. Each condition is
/// read again when macOS says it has changed, never polled. The rules for
/// what to say are in `BoothConditions`; this only reads the Mac.
@MainActor
final class BoothWatch {
    private(set) var conditions = BoothConditions() {
        didSet { if conditions != oldValue { onChange() } }
    }

    /// Called when anything in `conditions` changes.
    var onChange: () -> Void = {}

    /// The console's window. Mirroring matters when it is the console's
    /// display that is mirrored.
    weak var console: NSWindow? {
        didSet { readDisplays() }
    }

    /// Where the show is saved. Its disk is looked at when this changes.
    var showURL: URL? {
        didSet {
            guard showURL != oldValue else { return }
            conditions.showDisk = showURL.flatMap(Self.disk(of:))
        }
    }

    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var powerToken = NOTIFY_TOKEN_INVALID

    init() {
        let centre = NotificationCenter.default
        func observe(_ name: Notification.Name, _ read: @escaping @MainActor (BoothWatch) -> Void) {
            observers.append(centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { read(self) } }
            })
        }
        // A turn of the run loop later, once AppKit has finished rearranging
        // the displays.
        observe(NSApplication.didChangeScreenParametersNotification) { watch in
            DispatchQueue.main.async { [weak watch] in watch?.readDisplays() }
        }
        observe(NSApplication.didBecomeActiveNotification) { $0.readActive() }
        observe(NSApplication.didResignActiveNotification) { $0.readActive() }
        observe(ProcessInfo.thermalStateDidChangeNotification) { $0.readHeat() }
        observe(.NSProcessInfoPowerStateDidChange) { $0.readLowPowerMode() }
        observe(ShowControl.didChange) { $0.readShowControl() }
        // Any change to any power source: plugged in or out, and the
        // battery's level as it runs down.
        notify_register_dispatch(kIOPSNotifyAnyPowerSource, &powerToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.readPower() }
        }

        readDisplays()
        readActive()
        readHeat()
        readLowPowerMode()
        readPower()
        readShowControl()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if notify_is_valid_token(powerToken) { notify_cancel(powerToken) }
    }

    // MARK: Reading the Mac

    /// Also called when the console moves to another display.
    func readDisplays() {
        let screen = console?.screen ?? NSScreen.screens.first
        conditions.consoleMirrored = screen.map { Self.everyDisplayMirrors($0.displayID) } ?? false
    }

    private func readActive() {
        conditions.inBackground = !NSApp.isActive
    }

    private func readHeat() {
        switch ProcessInfo.processInfo.thermalState {
        case .serious: conditions.heat = .throttled
        case .critical: conditions.heat = .critical
        default: conditions.heat = .normal
        }
    }

    private func readLowPowerMode() {
        conditions.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func readPower() {
        conditions.power = Self.power()
    }

    private func readShowControl() {
        conditions.showControl = ShowControl.shared.problem
    }

    /// Whether every connected display shows this one's picture: there is
    /// more than one, and they are all in the same mirror set. A mirror
    /// elsewhere, such as the projector's picture on a stage manager's
    /// monitor, leaves the projector a display of its own and is fine.
    static func everyDisplayMirrors(_ display: CGDirectDisplayID) -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 1 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        // A display that mirrors another names the one it mirrors; the one
        // mirrored names none.
        func source(_ d: CGDirectDisplayID) -> CGDirectDisplayID {
            let mirrored = CGDisplayMirrorsDisplay(d)
            return mirrored == kCGNullDirectDisplay ? d : mirrored
        }
        let console = source(display)
        return displays.prefix(Int(count)).allSatisfy { source($0) == console }
    }

    /// Mains, or a battery or UPS with the share of it left.
    static func power() -> BoothConditions.Power {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?,
              providing != kIOPSACPowerValue else { return .mains }
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSPowerSourceStateKey] as? String == providing,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return .battery(percent: current * 100 / max)
        }
        return .battery(percent: nil)
    }

    /// The disk a show is on, when it isn't the Mac's internal one. Nothing
    /// is said when macOS can't tell.
    static func disk(of url: URL) -> BoothConditions.ShowDisk? {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsInternalKey, .volumeLocalizedNameKey]) else {
            return nil
        }
        let name = values.volumeLocalizedName ?? url.deletingLastPathComponent().lastPathComponent
        if values.volumeIsLocal == false { return .network(name) }
        if values.volumeIsInternal == false { return .external(name) }
        return nil
    }
}
