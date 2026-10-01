import Foundation

/// The part of a photo that becomes the picture, in the photo's pixels.
public struct Crop: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The largest rectangle of a shape, given as width over height, centred
    /// in a photo. By default, the display window's shape.
    public static func centered(
        width: Int, height: Int, aspectRatio: Double = Screen.windowAspectRatio
    ) -> Crop {
        let (photoWidth, photoHeight) = (Double(width), Double(height))
        let cropWidth = min(photoWidth, photoHeight * aspectRatio)
        let cropHeight = min(photoHeight, photoWidth / aspectRatio)
        return Crop(
            x: (photoWidth - cropWidth) / 2, y: (photoHeight - cropHeight) / 2, width: cropWidth,
            height: cropHeight)
    }
}

/// The tone controls applied to a photo before it is converted (plan,
/// section 6). They work on OKLab's lightness and colourfulness.
public struct Tones: Hashable, Sendable {
    /// Stretches the lightness first, so the photo's darkest and brightest
    /// parts reach black and white. On by default.
    public var automatic: Bool
    /// Added to the lightness, from −1 to 1: 0 changes nothing.
    public var brightness: Float
    /// Multiplies the lightness's spread around mid-grey: 1 changes nothing.
    public var contrast: Float
    /// Multiplies the colourfulness: 0 gives greys, 1 changes nothing.
    public var saturation: Float
    /// Raises the lightness to this power: below 1 brightens the shadows, 1
    /// changes nothing.
    public var gamma: Float
    /// How strongly edges are sharpened: 0 for not at all, 1 for a lot.
    public var sharpening: Float

    public init(
        automatic: Bool = true, brightness: Float = 0, contrast: Float = 1, saturation: Float = 1, gamma: Float = 1,
        sharpening: Float = 0
    ) {
        self.automatic = automatic
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.gamma = gamma
        self.sharpening = sharpening
    }

    /// No adjustment at all.
    public static let neutral = Tones(automatic: false)
}

/// What the converter aims for: a photo cropped to the display window's
/// shape, averaged down to a mode's pixel grid in linear light, with the tone
/// controls applied, in OKLab (plan, section 6).
public struct Target: Hashable, Sendable {
    public let width: Int
    public let height: Int
    /// Row by row from the top.
    public var colors: [OKLab] {
        didSet { precondition(colors.count == width * height, "One colour per pixel") }
    }

    public init(width: Int, height: Int, colors: [OKLab]) {
        precondition(width > 0 && height > 0 && colors.count == width * height, "One colour per pixel")
        self.width = width
        self.height = height
        self.colors = colors
    }

    /// Prepares a photo for a mode's pixel grid.
    public init(_ photo: RGBImage, for spec: ModeSpec, crop: Crop? = nil, tones: Tones = Tones()) {
        self.init(photo, width: spec.width, height: spec.height, crop: crop, tones: tones)
    }

    /// Prepares a photo: each of the `width` × `height` pixels takes the
    /// average, in linear light, of the part of the crop it covers. The crop
    /// is the largest centred one of the display window's shape by default.
    public init(_ photo: RGBImage, width: Int, height: Int, crop: Crop? = nil, tones: Tones = Tones()) {
        precondition(width > 0 && height > 0 && photo.width > 0 && photo.height > 0)
        var crop = crop ?? Crop.centered(width: photo.width, height: photo.height)
        crop.x = min(max(crop.x, 0), Double(photo.width) - 1)
        crop.y = min(max(crop.y, 0), Double(photo.height) - 1)
        crop.width = min(max(crop.width, 1), Double(photo.width) - crop.x)
        crop.height = min(max(crop.height, 1), Double(photo.height) - crop.y)

        let averages = Self.averaged(photo, crop: crop, width: width, height: height)
        var colors = (0..<width * height).map { pixel in
            OKLab(LinearRGB(r: averages[pixel * 3], g: averages[pixel * 3 + 1], b: averages[pixel * 3 + 2]))
        }
        Self.apply(tones, to: &colors, width: width, height: height)
        self.init(width: width, height: height, colors: colors)
    }

    /// The target as an 8-bit sRGB picture, with colours outside sRGB
    /// clamped.
    public var rgbImage: RGBImage {
        var image = RGBImage(width: width, height: height, fill: RGB(0, 0, 0))
        for y in 0..<height {
            for x in 0..<width {
                image[x, y] = colors[y * width + x].linear.rgb
            }
        }
        return image
    }

    // MARK: - Averaging

    /// Which source pixels one output pixel covers along an axis, and how
    /// much of each: weights that add up to 1.
    private struct Footprint {
        var first: Int
        var weights: [Float]
    }

    /// The footprints of `count` output pixels spread evenly over
    /// `start..<start + length` of a source axis.
    private static func footprints(start: Double, length: Double, count: Int) -> [Footprint] {
        let step = length / Double(count)
        return (0..<count).map { index in
            let low = start + Double(index) * step
            let high = low + step
            let first = Int(low.rounded(.down))
            let last = max(first, Int(high.rounded(.up)) - 1)
            let weights = (first...last).map { source in
                Float((min(Double(source + 1), high) - max(Double(source), low)) / step)
            }
            return Footprint(first: first, weights: weights)
        }
    }

