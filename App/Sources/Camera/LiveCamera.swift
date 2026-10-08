import AVFoundation
import C64Core
import CoreGraphics
import Observation

/// The camera as the camera screen uses it: whether it is allowed and
/// working, what it can do, and the viewfinder's pictures.
@Observable
final class LiveCamera {
    enum State: Equatable {
        /// Asking for permission, or starting.
        case starting
        case running
        /// Switched off with the TV, which saves the battery.
        case off
        /// The user said no, or the phone's restrictions do.
        case notAllowed
        /// There is no camera, as in the Simulator, or it would not start.
        case unavailable
        /// Another app or a call has the camera for now, or the app is away.
        case interrupted
    }

    private(set) var state = State.starting
    /// What the camera in use can do, once it has started.
    private(set) var capabilities: Camera.Capabilities?
    /// The viewfinder's pictures.
    let feed: ViewfinderFeed
    private let camera = Camera()
    private let viewfinder: Viewfinder
    /// How many times the camera was switched off. A start or a check that
    /// it was switched off during leaves the state alone, even if it was
    /// switched back on since: the starts since set it.
    @ObservationIgnored private var switchOffs = 0

    init() {
        let feed = ViewfinderFeed()
        self.feed = feed
        viewfinder = Viewfinder(feed: feed)
    }

    /// Starts the camera facing a way, or turns it round, asking for
    /// permission first if the user has not been asked.
    ///
    /// Starting it again checks that it runs, and starts it if it stopped.
    /// iOS may stop it while the app is away, when it resets its media
    /// services, so the camera starts again whenever the app comes back,
    /// after an interruption, after such a reset, and after a failed shot.
    /// A camera switched off with the TV stays off: only `switchOn` starts
    /// it again.
    func start(_ position: Camera.Position) async {
        guard state != .off else { return }
        let switchOffs = self.switchOffs
        guard Camera.exists else {
            state = .unavailable
            return
        }
        let allowed = await Self.isAllowed()
        guard self.switchOffs == switchOffs else { return }
        guard allowed else {
            state = .notAllowed
            return
        }
        do {
            capabilities = try await camera.start(position, frames: viewfinder)
            let activity = await camera.activity
            // Switched off meanwhile, the camera stopped after this start.
            guard self.switchOffs == switchOffs else { return }
            state = Self.state(of: activity)
        } catch {
            if self.switchOffs == switchOffs {
                state = .unavailable
            }
        }
    }

    /// Switches the camera off with the TV, which saves the battery. It
    /// stays off, whatever happens, until `switchOn`.
    func switchOff() {
        guard state != .off else { return }
        state = .off
        switchOffs += 1
        Task { await camera.stop() }
    }

    /// Switches the camera back on with the TV. The viewfinder starts over:
    /// the TV's warm-up waits for its first picture since.
    func switchOn(_ position: Camera.Position) {
        guard state == .off else { return }
        state = .starting
        feed.clear()
        Task { await start(position) }
    }

    /// The state the camera is in when its session does something.
    static func state(of activity: Camera.Activity) -> State {
        switch activity {
        case .running: .running
        case .interrupted: .interrupted
        case .stopped: .unavailable
        }
    }

    /// The camera's session stopped on an error
    /// (`AVCaptureSession.runtimeErrorNotification`). When iOS reset its media
    /// services, the camera starts again. Other errors leave it as it is until
    /// the app comes back or the capture key is pressed, so that a camera
    /// that keeps failing is not started over and over.
    func sessionFailed(_ error: AVError.Code?, position: Camera.Position) async {
        guard state != .off else { return }
        if Self.startsAgain(after: error) {
            await start(position)
        } else {
            let switchOffs = self.switchOffs
            let activity = await camera.activity
            if self.switchOffs == switchOffs {
                state = Self.state(of: activity)
            }
        }
    }

    /// Whether the camera starts again by itself after its session stopped
    /// on an error: only when iOS reset its media services, as in Apple's
    /// AVCam sample.
    static func startsAgain(after error: AVError.Code?) -> Bool {
        error == .mediaServicesWereReset
    }

    private static func isAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Sets what the viewfinder makes of frames, or nil to drop them.
    func show(_ settings: Viewfinder.Settings?) {
        viewfinder.use(settings)
    }

    /// Zooms to a value as the buttons show it.
    func zoom(to zoom: Double, animated: Bool) {
        Task { await camera.zoom(to: zoom, animated: animated) }
    }

    /// Focuses and meters on a point of the picture, across and down from 0
    /// to 1, with frames seen in an orientation.
    func focus(onPicturePoint point: CGPoint, orientation: ImageOrientation) {
        guard let size = viewfinder.lastFrameSize else { return }
        let cameraPoint = Viewfinder.cameraPoint(
            ofPicturePoint: point, frameWidth: size.width, frameHeight: size.height, orientation: orientation)
        Task { await camera.focus(at: cameraPoint) }
    }

    /// Makes pictures brighter or darker than the camera's own exposure, in
    /// stops.
    func setExposureBias(_ bias: Float) {
        Task { await camera.setExposureBias(bias) }
    }

    /// Takes a photo, upright as the phone is held, and decodes it. A front
    /// camera's photo is mirrored, like its viewfinder.
    func takePhoto(flash: Bool, held: HeldOrientation) async throws -> Photo {
        let mirrored = capabilities?.position == .front
        let angle = held.uprightAngle(frontCamera: mirrored)
        let data = try await camera.takePhoto(flash: flash, uprightAngle: angle)
        let photo = await Task.detached(priority: .userInitiated) {
            Photo(data: data, mirrored: mirrored)
        }.value
        guard let photo else { throw Camera.Failure.noPhoto }
        return photo
    }

    func wasInterrupted() {
        if state == .running {
            state = .interrupted
        }
    }

    /// The interruption ended. The session runs again by itself, unless iOS
    /// stopped it meanwhile, as when it resets its media services while the
    /// app is away: then it starts again.
    func interruptionEnded(_ position: Camera.Position) async {
        guard state == .interrupted else { return }
        await start(position)
    }
}
