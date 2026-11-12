import CoreGraphics
import Testing

@testable import CameraC64

/// The grooves that recall the C64's vent on the camera screen's case.
struct VentTests {
    private let layout = VentLayout()

    /// Beside an element, the grooves stop short of it, on both sides, as the
    /// C64's stop round its badge, and no piece is too short to read as a
    /// groove.
    @Test func groovesStopShortOfElements() {
        let key = CGRect(x: 100, y: 40, width: 120, height: 40)
        let grooves = layout.grooves(
            width: 402, from: 0, to: 120, clearings: [VentClearing(frame: key, cornerRadius: 8)])
        #expect(grooves.allSatisfy { $0.width >= layout.shortest })
        // Where the element's sides are straight.
        let beside = grooves.filter { $0.minY >= key.minY + 8 && $0.maxY + layout.light <= key.maxY - 8 }
        #expect(!beside.isEmpty)
        for groove in beside {
            let clear =
                groove.maxX <= key.minX - layout.margin + 0.001 || groove.minX >= key.maxX + layout.margin - 0.001
            #expect(clear, "A groove at \(groove) runs into the element at \(key)")
        }
        #expect(beside.contains { $0.maxX < key.minX } && beside.contains { $0.minX > key.maxX })
        // Above it, they run across the case, short of its sides.
        let above = grooves.filter { $0.maxY + layout.light < key.minY - layout.margin }
        #expect(above.allSatisfy { $0.minX == layout.edge && $0.maxX == 402 - layout.edge })
    }

    /// Along the top of the screen, the grooves follow its rounded corners.
    @Test func groovesFollowTheScreensCorners() throws {
        let grooves = layout.grooves(width: 402, from: 9, to: 65, clearings: [], cornerRadius: 55)
        let first = try #require(grooves.first)
        let last = try #require(grooves.last)
        #expect(first.minX > last.minX + 20, "The top groove starts at \(first.minX), the lowest at \(last.minX)")
        #expect(grooves.allSatisfy { abs($0.midX - 201) < 0.001 })
    }
}
