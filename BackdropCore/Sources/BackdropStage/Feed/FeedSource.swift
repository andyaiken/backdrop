import BackdropCore
import CoreGraphics
import QuartzCore

/// A camera the live feed can show, as the editor lists it.
public struct FeedDevice: Equatable, Sendable, Identifiable {
    /// The device's unique ID, which a cue stores.
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Where live pictures come from: the Mac's capture devices on stage, or a
/// stand-in for them in tests. Everything about turning, mirroring and
/// fitting the picture is the renderer's, so it is done once for any source.
@MainActor
public protocol FeedCamera: AnyObject {
    /// The cameras that can be chosen now.
    func devices() -> [FeedDevice]

    /// Starts the camera a cue names. This never throws or waits: a camera
    /// that can't be had is a session that says why, and a camera that is
    /// slow to start is one that has no picture yet.
    func open(_ settings: FeedSettings) -> FeedSession

    /// Calls `handler` when a camera is plugged in, comes into range, or
    /// goes, for as long as the returned token is kept.
    func observeDevices(_ handler: @escaping @MainActor () -> Void) -> AnyObject

    /// Asks the user for permission to use cameras, if that hasn't been
    /// done, so the question is asked while editing and not mid-show.
    func requestAccess()
}

/// Who is told when the cameras change: any number of watchers, each held
/// only by its token, so one that is gone is not called.
@MainActor
public final class FeedObservers {
    private final class Token {
        let handler: @MainActor () -> Void
        init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    }

    private struct Weak { weak var token: Token? }
    private var tokens: [Weak] = []

    public init() {}

    public func add(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        let token = Token(handler)
        tokens.removeAll { $0.token == nil }
        tokens.append(Weak(token: token))
        return token
    }

    public func notify() {
        for token in tokens.compactMap(\.token) { token.handler() }
    }
}

/// One camera, running.
@MainActor
public protocol FeedSession: AnyObject {
    /// When the newest picture arrived, on `CACurrentMediaTime`'s clock, or
    /// nil before the first.
    var lastFrameTime: Double? { get }

    /// Why no picture can come at all: the camera isn't there, or the app
    /// may not use it. Nil while there is, or may yet be, a picture.
    var failure: String? { get }

    /// The newest picture, as it came from the camera: not mirrored or
    /// turned.
    var frame: CGImage? { get }

    /// A layer that shows the picture as it comes, filling its bounds.
    func makePictureLayer(fit: FeedFit) -> CALayer

    /// Lets the camera go.
    func stop()
}
