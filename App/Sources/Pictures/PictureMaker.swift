import C64Core
import CoreGraphics
import Foundation
import Observation

/// A picture as the TV shows it, through the chosen monitor, with the C64
/// memory it is drawn from. (CGImage is immutable, so threads can share it.)
nonisolated struct ShownPicture: @unchecked Sendable {
    /// The C64 memory the converter made, which C64 files hold.
    let frame: C64Frame
    /// The whole screen, border included: 384 × 272 C64 pixels.
    let screen: CGImage
    /// The display window alone: the 320 × 200 picture.
    let window: CGImage
    /// The whole screen as the CRT layer reads it.
    let crt: CRTSource
}

nonisolated extension ShownPicture {
    /// A frame's whole screen as a monitor shows it, border included.
    init?(_ screen: RGBImage, frame: C64Frame) {
        let windowArea = CGRect(
            x: Screen.windowX, y: Screen.windowY, width: Screen.windowWidth, height: Screen.windowHeight)
        guard let image = screen.cgImage, let window = image.cropping(to: windowArea) else { return nil }
        self.init(frame: frame, screen: image, window: window, crt: CRTSource(screen))
    }
}

/// Makes the pictures of a shot with C64Core (CLAUDE.md, core rule): the
/// converter turns the photo into C64 memory, the renderer draws that memory
/// as the VIC-II shows it, and the monitor's display model shows the result.
@Observable
final class PictureMaker {
    /// A picture: a mode's, for a monitor.
    struct Key: Hashable {
        var mode: PictureMode
        var monitor: Monitor

        init(_ mode: PictureMode, on monitor: Monitor) {
            self.mode = mode
            self.monitor = monitor
        }
    }

    /// The photo the pictures are made from: the last shot, or nil before
    /// the first and after it is deleted.
    private(set) var photo: Photo?
    private(set) var pictures: [Key: ShownPicture] = [:]
    /// The pictures being made, each with the photo it is made from.
    @ObservationIgnored private var making: Set<Job> = []

    private struct Job: Hashable {
        var key: Key
        var photo: UUID?
    }

    init(photo: Photo? = nil) {
        self.photo = photo
    }

    func picture(_ key: Key) -> ShownPicture? {
        pictures[key]
    }

    /// Makes the pictures from another photo, forgetting the last one's.
    func use(_ photo: Photo) {
        self.photo = photo
        pictures = [:]
    }

    /// Forgets the photo and its pictures, as when the shot is deleted.
    func forget() {
        photo = nil
        pictures = [:]
    }

    /// Makes every mode's picture for a monitor, the given mode first, unless
    /// they are made already.
    func makeAll(for monitor: Monitor, first: PictureMode) async {
        for mode in [first] + PictureMode.allCases.filter({ $0 != first }) {
            guard !Task.isCancelled else { return }
            await make(Key(mode, on: monitor))
        }
    }

    /// Makes a picture of the photo, unless it is made already.
    func make(_ key: Key) async {
        let job = Job(key: key, photo: photo?.id)
        guard let photo, pictures[key] == nil, !making.contains(job) else { return }
        making.insert(job)
        defer { making.remove(job) }
        let (spec, settings) = (key.mode.spec, key.mode.converterSettings(on: key.monitor))
        let picture = await Task.detached(priority: .userInitiated) {
            PictureMaker.picture(of: photo.image, orientation: photo.orientation, in: spec, settings: settings)
        }.value
        // A picture of a photo since replaced is dropped.
        guard self.photo?.id == job.photo, let picture else { return }
        pictures[key] = picture
    }

    /// A photo, seen in an orientation, converted in a mode and shown on the
    /// monitor the settings are for.
    nonisolated static func picture(
        of photo: RGBImage, orientation: ImageOrientation, in spec: ModeSpec, settings: Converter.Settings
    ) -> ShownPicture? {
        let frame = Converter(spec: spec, settings: settings).convert(photo, orientation: orientation).frame
        return ShownPicture(settings.display.show(VICII.render(frame), palette: settings.palette), frame: frame)
    }
}
