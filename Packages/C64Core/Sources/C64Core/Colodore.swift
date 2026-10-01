import Foundation

/// How many brightness levels a VIC-II has.
public enum LumaLevels: Int, CaseIterable, Sendable {
    /// The earliest chips (6569R1): 5 levels, so more colours share a brightness.
    case five = 5
    /// Every later chip: 9 levels. The default.
    case nine = 9
}

/// A colour as a PAL video signal: brightness (luma) and two colour
/// differences.
///
/// Values are in Colodore's units, where 255 is full brightness on screen.
/// Luma can go past it: white is brighter than the screen can show.
public struct YUV: Hashable, Sendable {
    public var y: Double
    public var u: Double
    public var v: Double

    public init(y: Double, u: Double, v: Double) {
        self.y = y
        self.u = u
        self.v = v
    }
}

/// Pepto's Colodore model of the VIC-II's colours (2017), as published at
/// https://www.colodore.com.
///
/// The VIC-II does not output RGB. It outputs a brightness signal with a few
/// fixed levels, and a colour signal whose phase sets the hue. Colodore takes
/// both from measurements of real chips and converts them to sRGB the way a
/// PAL monitor would, including the monitor's brightness, contrast and
/// saturation knobs. The display models (plan, section 7) blend colours in
/// this signal space, before converting them.
public struct Colodore: Hashable, Sendable {
    /// The monitor's brightness knob, from 0 to 100. 50 changes nothing.
    public var brightness: Double
    /// The monitor's contrast knob, from 0 to 100.
    public var contrast: Double
    /// The monitor's colour knob, from 0 to 100.
    public var saturation: Double
    public var lumaLevels: LumaLevels

    /// Colodore's defaults, which give its published palette.
    public init(
        brightness: Double = 50, contrast: Double = 100, saturation: Double = 50, lumaLevels: LumaLevels = .nine
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.lumaLevels = lumaLevels
    }

    /// The signal the VIC-II outputs for a colour, after the monitor's knobs.
    public func signal(_ color: C64Color) -> YUV {
        // Colodore turns the knobs into gains; the extra fifth of contrast
        // makes the knob behave like a Commodore 1084S monitor's.
        let contrastGain = contrast / 100 + 1 / 5
        let saturationGain = saturation / 1.25
        let brightnessOffset = brightness - 50

        let luma = Double(Self.luma(color, lumaLevels)) * 256 / 32
        var u = 0.0
        var v = 0.0
        if let phase = Self.phase(color) {
            // 16 phase steps of 22.5°, offset by half a step.
            let angle = (Double(phase) * 22.5 + 11.25) * Double.pi / 180
            u = saturationGain * cos(angle)
            v = saturationGain * sin(angle)
        }
        return YUV(y: luma * contrastGain + brightnessOffset, u: u * contrastGain, v: v * contrastGain)
    }

    /// Converts a signal to sRGB, as a PAL monitor shows it: each channel from
    /// 0 to 255, not rounded.
    public static func rgb(_ signal: YUV) -> (r: Double, g: Double, b: Double) {
        func clamped(_ value: Double) -> Double { min(max(value, 0), 255) }
        let r = clamped(signal.y + 1.140 * signal.v)
        let g = clamped(signal.y - 0.396 * signal.u - 0.581 * signal.v)
        let b = clamped(signal.y + 2.029 * signal.u)
        return (gammaCorrected(r), gammaCorrected(g), gammaCorrected(b))
    }

    /// The palette these settings give, with the model's signals.
    public var palette: C64Palette {
        let signals = C64Color.allCases.map(signal)
        return C64Palette(
            name: "Colodore",
            colors: signals.map { signal in
                let rgb = Self.rgb(signal)
                return RGB(UInt8(rgb.r.rounded()), UInt8(rgb.g.rounded()), UInt8(rgb.b.rounded()))
            }, signals: signals)
    }

    /// The signal that `rgb(_:)` turns into a colour: how a PAL monitor
    /// would show a palette that is not Colodore's.
    public static func signal(showing color: RGB) -> YUV {
        // Undo the gamma correction, then the conversion to RGB.
        func uncorrected(_ value: UInt8) -> Double { 255 * pow(Double(value) / 255, 2.2 / 2.8) }
        let (r, g, b) = (uncorrected(color.r), uncorrected(color.g), uncorrected(color.b))
        let (blueWeight, redWeight) = (0.396 / 2.029, 0.581 / 1.140)
        let y = (g + blueWeight * b + redWeight * r) / (1 + blueWeight + redWeight)
        return YUV(y: y, u: (b - y) / 2.029, v: (r - y) / 1.140)
    }

    /// From the PAL signal's gamma (2.8) to sRGB's (2.2).
    static func gammaCorrected(_ value: Double) -> Double {
        let linear = pow(255, 1 - 2.8) * pow(value, 2.8)
        return min(max(pow(255, 1 - 1 / 2.2) * pow(linear, 1 / 2.2), 0), 255)
    }

    /// The colour's luma level, from 0 (black) to 32 (white).
    private static func luma(_ color: C64Color, _ levels: LumaLevels) -> Int {
        switch levels {
        case .nine:
            switch color {
            case .black: 0
            case .blue, .brown: 8
            case .red, .darkGrey: 10
            case .purple, .orange: 12
            case .grey, .lightBlue: 15
            case .green, .lightRed: 16
            case .cyan, .lightGrey: 20
            case .yellow, .lightGreen: 24
            case .white: 32
            }
        case .five:
            switch color {
            case .black: 0
            case .red, .blue, .brown, .darkGrey: 8
            case .purple, .green, .orange, .lightRed, .grey, .lightBlue: 16
            case .cyan, .yellow, .lightGreen, .lightGrey: 24
            case .white: 32
            }
        }
    }

    /// The colour signal's phase, in 16ths of a turn, or nil for the greys.
    private static func phase(_ color: C64Color) -> Int? {
        switch color {
        case .black, .white, .darkGrey, .grey, .lightGrey: nil
        case .red, .lightRed: 4
        case .cyan: 4 + 8
        case .purple: 2
        case .green, .lightGreen: 2 + 8
        case .blue, .lightBlue: 7 + 8
        case .yellow: 7
        case .orange: 5
        case .brown: 6
        }
    }
}

extension C64Palette {
    /// Colodore with its default settings: the default palette.
    public static let colodore = Colodore().palette
}
