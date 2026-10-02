import C64Core
import Foundation
import Testing

@testable import C64Tools

/// A picture whose every pixel comes from a function of its position.
private func picture(width: Int = 64, height: Int = 40, _ color: (Int, Int) -> RGB) -> RGBImage {
    var image = RGBImage(width: width, height: height, fill: RGB(0, 0, 0))
    for y in 0..<height {
        for x in 0..<width {
            image[x, y] = color(x, y)
        }
    }
    return image
}

/// The target of a picture taken whole, as it is.
private func target(of image: RGBImage) -> Target {
    Target(
        image, width: image.width, height: image.height,
        crop: Crop(x: 0, y: 0, width: Double(image.width), height: Double(image.height)), tones: .neutral)
}

@Test func aPictureScoresZeroAgainstItself() {
    let image = picture { x, y in RGB(UInt8(x * 4), UInt8(y * 6), 90) }
    #expect(Quality.score(image, target: target(of: image)) < 0.01)
}

@Test func aColourCastScoresItsDistance() {
    let grey = picture { _, _ in RGB(128, 128, 128) }
    let pink = picture { _, _ in RGB(150, 120, 128) }
    let distance = Double(OKLab(RGB(128, 128, 128)).distance(to: OKLab(RGB(150, 120, 128))))
    #expect(abs(Quality.score(pink, target: target(of: grey)) - distance * 100) < 0.01)
    // A monochrome monitor only counts lightness.
    let lightness = Double(abs(OKLab(RGB(128, 128, 128)).l - OKLab(RGB(150, 120, 128)).l))
    #expect(abs(Quality.score(pink, target: target(of: grey), monochrome: true) - lightness * 100) < 0.01)
}

/// The eye averages a fine dither out, but not broad stripes.
@Test func fineDitherLooksLikeItsAverage() {
    let grey = LinearRGB(r: 0.5, g: 0.5, b: 0.5).rgb
    let flat = target(of: picture { _, _ in grey })
    let fine = picture { x, y in (x + y) % 2 == 0 ? RGB(0, 0, 0) : RGB(255, 255, 255) }
    let broad = picture { x, _ in x / 16 % 2 == 0 ? RGB(0, 0, 0) : RGB(255, 255, 255) }
    #expect(Quality.score(fine, target: flat) < 5)
    #expect(Quality.score(broad, target: flat) > 30)
}

@Test func scoresRoundTripThroughTheirFile() throws {
    let shown = picture { _, _ in RGB(0, 0, 0) }
    let entries = [
        Benchmark.Entry(photo: "chart", mode: "hires", monitor: "tv", score: 3.25, seconds: 0.02, shown: shown),
        Benchmark.Entry(photo: "kodim04", mode: "multicolour", monitor: "bw", score: 1.5, seconds: 0.01, shown: shown),
    ]
    let file = try temporaryFile(named: "scores.txt", contents: [])
    try Benchmark.write(entries, to: file)
    #expect(try Benchmark.scores(in: file) == ["chart hires tv": 3.25, "kodim04 multicolour bw": 1.5])
}

@Test func comparisonsCatchWorseScores() {
    let shown = picture { _, _ in RGB(0, 0, 0) }
    func entries(_ scores: [Double]) -> [Benchmark.Entry] {
        scores.enumerated().map { index, score in
            Benchmark.Entry(
                photo: "photo\(index)", mode: "hires", monitor: "tv", score: score, seconds: 0, shown: shown)
        }
    }
    let baseline = ["photo0 hires tv": 4.0, "photo1 hires tv": 3.0]
    #expect(Benchmark.compare(entries([4.0, 3.0]), with: baseline).passed)
    #expect(Benchmark.compare(entries([3.0, 3.05]), with: baseline).passed)
    // One picture more than 2% worse.
    let worse = Benchmark.compare(entries([4.1, 2.0]), with: baseline)
    #expect(!worse.passed && worse.regressions.map(\.key) == ["photo0 hires tv"])
    // Each picture a little worse, but the mean more than 0.5%.
    #expect(!Benchmark.compare(entries([4.06, 3.04]), with: baseline).passed)
    // A picture missing from the baseline needs the baseline updated.
    let added = Benchmark.compare(entries([4.0, 3.0, 2.0]), with: baseline)
    #expect(!added.passed && added.unmatched == ["photo2 hires tv"])
}

@Test func darkerPhotosLoseStops() throws {
    let file = try temporaryFile(named: "photo.png", contents: PNG.encode(picture { _, _ in RGB(255, 255, 255) }))
    let photo = try Benchmark.photo(named: "white", description: "", file: file, exposure: -1)
    #expect(photo.image[0, 0] == LinearRGB(r: 0.5, g: 0.5, b: 0.5).rgb)
}

@Test func thePhotoListReadsItsLines() throws {
    let directory = try temporaryFile(named: "list.txt", contents: []).deletingLastPathComponent()
    try Data(PNG.encode(picture { _, _ in RGB(10, 20, 30) })).write(to: directory.appendingPathComponent("a.png"))
    let list = directory.appendingPathComponent("list.txt")
    try "# A comment\na.png 0123 0 A test photo\na.png 0123 -2.5 The same, darker\n".write(
        to: list, atomically: true, encoding: .utf8)
    let photos = try Benchmark.photos(list: list, directory: directory)
    #expect(photos.map(\.name) == ["a", "a-dark"])
    #expect(photos.map(\.description) == ["A test photo", "The same, darker"])
    #expect(throws: Benchmark.Error.self) {
        try Benchmark.photos(list: list, directory: directory.appendingPathComponent("missing"))
    }
}
