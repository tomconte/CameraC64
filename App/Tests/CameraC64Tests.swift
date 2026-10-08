import AVFoundation
import C64Core
import CoreVideo
import ImageIO
import SwiftUI
import Testing

@testable import CameraC64

/// The camera screen's logic. C64 logic is tested in Packages/C64Core.
@MainActor
struct CameraScreenTests {
    /// The sample photo, which the app bundles for previews and tests.
    /// (Passed straight to a `Photo?` parameter, `#require` would check a
    /// doubly optional value that is never nil.)
    private func samplePhoto() throws -> Photo {
        try #require(Photo.sample)
    }

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
        #expect(PictureMode.bbs.moved(by: 1) == .bbs)
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

    /// 3.0 has the standard modes, with PETSCII twice: with only the
    /// graphics characters, and with all of them, as BBS.
    @Test func petsciiComesTwice() {
        #expect(PictureMode.allCases == [.hires, .multicolour, .petscii, .bbs])
        #expect(PictureMode.petscii.spec == .petscii && PictureMode.bbs.spec == .petscii)
        #expect(PictureMode.petscii.converterSettings(on: .tv).petsciiCharacters == .graphics)
        #expect(PictureMode.bbs.converterSettings(on: .tv).petsciiCharacters == .all)
        #expect(PictureMode.multicolour.converterSettings(on: .amber).display == .amber)
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
    /// and its display window at the picture's, with the C64 memory it is
    /// drawn from.
    @Test func everyModeHasAPicture() async throws {
        let maker = PictureMaker(photo: try samplePhoto())
        for mode in PictureMode.allCases {
            let key = PictureMaker.Key(mode, on: .tv)
            await maker.make(key)
            let picture = maker.picture(key)
            #expect(picture?.screen.width == 384 && picture?.screen.height == 272, "\(mode.name)")
            #expect(picture?.window.width == 320 && picture?.window.height == 200, "\(mode.name)")
            #expect(picture?.frame.mode == mode.spec.graphicsMode, "\(mode.name)")
        }
        #expect(maker.picture(PictureMaker.Key(.hires, on: .sharp)) == nil)
    }

    /// PETSCII takes only the graphics characters, for the classic look, and
    /// BBS all of them.
    @Test func petsciiTakesOnlyTheGraphicsCharacters() async throws {
        let maker = PictureMaker(photo: try samplePhoto())
        let (petscii, bbs) = (PictureMaker.Key(.petscii, on: .tv), PictureMaker.Key(.bbs, on: .tv))
        await maker.make(petscii)
        #expect(maker.picture(bbs) == nil)
        await maker.make(bbs)
        let petsciiPicture = try #require(maker.picture(petscii))
        let bbsPicture = try #require(maker.picture(bbs))
        let graphics = Set(CharacterROM.Selection.graphics.codes(in: .upperCase).map { UInt8($0) })
        #expect(petsciiPicture.frame.screen.allSatisfy { graphics.contains($0) })
        #expect(!bbsPicture.frame.screen.allSatisfy { graphics.contains($0) })
        let petsciiPixels = try #require(RGBImage(petsciiPicture.window)).bytes
        let bbsPixels = try #require(RGBImage(bbsPicture.window)).bytes
        #expect(petsciiPixels != bbsPixels)
    }

    /// The black-and-white monitor shows greys, from the display model rather
    /// than a tint.
    @Test func blackAndWhiteShowsGreys() async throws {
        let maker = PictureMaker(photo: try samplePhoto())
        let key = PictureMaker.Key(.multicolour, on: .blackAndWhite)
        await maker.make(key)
        let screen = try #require(maker.picture(key)?.screen)
        let pixels = try #require(RGBImage(screen)).bytes
        #expect(stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0] == pixels[$0 + 1] })
        #expect(stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0 + 1] == pixels[$0 + 2] })
    }

    /// Before the first shot, there are no pictures to make.
    @Test func withoutAPhotoThereAreNoPictures() async {
        let maker = PictureMaker()
        await maker.make(PictureMaker.Key(.hires, on: .tv))
        #expect(maker.picture(PictureMaker.Key(.hires, on: .tv)) == nil)
    }

    /// A new shot replaces the last one's pictures, and deleting it forgets
    /// them. (On the black-and-white monitor, whose search is the quickest.)
    @Test func aNewPhotoReplacesThePictures() async throws {
        let maker = PictureMaker(photo: try samplePhoto())
        let key = PictureMaker.Key(.hires, on: .blackAndWhite)
        await maker.make(key)
        #expect(maker.picture(key) != nil)
        let next = try samplePhoto()
        maker.use(next)
        #expect(maker.photo?.id == next.id)
        #expect(maker.picture(key) == nil)
        await maker.make(key)
        #expect(maker.picture(key) != nil)
        maker.forget()
        #expect(maker.photo == nil && maker.picture(key) == nil)
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

    /// The back camera's frames are upright with the top of the phone to the
    /// left, and need a quarter turn clockwise held upright.
    @Test func backCameraFramesTurnWithThePhone() {
        #expect(HeldOrientation.portrait.frameOrientation(frontCamera: false) == .right)
        #expect(HeldOrientation.landscapeLeft.frameOrientation(frontCamera: false) == .up)
        #expect(HeldOrientation.landscapeRight.frameOrientation(frontCamera: false) == .down)
        // Held upright, the top of the picture is the frame's left side.
        let top = HeldOrientation.portrait.frameOrientation(frontCamera: false).storedPoint(x: 0.5, y: 0)
        #expect(top.x == 0 && top.y == 0.5)
    }

    /// The front camera's frames are upright with the top of the phone to the
    /// right, and turn the other way to the back camera's as the phone turns.
    /// They are mirrored once upright.
    @Test func frontCameraFramesTurnTheOtherWay() {
        #expect(HeldOrientation.portrait.frameOrientation(frontCamera: true) == .leftMirrored)
        #expect(HeldOrientation.landscapeLeft.frameOrientation(frontCamera: true) == .downMirrored)
        #expect(HeldOrientation.landscapeRight.frameOrientation(frontCamera: true) == .upMirrored)
        // Held upright, the top of the picture is still the frame's left
        // side, and its left is the frame's top, as in a mirror.
        let front = HeldOrientation.portrait.frameOrientation(frontCamera: true)
        let top = front.storedPoint(x: 0.5, y: 0)
        let left = front.storedPoint(x: 0, y: 0.5)
        #expect(top.x == 0 && top.y == 0.5)
        #expect(left.x == 0.5 && left.y == 0)
    }

    /// A photo is stored with the turn its camera's frames need, counted from
    /// the sensor, so it gets the turn AVFoundation gives the frames as well.
    /// On the iPhone 17's front camera, whose frames AVFoundation turns by 270°
    /// to send them sideways, the angles are a quarter turn less than on
    /// earlier front cameras, as AVFoundation's rotation coordinator gives
    /// them there.
    @Test func photosAreStoredAsThePhoneIsHeld() {
        let held: [HeldOrientation] = [.portrait, .landscapeLeft, .landscapeRight]
        func angles(frontCamera: Bool, framesRotationAngle: CGFloat = 0) -> [CGFloat] {
            held.map {
                Camera.photoRotationAngle(
                    upright: $0.uprightAngle(frontCamera: frontCamera), framesRotationAngle: framesRotationAngle)
            }
        }
        #expect(angles(frontCamera: false) == [90, 0, 180])
        #expect(angles(frontCamera: true) == [90, 180, 0])
        #expect(angles(frontCamera: true, framesRotationAngle: 270) == [0, 90, 270])
    }

    /// iOS stops the camera when it resets its media services, as it may while
    /// the app is away, and the camera starts again. Other errors leave it
    /// off, so that a camera that keeps failing is not started over and
    /// over. (The Simulator has no camera, so there it stays unavailable.)
    @Test func cameraStartsAgainAfterMediaServicesAreReset() async {
        #expect(LiveCamera.startsAgain(after: .mediaServicesWereReset))
        #expect(!LiveCamera.startsAgain(after: .unknown))
        #expect(!LiveCamera.startsAgain(after: nil))
        // The screen follows what the session does.
        #expect(LiveCamera.state(of: .running) == .running)
        #expect(LiveCamera.state(of: .interrupted) == .interrupted)
        #expect(LiveCamera.state(of: .stopped) == .unavailable)
        let camera = LiveCamera()
        await camera.sessionFailed(.mediaServicesWereReset, position: .back)
        #expect(camera.state == .unavailable)
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

    /// A corner of the picture. (Declared inside a test, a type makes Swift
    /// Testing's `#require` warn that nothing in it throws.)
    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    /// The viewfinder converts frames into whole screens, seen as the phone is
    /// held, and mirrored for the front camera. (Without dithering, which
    /// makes the search quicker and changes nothing here.)
    @Test func viewfinderTurnsAndMirrorsFrames() throws {
        // A frame as the camera sends them, sideways: red in its top left
        // quarter, blue elsewhere.
        let frame = try cameraFrame(width: 480, height: 360) { x, y in
            x < 240 && y < 180 ? RGB(220, 30, 30) : RGB(30, 30, 220)
        }
        let viewfinder = Viewfinder(feed: ViewfinderFeed())
        /// The corner of the picture that is red, if only one is.
        func redCorner(_ held: HeldOrientation, frontCamera: Bool) throws -> Corner? {
            let settings = Viewfinder.Settings(
                spec: .hires, converter: Converter.Settings(display: .sharp, dithering: 0),
                orientation: held.frameOrientation(frontCamera: frontCamera))
            let screen = try #require(viewfinder.picture(of: frame, settings))
            #expect(screen.width == Screen.width && screen.height == Screen.height)
            let corners: [(Corner, x: Int, y: Int)] = [
                (.topLeft, 20, 20), (.topRight, 300, 20), (.bottomLeft, 20, 180), (.bottomRight, 300, 180),
            ]
            let red = corners.filter { _, x, y in
                let color = screen[Screen.windowX + x, Screen.windowY + y]
                return color.r > color.b
            }
            return red.count == 1 ? red[0].0 : nil
        }

        #expect(try redCorner(.portrait, frontCamera: false) == .topRight)
        #expect(try redCorner(.landscapeLeft, frontCamera: false) == .topLeft)
        #expect(try redCorner(.landscapeRight, frontCamera: false) == .bottomRight)
        // The front camera's pictures are mirrored, and turn the other way
        // with the phone sideways.
        #expect(try redCorner(.portrait, frontCamera: true) == .topLeft)
        #expect(try redCorner(.landscapeLeft, frontCamera: true) == .bottomLeft)
        #expect(try redCorner(.landscapeRight, frontCamera: true) == .topRight)
    }

    /// A tap focuses where it lands: the centre of the picture is the centre
    /// of the camera's view, and its corners map into the frame as the camera
    /// sends it, which is how the camera measures points of interest.
    @Test func tapsFocusWhereTheyLand() {
        for orientation in ImageOrientation.allCases {
            let centre = Viewfinder.cameraPoint(
                ofPicturePoint: CGPoint(x: 0.5, y: 0.5), frameWidth: 1920, frameHeight: 1440, orientation: orientation)
            #expect(abs(centre.x - 0.5) < 1e-9 && abs(centre.y - 0.5) < 1e-9)
        }
        let topLeft = CGPoint(x: 0, y: 0)
        // Held upright, the picture is a band down the middle of the frame,
        // and its top is along the frame's left side.
        let upright = Viewfinder.cameraPoint(
            ofPicturePoint: topLeft, frameWidth: 1920, frameHeight: 1440, orientation: .right)
        #expect(abs(upright.x - 0.2496) < 0.001 && abs(upright.y - 1) < 1e-9)
        // Held with the top to the left, the back camera sees the picture
        // upright.
        let sideways = Viewfinder.cameraPoint(
            ofPicturePoint: topLeft, frameWidth: 1920, frameHeight: 1440, orientation: .up)
        #expect(abs(sideways.x) < 1e-9 && abs(sideways.y - 0.0548) < 0.001)
        // The front camera's mirrored picture, held upright, starts at the
        // frame's top.
        let front = Viewfinder.cameraPoint(
            ofPicturePoint: topLeft, frameWidth: 1920, frameHeight: 1440, orientation: .leftMirrored)
        #expect(abs(front.x - 0.2496) < 0.001 && abs(front.y) < 1e-9)
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

    // MARK: - The CRT layer

    /// A whole screen in one colour.
    private func flatScreen(_ color: RGB) -> RGBImage {
        RGBImage(width: Screen.width, height: Screen.height, fill: color)
    }

    /// The glow's light, as RGBA floats.
    private func glowLight(_ source: CRTSource) -> [Float] {
        source.glow.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// The CRT layer reads a screen as RGBA bytes, with the glow at a quarter
    /// of its size each way, in linear light.
    @Test func crtSourceHoldsTheScreenAndItsGlow() {
        let source = CRTSource(flatScreen(RGB(128, 64, 255)))
        #expect(source.width == 384 && source.height == 272)
        #expect(source.pixels.count == 384 * 272 * 4)
        #expect(Array(source.pixels.prefix(8)) == [128, 64, 255, 255, 128, 64, 255, 255])
        #expect(source.glowWidth == 96 && source.glowHeight == 68)
        #expect(source.glow.count == 96 * 68 * 16)
        // A screen in one colour glows evenly, in that colour's light.
        let glow = glowLight(source)
        let middle = (30 * 96 + 50) * 4
        #expect(abs(glow[middle] - SRGB.linear[128]) < 1e-5)
        #expect(abs(glow[middle + 1] - SRGB.linear[64]) < 1e-5)
        #expect(abs(glow[middle + 2] - SRGB.linear[255]) < 1e-5)
    }

    /// The glow spreads a bright area's light into the dark around it.
    @Test func glowSpreadsLight() {
        var screen = flatScreen(RGB(0, 0, 0))
        for y in 120..<152 {
            for x in 176..<208 {
                screen[x, y] = RGB(255, 255, 255)
            }
        }
        let glow = glowLight(CRTSource(screen))
        // The glow's pixel 42 across covers the screen's pixels 168 to 171,
        // just left of the white square.
        #expect(glow[(34 * 96 + 42) * 4] > 0.05)
        #expect(glow[(5 * 96 + 5) * 4] < 1e-4)
    }

    /// Development builds save the tuned look as text.
    @Test func crtLookRoundTripsAsText() {
        var look = CRT.standard
        look.glow = 0.25
        #expect(CRT(text: look.text) == look)
        #expect(CRT(text: CRT.standard.text) == .standard)
        #expect(CRT(text: "") == nil)
        #expect(CRT(text: "0.2 0.4 0.5") == nil)
    }

    /// A phosphor lights up at once, and fades over its afterglow: after
    /// that long, its light is down to about a third.
    @Test func afterglowFadesButLightsUpAtOnce() {
        let (white, black) = (flatScreen(RGB(255, 255, 255)), flatScreen(RGB(0, 0, 0)))
        var phosphor = Afterglow(duration: 0.1)
        let lit = phosphor.show(white, at: 0)
        let faded = phosphor.show(black, at: 0.1)
        let fainter = phosphor.show(black, at: 0.2)
        let relit = phosphor.show(white, at: 0.25)
        let third = SRGB.encoded(Float(exp(-1.0)))
        #expect(lit == white)
        #expect(faded[10, 10] == RGB(third, third, third))
        #expect(fainter[10, 10].r < third)
        #expect(relit == white)
        // Without an afterglow, each screen shows as it is.
        var none = Afterglow(duration: 0)
        _ = none.show(white, at: 0)
        let next = none.show(black, at: 0.01)
        #expect(next == black)
    }

    /// The viewfinder's phosphor glows on only when its settings say so.
    @Test func viewfinderGlowsOnWithAnAfterglow() {
        let viewfinder = Viewfinder(feed: ViewfinderFeed())
        let (white, black) = (flatScreen(RGB(255, 255, 255)), flatScreen(RGB(0, 0, 0)))
        var settings = Viewfinder.Settings(
            spec: .hires, converter: Converter.Settings(display: .green), orientation: .up, afterglow: 0.1)
        _ = viewfinder.glowing(white, settings, at: 0)
        let trail = viewfinder.glowing(black, settings, at: 0.05)
        settings.afterglow = 0
        let plain = viewfinder.glowing(black, settings, at: 0.1)
        #expect(trail != black)
        #expect(plain == black)
    }

    /// Sharp is a flat screen: it shows no CRT layer, and its CRT switch says
    /// so. Only the amber and green monitors glow on.
    @Test func sharpHasNoCRT() {
        let model = CameraModel()
        #expect(model.crtOn && model.crtShown)
        model.select(Monitor.sharp)
        #expect(!model.crtShown)
        model.toggleCRT()
        #expect(model.crtOn)
        #expect(model.message?.title == "NO CRT ON SHARP")
        model.select(Monitor.tv)
        #expect(model.crtShown)
        model.toggleCRT()
        #expect(!model.crtOn && !model.crtShown)
        #expect(Monitor.allCases.filter { $0.hasAfterglow } == [.amber, .green])
    }

    /// The CRT shader compiles, with the arguments the TV gives it.
    @Test func crtShaderCompiles() async throws {
        let source = CRTSource(flatScreen(RGB(100, 100, 100)))
        try await CRTScreen.shader(source, .standard, scale: 3).compile(as: .shapeStyle)
    }

    /// The picture as on TV, which is shared, shows the CRT layer when it is
    /// on: down a grey screen, its lines have dark gaps between them. Without
    /// it, every line of the grey looks the same.
    @Test func sharedPictureShowsTheCRTLayer() throws {
        let picture = try #require(ShownPicture(flatScreen(RGB(100, 100, 100)), frame: C64Frame(mode: .hiresBitmap)))
        let plain = try #require(TVView.shareImage(of: picture, crt: nil)?.cgImage.flatMap { RGBImage($0) })
        let crt = try #require(TVView.shareImage(of: picture, crt: .standard)?.cgImage.flatMap { RGBImage($0) })
        #expect(plain.width == 1536 && crt.width == 1536)
        /// Ten lines down the middle of the screen, about four pixels each.
        func middle(_ image: RGBImage) -> [UInt8] {
            (image.height / 2..<image.height / 2 + 43).map { image[image.width / 2, $0].g }
        }
        let (plainColumn, crtColumn) = (middle(plain), middle(crt))
        #expect(Set(plainColumn).count == 1, "Without the CRT layer: \(plainColumn)")
        #expect(
            (crtColumn.max() ?? 0) - (crtColumn.min() ?? 0) > 40, "With the CRT layer: \(crtColumn)")
    }

    // MARK: - Switching the TV off and on

    /// When the tubes in these tests begin moving.
    private let poweredAt = Date(timeIntervalSinceReferenceDate: 0)

    /// Switching off, the picture closes into a line, brighter as it closes,
    /// and the line shrinks to a dot, which fades (docs/UX.md, section 3).
    @Test func switchingOffClosesThePictureIntoALineThenADot() {
        var tube = Tube(.on)
        tube.move(to: .off, animated: true, at: poweredAt)
        func raster(_ seconds: Double) -> Raster { tube.raster(at: poweredAt + seconds) }
        #expect(raster(0) == .on)
        let closing = raster(0.08)
        #expect(closing.height > 0.5 && closing.height < 1 && closing.width == 1)
        #expect(closing.gain > 1 && closing.beam == 0 && closing.pictureOpacity == 1)
        let line = raster(0.17)
        #expect(line.height == 0 && line.width > 0.99 && line.beam == 1 && line.pictureOpacity == 0)
        let shrinking = raster(0.3)
        #expect(shrinking.height == 0 && shrinking.width > 0 && shrinking.width < 1 && shrinking.light == 1)
        let fading = raster(0.6)
        #expect(fading.width == 0 && fading.light > 0 && fading.light < 1 && fading.beam == fading.light)
        #expect(abs(tube.end.timeIntervalSince(poweredAt) - 1.18) < 1e-9)
        #expect(raster(1.2) == .off)
        // It stops redrawing once it gets there.
        #expect(!tube.isSettled && tube.settled.isSettled && tube.settled.raster(at: poweredAt) == .off)
    }

    /// Warming up, a dot stretches into a line, which holds until there is a
    /// picture, then opens into it.
    @Test func warmingUpHoldsTheLineUntilThereIsAPicture() {
        var tube = Tube(.off)
        tube.move(to: .line, animated: true, at: poweredAt)
        func raster(_ seconds: Double) -> Raster { tube.raster(at: poweredAt + seconds) }
        let dot = raster(0.03)
        #expect(dot.width == 0 && dot.light > 0 && dot.light < 1)
        let stretching = raster(0.2)
        #expect(stretching.height == 0 && stretching.width > 0 && stretching.width < 1 && stretching.light == 1)
        #expect(raster(5) == Raster(level: 2) && raster(5).beam == 1)
        tube.move(to: .on, animated: true, at: poweredAt + 5)
        let opening = raster(5.2)
        #expect(opening.height > 0 && opening.height < 1 && opening.gain > 1)
        #expect(raster(5.5) == .on)
    }

    /// A tube that turns back halfway goes back from where it is.
    @Test func aTubeTurnsBackFromWhereItIs() {
        var tube = Tube(.on)
        tube.move(to: .off, animated: true, at: poweredAt)
        let turn = poweredAt + 0.3
        let halfway = tube.level(at: turn)
        tube.move(to: .on, animated: true, at: turn)
        #expect(tube.level(at: turn) == halfway)
        #expect(tube.level(at: turn + 0.05) > halfway)
        #expect(tube.raster(at: turn + 2) == .on)
    }

    /// With Reduce Motion on, or without the CRT layer, the TV switches off
    /// and on at once, and shows no line while it warms up.
    @Test func withoutMotionTheTVSwitchesAtOnce() {
        var tube = Tube(.on)
        tube.move(to: .off, animated: false, at: poweredAt)
        #expect(tube.isSettled && tube.raster(at: poweredAt) == .off)
        tube.move(to: .line, animated: false, at: poweredAt)
        #expect(tube.raster(at: poweredAt) == .off)
        tube.move(to: .on, animated: false, at: poweredAt)
        #expect(tube.raster(at: poweredAt) == .on)
    }

    /// The picture gains as much light as it loses height, and the line takes
    /// over from it over its last 5%.
    @Test func theLineTakesOverAsThePictureCloses() {
        let open = Raster(level: 3)
        #expect(open == .on && open.gain == 1 && open.beam == 0 && open.pictureOpacity == 1)
        let half = Raster(height: 0.5, width: 1, light: 1)
        #expect(half.gain == 2 && half.beam == 0)
        let almost = Raster(height: 0.025, width: 1, light: 1)
        #expect(abs(almost.beam - 0.25) < 1e-9 && abs(almost.pictureOpacity - 0.75) < 1e-9)
        #expect(abs(almost.gain - 40) < 1e-9)
        let line = Raster(level: 2)
        #expect(line.beam == 1 && line.pictureOpacity == 0)
        #expect(Raster(level: 0) == .off)
    }

    /// The badge switches the TV off, and what was on its glass goes with
    /// it; any key, or the badge again, switches it back on.
    @Test func theBadgeSwitchesTheTVOff() {
        let model = CameraModel()
        #expect(model.tvOn)
        model.select(Monitor.amber)
        #expect(model.message != nil)
        model.togglePower()
        #expect(!model.tvOn && model.message == nil)
        model.switchOn()
        #expect(model.tvOn)
        model.togglePower()
        model.togglePower()
        #expect(model.tvOn)
    }

    /// A camera switched off with the TV stays off, whatever would start it
    /// again, until the TV is switched back on. Its viewfinder then starts
    /// over, so that the TV's warm-up waits for its first picture since.
    /// (The Simulator has no camera, so there it ends up unavailable.)
    @Test func aSwitchedOffCameraStaysOff() async throws {
        let camera = LiveCamera()
        let picture = try #require(ShownPicture(flatScreen(RGB(0, 0, 0)), frame: C64Frame(mode: .hiresBitmap)))
        camera.feed.show(picture)
        camera.switchOff()
        #expect(camera.state == .off)
        await camera.start(.back)
        await camera.sessionFailed(.mediaServicesWereReset, position: .back)
        camera.wasInterrupted()
        await camera.interruptionEnded(.back)
        #expect(camera.state == .off && camera.feed.hasPicture)
        camera.switchOn(.back)
        #expect(camera.state == .starting && !camera.feed.hasPicture)
        await camera.start(.back)
        #expect(camera.state == .unavailable)
    }

    /// The tube's shaders compile, with the arguments the TV gives them, and
    /// its line and dot take the monitor's phosphor colour.
    @Test func tubeShadersCompile() async throws {
        #expect(Monitor.tv.phosphor == RGB(255, 255, 255))
        #expect(Monitor.amber.phosphor == DisplayModel.Phosphor.amber.color)
        let face = TubeFace.shader(Raster(level: 2), phosphor: Monitor.green.phosphor, crt: .standard, scale: 3)
        try await face.compile(as: .shapeStyle)
        try await TubeFace.gain(4).compile(as: .colorEffect)
    }

    /// The tube's face is its dark glass, rounded like the CRT layer's tube,
    /// with the line across its middle in the phosphor's colour, white-hot at
    /// its core.
    @Test func tubeFaceShowsTheLineOnTheGlass() throws {
        func drawn(_ raster: Raster) throws -> RGBImage {
            let face = TubeFace(raster: raster, phosphor: Monitor.green.phosphor, crt: .standard)
                .frame(width: 400, height: 300)
                .environment(\.displayScale, 1)
            let renderer = ImageRenderer(content: face)
            renderer.scale = 1
            renderer.isOpaque = true
            return try #require(renderer.cgImage.flatMap { RGBImage($0) })
        }
        let line = try drawn(Raster(level: 2))
        let core = line[200, 150]
        #expect(core.g > 200 && core.r > 150 && core.g > core.r, "The line's core: \(core)")
        let glass = line[200, 60]
        #expect(glass.g > 15 && glass.g < 80 && glass.g > glass.r, "The glass: \(glass)")
        #expect(line[0, 0].g < 3, "Beyond the tube's corner: \(line[0, 0])")
        let off = try drawn(.off)
        #expect(off[200, 150].g < 80, "Off: \(off[200, 150])")
    }

    /// As the picture closes, it gains light, saturating towards white, and
    /// black stays black.
    @Test func closingPictureGainsLight() throws {
        func drawn(gain: Double) throws -> RGBImage {
            let picture = HStack(spacing: 0) {
                Color(white: 0.5)
                Color.black
            }
            .frame(width: 20, height: 10)
            .colorEffect(TubeFace.gain(gain))
            let renderer = ImageRenderer(content: picture)
            renderer.scale = 1
            return try #require(renderer.cgImage.flatMap { RGBImage($0) })
        }
        let plain = try drawn(gain: 1)
        let brighter = try drawn(gain: 4)
        #expect(Int(brighter[5, 5].g) > Int(plain[5, 5].g) + 40, "\(plain[5, 5]) and \(brighter[5, 5])")
        #expect(brighter[15, 5].g < 3, "Black: \(brighter[15, 5])")
    }
}
