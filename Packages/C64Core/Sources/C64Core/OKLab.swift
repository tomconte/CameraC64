import Foundation

/// An sRGB colour in linear light: each channel proportional to the light
/// emitted, from 0 to 1.
///
/// Light adds up here, so averaging pixels and mixing colours by dithering
/// both happen in linear light (plan, section 6).
public struct LinearRGB: Hashable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float

    public init(r: Float, g: Float, b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// An 8-bit sRGB colour in linear light.
    public init(_ color: RGB) {
        self.init(r: SRGB.linear[Int(color.r)], g: SRGB.linear[Int(color.g)], b: SRGB.linear[Int(color.b)])
    }

    /// The nearest 8-bit sRGB colour, with each channel clamped to 0–1 first.
    public var rgb: RGB {
        RGB(SRGB.encoded(r), SRGB.encoded(g), SRGB.encoded(b))
    }

    /// The mix of two colours that shows `ratio` of the second: what the eye
    /// sees of a fine pattern of the two.
    public static func mix(_ first: LinearRGB, _ second: LinearRGB, ratio: Float) -> LinearRGB {
        LinearRGB(
            r: first.r + (second.r - first.r) * ratio, g: first.g + (second.g - first.g) * ratio,
            b: first.b + (second.b - first.b) * ratio)
    }
}

/// A colour in OKLab, Björn Ottosson's perceptual colour space (2020), where
/// the straight distance between two colours follows how different they look.
///
/// `l` is the lightness, from 0 (black) to 1 (white); `a` runs from green to
/// red and `b` from blue to yellow. The converter measures every colour
/// difference here (plan, section 6).
public struct OKLab: Hashable, Sendable {
    public var l: Float
    public var a: Float
    public var b: Float

    public init(l: Float, a: Float, b: Float) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// A linear-light colour in OKLab.
    public init(_ color: LinearRGB) {
        let long = 0.412_221_470_8 * color.r + 0.536_332_536_3 * color.g + 0.051_445_992_9 * color.b
        let medium = 0.211_903_498_2 * color.r + 0.680_699_545_1 * color.g + 0.107_396_956_6 * color.b
        let short = 0.088_302_461_9 * color.r + 0.281_718_837_6 * color.g + 0.629_978_700_5 * color.b
        let (lc, mc, sc) = (Self.cubeRoot(long), Self.cubeRoot(medium), Self.cubeRoot(short))
        l = 0.210_454_255_3 * lc + 0.793_617_785_0 * mc - 0.004_072_046_8 * sc
        a = 1.977_998_495_1 * lc - 2.428_592_205_0 * mc + 0.450_593_709_9 * sc
        b = 0.025_904_037_1 * lc + 0.782_771_766_2 * mc - 0.808_675_766_0 * sc
    }

    /// A cube root, as the conversion needs three for every colour: never
    /// more than a unit in the last place from the exact root, and about
    /// twice as fast as the C library's `cbrt`. A third of the exponent, taken
    /// from the number's bits, comes within 2%, and two steps of Halley's
    /// method finish it, the last in double precision. It uses only integer
    /// and IEEE arithmetic, so it gives the same results on every platform.
    static func cubeRoot(_ value: Float) -> Float {
        let magnitude = abs(value)
        guard magnitude >= .leastNormalMagnitude, magnitude.isFinite else { return cbrt(value) }
        var root = Float(bitPattern: magnitude.bitPattern / 3 &+ 0x2A51_37A0)
        let cube = root * root * root
        root *= (cube + 2 * magnitude) / (2 * cube + magnitude)
        var precise = Double(root)
        let preciseCube = precise * precise * precise
        precise *= (preciseCube + 2 * Double(magnitude)) / (2 * preciseCube + Double(magnitude))
        return value < 0 ? -Float(precise) : Float(precise)
    }

    /// An 8-bit sRGB colour in OKLab.
    public init(_ color: RGB) {
        self.init(LinearRGB(color))
    }

    /// The colour in linear light, not clamped: colours outside sRGB have
    /// channels below 0 or above 1.
    public var linear: LinearRGB {
        let lc = l + 0.396_337_777_4 * a + 0.215_803_757_3 * b
        let mc = l - 0.105_561_345_8 * a - 0.063_854_172_8 * b
        let sc = l - 0.089_484_177_5 * a - 1.291_485_548_0 * b
        let (long, medium, short) = (lc * lc * lc, mc * mc * mc, sc * sc * sc)
        return LinearRGB(
            r: 4.076_741_662_1 * long - 3.307_711_591_3 * medium + 0.230_969_929_2 * short,
            g: -1.268_438_004_6 * long + 2.609_757_401_1 * medium - 0.341_319_396_5 * short,
            b: -0.004_196_086_3 * long - 0.703_418_614_7 * medium + 1.707_614_701_0 * short)
    }

    /// The square of the distance to another colour.
    public func distanceSquared(to other: OKLab) -> Float {
        let (dl, da, db) = (l - other.l, a - other.a, b - other.b)
        return dl * dl + da * da + db * db
    }

    /// The distance to another colour: about 0.02 is just noticeable, and
    /// black and white are 1 apart.
    public func distance(to other: OKLab) -> Float {
        distanceSquared(to: other).squareRoot()
    }
}

/// sRGB's transfer function, between its 8-bit values and linear light.
public enum SRGB {
    /// Linear light for each 8-bit value.
    public static let linear: [Float] = (0..<256).map { decoded(Float($0) / 255) }

    /// Linear light for an sRGB value, both from 0 to 1.
    public static func decoded(_ value: Float) -> Float {
        value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// The 8-bit sRGB value for linear light, clamped to 0–1 first.
    public static func encoded(_ linear: Float) -> UInt8 {
        let value = min(max(linear, 0), 1)
        let encoded = value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
        return UInt8((encoded * 255).rounded())
    }
}
