import AVFoundation
import CoreGraphics
import CoreMedia

/// The camera (docs/UX.md, sections 2 to 5): a capture session with one of
/// the phone's cameras, a video data output for the viewfinder and a photo
/// output for shots.
///
/// Everything runs on the camera's own queue, since starting the session and
/// configuring a camera can block. Frames go to the viewfinder on another
/// queue, so converting them never holds the camera up.
///
/// Frames come sideways, in the orientation AVFoundation gives them by
/// default, and never mirrored: the viewfinder turns them as the phone is held
/// and mirrors the front camera's itself (`HeldOrientation.uprightTurns`).
/// Their rotation angle is left alone: the iPhone 17's front camera, whose
/// sensor is mounted upright, needs a different angle from other cameras to
/// keep the usual orientation, and AVFoundation sets it. Photos are stored as
/// the sensor reads them, with an orientation for the way the phone was held.
/// Their rotation angle counts from the sensor, so a photo gets the turn
/// AVFoundation gives the frames as well (`photoRotationAngle`).
actor Camera {
    /// Which way a camera faces.
    nonisolated enum Position: Sendable {
        case back
        case front
    }

    /// What the camera in use can do.
    nonisolated struct Capabilities: Equatable, Sendable {
        var position: Position
        /// Zoom as the buttons show it: 1 for the main camera, 0.5 for the
        /// ultra wide one.
        var zoomRange: ClosedRange<Double>
        /// The zoom buttons' values.
        var zoomPresets: [Double]
    }

    nonisolated enum Failure: Error {
        /// No camera faces that way.
        case noCamera
        /// The session would not take the camera.
        case cannotConfigure
        /// The session would not run.
        case cannotStart
        /// The camera took no photo.
        case noPhoto
    }

    /// Whether the phone has a camera at all: the Simulator has none.
    nonisolated static var exists: Bool { AVCaptureDevice.default(for: .video) != nil }

    private let queue = DispatchSerialQueue(label: "com.camerac64.camera")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var capabilities: Capabilities?
    /// The device's zoom factor for 1×: on a set of cameras whose zoom starts
    /// with the ultra wide one, the factor where the main camera takes over.
    private var mainZoomFactor: CGFloat = 1

    /// Starts the camera facing a way, sending its frames to the viewfinder,
    /// and says what it can do.
    ///
    /// Starting it again checks that it runs. When iOS resets its media
    /// services, as it may while the app is away, it stops the session and
    /// leaves it to the app to start it again (Apple's AVCam sample does the
    /// same), which may take a new input for the camera.
    func start(_ position: Position, frames viewfinder: Viewfinder) throws -> Capabilities {
        if session.outputs.isEmpty {
            try addOutputs(sendingFramesTo: viewfinder)
        }
        var capabilities: Capabilities
        if let current = self.capabilities, current.position == position {
            capabilities = current
        } else {
            capabilities = try use(position)
            self.capabilities = capabilities
        }
        // An interrupted session runs again by itself when the interruption
        // ends.
        if !session.isRunning && !session.isInterrupted {
            session.startRunning()
            if !session.isRunning && !session.isInterrupted {
                capabilities = try use(position)
                self.capabilities = capabilities
                session.startRunning()
            }
        }
        guard session.isRunning || session.isInterrupted else { throw Failure.cannotStart }
        return capabilities
    }

    /// Stops the camera, as when the TV switches off, which saves the
    /// battery. The session no longer runs again by itself when an
    /// interruption ends: only `start` runs it again.
    func stop() {
        session.stopRunning()
    }

    /// What the session does.
    nonisolated enum Activity: Sendable {
        case running
        /// Another app or a call has the camera for now, or the app is away.
        case interrupted
        case stopped
    }

    var activity: Activity {
        if session.isInterrupted {
            return .interrupted
        }
        return session.isRunning ? .running : .stopped
    }

    /// Zooms to a value as the buttons show it, smoothly if `animated`.
    func zoom(to zoom: Double, animated: Bool) {
        guard let device = input?.device else { return }
        do { try device.lockForConfiguration() } catch { return }
        defer { device.unlockForConfiguration() }
        let factor = min(
            max(CGFloat(zoom) * mainZoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        if animated {
            device.ramp(toVideoZoomFactor: factor, withRate: 6)
        } else {
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = factor
        }
    }

    /// Focuses and meters on a point of the camera's picture, measured across
    /// and down from 0 to 1 as the camera measures it, and sets the exposure
    /// back to the camera's own.
    func focus(at point: CGPoint) {
        guard let device = input?.device else { return }
        do { try device.lockForConfiguration() } catch { return }
        defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusPointOfInterest = point
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposurePointOfInterest = point
            device.exposureMode = .continuousAutoExposure
        }
        device.setExposureTargetBias(0, completionHandler: nil)
    }

    /// Makes pictures brighter or darker than the camera's own exposure, in
    /// stops.
    func setExposureBias(_ bias: Float) {
        guard let device = input?.device else { return }
        do { try device.lockForConfiguration() } catch { return }
        defer { device.unlockForConfiguration() }
        let bias = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
        device.setExposureTargetBias(bias, completionHandler: nil)
    }

    /// Takes a photo and returns its file, a HEIC where the camera can make
    /// one. `uprightAngle` is the turn the frames need to be upright as the
    /// phone is held: the photo is stored as the sensor reads it, with an
    /// orientation that turns it upright.
    func takePhoto(flash: Bool, uprightAngle: CGFloat) async throws -> Data {
        // Without a working connection, as while the camera turns round, the
        // photo output would raise an exception.
        guard let connection = photoOutput.connection(with: .video), connection.isEnabled && connection.isActive
        else { throw Failure.noPhoto }
        // How far AVFoundation turns the frames from the sensor's own
        // orientation to send them sideways, as every camera's come: 0 but for
        // a sensor mounted another way, like the iPhone 17's front camera's.
        // Nothing else sets it.
        let framesRotationAngle = videoOutput.connection(with: .video)?.videoRotationAngle ?? 0
        let angle = Self.photoRotationAngle(upright: uprightAngle, framesRotationAngle: framesRotationAngle)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        let settings =
            photoOutput.availablePhotoCodecTypes.contains(.hevc)
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc]) : AVCapturePhotoSettings()
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        if flash && photoOutput.supportedFlashModes.contains(.on) {
            settings.flashMode = .on
        }
        // The photo output does not keep its delegate, so this does until
        // the photo is taken.
        let delegate = PhotoDelegate()
        let data = try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
        withExtendedLifetime(delegate) {}
        return data
    }

    // MARK: - Setting up

    private func addOutputs(sendingFramesTo viewfinder: Viewfinder) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // A frame that comes while the viewfinder is busy is dropped.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(viewfinder, queue: viewfinder.queue)
        guard session.canAddOutput(videoOutput) else { throw Failure.cannotConfigure }
        session.addOutput(videoOutput)
        guard session.canAddOutput(photoOutput) else { throw Failure.cannotConfigure }
        session.addOutput(photoOutput)
    }

    /// Puts the camera facing a way in the session, in place of the one
    /// there, and says what it can do.
    private func use(_ position: Position) throws -> Capabilities {
        guard let device = Self.camera(facing: position) else { throw Failure.noCamera }
        let newInput = try AVCaptureDeviceInput(device: device)
        let format = Self.viewfinderFormat(of: device)

        session.beginConfiguration()
        do {
            defer { session.commitConfiguration() }
            if let input {
                session.removeInput(input)
            }
            let preset: AVCaptureSession.Preset = format == nil ? .photo : .inputPriority
            if session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
            }
            guard session.canAddInput(newInput) else {
                if let input, session.canAddInput(input) {
                    session.addInput(input)
                }
                throw Failure.cannotConfigure
            }
            session.addInput(newInput)
            input = newInput
            if let format, (try? device.lockForConfiguration()) != nil {
                device.activeFormat = format
                // No faster than the viewfinder converts.
                let ranges = format.videoSupportedFrameRateRanges
                if ranges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                }
                device.unlockForConfiguration()
            }
        }

        // Once the session has settled on the camera's format, which a
        // preset only does as the configuration ends.
        mainZoomFactor = Self.mainZoomFactor(of: device)
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = min(
                max(mainZoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
        if let dimensions = Self.photoDimensions(of: device.activeFormat) {
            photoOutput.maxPhotoDimensions = dimensions
        }
        Self.unmirror(videoOutput.connection(with: .video))
        Self.unmirror(photoOutput.connection(with: .video))
        // AVFoundation may turn the iPhone 17's front camera's photos to match
        // earlier front cameras', at a cost (WWDC26, session 341), but those
        // cameras' angles left this app's shots a quarter turn off there.
        // With that off, a photo's angle counts from the sensor, as for every
        // camera.
        if photoOutput.isCameraSensorOrientationCompensationSupported {
            photoOutput.isCameraSensorOrientationCompensationEnabled = false
        }

        let low = Double(device.minAvailableVideoZoomFactor / mainZoomFactor)
        let high = Double(
            min(device.maxAvailableVideoZoomFactor, CGFloat(CameraZoom.limit) * mainZoomFactor) / mainZoomFactor)
        let range = low...max(low, high)
        let lenses = device.virtualDeviceSwitchOverVideoZoomFactors.map {
            Double(truncating: $0) / Double(mainZoomFactor)
        }
        return Capabilities(
            position: position, zoomRange: range, zoomPresets: CameraZoom.presets(in: range, lenses: lenses))
    }

    /// The rotation angle that stores a photo upright, when `upright` turns
    /// the frames upright and AVFoundation turns the frames by
    /// `framesRotationAngle` from the sensor's own orientation: photos' angles
    /// count from the sensor. On the iPhone 17's front camera, they come out a
    /// quarter turn less than on earlier front cameras, as AVFoundation's
    /// rotation coordinator's do.
    nonisolated static func photoRotationAngle(upright: CGFloat, framesRotationAngle: CGFloat) -> CGFloat {
        let sum = (upright + framesRotationAngle).truncatingRemainder(dividingBy: 360)
        return sum < 0 ? sum + 360 : sum
    }

    /// Keeps an output's pictures unmirrored: the viewfinder mirrors the front
    /// camera's itself, once they are upright.
    private nonisolated static func unmirror(_ connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = false
    }

    /// The camera facing a way: at the back, a set of cameras that hand over
    /// to each other as the zoom changes, where the phone has one.
    private nonisolated static func camera(facing position: Position) -> AVCaptureDevice? {
        switch position {
        case .back:
            let types: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
            ]
            for type in types {
                if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                    return device
                }
            }
            return nil
        case .front:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    private nonisolated static func viewfinderFormat(of device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = device.formats
        return CameraFormats.best(formats.map { CameraFormats.Candidate($0) }).map { formats[$0] }
    }

    private nonisolated static func mainZoomFactor(of device: AVCaptureDevice) -> CGFloat {
        guard device.constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera }),
            let factor = device.virtualDeviceSwitchOverVideoZoomFactors.first
        else { return 1 }
        return CGFloat(truncating: factor)
    }

    /// The largest photos a format takes, up to `CameraFormats.photoLimit`.
    private nonisolated static func photoDimensions(of format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        format.supportedMaxPhotoDimensions
            .filter { Int($0.width) * Int($0.height) <= CameraFormats.photoLimit }
            .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
    }
}

