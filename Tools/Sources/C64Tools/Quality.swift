import C64Core
import Foundation

/// How close a picture, as a monitor shows it, comes to what it was made
/// from: the quality benchmark's measure (plan, section 10).
public enum Quality {
    /// Brightness blurs less than colour, as in S-CIELAB: the eye resolves
    /// finer detail in brightness. Both in hires pixels, about what an iPhone
    /// shows at a point per C64 pixel, seen from 30 cm.
    static let lumaBlur: Float = 1
    static let chromaBlur: Float = 2

    /// The mean OKLab distance, times 100, between a picture as shown and its
    /// target, both blurred as the eye blurs them: lower is better, and
    /// about 2 is a just noticeable difference. For a monochrome monitor,
    /// only lightness counts.
    public static func score(_ shown: RGBImage, target: Target, monochrome: Bool = false) -> Double {
        precondition(shown.width == target.width && shown.height == target.height, "The same size")
        let count = shown.width * shown.height
        var shownLight = [LinearRGB](repeating: LinearRGB(r: 0, g: 0, b: 0), count: count)
        for y in 0..<shown.height {
            for x in 0..<shown.width {
                shownLight[y * shown.width + x] = LinearRGB(shown[x, y])
            }
        }
        let shownColors = blurred(shownLight, width: shown.width, height: shown.height)
        let targetColors = blurred(target.colors.map(\.linear), width: target.width, height: target.height)
        var total = 0.0
        for (one, two) in zip(shownColors, targetColors) {
            total += Double(monochrome ? abs(one.l - two.l) : one.distance(to: two))
        }
        return total / Double(count) * 100
    }

    /// A picture blurred as the eye sees it: its luminance a little, and what
    /// is left, its colour, more. Then in OKLab.
    private static func blurred(_ pixels: [LinearRGB], width: Int, height: Int) -> [OKLab] {
        let luminance = pixels.map { 0.2126 * $0.r + 0.7152 * $0.g + 0.0722 * $0.b }
        let luma = gaussian(luminance, width: width, height: height, deviation: lumaBlur)
        let channels = [\LinearRGB.r, \.g, \.b].map { channel in
            gaussian(
                zip(pixels, luminance).map { $0[keyPath: channel] - $1 }, width: width, height: height,
                deviation: chromaBlur)
        }
        return (0..<pixels.count).map { index in
            OKLab(
                LinearRGB(
                    r: luma[index] + channels[0][index], g: luma[index] + channels[1][index],
                    b: luma[index] + channels[2][index]))
        }
    }

    /// A Gaussian blur, repeating the edge pixels beyond the edges.
    private static func gaussian(_ plane: [Float], width: Int, height: Int, deviation: Float) -> [Float] {
        let radius = Int((3 * deviation).rounded(.up))
        var kernel = (-radius...radius).map { exp(-Float($0 * $0) / (2 * deviation * deviation)) }
        let sum = kernel.reduce(0, +)
        kernel = kernel.map { $0 / sum }
        var across = [Float](repeating: 0, count: plane.count)
        for y in 0..<height {
            for x in 0..<width {
                var value: Float = 0
                for (offset, weight) in kernel.enumerated() {
                    value += weight * plane[y * width + min(max(x + offset - radius, 0), width - 1)]
                }
                across[y * width + x] = value
            }
        }
        var result = [Float](repeating: 0, count: plane.count)
        for y in 0..<height {
            for x in 0..<width {
                var value: Float = 0
                for (offset, weight) in kernel.enumerated() {
                    value += weight * across[min(max(y + offset - radius, 0), height - 1) * width + x]
                }
                result[y * width + x] = value
            }
        }
        return result
    }
}
