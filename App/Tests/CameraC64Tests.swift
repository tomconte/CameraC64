import C64Core
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
        model.capture(animated: false)
        #expect(model.stage == .review)
        #expect(model.lastShot == .hires)
        #expect(model.reviewMode == .hires)

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
        #expect(PictureMode.allCases.filter { $0.spec != nil } == [.hires, .multicolour])
        #expect(PictureMode.allCases.allSatisfy { ($0.spec == nil) == ($0.sample != nil) })
    }

    /// Every mode's picture comes out at the screen's size, border included,
    /// and its display window at the picture's.
    @Test func everyModeHasAPicture() async {
        let maker = PictureMaker()
        #expect(maker.photo != nil)
        for mode in PictureMode.allCases {
            await maker.make(mode, for: .tv)
            let picture = maker.picture(mode, on: .tv)
            #expect(picture?.screen.width == 384 && picture?.screen.height == 272, "\(mode.name)")
            #expect(picture?.window.width == 320 && picture?.window.height == 200, "\(mode.name)")
        }
        #expect(maker.picture(.hires, on: .sharp) == nil)
    }

    /// The black-and-white monitor shows greys, from the display model rather
    /// than a tint.
    @Test func blackAndWhiteShowsGreys() async throws {
        let maker = PictureMaker()
        await maker.make(.multicolour, for: .blackAndWhite)
        let screen = try #require(maker.picture(.multicolour, on: .blackAndWhite)?.screen)
        let pixels = try #require(RGBImage(screen)).bytes
        #expect(stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0] == pixels[$0 + 1] })
        #expect(stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0 + 1] == pixels[$0 + 2] })
    }

    @Test func picturesRoundTripThroughCoreGraphics() throws {
        let image = RGBImage(width: 2, height: 1, layout: .rgb, bytes: [255, 0, 0, 10, 200, 30])
        let back = try #require(RGBImage(try #require(image.cgImage)))
        #expect(back.width == 2 && back.height == 1)
        #expect(Array(back.bytes[0..<3]) == [255, 0, 0])
        #expect(Array(back.bytes[4..<7]) == [10, 200, 30])
    }
}
