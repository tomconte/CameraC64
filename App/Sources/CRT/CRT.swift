import C64Core
import Foundation

/// The CRT layer's look (plan, section 7): how a tube's beams, glass and
/// phosphor show the picture the monitor's display model made. `CRT.metal`
/// draws it.
///
/// It is presentation only: the converter never sees it, and C64 files never
/// include it. The picture as on TV, which is shared, includes it when it is
/// on. The Sharp monitor is a flat screen, so it has none.
nonisolated struct CRT: Hashable, Sendable {
    /// How far a black line's beam spreads, as a Gaussian's standard deviation
    /// in lines: the thinner the beam, the darker the gaps between dark lines.
    var beamMin: Double
    /// How far a white line's beam spreads: wide enough to nearly fill the
    /// gaps.
    var beamMax: Double
    /// How wide the step between neighbouring pixels along a line is, in
    /// pixels: 0 is a hard edge, 1 a smooth slope.
    var edge: Double
    /// How much of the light the glass scatters into a glow around it.
    var glow: Double
    /// How far the glass bulges: how much the picture's corners move in.
    var curvature: Double
    /// How much darker the corners are than the centre.
    var vignette: Double
    /// The tube's corner radius, as a fraction of its height.
    var corner: Double
    var brightness: Double
    /// How long the amber and green monitors' phosphor glows on, in seconds:
    /// the time its light takes to fall to about a third.
    var afterglow: Double

    /// The look the app uses, and that development builds start from.
    static let standard = CRT(
        beamMin: 0.17, beamMax: 0.45, edge: 0.5, glow: 0.1, curvature: 0.03, vignette: 0.25, corner: 0.04,
        brightness: 1.05, afterglow: 0.1)

    /// The values `CRT.metal` reads, in the order of its `CRTSettings`, for a
    /// screen drawn with `scale` device pixels per point. While a picture
    /// fills in, `revealed` of its display window's 1,000 cells show.
    func shaderSettings(for source: CRTSource, scale: Double, revealed: Double = 1000) -> [Float] {
        [
            Double(source.width), Double(source.height),
            Double(Screen.windowX), Double(Screen.windowY), Double(Screen.windowWidth), Double(Screen.windowHeight),
            Double(source.glowWidth), Double(source.glowHeight),
            scale, beamMin, beamMax, edge, glow, curvature, vignette, corner, brightness, revealed,
        ].map(Float.init)
    }
}

nonisolated extension CRT {
    private var values: [Double] {
        [beamMin, beamMax, edge, glow, curvature, vignette, corner, brightness, afterglow]
    }

    /// The look as text: its values in order, separated by spaces. Development
    /// builds save the look they tune this way, and testers can send it.
    var text: String {
        values.map { String(format: "%.3f", $0) }.joined(separator: " ")
    }

    /// A look from its text, or nil if the text holds a different number of
    /// values.
    init?(text: String) {
        let values = text.split(separator: " ").compactMap { Double($0) }
        guard values.count == CRT.standard.values.count else { return nil }
        self.init(
            beamMin: values[0], beamMax: values[1], edge: values[2], glow: values[3], curvature: values[4],
            vignette: values[5], corner: values[6], brightness: values[7], afterglow: values[8])
    }
}

