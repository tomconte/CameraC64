import Foundation
import Testing

@testable import C64Core

private let bitmapModes: [ModeSpec] = [.hires, .multicolor]

/// A smooth, colourful target: hue across, lightness down.
private func gradient(for spec: ModeSpec) -> Target {
    var colors: [OKLab] = []
    for y in 0..<spec.height {
        for x in 0..<spec.width {
            let angle = Float(x) / Float(spec.width) * 2 * .pi
            let lightness = 0.1 + 0.8 * Float(y) / Float(spec.height)
            colors.append(OKLab(l: lightness, a: 0.12 * cos(angle), b: 0.12 * sin(angle)))
        }
    }
    return Target(width: spec.width, height: spec.height, colors: colors)
}

/// Every set of `size` numbers below `count`.
private func combinations(_ count: Int, _ size: Int) -> [[Int]] {
    guard size > 0 else { return [[]] }
    guard count >= size else { return [] }
    return combinations(count - 1, size) + combinations(count - 1, size - 1).map { $0 + [count - 1] }
}

@Test func convertsTheBitmapModes() {
    #expect(Converter.supports(.hires) && Converter.supports(.multicolor))
    #expect(!Converter.supports(.characterSet))
    #expect(!Converter.supports(.multicolorCharacterSet))
    #expect(!Converter.supports(.extendedColorCharacterSet))
}

/// A picture that a C64 can show converts to itself, pixel for pixel.
@Test(arguments: bitmapModes)
func picturesTheC64CanShowComeBackUnchanged(spec: ModeSpec) {
    for seed in 1...2 {
        let original = ModePicture.random(spec, seed: UInt64(seed))
        let image = original.image()
        let settings = Converter.Settings(display: .sharp, border: original.borderColor)
        let full = Crop(x: 0, y: 0, width: 320, height: 200)
        let conversion = Converter(spec: spec, settings: settings).convert(
            image.rgbImage(.colodore), crop: full, tones: .neutral)
        #expect(conversion.picture.image() == image)
        let screen = VICII.render(conversion.frame)
        #expect(screen.window == image)
        #expect(screen[0, 0] == original.borderColor)
    }
}

/// The search finds, for each background, the best set containing it, or
/// the best overall: the same as trying every set one by one.
@Test(arguments: bitmapModes)
func searchFindsTheBestSets(spec: ModeSpec) {
    let converter = Converter(spec: spec)
    let pixels = converter.cellWidth * converter.cellHeight
    let workspace = Converter.Workspace(converter, pixels: pixels)
    defer { workspace.deallocate() }
    var generator = SeededGenerator(seed: 11)
    for index in 0..<converter.pairFirst.count * pixels {
        workspace.rows[index] = UInt16.random(in: 0...20_000, using: &generator)
    }
    let count = converter.candidates.count
    let slots = converter.backgroundMap == nil ? 1 : count
    var scores = [UInt32](repeating: .max, count: slots)
    var sets = [UInt32](repeating: .max, count: slots)
    scores.withUnsafeMutableBufferPointer { scores in
        sets.withUnsafeMutableBufferPointer { sets in
            converter.search(workspace, scores: scores.baseAddress!, sets: sets.baseAddress!)
        }
    }

    var expected = [UInt32](repeating: .max, count: slots)
    for set in combinations(count, converter.setSize) {
        var packed = UInt32.max
        for (index, member) in set.enumerated() {
            packed = packed & ~(0xFF << (8 * index)) | UInt32(member) << (8 * index)
        }
        let score = converter.score(of: packed, workspace)
        for slot in slots == 1 ? [0] : set {
            expected[slot] = min(expected[slot], score)
        }
    }
    #expect(scores == expected)
    for slot in 0..<slots {
        #expect(converter.score(of: sets[slot], workspace) == scores[slot])
        #expect(slots == 1 || Converter.members(sets[slot]).contains(slot))
    }
}

/// Each pair's cost for a pixel is the squared OKLab distance to the closer
/// of its colours, or to its best mix as the monitor shows it, plus the mix's
/// texture penalty.
@Test(arguments: [DisplayModel.tv, .sharp])
func pairCostsFollowTheDisplayModel(display: DisplayModel) {
    let spec = ModeSpec.multicolor
    let settings = Converter.Settings(display: display, dithering: 0.6)
    let converter = Converter(spec: spec, settings: settings)
    let target = gradient(for: spec)
    let workspace = Converter.Workspace(converter, pixels: 32)
    defer { workspace.deallocate() }
    let cell = 413
    workspace.load(cell, of: target, for: converter)
    converter.pairCosts(workspace)
    for pair in [0, 17, 60, 119] {
        let first = C64Color.allCases[Int(converter.pairFirst[pair])]
        let second = C64Color.allCases[Int(converter.pairSecond[pair])]
        let mixes = display.mixes(first, second, palette: .colodore, pixelWidth: 2)
        for pixel in [0, 13, 31] {
            let (x, y) = (cell % 40 * 4 + pixel % 4, cell / 40 * 8 + pixel / 4)
            let color = target.colors[y * spec.width + x]
            var best = [first, second].map { color.distanceSquared(to: OKLab(C64Palette.colodore[$0])) }.min()!
            for mix in mixes {
                best = min(best, color.distanceSquared(to: OKLab(mix.color)) + 0.4 * mix.texture)
            }
            let cost = Float(workspace.rows[pair * 32 + pixel])
            #expect(abs(cost - best * 262_144) <= 2, "pair \(pair), pixel \(pixel)")
        }
    }
}

