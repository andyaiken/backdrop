import BackdropCore
import CoreGraphics
import QuartzCore

/// A camera that is a test card: a stand-in for a real one that needs no
/// hardware. Its picture is lopsided on purpose, so which way up and which
/// way round it ends is something a test can see.
///
/// The left half is red and the right half blue; the top left corner is
/// green; the bottom right corner is white.
@MainActor
public final class PatternCamera: FeedCamera {
    public nonisolated static let deviceID = "pattern"

    public var present = true {
        didSet { if present != oldValue { observers.notify() } }
    }
    private let observers = FeedObservers()
    /// Sessions opened, so a test can see what was kept and what was let go.
    public private(set) var sessions: [PatternSession] = []

    public init() {}

    public func devices() -> [FeedDevice] {
        present ? [FeedDevice(id: Self.deviceID, name: "Test pattern")] : []
    }

    public func open(_ settings: FeedSettings) -> FeedSession {
        let session = PatternSession(available: present && settings.device == Self.deviceID, name: settings.deviceName)
        sessions.append(session)
        return session
    }

    public func observeDevices(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        observers.add(handler)
    }

    public func requestAccess() {}
}

@MainActor
public final class PatternSession: FeedSession {
    public static let image: CGImage = {
        let w = 160, h = 90
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h - 20, width: 20, height: 20))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: w - 20, y: 0, width: 20, height: 20))
        return ctx.makeImage()!
    }()

    private let available: Bool
    private let name: String
    private(set) public var isStopped = false
    private let opened = CACurrentMediaTime()
    /// A test sets this to stand for a feed that has stopped arriving.
    public var stalled = false
    private var stalledAt: Double?

    init(available: Bool, name: String) {
        self.available = available
        self.name = name
    }

    public var failure: String? {
        available ? nil : "\(name.isEmpty ? "The camera" : name) isn\u{2019}t connected."
    }

    public var lastFrameTime: Double? {
        guard available, !isStopped else { return nil }
        if stalled {
            if stalledAt == nil { stalledAt = CACurrentMediaTime() - 5 }
            return stalledAt
        }
        stalledAt = nil
        return CACurrentMediaTime()
    }

    public var frame: CGImage? { available ? Self.image : nil }

    public func makePictureLayer(fit: FeedFit) -> CALayer {
        let layer = StillLayer()
        layer.contents = Self.image
        layer.contentsGravity = fit == .fit ? .resizeAspect : .resizeAspectFill
        layer.masksToBounds = true
        return layer
    }

    public func stop() { isStopped = true }
}
