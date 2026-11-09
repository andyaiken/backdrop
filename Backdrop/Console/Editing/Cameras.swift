import BackdropCore
import BackdropStage
import SwiftUI

/// The cameras the cue editor offers, kept up to date as they come and go.
/// The renderer has a camera of its own for running the show; this one only
/// lists what is there.
@MainActor
final class Cameras: ObservableObject {
    static let shared = Cameras()

    private let camera = CaptureCamera.shared
    private var observation: AnyObject?
    @Published private(set) var devices: [FeedDevice] = []

    private init() {
        observation = camera.observeDevices { [weak self] in self?.refresh() }
        devices = camera.devices()
    }

    /// Only a change is published, so asking again as a view appears doesn't
    /// redraw every view that shows the list.
    func refresh() {
        let found = camera.devices()
        if found != devices { devices = found }
    }

    /// Asks to use cameras if not yet asked, so the question comes while a
    /// camera is being chosen and not when the cue fires.
    func requestAccess() {
        camera.requestAccess()
    }
}
