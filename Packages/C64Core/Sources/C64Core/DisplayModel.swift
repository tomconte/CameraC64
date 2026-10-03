import Foundation

/// How a monitor shows the VIC-II's picture (plan, section 7).
///
/// The VIC-II sends brightness and colour as separate parts of a PAL signal,
/// and the model works on that signal, as Colodore defines it, before
/// converting it to RGB:
///
/// 1. A TV carries colour at about a sixth of the hires pixel rate, so
///    neighbouring pixels' colours smear together horizontally.
/// 2. The PAL delay line averages each line's colour with the line above.
/// 3. Through a composite connection, brightness softens a little too.
///
/// Only colour blends, so two colours of the same brightness blend into a new,
/// flicker-free tint. Monochrome monitors show brightness alone, in their
/// phosphor's colour. Real TVs vary: the presets are approximations. Their
/// blurs spread as far as those of VICE's PAL emulation with its default
/// settings: brightness over 3 pixels, weighted 1/8, 3/4, 1/8, and colour over
/// 4.
public struct DisplayModel: Hashable, Sendable {
    /// A monochrome monitor's phosphor.
    public enum Phosphor: Hashable, Sendable {
        case white
        case green
        case amber

        /// The phosphor's colour at full brightness.
        public var color: RGB {
            switch self {
            case .white: RGB(0xFF, 0xFF, 0xFF)
            case .green: RGB(0x5C, 0xFF, 0x7A)
            case .amber: RGB(0xFF, 0xB4, 0x3C)
            }
        }
    }

    /// How far colour smears horizontally: the standard deviation of a
    /// Gaussian blur, in hires pixels. 0 keeps it sharp.
    public var chromaBlur: Double
    /// Whether the PAL delay line averages each line's colour with the line
    /// above.
    public var delayLine: Bool
    /// How far brightness smears horizontally, in hires pixels.
    public var lumaBlur: Double
    /// For a monochrome monitor, its phosphor: it shows brightness only.
    public var phosphor: Phosphor?

    public init(chromaBlur: Double = 0, delayLine: Bool = false, lumaBlur: Double = 0, phosphor: Phosphor? = nil) {
        precondition(chromaBlur >= 0 && lumaBlur >= 0)
        self.chromaBlur = chromaBlur
        self.delayLine = delayLine
        self.lumaBlur = lumaBlur
        self.phosphor = phosphor
    }

    /// No blending: HDMI output, or an emulator without CRT emulation.
    public static let sharp = DisplayModel()
    /// A PAL TV through the composite connection: the default.
    public static let tv = DisplayModel(chromaBlur: 1.1, delayLine: true, lumaBlur: 0.5)
    /// A Commodore monitor fed brightness and colour separately: brightness
    /// stays sharp.
    public static let commodoreMonitor = DisplayModel(chromaBlur: 1.1, delayLine: true)
    /// A black-and-white TV.
    public static let blackAndWhite = DisplayModel(lumaBlur: 0.5, phosphor: .white)
    public static let green = DisplayModel(lumaBlur: 0.4, phosphor: .green)
    public static let amber = DisplayModel(lumaBlur: 0.4, phosphor: .amber)

    public var isMonochrome: Bool { phosphor != nil }

    /// The same monitor with a white phosphor, if it is monochrome: brightness
    /// as a grey.
    var untinted: DisplayModel {
        var model = self
        if model.phosphor != nil {
            model.phosphor = .white
        }
        return model
    }

    /// What an area of one colour looks like.
    public func color(of color: C64Color, palette: C64Palette) -> RGB {
        guard let phosphor else { return palette[color] }
        return Self.tint(grey: Self.signalTable[Self.tableIndex(palette.signals[Int(color.rawValue)].y)], phosphor)
    }

