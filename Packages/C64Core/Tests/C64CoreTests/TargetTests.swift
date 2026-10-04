import Foundation
import Testing

@testable import C64Core

/// OKLab values of sRGB's primaries, from Björn Ottosson's reference code.
@Test(arguments: [
    (RGB(255, 0, 0), OKLab(l: 0.627_955, a: 0.224_863, b: 0.125_846)),
    (RGB(0, 255, 0), OKLab(l: 0.866_440, a: -0.233_888, b: 0.179_498)),
    (RGB(0, 0, 255), OKLab(l: 0.452_014, a: -0.032_457, b: -0.311_528)),
    (RGB(255, 255, 255), OKLab(l: 1, a: 0, b: 0)),
    (RGB(0, 0, 0), OKLab(l: 0, a: 0, b: 0)),
])
func okLabMatchesTheReference(color: RGB, expected: OKLab) {
    let lab = OKLab(color)
    #expect(lab.distance(to: expected) < 0.001)
}

@Test func okLabRoundTrips() {
    for value in stride(from: 0, through: 255, by: 15) {
        let color = RGB(UInt8(value), UInt8(255 - value), UInt8(value / 2))
        #expect(OKLab(color).linear.rgb == color)
    }
}

/// OKLab's cube roots are never more than a unit in the last place from the
/// exact root, on any platform, whatever the number.
@Test func cubeRootsAreRight() {
    var generator = SeededGenerator(seed: 27)
    var values: [Float] = [
        0, -0, 1, 8, -27, 0.001, .leastNormalMagnitude / 2, .leastNonzeroMagnitude, .infinity, -.infinity,
    ]
    values += (0..<100_000).map { index in
        let value = pow(10, Float.random(in: -37...3, using: &generator))
        return index % 3 == 0 ? -value : value
    }
    for value in values {
        let exact = Float(cbrt(Double(value)))
        let root = OKLab.cubeRoot(value)
        #expect(abs(Int(root.bitPattern) - Int(exact.bitPattern)) <= 1, "\(value)")
    }
    #expect(OKLab.cubeRoot(.nan).isNaN)
}

@Test func srgbRoundTrips() {
    for value in 0...255 {
        #expect(SRGB.encoded(SRGB.linear[value]) == UInt8(value))
    }
    #expect(abs(SRGB.linear[128] - 0.2159) < 0.0001)
}

@Test func linearMixesAddLight() {
    let grey = LinearRGB.mix(LinearRGB(RGB(0, 0, 0)), LinearRGB(RGB(255, 255, 255)), ratio: 0.5)
    #expect(grey.rgb == RGB(188, 188, 188))
}

@Test func rgbImagesReadEveryLayout() {
    let rgb = RGBImage(width: 1, height: 1, layout: .rgb, bytes: [10, 20, 30])
    let rgba = RGBImage(width: 1, height: 1, layout: .rgba, bytes: [10, 20, 30, 255])
    let bgra = RGBImage(width: 1, height: 1, layout: .bgra, bytes: [30, 20, 10, 255])
    #expect(rgb[0, 0] == RGB(10, 20, 30) && rgba[0, 0] == RGB(10, 20, 30) && bgra[0, 0] == RGB(10, 20, 30))
}

@Test func cropsTakeTheWindowsShape() {
    #expect(abs(Screen.windowAspectRatio - 1.4976) < 0.0001)
    let wide = Crop.centered(width: 4032, height: 3024)
    #expect(abs(wide.width / wide.height - Screen.windowAspectRatio) < 0.0001)
    #expect(wide.width == 4032 && abs(wide.y - (3024 - wide.height) / 2) < 0.0001)
    let tall = Crop.centered(width: 3024, height: 4032)
    #expect(tall.width == 3024 && abs(tall.height - 3024 / Screen.windowAspectRatio) < 0.0001)
}

/// A photo whose every pixel is the given colour, or a pattern of colours.
private func photo(width: Int, height: Int, _ color: (Int, Int) -> RGB) -> RGBImage {
    var image = RGBImage(width: width, height: height, fill: RGB(0, 0, 0))
    for y in 0..<height {
        for x in 0..<width {
            image[x, y] = color(x, y)
        }
    }
    return image
}

