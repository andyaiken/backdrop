@preconcurrency import AVFoundation
import BackdropCore
import QuartzCore
import VideoToolbox

/// The Mac's cameras: built in, plugged in (a webcam, or a capture card
/// taking an HDMI camera), an iPhone by Continuity Camera, or a virtual
/// camera that another app provides for a wireless source such as NDI.
@MainActor
public final class CaptureCamera: FeedCamera {
    /// The camera everything on stage shares. Two sessions opened on one
    /// device is a gamble with some capture hardware, so the stage's
    /// renderers, and the console's previews of what is next, all come here
    /// and are given the one running session.
    public static let shared = CaptureCamera()

    private let observers = FeedObservers()
    private nonisolated(unsafe) var notifications: [NSObjectProtocol] = []
    /// Sessions running, by camera, and how many are using each.
    private var running: [String: CaptureSession] = [:]

    public init() {
        let centre = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            notifications.append(centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.observers.notify() }
            })
        }
    }

    deinit {
        for observer in notifications { NotificationCenter.default.removeObserver(observer) }
    }

    static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified)
    }

    public func devices() -> [FeedDevice] {
        Self.discovery().devices.map { FeedDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    public func observeDevices(_ handler: @escaping @MainActor () -> Void) -> AnyObject {
        observers.add(handler)
    }

    /// The session for a camera, started if nothing is using it. One that has
    /// failed or stopped delivering is not shared: asking again is asking to
    /// start it afresh.
    public func open(_ settings: FeedSettings) -> FeedSession {
        let key = settings.device + "\u{1}" + settings.deviceName
        let session: CaptureSession
        if let existing = running[key], existing.isUsable {
            session = existing
        } else {
            session = CaptureSession(settings)
            running[key] = session
            session.onIdle = { [weak self, weak session] in
                guard let self, let session, self.running[key] === session else { return }
                self.running.removeValue(forKey: key)
            }
        }
        return SessionHandle(session)
    }

    public func requestAccess() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { _ in }
    }
}

/// One user's hold on a shared session. The camera runs while any holds
/// remain, and is let go when the last is.
@MainActor
final class SessionHandle: FeedSession {
    private let session: CaptureSession
    private var released = false

    init(_ session: CaptureSession) {
        self.session = session
        session.users += 1
    }

    var lastFrameTime: Double? { session.lastFrameTime }
    var failure: String? { session.failure }
    var frame: CGImage? { session.frame }

    func makePictureLayer(fit: FeedFit) -> CALayer {
        session.makePictureLayer(fit: fit)
    }

    func stop() {
        guard !released else { return }
        released = true
        session.users -= 1
        if session.users <= 0 { session.shutDown() }
    }
}

/// The newest picture off the camera, written on the capture queue and read
/// on the main thread.
private final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var time: Double?
    private var image: CGImage?

    func store(_ buffer: CVPixelBuffer) {
        lock.lock()
        self.buffer = buffer
        image = nil
        time = CACurrentMediaTime()
        lock.unlock()
    }

    var lastTime: Double? {
        lock.lock()
        defer { lock.unlock() }
        return time
    }

    /// The newest picture as an image, made once however often it is asked for.
    var cgImage: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let image { return image }
        guard let buffer else { return nil }
        var made: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &made)
        image = made
        return made
    }
}

/// A preview layer with no implicit animations, like every layer on stage.
final class StillPreviewLayer: AVCaptureVideoPreviewLayer {
    override func action(forKey event: String) -> (any CAAction)? {
        nil
    }
}

@MainActor
final class CaptureSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let box = FrameBox()
    private let queue = DispatchQueue(label: "backdrop.feed.capture")
    private let settings: FeedSettings
    private var layers: [WeakLayer] = []
    private(set) var failure: String?
    /// How many handles hold this session, and what to tell the camera when
    /// it is let go.
    var users = 0
    var onIdle: (() -> Void)?
    private let openedAt = CACurrentMediaTime()

    private struct WeakLayer {
        weak var layer: AVCaptureVideoPreviewLayer?
    }

    init(_ settings: FeedSettings) {
        self.settings = settings
        super.init()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.configure() } else { self.failure = Self.denied }
                }
            }
        default:
            failure = Self.denied
        }
    }

    private static let denied = "Backdrop isn\u{2019}t allowed to use the camera. Allow it in System Settings, under Privacy & Security, Camera."

    var lastFrameTime: Double? { box.lastTime }

    /// Whether another user may be given it: not failed, and either still
    /// starting or still delivering pictures.
    var isUsable: Bool {
        guard failure == nil else { return false }
        let now = CACurrentMediaTime()
        guard let last = lastFrameTime else { return now - openedAt < FeedRenderer.noPictureAfter }
        return now - last < FeedRenderer.staleAfter
    }
    var frame: CGImage? { box.cgImage }

    /// The device a cue means: by ID, or failing that by name, since a
    /// camera may have another ID on another Mac.
    private func device() -> AVCaptureDevice? {
        if let device = AVCaptureDevice(uniqueID: settings.device) { return device }
        guard !settings.deviceName.isEmpty else { return nil }
        return CaptureCamera.discovery().devices.first { $0.localizedName == settings.deviceName }
    }

    private func configure() {
        guard let device = device() else {
            let name = settings.deviceName.isEmpty ? "The camera" : settings.deviceName
            failure = "\(name) isn\u{2019}t connected."
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CocoaError(.fileReadUnknown) }
            session.beginConfiguration()
            // The picture is asked for at 1080p where the camera has it, and
            // left alone where it doesn't, rather than let the system change
            // it with the light.
            if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
            session.addInput(input)
            // A frame to keep for a crossfade, and for the last picture
            // when the feed is lost.
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
        } catch {
            failure = "\(device.localizedName) couldn\u{2019}t be opened."
            return
        }
        for entry in layers { entry.layer.map(normalise) }
        let session = session
        queue.async { session.startRunning() }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        box.store(pixels)
    }

    func makePictureLayer(fit: FeedFit) -> CALayer {
        let layer = StillPreviewLayer(session: session)
        layer.videoGravity = fit == .fit ? .resizeAspect : .resizeAspectFill
        layers.removeAll { $0.layer == nil }
        layers.append(WeakLayer(layer: layer))
        normalise(layer)
        return layer
    }

    /// The picture as the camera sends it. The system mirrors some
    /// cameras' previews on its own; the cue's own setting is the only
    /// mirroring there is.
    private func normalise(_ layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
    }

    func shutDown() {
        let session = session
        queue.async { session.stopRunning() }
        onIdle?()
    }
}