    /// The picture as this monitor shows it: one RGB pixel for each of the
    /// picture's pixels.
    public func show(_ image: IndexedImage, palette: C64Palette) -> RGBImage {
        if self == .sharp {
            return image.rgbImage(palette)
        }
        let (width, height) = (image.width, image.height)
        let signals = palette.signals.map { (y: Float($0.y), u: Float($0.u), v: Float($0.v)) }
        let tints = phosphor.map { phosphor in (0..<256).map { Self.tint(grey: UInt8($0), phosphor) } }
        var output = [UInt8](repeating: 0, count: width * height * 3)
        output.withUnsafeMutableBufferPointer { output in
            let shared = Shared(output.baseAddress!)
            concurrently(height, inChunksOf: 16) { lines in
                let output = shared.value
                let (lumaKernel, chromaKernel) = (Self.gaussian(lumaBlur), Self.gaussian(chromaBlur))
                // A line's signals, the previous line's colour, and room to
                // blur them, each in its own memory.
                let buffers = UnsafeMutablePointer<Float>.allocate(capacity: 6 * width)
                buffers.initialize(repeating: 0, count: 6 * width)
                defer { buffers.deallocate() }
                let (luma, u, v) = (buffers, buffers + width, buffers + 2 * width)
                let (previousU, previousV, scratch) = (buffers + 3 * width, buffers + 4 * width, buffers + 5 * width)
                // The delay line averages each line with the line above as it
                // came, not as it was shown, so a chunk starts there.
                let first = delayLine && tints == nil ? max(lines.lowerBound - 1, 0) : lines.lowerBound
                Self.signalTable.withUnsafeBufferPointer { table in
                    for y in first..<lines.upperBound {
                        for x in 0..<width {
                            let signal = signals[Int(image.pixels[y * width + x])]
                            luma[x] = signal.y
                            u[x] = signal.u
                            v[x] = signal.v
                        }
                        let row = y * width * 3
                        if let tints {
                            Self.blur(luma, count: width, lumaKernel, scratch: scratch)
                            for x in 0..<width {
                                let tint = tints[Int(table[Self.tableIndex(luma[x])])]
                                output[row + x * 3] = tint.r
                                output[row + x * 3 + 1] = tint.g
                                output[row + x * 3 + 2] = tint.b
                            }
                            continue
                        }
                        Self.blur(u, count: width, chromaKernel, scratch: scratch)
                        Self.blur(v, count: width, chromaKernel, scratch: scratch)
                        if delayLine {
                            if y == first {
                                previousU.update(from: u, count: width)
                                previousV.update(from: v, count: width)
                            }
                            if y < lines.lowerBound {
                                continue
                            }
                            for x in 0..<width {
                                (previousU[x], u[x]) = (u[x], (u[x] + previousU[x]) / 2)
                                (previousV[x], v[x]) = (v[x], (v[x] + previousV[x]) / 2)
                            }
                        }
                        Self.blur(luma, count: width, lumaKernel, scratch: scratch)
                        for x in 0..<width {
                            // Colodore's conversion to RGB, then its gamma
                            // correction.
                            output[row + x * 3] = table[Self.tableIndex(luma[x] + 1.140 * v[x])]
                            output[row + x * 3 + 1] = table[Self.tableIndex(luma[x] - 0.396 * u[x] - 0.581 * v[x])]
                            output[row + x * 3 + 2] = table[Self.tableIndex(luma[x] + 2.029 * u[x])]
                        }
                    }
                }
            }
        }
        return RGBImage(width: width, height: height, bytes: output)
    }

    /// How dithered mixes of two colours look on this monitor, seen from far
    /// enough for the eye to average them out. For each Bayer pattern that
    /// shows 1 to 15 sixteenths of the second colour, with pixels
    /// `pixelWidth` hires pixels wide: the pattern's average colour in linear
    /// light, and how visible its texture is, as the mean squared OKLab
    /// distance of its pixels from that average. Monochrome monitors give
    /// greys.
    ///
    /// A TV blends the colours before its gamma, so the average is not simply
    /// the two colours mixed in linear light, as it is on a sharp display.
    public func mixes(
        _ first: C64Color, _ second: C64Color, palette: C64Palette, pixelWidth: Int
    ) -> [(color: LinearRGB, texture: Float)] {
        mixes(first, second, palette: palette, patterns: patterns(pixelWidth: pixelWidth))
    }

    /// The Bayer patterns of each level, 4 × 4 pixels wide and repeating, as
    /// the monitor blurs them: for each position, how much of the second
    /// colour's brightness and colour signal it shows.
    struct Patterns {
        var luma: [[Float]]
        var chroma: [[Float]]
    }

    func patterns(pixelWidth: Int) -> Patterns {
        let width = 4 * pixelWidth
        var patterns = Patterns(luma: [], chroma: [])
        for level in 1...15 {
            var luma: [Float] = []
            var chroma: [Float] = []
            var previous: [Float] = []
            for y in 0..<5 {
                // One line of the repeating pattern, three times over so the
                // middle one blurs as if it went on forever.
                let line = (0..<3 * width).map { x in
                    Float(Bayer.showsSecond(level: level, x: x % width / pixelWidth, y: y % 4) ? 1 : 0)
                }
                let lumaLine = Self.blurred(line, Self.gaussian(lumaBlur))
                let chromaLine = Self.blurred(line, Self.gaussian(chromaBlur))
                let middle = Array(chromaLine[width..<2 * width])
                // The first line is only there to be the line above the last.
                if y > 0 {
                    luma += lumaLine[width..<2 * width]
                    chroma += delayLine ? zip(middle, previous).map { ($0 + $1) / 2 } : middle
                }
                previous = middle
            }
            patterns.luma.append(luma)
            patterns.chroma.append(chroma)
        }
        return patterns
    }

