import C64Core
import CoreVideo
import ImageIO
import SwiftUI
import Testing

@testable import CameraC64

/// The camera screen's logic. C64 logic is tested in Packages/C64Core.
@MainActor
struct CameraScreenTests {
    @Test func gravityTellsHowThePhoneIsHeld() {
        #expect(HeldOrientation(gravityX: 0, y: -1) == .portrait)
        #expect(HeldOrientation(gravityX: -1, y: 0) == .landscapeLeft)
        #expect(HeldOrientation(gravityX: 1, y: 0) == .landscapeRight)
        // Flat on a table, or upside down: keep the previous orientation.
        #expect(HeldOrientation(gravityX: 0.1, y: 0.1) == nil)
        #expect(HeldOrientation(gravityX: 0, y: 1) == nil)
    }

    @Test func contentTurnsAgainstThePhone() {
        #expect(HeldOrientation.portrait.contentRotation == .zero)
        #expect(HeldOrientation.landscapeLeft.contentRotation == .degrees(90))
        #expect(HeldOrientation.landscapeRight.contentRotation == .degrees(-90))
    }

    @Test func swipesAreReadAsTheUserSeesThem() {
        // With the top of the phone pointing left, a drag towards the phone's
        // bottom edge goes right for the user.
        let towardsBottomEdge = CGSize(width: 0, height: 100)
        #expect(HeldOrientation.portrait.upright(towardsBottomEdge) == towardsBottomEdge)
        #expect(HeldOrientation.landscapeLeft.upright(towardsBottomEdge) == CGSize(width: 100, height: 0))
        #expect(HeldOrientation.landscapeRight.upright(towardsBottomEdge) == CGSize(width: -100, height: 0))
    }

    @Test func tvIsAbout4By3AndThePicture3By2() {
        #expect(abs(TVGeometry.aspectRatio - 1.3214) < 0.001)
        let tv = CGSize(width: 402, height: 402 / TVGeometry.aspectRatio)
        let picture = TVGeometry.pictureFrame(inTV: tv)
        #expect(abs(picture.width / picture.height - 1.4976) < 0.001)
        #expect(abs(picture.midX - tv.width / 2) < 0.001)
        // The border is 35 lines above the picture and 37 below.
        #expect(abs(picture.minY - tv.height * 35 / 272) < 0.001)
        #expect(abs(tv.height - picture.maxY - tv.height * 37 / 272) < 0.001)
    }

    @Test func portraitTVSpansTheWidth() {
        let tv = TVGeometry.size(fitting: CGSize(width: 402, height: 500), turned: false)
        #expect(tv.width == 402)
        #expect(abs(tv.height - 304.2) < 0.1)
    }

    @Test func turnedTVRunsAlongTheHeight() {
        let area = ScreenMetrics.tvArea(in: CGSize(width: 402, height: 778), turned: true, stage: .live)
        let tv = TVGeometry.size(fitting: area, turned: true)
        #expect(tv.width == area.height)
        #expect(tv.height <= area.width)
        #expect(tv.width > 402)
    }

    @Test func modeDialStopsAtTheEnds() {
        #expect(PictureMode.hires.moved(by: -1) == .hires)
        #expect(PictureMode.hires.moved(by: 1) == .multicolour)
        #expect(PictureMode.afli.moved(by: 1) == .afli)
    }

    @Test func aShotIsHeldForReviewAndKept() {
        let model = CameraModel()
        model.select(PictureMode.hires)
        model.capture()
        #expect(model.stage == .review)
        #expect(model.lastShot == .hires)
        #expect(model.reviewMode == .hires)
        model.pictureReady(animated: false)
        #expect(model.fillStart == nil)

        model.backToLive()
        #expect(model.stage == .live)
        #expect(model.lastShot == .hires)

        model.showLastShot()
        #expect(model.stage == .review)

        model.deleteShot()
        #expect(model.lastShot == nil)
        #expect(model.stage == .live)
    }

    @Test func modesConvertOrShowASample() {
        #expect(PictureMode.allCases.filter { $0.spec != nil } == [.hires, .multicolour, .petscii])
        #expect(PictureMode.allCases.allSatisfy { ($0.spec == nil) == ($0.sample != nil) })
    }