/// A grey that only a half-and-half pattern of black and white can show
/// comes out as that pattern.
@Test func ditheringFollowsTheBayerPattern() {
    let spec = ModeSpec.hires
    let grey = OKLab(LinearRGB(r: 0.5, g: 0.5, b: 0.5))
    let target = Target(width: 320, height: 200, colors: Array(repeating: grey, count: 64_000))
    let settings = Converter.Settings(display: .sharp, dithering: 1)
    let image = Converter(spec: spec, settings: settings).convert(target).picture.image()
    for y in 0..<200 {
        for x in 0..<320 {
            let expected: C64Color = Bayer.showsSecond(level: 8, x: x, y: y) ? .white : .black
            guard image[x, y] == expected else {
                Issue.record("(\(x), \(y)) is \(image[x, y])")
                return
            }
        }
    }
}

/// Without dithering, each pixel takes whichever of its cell's colours is
/// closest.
@Test func withoutDitheringPixelsTakeTheClosestColour() {
    let spec = ModeSpec.hires
    let target = gradient(for: spec)
    let settings = Converter.Settings(display: .sharp, dithering: 0)
    let picture = Converter(spec: spec, settings: settings).convert(target).picture
    let image = picture.image()
    for cell in stride(from: 0, to: 1000, by: 37) {
        let colors = [picture.colors[0][cell], picture.colors[1][cell]].map { OKLab(C64Palette.colodore[$0]) }
        for pixel in 0..<64 {
            let (x, y) = (cell % 40 * 8 + pixel % 8, cell / 40 * 8 + pixel / 8)
            let wanted = target.colors[y * 320 + x]
            let shown = OKLab(C64Palette.colodore[image[x, y]])
            #expect(wanted.distanceSquared(to: shown) <= colors.map(wanted.distanceSquared).min()! + 0.0001)
        }
    }
}

/// On a monochrome monitor only lightness counts, and each brightness has one
/// colour, a grey where there is one.
@Test(arguments: bitmapModes)
func monochromeSearchesBrightnessOnly(spec: ModeSpec) {
    let converter = Converter(spec: spec, settings: Converter.Settings(display: .blackAndWhite))
    #expect(converter.candidates == [.black, .white, .purple, .green, .blue, .yellow, .darkGrey, .grey, .lightGrey])
    let target = gradient(for: spec)
    var grey = target
    for index in grey.colors.indices {
        grey.colors[index].a = 0
        grey.colors[index].b = 0
    }
    let conversion = converter.convert(target)
    #expect(conversion == converter.convert(grey))
    let used = Set(conversion.picture.image().pixels.map { C64Color(rawValue: $0)! })
    #expect(used.isSubset(of: Set(converter.candidates)))
}

@Test func theBorderMatchesTheEdges() {
    var image = IndexedImage(width: 320, height: 200, fill: .red)
    for x in 0..<320 {
        image[x, 0] = .blue
        image[x, 199] = .blue
    }
    #expect(image.edgeColor == .blue)
    // Equal counts: the lower colour.
    var halves = IndexedImage(width: 4, height: 4, fill: .cyan)
    for y in 0..<4 {
        halves[0, y] = .red
        halves[1, y] = .red
    }
    #expect(halves.edgeColor == .red)

    let spec = ModeSpec.multicolor
    let target = gradient(for: spec)
    let automatic = Converter(spec: spec).convert(target).picture
    #expect(automatic.borderColor == automatic.image().edgeColor)
    let chosen = Converter(spec: spec, settings: Converter.Settings(border: .lightBlue)).convert(target)
    #expect(chosen.picture.borderColor == .lightBlue && chosen.frame.borderColor == .lightBlue)
}

@Test(arguments: bitmapModes)
func conversionsAreRepeatable(spec: ModeSpec) {
    let converter = Converter(spec: spec)
    let target = gradient(for: spec)
    let conversion = converter.convert(target)
    #expect(conversion == converter.convert(target))
    #expect(VICII.render(conversion.frame).window == conversion.picture.image())
}

/// In the viewfinder, a cell keeps its colours from one frame to the next
/// unless new ones are clearly better.
@Test(arguments: bitmapModes)
func viewfinderFramesKeepTheirColours(spec: ModeSpec) {
    let converter = Converter(spec: spec)
    let target = gradient(for: spec)
    let first = converter.convert(target)
    // The same scene with a little noise, as the next video frame.
    var generator = SeededGenerator(seed: 3)
    var next = target
    for index in next.colors.indices {
        next.colors[index].l += Float.random(in: -0.03...0.03, using: &generator)
    }
    func changedCells(_ conversion: Conversion) -> Int {
        (0..<1000).filter { cell in
            spec.maps.indices.contains { map in
                let index = spec.maps[map].granularity == .global ? 0 : cell
                return conversion.picture.colors[map][index] != first.picture.colors[map][index]
            }
        }.count
    }
    let fresh = changedCells(converter.convert(next))
    let steady = changedCells(converter.convert(next, keeping: first))
    #expect(fresh >= 10)
    #expect(steady <= fresh / 5)

    // In a different scene, most cells take new colours: only those whose
    // old colours are nearly as good keep them.
    var other = target
    other.colors.reverse()
    #expect(changedCells(converter.convert(other, keeping: first)) >= 800)
}

@Test func speedBenchmarkTimesEveryStage() {
    #expect(SpeedBenchmark.cases.count == 6)
    let frame = SpeedBenchmark.cameraFrame(width: 160, height: 120)
    #expect(frame.layout == .bgra && frame.bytes.count == 160 * 120 * 4)
    let timing = SpeedBenchmark.measure(SpeedBenchmark.cases[0], frame: frame, runs: 1)
    #expect([timing.target, timing.conversion, timing.rendering, timing.display].allSatisfy { $0 > 0 })
    #expect(abs(timing.total - timing.target - timing.conversion - timing.rendering - timing.display) < 1e-9)
    #expect(SpeedBenchmark.describe(timing).hasSuffix("fps"))
}