    func mixes(
        _ first: C64Color, _ second: C64Color, palette: C64Palette, patterns: Patterns
    ) -> [(color: LinearRGB, texture: Float)] {
        let model = untinted
        let (one, two) = (palette.signals[Int(first.rawValue)], palette.signals[Int(second.rawValue)])
        let sharp = lumaBlur == 0 && chromaBlur == 0 && !delayLine
        return (0..<15).map { index in
            var pixels: [LinearRGB] = []
            for position in patterns.luma[index].indices {
                let (luma, chroma) = (Double(patterns.luma[index][position]), Double(patterns.chroma[index][position]))
                let rgb: RGB
                if sharp {
                    // Each pixel is exactly one of the two colours.
                    rgb = model.color(of: luma == 0 ? first : second, palette: palette)
                } else {
                    let y = Float(one.y + (two.y - one.y) * luma)
                    if isMonochrome {
                        let grey = Self.signalTable[Self.tableIndex(y)]
                        rgb = RGB(grey, grey, grey)
                    } else {
                        let u = Float(one.u + (two.u - one.u) * chroma)
                        let v = Float(one.v + (two.v - one.v) * chroma)
                        rgb = RGB(
                            Self.signalTable[Self.tableIndex(y + 1.140 * v)],
                            Self.signalTable[Self.tableIndex(y - 0.396 * u - 0.581 * v)],
                            Self.signalTable[Self.tableIndex(y + 2.029 * u)])
                    }
                }
                pixels.append(LinearRGB(rgb))
            }
            let count = Float(pixels.count)
            let average = LinearRGB(
                r: pixels.reduce(0) { $0 + $1.r } / count, g: pixels.reduce(0) { $0 + $1.g } / count,
                b: pixels.reduce(0) { $0 + $1.b } / count)
            let center = OKLab(average)
            let texture = pixels.reduce(0) { $0 + OKLab($1).distanceSquared(to: center) } / count
            return (average, texture)
        }
    }

    // MARK: - Signal processing

    /// Normalised weights of a Gaussian blur, from -radius to radius, or nil
    /// for no blur.
    static func gaussian(_ deviation: Double) -> [Float]? {
        guard deviation > 0 else { return nil }
        let radius = Int((3 * deviation).rounded(.up))
        let weights = (-radius...radius).map { exp(-Double($0 * $0) / (2 * deviation * deviation)) }
        let sum = weights.reduce(0, +)
        return weights.map { Float($0 / sum) }
    }

    /// Blurs a line in place, repeating its end pixels beyond its edges.
    private static func blur(
        _ line: UnsafeMutablePointer<Float>, count: Int, _ kernel: [Float]?, scratch: UnsafeMutablePointer<Float>
    ) {
        guard let kernel else { return }
        let radius = kernel.count / 2
        for x in 0..<count {
            var sum: Float = 0
            for (offset, weight) in kernel.enumerated() {
                sum += weight * line[min(max(x + offset - radius, 0), count - 1)]
            }
            scratch[x] = sum
        }
        line.update(from: scratch, count: count)
    }

    /// A line blurred, repeating its end pixels beyond its edges.
    private static func blurred(_ line: [Float], _ kernel: [Float]?) -> [Float] {
        guard let kernel else { return line }
        let radius = kernel.count / 2
        return line.indices.map { x in
            kernel.enumerated().reduce(0) { sum, tap in
                sum + tap.element * line[min(max(x + tap.offset - radius, 0), line.count - 1)]
            }
        }
    }

    /// Each signal level's gamma-corrected value, 64 steps per unit, from 0
    /// to 255: Colodore's conversion of one RGB channel, clamped.
    static let signalTable: [UInt8] = (0...255 * 64).map {
        UInt8(Colodore.gammaCorrected(Double($0) / 64).rounded())
    }

    static func tableIndex(_ level: Float) -> Int {
        Int(min(max(level, 0), 255) * 64 + 0.5)
    }

    private static func tableIndex(_ level: Double) -> Int {
        tableIndex(Float(level))
    }

    /// A grey level in the phosphor's colour: the phosphor glows in
    /// proportion to the grey's light.
    private static func tint(grey: UInt8, _ phosphor: Phosphor) -> RGB {
        let light = SRGB.linear[Int(grey)]
        let color = LinearRGB(phosphor.color)
        return LinearRGB(r: color.r * light, g: color.g * light, b: color.b * light).rgb
    }
}

/// The 4 × 4 Bayer pattern of ordered dithering, fixed to the screen: a mix
/// that shows n sixteenths of its second colour shows it where the pattern is
/// below n.
enum Bayer {
    static let thresholds: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    static func showsSecond(level: Int, x: Int, y: Int) -> Bool {
        thresholds[(y & 3) * 4 + (x & 3)] < level
    }
}
