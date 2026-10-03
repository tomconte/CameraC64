import C64Core
import CoreGraphics
import Observation
import UIKit

/// A picture as the TV shows it, through the chosen monitor.
struct ShownPicture {
    /// The whole screen, border included: 384 × 272 C64 pixels.
    let screen: CGImage
    /// The display window alone: the 320 × 200 picture.
    let window: CGImage
}

/// Makes the camera screen's pictures with C64Core (CLAUDE.md, core rule): the
/// converter turns the photo into C64 memory, the renderer draws that memory as
/// the VIC-II shows it, and the monitor's display model shows the result.
///
/// Until the camera comes (plan, milestone 3), the photo is the bundled sample.
/// Modes without a converter yet show sample pictures, through the same display
/// models.
@Observable
final class PictureMaker {
    /// A picture: a mode's, for a monitor.
    struct Key: Hashable {
        var mode: PictureMode
        var monitor: Monitor
        /// The characters a PETSCII picture may use. The other modes have
        /// none, so for them it is always `.all`.
        var petsciiCharacters: CharacterROM.Selection

        init(_ mode: PictureMode, on monitor: Monitor, petsciiCharacters: CharacterROM.Selection = .all) {
            self.mode = mode
            self.monitor = monitor
            self.petsciiCharacters = mode == .petscii ? petsciiCharacters : .all
        }
    }

    /// The photo the pictures are made from.
    let photo: RGBImage?
    private(set) var pictures: [Key: ShownPicture] = [:]
    @ObservationIgnored private var making: Set<Key> = []

    init(photo: RGBImage? = UIImage(named: "SamplePhoto")?.cgImage.flatMap { RGBImage($0) }) {
        self.photo = photo
    }

    func picture(_ key: Key) -> ShownPicture? {
        pictures[key]
    }

    /// Makes every mode's picture for a monitor, the given mode first, unless
    /// they are made already.
    func makeAll(for monitor: Monitor, petsciiCharacters: CharacterROM.Selection, first: PictureMode) async {
        for mode in [first] + PictureMode.allCases.filter({ $0 != first }) {
            guard !Task.isCancelled else { return }
            await make(Key(mode, on: monitor, petsciiCharacters: petsciiCharacters))
        }
    }

    /// Makes a picture, unless it is made already.
    func make(_ key: Key) async {
        guard pictures[key] == nil, !making.contains(key) else { return }
        let source: Source
        if let spec = key.mode.spec, let photo {
            source = .photo(photo, spec, key.petsciiCharacters)
        } else if let name = key.mode.sample, let sample = UIImage(named: name)?.cgImage.flatMap({ RGBImage($0) }) {
            source = .sample(sample)
        } else {
            return
        }
        making.insert(key)
        defer { making.remove(key) }
        let display = key.monitor.display
        let shown = await Task.detached(priority: .userInitiated) {
            PictureMaker.screen(of: source, on: display)
        }.value
        let windowArea = CGRect(
            x: Screen.windowX, y: Screen.windowY, width: Screen.windowWidth, height: Screen.windowHeight)
        guard let screen = shown.cgImage, let window = screen.cropping(to: windowArea) else { return }
        pictures[key] = ShownPicture(screen: screen, window: window)
    }

    /// What a picture is made from.
    nonisolated enum Source: Sendable {
        /// A photo, converted in a mode, with the characters PETSCII may use.
        case photo(RGBImage, ModeSpec, CharacterROM.Selection)
        /// A sample picture of the display window, in Colodore's colours.
        case sample(RGBImage)
    }

    /// The whole screen as a monitor shows it.
    nonisolated static func screen(of source: Source, on display: DisplayModel) -> RGBImage {
        let screen: IndexedImage
        switch source {
        case .photo(let photo, let spec, let petsciiCharacters):
            let settings = Converter.Settings(display: display, petsciiCharacters: petsciiCharacters)
            let converter = Converter(spec: spec, settings: settings)
            screen = VICII.render(converter.convert(photo).frame)
        case .sample(let picture):
            screen = sampleScreen(picture)
        }
        return display.show(screen, palette: .colodore)
    }

    /// A sample picture as a screen: each pixel takes the nearest of
    /// Colodore's colours, and the border matches the picture's edges.
    nonisolated static func sampleScreen(_ picture: RGBImage) -> IndexedImage {
        let palette = C64Palette.colodore.colors.map(OKLab.init)
        var window = IndexedImage(width: Screen.windowWidth, height: Screen.windowHeight)
        for y in 0..<min(picture.height, window.height) {
            for x in 0..<min(picture.width, window.width) {
                let color = OKLab(picture[x, y])
                let distances = palette.map { $0.distanceSquared(to: color) }
                let nearest = distances.indices.min { distances[$0] < distances[$1] }!
                window[x, y] = C64Color(rawValue: UInt8(nearest))!
            }
        }
        var screen = IndexedImage(width: Screen.width, height: Screen.height, fill: window.edgeColor)
        for y in 0..<window.height {
            for x in 0..<window.width {
                screen[Screen.windowX + x, Screen.windowY + y] = window[x, y]
            }
        }
        return screen
    }
}
