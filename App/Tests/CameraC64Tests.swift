import SwiftUI
import Testing

@testable import CameraC64

/// The placeholder camera screen's logic. C64 logic is tested in Packages/C64Core.
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
        #expect(abs(picture.midY - tv.height / 2) < 0.001)
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
}