@Test func pixelsAverageTheirAreaInLinearLight() {
    // A checkerboard of black and white pixels, two photo pixels for each
    // target pixel each way, averages to the grey of half the light.
    let checkerboard = photo(width: 640, height: 400) { x, y in
        (x + y) % 2 == 0 ? RGB(0, 0, 0) : RGB(255, 255, 255)
    }
    let target = Target(
        checkerboard, width: 320, height: 200, crop: Crop(x: 0, y: 0, width: 640, height: 400), tones: .neutral)
    let expected = OKLab(LinearRGB(r: 0.5, g: 0.5, b: 0.5))
    #expect(target.colors.allSatisfy { $0.distance(to: expected) < 0.0001 })
}

@Test func partlyCoveredPixelsCountForTheirShare() {
    // Three photo pixels, black, white and black, into two: each target pixel
    // covers one and a half photo pixels, half of them the white one.
    let stripes = photo(width: 3, height: 1) { x, _ in x == 1 ? RGB(255, 255, 255) : RGB(0, 0, 0) }
    let target = Target(stripes, width: 2, height: 1, crop: Crop(x: 0, y: 0, width: 3, height: 1), tones: .neutral)
    let third = OKLab(LinearRGB(r: 1 / 3, g: 1 / 3, b: 1 / 3))
    #expect(target.colors.allSatisfy { $0.distance(to: third) < 0.0001 })
}

@Test func targetsTakeTheCentreByDefault() {
    // A square photo with a red band across the middle third: the window's
    // shape crops off the top and the bottom.
    let band = photo(width: 300, height: 300) { _, y in (100..<200).contains(y) ? RGB(255, 0, 0) : RGB(0, 0, 255) }
    let target = Target(band, width: 16, height: 10, tones: .neutral)
    let red = OKLab(RGB(255, 0, 0))
    #expect(target.colors[5 * 16 + 8].distance(to: red) < 0.0001)
    #expect(target.colors[0].distance(to: red) > 0.1)
    #expect(target.rgbImage[8, 5] == RGB(255, 0, 0))
}

@Test func neutralTonesChangeNothing() {
    let colors = photo(width: 8, height: 8) { x, y in RGB(UInt8(x * 30), UInt8(y * 30), 128) }
    let target = Target(colors, width: 8, height: 8, crop: Crop(x: 0, y: 0, width: 8, height: 8), tones: .neutral)
    for y in 0..<8 {
        for x in 0..<8 {
            #expect(target.colors[y * 8 + x].distance(to: OKLab(colors[x, y])) < 0.0001)
        }
    }
}

@Test func toneControlsMoveLightnessAndColour() {
    let grey = photo(width: 4, height: 4) { _, _ in RGB(119, 119, 119) }
    let crop = Crop(x: 0, y: 0, width: 4, height: 4)
    let base = OKLab(RGB(119, 119, 119)).l
    func lightness(_ tones: Tones) -> Float {
        Target(grey, width: 2, height: 2, crop: crop, tones: tones).colors[0].l
    }
    #expect(abs(lightness(Tones(automatic: false, brightness: 0.1)) - (base + 0.1)) < 0.0001)
    #expect(abs(lightness(Tones(automatic: false, contrast: 2)) - (0.5 + (base - 0.5) * 2)) < 0.0001)
    #expect(abs(lightness(Tones(automatic: false, gamma: 2)) - base * base) < 0.0001)

    let orange = photo(width: 4, height: 4) { _, _ in RGB(230, 120, 20) }
    let pale = Target(orange, width: 2, height: 2, crop: crop, tones: Tones(automatic: false, saturation: 0))
    #expect(pale.colors.allSatisfy { $0.a == 0 && $0.b == 0 })
}