    /// When the camera takes no photo, the last picture stays as it was.
    @Test func aFailedShotKeepsTheLastPicture() {
        let model = CameraModel()
        model.capture()
        let previous = model.lastShot
        model.select(PictureMode.hires)
        model.capture()
        model.captureFailed(lastShot: previous)
        #expect(model.stage == .live)
        #expect(model.lastShot == .multicolour)
    }

    /// Every mode's picture comes out at the screen's size, border included,
    /// and its display window at the picture's.
    @Test func everyModeHasAPicture() async throws {
        let maker = PictureMaker(photo: try #require(Photo.sample))
        for mode in PictureMode.allCases {
            let key = PictureMaker.Key(mode, on: .tv)
            await maker.make(key)
            let picture = maker.picture(key)
            #expect(picture?.screen.width == 384 && picture?.screen.height == 272, "\(mode.name)")
            #expect(picture?.window.width == 320 && picture?.window.height == 200, "\(mode.name)")
        }
        #expect(maker.picture(PictureMaker.Key(.hires, on: .sharp)) == nil)
    }

    /// PETSCII pictures can take only the graphics characters, a setting the
    /// other modes ignore.
    @Test func petsciiCanUseOnlyTheGraphicsCharacters() async throws {
        #expect(PictureMaker.Key(.hires, on: .tv, petsciiCharacters: .graphics) == PictureMaker.Key(.hires, on: .tv))
        let maker = PictureMaker(photo: try #require(Photo.sample))
        let all = PictureMaker.Key(.petscii, on: .tv)
        let graphics = PictureMaker.Key(.petscii, on: .tv, petsciiCharacters: .graphics)
        await maker.make(all)
        #expect(maker.picture(graphics) == nil)
        await maker.make(graphics)
        let allPixels = try #require(maker.picture(all).flatMap { RGBImage($0.window) }).bytes
        let graphicsPixels = try #require(maker.picture(graphics).flatMap { RGBImage($0.window) }).bytes
        #expect(allPixels != graphicsPixels)
    }

    /// The black-and-white monitor shows greys, from the display model rather
    /// than a tint.
    @Test func blackAndWhiteShowsGreys() async throws {
        let maker = PictureMaker(photo: try #require(Photo.sample))
        let key = PictureMaker.Key(.multicolour, on: .blackAndWhite)
        await maker.make(key)
        let screen = try #require(maker.picture(key)?.screen)
        let pixels = try #require(RGBImage(screen)).bytes
        #expect(stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0] == pixels[$0 + 1] })
        #expect(stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0 + 1] == pixels[$0 + 2] })
    }

    /// Before the first shot, only the modes without a converter have
    /// pictures: their samples.
    @Test func withoutAPhotoOnlySamplesHavePictures() async {
        let maker = PictureMaker()
        await maker.make(PictureMaker.Key(.hires, on: .tv))
        await maker.make(PictureMaker.Key(.fli, on: .tv))
        #expect(maker.picture(PictureMaker.Key(.hires, on: .tv)) == nil)
        #expect(maker.picture(PictureMaker.Key(.fli, on: .tv)) != nil)
    }

    /// A new shot replaces the last one's pictures.
    @Test func aNewPhotoReplacesThePictures() async throws {
        let maker = PictureMaker(photo: try #require(Photo.sample))
        let key = PictureMaker.Key(.hires, on: .tv)
        await maker.make(key)
        #expect(maker.picture(key) != nil)
        let next = try #require(Photo.sample)
        maker.use(next)
        #expect(maker.photo?.id == next.id)
        #expect(maker.picture(key) == nil)
        await maker.make(key)
        #expect(maker.picture(key) != nil)
    }

    /// A photo keeps its pixels as stored, with the orientation its file
    /// gives, mirrored for the front camera.
    @Test func photosKeepTheirOrientation() throws {
        // A 40 × 30 JPEG whose EXIF orientation says it is seen after a
        // quarter turn clockwise, as a photo taken upright is stored.
        let image = try #require(RGBImage(width: 40, height: 30, fill: RGB(200, 120, 40)).cgImage)
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let photo = try #require(Photo(data: data as Data, mirrored: false))
        #expect(photo.image.width == 40 && photo.image.height == 30)
        #expect(photo.orientation == .right)
        // The preview is upright.
        #expect(photo.preview.width == 30 && photo.preview.height == 40)
        #expect(Photo(data: data as Data, mirrored: true)?.orientation == .leftMirrored)
    }

    /// Frames come upright for a phone held in portrait; held sideways, the
    /// scene's top is along a side of the frame, and a front camera's frames
    /// are mirrored once upright.
    @Test func framesTurnWithThePhone() {
        #expect(HeldOrientation.portrait.frameOrientation(mirrored: false) == .up)
        #expect(HeldOrientation.landscapeLeft.frameOrientation(mirrored: false) == .left)
        #expect(HeldOrientation.landscapeRight.frameOrientation(mirrored: false) == .right)
        // With the top of the phone to the left, the top of the picture is
        // the frame's right side.
        let top = HeldOrientation.landscapeLeft.frameOrientation(mirrored: false).storedPoint(x: 0.5, y: 0)
        #expect(top.x == 1 && top.y == 0.5)
        #expect(HeldOrientation.portrait.frameOrientation(mirrored: true) == .upMirrored)
        #expect(HeldOrientation.landscapeLeft.frameOrientation(mirrored: true) == .rightMirrored)
        #expect(HeldOrientation.landscapeRight.frameOrientation(mirrored: true) == .leftMirrored)
    }

    @Test func photosAreStoredAsThePhoneIsHeld() {
        #expect(HeldOrientation.portrait.photoRotationAngle == 90)
        #expect(HeldOrientation.landscapeLeft.photoRotationAngle == 0)
        #expect(HeldOrientation.landscapeRight.photoRotationAngle == 180)
    }

    /// A camera frame in BGRA, as the camera sends them.
    private func cameraFrame(width: Int, height: Int, _ color: (Int, Int) -> RGB) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        let frame = try #require(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        defer { CVPixelBufferUnlockBaseAddress(frame, []) }
        let base = try #require(CVPixelBufferGetBaseAddress(frame)).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(frame)
        for y in 0..<height {
            for x in 0..<width {
                let (pixel, rgb) = (base + y * bytesPerRow + x * 4, color(x, y))
                (pixel[0], pixel[1], pixel[2], pixel[3]) = (rgb.b, rgb.g, rgb.r, 255)
            }
        }
        return frame
    }

    /// The viewfinder converts frames into whole screens, seen as the phone is
    /// held, and mirrored for the front camera.
    @Test func viewfinderTurnsAndMirrorsFrames() throws {
        // Red at the top of a portrait frame, blue at the bottom.
        let frame = try cameraFrame(width: 360, height: 480) { _, y in y < 240 ? RGB(220, 30, 30) : RGB(30, 30, 220) }
        let viewfinder = Viewfinder(feed: ViewfinderFeed())
        func colors(_ orientation: ImageOrientation) throws -> (top: RGB, bottom: RGB, left: RGB, right: RGB) {
            let settings = Viewfinder.Settings(
                spec: .hires, converter: Converter.Settings(display: .sharp), orientation: orientation)
            let screen = try #require(viewfinder.picture(of: frame, settings))
            #expect(screen.width == Screen.width && screen.height == Screen.height)
            let (x, y) = (Screen.windowX, Screen.windowY)
            return (
                screen[x + 160, y + 20], screen[x + 160, y + 180], screen[x + 20, y + 100], screen[x + 300, y + 100]
            )
        }
        func isRed(_ color: RGB) -> Bool { color.r > color.b }

        let upright = try colors(.up)
        #expect(isRed(upright.top) && !isRed(upright.bottom))
        // Top to the left: the frame's top is on the left of the picture.
        let sideways = try colors(.left)
        #expect(isRed(sideways.left) && !isRed(sideways.right))
        let otherWay = try colors(.right)
        #expect(!isRed(otherWay.left) && isRed(otherWay.right))
        let mirrored = try colors(HeldOrientation.landscapeLeft.frameOrientation(mirrored: true))
        #expect(!isRed(mirrored.left) && isRed(mirrored.right))
    }

    /// A tap focuses where it lands: the centre of the picture is the centre
    /// of the camera's view, and its corners map into the sensor's own
    /// orientation, which is upright with the top of the phone to the left.
    @Test func tapsFocusWhereTheyLand() {
        for orientation in ImageOrientation.allCases {
            let centre = Viewfinder.cameraPoint(
                ofPicturePoint: CGPoint(x: 0.5, y: 0.5), frameWidth: 1440, frameHeight: 1920, orientation: orientation)
            #expect(abs(centre.x - 0.5) < 1e-9 && abs(centre.y - 0.5) < 1e-9)
        }
        let topLeft = CGPoint(x: 0, y: 0)
        // Held upright, the picture is a band across the middle of the
        // portrait frame, along the sensor's bottom edge.
        let upright = Viewfinder.cameraPoint(
            ofPicturePoint: topLeft, frameWidth: 1440, frameHeight: 1920, orientation: .up)
        #expect(abs(upright.x - 0.2496) < 0.001 && abs(upright.y - 1) < 1e-9)
        // Held with the top to the left, the sensor sees the picture upright.
        let sideways = Viewfinder.cameraPoint(
            ofPicturePoint: topLeft, frameWidth: 1440, frameHeight: 1920, orientation: .left)
        #expect(abs(sideways.x) < 1e-9 && abs(sideways.y - 0.0548) < 0.001)
    }

    /// The camera picks a 4:3 format with frames no larger than 1920 × 1440,
    /// taking the largest photos.
    @Test func cameraPicksA4By3Format() {
        typealias Candidate = CameraFormats.Candidate
        let twelveMegapixels = 4032 * 3024
        let formats = [
            Candidate(
                width: 1920, height: 1080, maxFrameRate: 60, photoPixels: twelveMegapixels, binned: false,
                fullRange: true),
            Candidate(
                width: 4032, height: 3024, maxFrameRate: 30, photoPixels: twelveMegapixels, binned: false,
                fullRange: true),
            Candidate(
                width: 1440, height: 1080, maxFrameRate: 60, photoPixels: twelveMegapixels, binned: true,
                fullRange: true),
            Candidate(
                width: 1920, height: 1440, maxFrameRate: 30, photoPixels: twelveMegapixels, binned: false,
                fullRange: false),
            Candidate(
                width: 1920, height: 1440, maxFrameRate: 30, photoPixels: twelveMegapixels, binned: false,
                fullRange: true),
            Candidate(
                width: 640, height: 480, maxFrameRate: 30, photoPixels: 640 * 480, binned: false, fullRange: true),
        ]
        #expect(CameraFormats.best(formats) == 4)
        // Larger photos come first, then frames that are not binned.
        #expect(CameraFormats.best([formats[5], formats[2]]) == 1)
        #expect(CameraFormats.best([formats[0], formats[1]]) == nil)
    }

    @Test func zoomButtonsFollowTheLenses() {
        // Ultra wide, wide and a 5× telephoto lens.
        #expect(CameraZoom.presets(in: 0.5...10, lenses: [1, 5]) == [0.5, 1, 2, 5])
        #expect(CameraZoom.presets(in: 0.5...10, lenses: [1]) == [0.5, 1, 2])
        // A front camera, and an older pair of wide and 2× lenses.
        #expect(CameraZoom.presets(in: 1...10, lenses: []) == [1, 2])
        #expect(CameraZoom.presets(in: 1...10, lenses: [2]) == [1, 2])
        #expect(CameraZoom.presets(in: 0.5...10, lenses: [1, 2.9999]) == [0.5, 1, 2, 3])
    }

    @Test func zoomButtonsShowTheZoom() {
        let buttons = ZoomButtons(presets: [0.5, 1, 2], zoom: 1)
        #expect(buttons.lit == 1)
        #expect([0.5, 1, 2].map(buttons.label) == [".5", "1×", "2"])
        // Between buttons, the one below shows the zoom.
        #expect(ZoomButtons(presets: [0.5, 1, 2], zoom: 1.4).label(1) == "1.4×")
        #expect(ZoomButtons(presets: [0.5, 1, 2], zoom: 0.7).label(0.5) == ".7×")
        #expect(ZoomButtons.name(0.5) == "0.5×" && ZoomButtons.name(2) == "2×")
    }

    @Test func picturesRoundTripThroughCoreGraphics() throws {
        let image = RGBImage(width: 2, height: 1, layout: .rgb, bytes: [255, 0, 0, 10, 200, 30])
        let cgImage = try #require(image.cgImage)
        let back = try #require(RGBImage(cgImage))
        #expect(back.width == 2 && back.height == 1)
        #expect(Array(back.bytes[0..<3]) == [255, 0, 0])
        #expect(Array(back.bytes[4..<7]) == [10, 200, 30])
    }
}
