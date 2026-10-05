import AVFoundation
import C64Core
import CoreGraphics
import CoreVideo
import Observation
import Synchronization

/// Turns the camera's frames into the TV's live picture as a shot is made
/// (plan, section 6): each frame is converted in the chosen mode for the
/// chosen monitor, rendered as the VIC-II shows it, and shown through the
/// monitor's display model, off the main thread.
///
/// A frame that comes while the last one is being converted is dropped, so
/// the viewfinder runs as fast as the phone converts. A cell keeps the
/// previous frame's colours, and in PETSCII its character, unless new ones
/// are clearly better, so the picture does not flicker.
nonisolated final class Viewfinder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// What the viewfinder makes of frames.
    nonisolated struct Settings: Hashable, Sendable {
        var spec: ModeSpec
        var converter: Converter.Settings
        /// How frames are seen. The camera sends them sideways, as
        /// AVFoundation does by default, and unmirrored.
        var orientation: ImageOrientation
    }

    /// The queue frames come on.
    let queue = DispatchQueue(label: "com.camerac64.viewfinder", qos: .userInitiated)
    private let feed: ViewfinderFeed
    /// What to make of frames, or nil to drop them.
    private let settings = Mutex<Settings?>(nil)
    /// The newest picture, until the main actor takes it.
    private let newest = Mutex<RGBImage?>(nil)
    private let frameSize = Mutex<(width: Int, height: Int)?>(nil)

    // Only used on `queue`.
    private var converters: [ConverterKey: Converter] = [:]
    private var previous: (settings: Settings, conversion: Conversion)?

    init(feed: ViewfinderFeed) {
        self.feed = feed
        super.init()
    }

    /// Sets what the viewfinder makes of frames, or nil to drop them, as
    /// during a review.
    func use(_ newSettings: Settings?) {
        settings.withLock { $0 = newSettings }
    }

    /// The size of the frames coming in, once one has.
    var lastFrameSize: (width: Int, height: Int)? {
        frameSize.withLock { $0 }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard let settings = settings.withLock({ $0 }), let frame = CMSampleBufferGetImageBuffer(sampleBuffer),
            let screen = picture(of: frame, settings)
        else { return }
        deliver(screen)
    }

    /// A frame as the TV shows it: the whole screen, border included,
    /// through the monitor. A cell keeps the previous frame's colours unless
    /// new ones are clearly better, if the settings are the same.
    func picture(of frame: CVPixelBuffer, _ settings: Settings) -> RGBImage? {
        guard CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_32BGRA,
            CVPixelBufferLockBaseAddress(frame, .readOnly) == kCVReturnSuccess
        else { return nil }
        let (width, height) = (CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(frame)
        // The frame is read where it is, while it is locked.
        let target = CVPixelBufferGetBaseAddress(frame).map { base in
            Target(
                UnsafeRawBufferPointer(start: base, count: bytesPerRow * height), width: width, height: height,
                bytesPerRow: bytesPerRow, layout: .bgra, for: settings.spec, orientation: settings.orientation)
        }
        CVPixelBufferUnlockBaseAddress(frame, .readOnly)
        guard let target else { return nil }
        frameSize.withLock { $0 = (width, height) }

        let kept = previous?.settings == settings ? previous?.conversion : nil
        let conversion = converter(for: settings).convert(target, keeping: kept)
        previous = (settings, conversion)
        return settings.converter.display.show(VICII.render(conversion.frame), palette: settings.converter.palette)
    }

    /// Where a point of the picture lies in the camera's view, as the camera
    /// measures points of interest: across and down from 0 to 1, in the frame
    /// as the camera sends it, sideways. The point goes across and down the
    /// picture from 0 to 1, and the picture is the centred crop of a frame
    /// `frameWidth` × `frameHeight` pixels, seen in an orientation.
    static func cameraPoint(
        ofPicturePoint point: CGPoint, frameWidth: Int, frameHeight: Int, orientation: ImageOrientation
    ) -> CGPoint {
        let (seenWidth, seenHeight) = orientation.swapsAxes ? (frameHeight, frameWidth) : (frameWidth, frameHeight)
        let crop = Crop.centered(width: seenWidth, height: seenHeight)
        let seen = (
            x: (crop.x + point.x * crop.width) / Double(seenWidth),
            y: (crop.y + point.y * crop.height) / Double(seenHeight)
        )
        let inFrame = orientation.storedPoint(x: seen.x, y: seen.y)
        return CGPoint(x: inFrame.x, y: inFrame.y)
    }

    // MARK: - Converters and pictures

    nonisolated private struct ConverterKey: Hashable {
        var spec: ModeSpec
        var settings: Converter.Settings
    }

    /// A converter for the settings, made once: a PETSCII one takes as long
    /// as a few frames to make.
    private func converter(for settings: Settings) -> Converter {
        let key = ConverterKey(spec: settings.spec, settings: settings.converter)
        if let converter = converters[key] {
            return converter
        }
        let converter = Converter(spec: settings.spec, settings: settings.converter)
        converters[key] = converter
        return converter
    }

    /// Hands the newest picture to the feed, without queueing up pictures
    /// the main actor has not taken yet.
    private func deliver(_ screen: RGBImage) {
        let waiting = newest.withLock { newest in
            let waiting = newest != nil
            newest = screen
            return waiting
        }
        guard !waiting else { return }
        Task { @MainActor in
            feed.show(takeNewest())
        }
    }

    private func takeNewest() -> RGBImage? {
        newest.withLock { newest in
            defer { newest = nil }
            return newest
        }
    }
}

/// The viewfinder's newest picture, for the TV. Only the view that shows it
/// reads `picture`, so only that view redraws for each frame.
@Observable
final class ViewfinderFeed {
    private(set) var picture: ShownPicture?
    /// Whether a frame has come yet, for the CRT's warm-up.
    private(set) var hasPicture = false

    func show(_ screen: RGBImage?) {
        guard let screen, let picture = ShownPicture(screen) else { return }
        self.picture = picture
        if !hasPicture {
            hasPicture = true
        }
    }
}