@Test func automaticTonesStretchADullPhoto() {
    // A gradient from dark grey to light grey reaches black and white.
    func gradient(from start: Int, by step: Int) -> RGBImage {
        photo(width: 100, height: 10) { x, _ in
            let grey = UInt8(start + x * step / 10)
            return RGB(grey, grey, grey)
        }
    }
    let crop = Crop(x: 0, y: 0, width: 100, height: 10)
    let target = Target(gradient(from: 40, by: 16), width: 100, height: 10, crop: crop, tones: Tones())
    let lightness = target.colors.map(\.l)
    #expect(lightness.min()! < 0.01 && lightness.max()! > 0.99)
    // A narrow one is stretched 2.5 times at most, around its middle.
    let narrow = Target(gradient(from: 100, by: 4), width: 100, height: 10, crop: crop, tones: Tones())
    let spread = narrow.colors.map(\.l).max()! - narrow.colors.map(\.l).min()!
    let original = OKLab(RGB(139, 139, 139)).l - OKLab(RGB(100, 100, 100)).l
    #expect(abs(spread - original * 2.5) < 0.02)
    // A flat photo stays as it is.
    let flat = photo(width: 10, height: 10) { _, _ in RGB(90, 90, 90) }
    let unchanged = Target(flat, width: 10, height: 10, crop: Crop(x: 0, y: 0, width: 10, height: 10))
    #expect(abs(unchanged.colors[0].l - OKLab(RGB(90, 90, 90)).l) < 0.0001)
}

@Test func sharpeningSteepensEdges() {
    let edge = photo(width: 10, height: 4) { x, _ in x < 5 ? RGB(80, 80, 80) : RGB(160, 160, 160) }
    let crop = Crop(x: 0, y: 0, width: 10, height: 4)
    let soft = Target(edge, width: 10, height: 4, crop: crop, tones: .neutral)
    let sharp = Target(edge, width: 10, height: 4, crop: crop, tones: Tones(automatic: false, sharpening: 1))
    #expect(sharp.colors[14].l < soft.colors[14].l)
    #expect(sharp.colors[15].l > soft.colors[15].l)
    #expect(abs(sharp.colors[10].l - soft.colors[10].l) < 0.0001)
}

// MARK: - Orientations

/// The sides of a picture as seen.
private enum Side {
    case top, bottom, left, right
}

/// Where TIFF 6.0 (tag 274) says each orientation's first stored row and
/// first stored column are seen.
private let tiffSides: [ImageOrientation: (row: Side, column: Side)] = [
    .up: (.top, .left), .upMirrored: (.top, .right), .down: (.bottom, .right), .downMirrored: (.bottom, .left),
    .leftMirrored: (.left, .top), .right: (.right, .top), .rightMirrored: (.right, .bottom), .left: (.left, .bottom),
]

/// Where stored pixel (x, y) is seen, in a picture `width` × `height` pixels
/// as seen: stored row y lies y rows in from the side the first row is on,
/// and stored column x likewise.
private func seenPixel(x: Int, y: Int, _ orientation: ImageOrientation, width: Int, height: Int) -> (x: Int, y: Int) {
    let sides = tiffSides[orientation]!
    var seen = (x: 0, y: 0)
    for (side, distance) in [(sides.row, y), (sides.column, x)] {
        switch side {
        case .top: seen.y = distance
        case .bottom: seen.y = height - 1 - distance
        case .left: seen.x = distance
        case .right: seen.x = width - 1 - distance
        }
    }
    return seen
}

/// A photo turned, pixel by pixel, as its orientation says: as it is seen.
private func turned(_ stored: RGBImage, _ orientation: ImageOrientation) -> RGBImage {
    let (width, height) = orientation.swapsAxes ? (stored.height, stored.width) : (stored.width, stored.height)
    var seen = RGBImage(width: width, height: height, fill: RGB(0, 0, 0))
    for y in 0..<stored.height {
        for x in 0..<stored.width {
            let position = seenPixel(x: x, y: y, orientation, width: width, height: height)
            seen[position.x, position.y] = stored[x, y]
        }
    }
    return seen
}

/// A photo of random colours.
private func noise(width: Int, height: Int, seed: UInt64) -> RGBImage {
    var generator = SeededGenerator(seed: seed)
    return photo(width: width, height: height) { _, _ in
        RGB(
            UInt8.random(in: 0...255, using: &generator), UInt8.random(in: 0...255, using: &generator),
            UInt8.random(in: 0...255, using: &generator))
    }
}

