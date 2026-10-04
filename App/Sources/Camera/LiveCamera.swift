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
        /// The user said no, or the phone's restrictions do.
        case notAllowed
        /// There is no camera, as in the Simulator, or it would not start.
        case unavailable
        /// Another app, or a call, has the camera for now.
        case interrupted
    }

    private(set) var state = State.starting
    /// What the camera in use can do, once it has started.
    private(set) var capabilities: Camera.Capabilities?
    /// The viewfinder's pictures.
    let feed: ViewfinderFeed
    private let camera = Camera()
    private let viewfinder: Viewfinder

    init() {
        let feed = ViewfinderFeed()
        self.feed = feed
        viewfinder = Viewfinder(feed: feed)
    }

    /// Starts the camera facing a way, or turns it round, asking for
    /// permission first if the user has not been asked.
    func start(_ position: Camera.Position) async {
        guard Camera.exists else {
            state = .unavailable
            return
        }
        guard await Self.isAllowed() else {
            state = .notAllowed
            return
        }
        do {
            capabilities = try await camera.start(position, frames: viewfinder)
            state = .running
        } catch {
            state = .unavailable
        }
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
        let angle = held.photoRotationAngle(frontCamera: mirrored)
        let data = try await camera.takePhoto(flash: flash, rotationAngle: angle)
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

    func interruptionEnded() {
        if state == .interrupted {
            state = .running
        }
    }
}