/// A screen as `CRT.metal` reads it: its pixels as RGBA bytes, and the glow
/// the glass makes of them, in linear light at a quarter of the screen's size
/// each way, as RGBA floats.
nonisolated struct CRTSource: Hashable, Sendable {
    /// How many screen pixels each way one of the glow's pixels covers.
    static let glowDivisor = 4
    /// How far the glow spreads, as a Gaussian's standard deviation in the
    /// glow's pixels: 6 of the screen's.
    static let glowSpread = 1.5

    let width: Int
    let height: Int
    let pixels: Data
    let glowWidth: Int
    let glowHeight: Int
    let glow: Data

    init(_ screen: RGBImage) {
        let (width, height) = (screen.width, screen.height)
        let step = screen.layout.bytesPerPixel
        let (red, green, blue) = screen.layout == .bgra ? (2, 1, 0) : (0, 1, 2)
        let divisor = Self.glowDivisor
        let (glowWidth, glowHeight) = ((width + divisor - 1) / divisor, (height + divisor - 1) / divisor)
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        // The light of each block of pixels, added up.
        var blocks = [Float](repeating: 0, count: glowWidth * glowHeight * 3)
        var counts = [Float](repeating: 0, count: glowWidth * glowHeight)
        screen.bytes.withUnsafeBufferPointer { bytes in
            SRGB.linear.withUnsafeBufferPointer { linear in
                for y in 0..<height {
                    for x in 0..<width {
                        let (from, to) = ((y * width + x) * step, (y * width + x) * 4)
                        let (r, g, b) = (bytes[from + red], bytes[from + green], bytes[from + blue])
                        (rgba[to], rgba[to + 1], rgba[to + 2]) = (r, g, b)
                        let block = (y / divisor) * glowWidth + x / divisor
                        blocks[block * 3] += linear[Int(r)]
                        blocks[block * 3 + 1] += linear[Int(g)]
                        blocks[block * 3 + 2] += linear[Int(b)]
                        counts[block] += 1
                    }
                }
            }
        }
        for block in counts.indices where counts[block] > 0 {
            for channel in 0..<3 {
                blocks[block * 3 + channel] /= counts[block]
            }
        }
        let glow = Self.blurred(blocks, width: glowWidth, height: glowHeight, deviation: Self.glowSpread)
        var glowRGBA = [Float](repeating: 1, count: glowWidth * glowHeight * 4)
        for index in 0..<glowWidth * glowHeight {
            for channel in 0..<3 {
                glowRGBA[index * 4 + channel] = glow[index * 3 + channel]
            }
        }
        self.width = width
        self.height = height
        self.pixels = Data(rgba)
        self.glowWidth = glowWidth
        self.glowHeight = glowHeight
        self.glow = glowRGBA.withUnsafeBytes { Data($0) }
    }

    /// An RGB picture blurred by a Gaussian, across then down, repeating its
    /// edges beyond them.
    static func blurred(_ values: [Float], width: Int, height: Int, deviation: Double) -> [Float] {
        let radius = Int((3 * deviation).rounded(.up))
        let weights = (-radius...radius).map { Float(exp(-Double($0 * $0) / (2 * deviation * deviation))) }
        let total = weights.reduce(0, +)
        let kernel = weights.map { $0 / total }
        var across = [Float](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    var sum: Float = 0
                    for (offset, weight) in kernel.enumerated() {
                        let from = min(max(x + offset - radius, 0), width - 1)
                        sum += weight * values[(y * width + from) * 3 + channel]
                    }
                    across[(y * width + x) * 3 + channel] = sum
                }
            }
        }
        var down = [Float](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    var sum: Float = 0
                    for (offset, weight) in kernel.enumerated() {
                        let from = min(max(y + offset - radius, 0), height - 1)
                        sum += weight * across[(from * width + x) * 3 + channel]
                    }
                    down[(y * width + x) * 3 + channel] = sum
                }
            }
        }
        return down
    }
}

/// The afterglow of the amber and green monitors' phosphor, in the
/// viewfinder: a pixel lights up at once, but fades slowly, so whatever moves
/// leaves a fading trail.
nonisolated struct Afterglow {
    /// How long the phosphor glows on, in seconds: the time its light takes
    /// to fall to about a third.
    let duration: Double
    /// What the monitor showed last, and when.
    private var last: (screen: RGBImage, time: Double)?

    init(duration: Double) {
        self.duration = duration
    }

    /// A new screen as the phosphor shows it at a time, in seconds: each
    /// channel of each pixel is the brighter of the new one and what is left
    /// of the last one's light.
    mutating func show(_ screen: RGBImage, at time: Double) -> RGBImage {
        guard duration > 0, let last, last.screen.width == screen.width, last.screen.height == screen.height,
            last.screen.layout == screen.layout, time > last.time
        else {
            last = (screen, time)
            return screen
        }
        // Each 8-bit value's light, faded for the time since the last screen.
        let fade = Float(exp(-(time - last.time) / duration))
        let faded = SRGB.linear.map { SRGB.encoded($0 * fade) }
        var bytes = screen.bytes
        for index in bytes.indices {
            bytes[index] = max(bytes[index], faded[Int(last.screen.bytes[index])])
        }
        let shown = RGBImage(width: screen.width, height: screen.height, layout: screen.layout, bytes: bytes)
        self.last = (shown, time)
        return shown
    }
}
