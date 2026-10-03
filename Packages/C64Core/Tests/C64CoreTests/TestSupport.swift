import C64Core
import Foundation

/// A small seeded generator (SplitMix64), so random tests are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension C64Color {
    static func random(below limit: UInt8 = 16, using generator: inout SeededGenerator) -> C64Color {
        C64Color(rawValue: UInt8.random(in: 0..<limit, using: &generator))!
    }
}

extension ModePicture {
    /// A random picture that obeys its mode's limits. In the character ROM's
    /// characters, it takes them from the given set.
    static func random(
        _ spec: ModeSpec, seed: UInt64, characterSet: CharacterROM.Set = .upperCase
    ) -> ModePicture {
        var generator = SeededGenerator(seed: seed)
        var picture = ModePicture(spec: spec)
        let values = UInt8(spec.maps.count)
        let cellWidth = 8 / spec.pixelWidth

        // Character modes draw each cell from a set of characters: the fixed
        // set, or a random one within the limit.
        var tiles: [[UInt8]] = []
        func pixels(of set: [UInt8]) -> [[UInt8]] {
            (0..<set.count / 8).map { code in
                (0..<8).flatMap { line in
                    let byte = set[code * 8 + line]
                    return (0..<8).map { (byte >> (7 - $0)) & 1 }
                }
            }
        }
        switch spec.pixels {
        case .bitmap:
            break
        case .characters(.fixed(let set)):
            tiles = pixels(of: set)
        case .characters(.rom):
            tiles = pixels(of: characterSet.characters)
        case .characters(.own(let limit)):
            tiles = (0..<limit).map { _ in
                (0..<cellWidth * 8).map { _ in UInt8.random(in: 0..<values, using: &generator) }
            }
        }
        for cell in 0..<C64Frame.cellCount {
            let tile = tiles.isEmpty ? nil : tiles.randomElement(using: &generator)!
            for line in 0..<8 {
                for column in 0..<cellWidth {
                    let pixel = (cell / 40 * 8 + line) * spec.width + cell % 40 * cellWidth + column
                    picture.pixels[pixel] =
                        tile?[line * cellWidth + column] ?? UInt8.random(in: 0..<values, using: &generator)
                }
            }
        }

        for (index, map) in spec.maps.enumerated() {
            var palette: [C64Color] = []
            if case .shared(let count) = map.values {
                palette = (0..<count).map { _ in C64Color.random(using: &generator) }
            }
            picture.colors[index] = picture.colors[index].map { _ in
                switch map.values {
                case .any: C64Color.random(using: &generator)
                case .firstEight: C64Color.random(below: 8, using: &generator)
                case .shared: palette.randomElement(using: &generator)!
                }
            }
        }
        picture.borderColor = C64Color.random(using: &generator)
        return picture
    }
}

/// A random character set: 256 characters of 8 bytes.
func randomCharacterSet(seed: UInt64) -> [UInt8] {
    var generator = SeededGenerator(seed: seed)
    return (0..<2048).map { _ in UInt8.random(in: 0...255, using: &generator) }
}

/// A smooth, colourful target: hue across, lightness down.
func gradient(for spec: ModeSpec) -> Target {
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
