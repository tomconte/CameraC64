import C64Core
import SwiftUI
import Testing
import UIKit

@testable import CameraC64

/// The test bundle, which holds an image of the SVG features the skin uses.
private final class TestBundle {}

/// The skin's images, drawn in `design/svg` and put into the asset catalog by
/// `design/export_skin.py` (docs/UX.md, section 7).
@MainActor
struct SkinTests {
    /// Each SVG feature the skin's images use draws as Inkscape draws it: the
    /// colours below are Inkscape's, at those points.
    @Test func svgFeaturesDrawAsInTheEditors() throws {
        let image = Image("svg-features", bundle: Bundle(for: TestBundle.self))
            .resizable()
            .frame(width: 100, height: 60)
        let drawn = try rendered(image)
        let expected: [(x: Double, y: Double, color: RGB, feature: String)] = [
            (10, 10, RGB(131, 131, 131), "a gradient in its shape's units"),
            (50, 10, RGB(0, 246, 0), "a radial gradient"),
            (70, 10, RGB(127, 127, 127), "fill opacity on a rounded rectangle"),
            (84, 30, RGB(126, 0, 129), "a stroke painted with a gradient in the drawing's units"),
            (62, 30, RGB(126, 0, 129), "a stroke painted with a gradient in its shape's units"),
            (8, 40, RGB(255, 0, 0), "an even-odd frame in a clipped group"),
            (20, 40, RGB(255, 255, 255), "the even-odd frame's hole"),
            (2, 40, RGB(255, 255, 255), "the clip"),
            (55, 45, RGB(0, 0, 255), "a moved and scaled group"),
            (78, 50, RGB(0, 255, 0), "a round line cap"),
            (90, 50, RGB(131, 131, 131), "a gradient's stop opacity"),
            (20, 8, RGB(255, 128, 0), "arcs"),
            (30, 9, RGB(255, 128, 0), "a quadratic curve"),
        ]
        for point in expected {
            let color = drawn[Int(point.x * 2), Int(point.y * 2)]
            #expect(close(color, point.color), "\(point.feature) at (\(point.x), \(point.y)): \(color)")
        }
    }

    /// Every element of the skin is in the asset catalog, at the size of its
    /// canvas in `Skin`, with its face drawn where `Skin` says it is.
    @Test func everyElementIsThere() throws {
        for element in Skin.all {
            for name in element.images {
                let image = try #require(UIImage(named: name), "\(name) is not in the asset catalog")
                #expect(image.size == element.canvas, "\(name): \(image.size), not \(element.canvas)")
                let state = name.hasSuffix("-down") || name.hasSuffix("-on")
                let face = SkinImage(element: element, state: state, width: element.face.width)
                let drawn = try rendered(face)
                let middle = drawn[drawn.width / 2, drawn.height / 2]
                #expect(!close(middle, Self.backdrop), "\(name) has nothing in the middle of its face")
            }
        }
    }

    /// Drawn where nothing covers it.
    private static let backdrop = RGB(255, 0, 255)

    /// A view drawn two pixels to the point, on magenta.
    private func rendered(_ view: some View) throws -> RGBImage {
        let renderer = ImageRenderer(content: view.background(Color(red: 1, green: 0, blue: 1)))
        renderer.scale = 2
        renderer.isOpaque = true
        return try #require(renderer.cgImage.flatMap { RGBImage($0) })
    }

    private func close(_ a: RGB, _ b: RGB, within tolerance: Int = 12) -> Bool {
        abs(Int(a.r) - Int(b.r)) <= tolerance && abs(Int(a.g) - Int(b.g)) <= tolerance
            && abs(Int(a.b) - Int(b.b)) <= tolerance
    }
}
