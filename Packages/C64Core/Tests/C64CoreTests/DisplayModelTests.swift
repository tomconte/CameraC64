import C64Core
import Foundation
import Testing

/// A picture of 16 stripes, one per colour, each `width` pixels wide.
private func stripes(width: Int = 12, height: Int = 6) -> IndexedImage {
    var image = IndexedImage(width: 16 * width, height: height)
    for y in 0..<height {
        for x in 0..<image.width {
            image[x, y] = C64Color(rawValue: UInt8(x / width))!
        }
    }
    return image
}

/// A checkerboard of two colours, with pixels `pixelWidth` hires pixels wide.
private func checkerboard(_ first: C64Color, _ second: C64Color, pixelWidth: Int = 1) -> IndexedImage {
    var image = IndexedImage(width: 48, height: 12)
    for y in 0..<12 {
        for x in 0..<48 {
            image[x, y] = (x / pixelWidth + y) % 2 == 0 ? first : second
        }
    }
    return image
}

private func distance(_ a: RGB, _ b: RGB) -> Int {
    max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)))
}

@Test(arguments: [C64Palette.colodore, .pepto2001])
func sharpShowsThePalette(palette: C64Palette) {
    let image = stripes()
    #expect(DisplayModel.sharp.show(image, palette: palette) == image.rgbImage(palette))
}

/// Colodore's palettes keep the model's own signals; for others, the signals
/// turn back into the palette's colours.
@Test func palettesCarrySignals() {
    let model = Colodore()
    #expect(C64Palette.colodore.signals == C64Color.allCases.map(model.signal))
    for (color, signal) in zip(C64Palette.pepto2001.colors, C64Palette.pepto2001.signals) {
        let rgb = Colodore.rgb(signal)
        #expect(distance(RGB(UInt8(rgb.r.rounded()), UInt8(rgb.g.rounded()), UInt8(rgb.b.rounded())), color) == 0)
    }
}

/// Blending changes nothing inside an area of one colour.
@Test(arguments: [DisplayModel.tv, .commodoreMonitor])
func areasOfOneColourKeepIt(model: DisplayModel) {
    let image = stripes()
    let shown = model.show(image, palette: .colodore)
    for color in C64Color.allCases {
        let middle = Int(color.rawValue) * 12 + 6
        #expect(distance(shown[middle, 3], C64Palette.colodore[color]) <= 1, "\(color)")
    }
}

/// On a TV, two colours of the same brightness blend into a new tint: the
/// delay line and the colour blur leave next to no texture. Different
/// brightnesses stay visible.
@Test func tvBlendsColourNotBrightness() {
    let palette = C64Palette.colodore
    func spread(_ image: RGBImage) -> Int {
        var spread = 0
        for x in 20..<28 {
            spread = max(spread, distance(image[x, 6], image[x + 1, 6]), distance(image[x, 6], image[x, 7]))
        }
        return spread
    }
    let sameBrightness = checkerboard(.purple, .orange, pixelWidth: 2)
    #expect(spread(DisplayModel.tv.show(sameBrightness, palette: palette)) <= 3)
    #expect(spread(DisplayModel.sharp.show(sameBrightness, palette: palette)) > 100)
    let blackAndWhite = checkerboard(.black, .white, pixelWidth: 2)
    #expect(spread(DisplayModel.tv.show(blackAndWhite, palette: palette)) > 150)
}

/// The delay line averages each line's colour with the line above.
@Test func delayLineAveragesWithTheLineAbove() {
    var image = IndexedImage(width: 32, height: 4, fill: .grey)
    for x in 0..<32 {
        image[x, 1] = .lightBlue
    }
    let shown = DisplayModel.commodoreMonitor.show(image, palette: .colodore)
    let blue = C64Palette.colodore[.lightBlue]
    // Grey and light blue have the same brightness, so line 2 shows half the
    // colour of line 1.
    #expect(distance(shown[16, 1], blue) > 10)
    #expect(shown[16, 2] != C64Palette.colodore[.grey])
    #expect(distance(shown[16, 3], C64Palette.colodore[.grey]) <= 1)
}

@Test(arguments: [DisplayModel.blackAndWhite, .green, .amber])
func monochromeMonitorsShowBrightness(model: DisplayModel) {
    let shown = model.show(stripes(), palette: .colodore)
    let colors = C64Color.allCases.map { shown[Int($0.rawValue) * 12 + 6, 3] }
    // Brighter colours glow brighter, and colours of equal brightness look
    // the same.
    for a in C64Color.allCases {
        for b in C64Color.allCases {
            let (one, two) = (colors[Int(a.rawValue)], colors[Int(b.rawValue)])
            if a.lumaRank == b.lumaRank {
                #expect(distance(one, two) <= 1)
            } else if a.lumaRank < b.lumaRank {
                #expect(Int(one.g) < Int(two.g))
            }
        }
    }
    #expect(colors[0] == RGB(0, 0, 0))
    #expect(colors[1] == model.phosphor!.color)
    #expect(model.color(of: .white, palette: .colodore) == model.phosphor!.color)
}