    /// The crop averaged down to `width` × `height` pixels in linear light: 3
    /// channels per pixel, row by row.
    private static func averaged(_ photo: RGBImage, crop: Crop, width: Int, height: Int) -> [Float] {
        let columns = footprints(start: crop.x, length: crop.width, count: width)
        let rows = footprints(start: crop.y, length: crop.height, count: height)
        let (bytesPerPixel, offsets) = (photo.layout.bytesPerPixel, photo.layout.offsets)
        let lastColumn = photo.width - 1
        let lastRow = photo.height - 1

        var output = [Float](repeating: 0, count: width * height * 3)
        output.withUnsafeMutableBufferPointer { output in
            photo.bytes.withUnsafeBufferPointer { bytes in
                let shared = Shared((output.baseAddress!, bytes.baseAddress!))
                concurrently(height, inChunksOf: 8) { outputRows in
                    let (output, bytes) = shared.value
                    // One source row averaged across, kept while the next
                    // output row needs it too.
                    var rowAverages = [Float](repeating: 0, count: width * 3)
                    var cachedRow = -1
                    SRGB.linear.withUnsafeBufferPointer { linear in
                        for outputRow in outputRows {
                            let footprint = rows[outputRow]
                            for (offset, rowWeight) in footprint.weights.enumerated() {
                                let sourceRow = min(footprint.first + offset, lastRow)
                                if sourceRow != cachedRow {
                                    let rowStart = sourceRow * photo.width
                                    for (outputColumn, column) in columns.enumerated() {
                                        var (r, g, b): (Float, Float, Float) = (0, 0, 0)
                                        for (index, weight) in column.weights.enumerated() {
                                            let pixel =
                                                (rowStart + min(column.first + index, lastColumn)) * bytesPerPixel
                                            r += weight * linear[Int(bytes[pixel + offsets.r])]
                                            g += weight * linear[Int(bytes[pixel + offsets.g])]
                                            b += weight * linear[Int(bytes[pixel + offsets.b])]
                                        }
                                        rowAverages[outputColumn * 3] = r
                                        rowAverages[outputColumn * 3 + 1] = g
                                        rowAverages[outputColumn * 3 + 2] = b
                                    }
                                    cachedRow = sourceRow
                                }
                                let start = outputRow * width * 3
                                for index in 0..<width * 3 {
                                    output[start + index] += rowWeight * rowAverages[index]
                                }
                            }
                        }
                    }
                }
            }
        }
        return output
    }

    // MARK: - Tones

    private static func apply(_ tones: Tones, to colors: inout [OKLab], width: Int, height: Int) {
        if tones.automatic {
            stretchLightness(&colors)
        }
        for index in colors.indices {
            var color = colors[index]
            var lightness = max(color.l, 0)
            if tones.gamma != 1 {
                lightness = pow(lightness, tones.gamma)
            }
            lightness = 0.5 + (lightness - 0.5) * tones.contrast + tones.brightness
            color.l = min(max(lightness, 0), 1)
            color.a *= tones.saturation
            color.b *= tones.saturation
            colors[index] = color
        }
        if tones.sharpening > 0 {
            sharpen(&colors, width: width, height: height, amount: tones.sharpening)
        }
    }

    /// Stretches the lightness so the darkest and brightest 0.5% of the
    /// pixels become black and white, by at most 2.5 times, leaving very flat
    /// photos alone.
    private static func stretchLightness(_ colors: inout [OKLab]) {
        let bins = 1024
        var histogram = [Int](repeating: 0, count: bins)
        for color in colors {
            histogram[min(max(Int(color.l * Float(bins)), 0), bins - 1)] += 1
        }
        let tail = colors.count / 200
        var (darkCount, darkBin) = (0, 0)
        while darkBin < bins - 1 && darkCount + histogram[darkBin] <= tail {
            darkCount += histogram[darkBin]
            darkBin += 1
        }
        var (brightCount, brightBin) = (0, bins - 1)
        while brightBin > 0 && brightCount + histogram[brightBin] <= tail {
            brightCount += histogram[brightBin]
            brightBin -= 1
        }
        let low = Float(darkBin) / Float(bins)
        let high = Float(brightBin + 1) / Float(bins)
        guard high - low > 0.1 else { return }
        let gain = min(1 / (high - low), 2.5)
        // With the gain limited, the stretch keeps the middle of the range in
        // place.
        let center = (low + high) / 2
        for index in colors.indices {
            colors[index].l = min(max(0.5 + (colors[index].l - center) * gain, 0), 1)
        }
    }

    /// Unsharp masking of the lightness: each pixel moves away from the
    /// average of its neighbours.
    private static func sharpen(_ colors: inout [OKLab], width: Int, height: Int, amount: Float) {
        let lightness = colors.map(\.l)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                var weightSum: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let (nx, ny) = (x + dx, y + dy)
                        guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }
                        let weight: Float = (dx == 0 ? 2 : 1) * (dy == 0 ? 2 : 1)
                        sum += weight * lightness[ny * width + nx]
                        weightSum += weight
                    }
                }
                let index = y * width + x
                colors[index].l = min(max(lightness[index] + amount * (lightness[index] - sum / weightSum), 0), 1)
            }
        }
    }
}