/// Hands a photo's file back to `Camera.takePhoto`.
nonisolated private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<Data, any Error>?
    private var result: Result<Data, any Error> = .failure(Camera.Failure.noPhoto)

    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?
    ) {
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        }
    }

    // Always comes last, once.
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        if let error, case .success = result {
            result = .failure(error)
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}

/// How the camera picks its format: 4:3, the sensor's own shape (docs/UX.md,
/// section 2), with frames no larger than the speed benchmark's, at 30 frames
/// a second, taking the largest photos up to 12 megapixels. Apart from
/// AVFoundation, so the tests can check it.
nonisolated enum CameraFormats {
    /// A format, as far as the choice goes.
    nonisolated struct Candidate: Equatable {
        var width: Int
        var height: Int
        var maxFrameRate: Double
        /// The largest photo it takes, in pixels, up to `photoLimit`, or 0.
        var photoPixels: Int
        /// Whether its frames are made by adding up neighbouring sensor
        /// pixels, which loses detail.
        var binned: Bool
        /// Whether its brightness takes the full range of values.
        var fullRange: Bool
    }

    static let largestFrameWidth = 1920
    /// 12 megapixels. A 48-megapixel photo would take 200 MB to convert.
    static let photoLimit = 4032 * 3024

    /// The best of a camera's formats, or nil if none will do.
    static func best(_ candidates: [Candidate]) -> Int? {
        let suitable = candidates.indices.filter { index in
            let candidate = candidates[index]
            return candidate.width * 3 == candidate.height * 4 && candidate.width <= largestFrameWidth
                && candidate.maxFrameRate >= 30
        }
        func rank(_ index: Int) -> (Int, Int, Int, Int) {
            let candidate = candidates[index]
            return (candidate.photoPixels, candidate.binned ? 0 : 1, candidate.width, candidate.fullRange ? 1 : 0)
        }
        return suitable.max { rank($0) < rank($1) }
    }
}

extension CameraFormats.Candidate {
    nonisolated init(_ format: AVCaptureDevice.Format) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        width = Int(dimensions.width)
        height = Int(dimensions.height)
        maxFrameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        photoPixels =
            format.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }
            .filter { $0 <= CameraFormats.photoLimit }.max() ?? 0
        binned = format.isVideoBinned
        fullRange =
            CMFormatDescriptionGetMediaSubType(format.formatDescription)
            == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    }
}

/// The zoom buttons' values: 0.5×, 1× and 2×, and each of the camera's other
/// lenses, as far as the camera reaches.
nonisolated enum CameraZoom {
    static let standard: [Double] = [0.5, 1, 2]
    /// The furthest the zoom goes, as the buttons show it.
    static let limit = 10.0

    /// The buttons' values for a camera that zooms over a range, and whose
    /// lenses take over at the given zooms.
    static func presets(in range: ClosedRange<Double>, lenses: [Double]) -> [Double] {
        let values = standard + lenses.map { ($0 * 10).rounded() / 10 }
        return Set(values).filter { range.contains($0) }.sorted()
    }
}