/// On a sharp display, a dithered mix is the two colours mixed in linear
/// light, and its texture is exactly what its pixels leave.
@Test func sharpMixesAreLinearLightMixes() {
    let mixes = DisplayModel.sharp.mixes(.black, .white, palette: .colodore, pixelWidth: 1)
    #expect(mixes.count == 15)
    for (index, mix) in mixes.enumerated() {
        let share = Float(index + 1) / 16
        #expect(abs(mix.color.g - share) < 0.0001)
        let center = OKLab(mix.color)
        let expected = (1 - share) * center.l * center.l + share * (1 - center.l) * (1 - center.l)
        #expect(abs(mix.texture - expected) < 0.0001)
    }
}

/// A TV hides most of the texture of colours with the same brightness, so
/// the converter can dither them freely.
@Test func tvHidesTheTextureOfEqualBrightness() {
    let tv = DisplayModel.tv.mixes(.purple, .orange, palette: .colodore, pixelWidth: 2)
    let sharp = DisplayModel.sharp.mixes(.purple, .orange, palette: .colodore, pixelWidth: 2)
    #expect(tv[7].texture < sharp[7].texture / 20)
    let contrast = DisplayModel.tv.mixes(.black, .white, palette: .colodore, pixelWidth: 2)
    #expect(contrast[7].texture > sharp[7].texture * 10)
    // The mix of a colour with itself is that colour, without texture.
    let same = DisplayModel.tv.mixes(.cyan, .cyan, palette: .colodore, pixelWidth: 1)
    #expect(same.allSatisfy { $0.texture < 0.0001 && $0.color.rgb == C64Palette.colodore[.cyan] })
}

/// The display model done plainly, line by line in Double precision, to
/// check the fast one against.
private func plainly(_ image: IndexedImage, on model: DisplayModel, palette: C64Palette) -> RGBImage {
    func kernel(_ deviation: Double) -> [Double]? {
        guard deviation > 0 else { return nil }
        let radius = Int((3 * deviation).rounded(.up))
        let weights = (-radius...radius).map { exp(-Double($0 * $0) / (2 * deviation * deviation)) }
        return weights.map { $0 / weights.reduce(0, +) }
    }
    func blurred(_ line: [Double], _ kernel: [Double]?) -> [Double] {
        guard let kernel else { return line }
        return line.indices.map { x in
            kernel.indices.reduce(0) { $0 + kernel[$1] * line[min(max(x + $1 - kernel.count / 2, 0), line.count - 1)] }
        }
    }
    var shown = RGBImage(width: image.width, height: image.height, fill: RGB(0, 0, 0))
    var above: (u: [Double], v: [Double])?
    for y in 0..<image.height {
        let signals = (0..<image.width).map { palette.signals[Int(image[$0, y].rawValue)] }
        let luma = blurred(signals.map(\.y), kernel(model.lumaBlur))
        var u = blurred(signals.map(\.u), kernel(model.chromaBlur))
        var v = blurred(signals.map(\.v), kernel(model.chromaBlur))
        if model.delayLine {
            let previous = above ?? (u, v)
            above = (u, v)
            u = zip(u, previous.u).map { ($0 + $1) / 2 }
            v = zip(v, previous.v).map { ($0 + $1) / 2 }
        }
        for x in 0..<image.width {
            let signal = model.isMonochrome ? YUV(y: luma[x], u: 0, v: 0) : YUV(y: luma[x], u: u[x], v: v[x])
            let rgb = Colodore.rgb(signal)
            shown[x, y] = RGB(UInt8(rgb.r.rounded()), UInt8(rgb.g.rounded()), UInt8(rgb.b.rounded()))
        }
    }
    return shown
}

/// The fast display model, which works on lines in parallel, shows exactly
/// what the plain one does, within the rounding of its gamma table.
@Test(arguments: [DisplayModel.tv, .commodoreMonitor, .blackAndWhite])
func displayModelsMatchAPlainImplementation(model: DisplayModel) {
    var generator = SeededGenerator(seed: 5)
    var image = IndexedImage(width: 96, height: 40)
    for y in 0..<40 {
        for x in 0..<96 {
            image[x, y] = C64Color.random(using: &generator)
        }
    }
    let (shown, expected) = (model.show(image, palette: .colodore), plainly(image, on: model, palette: .colodore))
    var worst = (difference: 0, x: 0, y: 0)
    for y in 0..<40 {
        for x in 0..<96 where distance(shown[x, y], expected[x, y]) > worst.difference {
            worst = (distance(shown[x, y], expected[x, y]), x, y)
        }
    }
    #expect(worst.difference <= 1, "(\(worst.x), \(worst.y)) is off by \(worst.difference)")
}