/// Each orientation turns a photo upright as TIFF defines it.
@Test(arguments: ImageOrientation.allCases)
func orientationsTurnPhotosAsTIFFDefines(orientation: ImageOrientation) {
    let stored = photo(width: 3, height: 2) { x, y in
        let grey = UInt8(20 + 40 * (y * 3 + x))
        return RGB(grey, grey, grey)
    }
    let (width, height) = orientation.swapsAxes ? (2, 3) : (3, 2)
    let whole = Crop(x: 0, y: 0, width: Double(width), height: Double(height))
    let target = Target(stored, width: width, height: height, crop: whole, orientation: orientation, tones: .neutral)
    for y in 0..<2 {
        for x in 0..<3 {
            let seen = seenPixel(x: x, y: y, orientation, width: width, height: height)
            #expect(target.colors[seen.y * width + seen.x].distance(to: OKLab(stored[x, y])) < 0.0001)
        }
    }
}

/// A photo in an orientation makes the same target as the photo turned
/// upright: crops are measured on the photo as seen, and centred on it by
/// default.
@Test(arguments: ImageOrientation.allCases)
func turnedPhotosAreCroppedAsSeen(orientation: ImageOrientation) {
    let stored = noise(width: 37, height: 23, seed: UInt64(orientation.rawValue))
    let upright = turned(stored, orientation)
    for crop in [Crop(x: 2.3, y: 1.7, width: 15.5, height: 10.2), nil] {
        let target = Target(stored, width: 16, height: 10, crop: crop, orientation: orientation, tones: .neutral)
        let expected = Target(upright, width: 16, height: 10, crop: crop, tones: .neutral)
        let largest = zip(target.colors, expected.colors).map { $0.distance(to: $1) }.max()!
        #expect(largest < 0.0001, "\(crop.map { "\($0)" } ?? "centred")")
    }
}

/// Points map as the pixels around them do.
@Test(arguments: ImageOrientation.allCases)
func pointsMapAsPixelsDo(orientation: ImageOrientation) {
    let (storedWidth, storedHeight) = (5, 3)
    let (width, height) = orientation.swapsAxes ? (3, 5) : (5, 3)
    for y in 0..<storedHeight {
        for x in 0..<storedWidth {
            let seen = seenPixel(x: x, y: y, orientation, width: width, height: height)
            let point = orientation.storedPoint(
                x: (Double(seen.x) + 0.5) / Double(width), y: (Double(seen.y) + 0.5) / Double(height))
            #expect(abs(point.x - (Double(x) + 0.5) / Double(storedWidth)) < 1e-12)
            #expect(abs(point.y - (Double(y) + 0.5) / Double(storedHeight)) < 1e-12)
        }
    }
}

/// Mirroring flips the picture as seen, left to right, whatever its
/// orientation.
@Test func mirroringFlipsWhatIsSeen() {
    #expect(ImageOrientation.up.mirrored == .upMirrored)
    for orientation in ImageOrientation.allCases {
        #expect(orientation.mirrored.mirrored == orientation)
        #expect(orientation.mirrored.swapsAxes == orientation.swapsAxes)
        for (x, y) in [(0.25, 0.1), (0.9, 0.6)] {
            let flipped = orientation.storedPoint(x: 1 - x, y: y)
            let mirrored = orientation.mirrored.storedPoint(x: x, y: y)
            #expect(abs(flipped.x - mirrored.x) < 1e-12 && abs(flipped.y - mirrored.y) < 1e-12)
        }
    }
}

/// Camera frames are read where they are, whatever pads their rows, and make
/// the same target as the same pixels in a photo.
@Test func framesAreReadInPlace() {
    let (width, height, padding) = (400, 260, 12)
    let photo = noise(width: width, height: height, seed: 64)
    let bytesPerRow = width * 4 + padding
    var frame = [UInt8](repeating: 0xAB, count: height * bytesPerRow)
    for y in 0..<height {
        for x in 0..<width {
            let (pixel, color) = (y * bytesPerRow + x * 4, photo[x, y])
            (frame[pixel], frame[pixel + 1], frame[pixel + 2]) = (color.b, color.g, color.r)
        }
    }
    for orientation in [ImageOrientation.up, .left] {
        let target = frame.withUnsafeBytes { bytes in
            Target(
                bytes, width: width, height: height, bytesPerRow: bytesPerRow, layout: .bgra, for: .hires,
                orientation: orientation)
        }
        #expect(target == Target(photo, for: .hires, orientation: orientation))
    }
}
