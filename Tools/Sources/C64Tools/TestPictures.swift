import C64Core

/// A small seeded random generator (SplitMix64): the same seed always gives
/// the same numbers, on every platform.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Random pictures that obey their mode's limits, for test cards and the VICE
/// tests: random data reaches every colour, every bit pattern and every cell.
public enum TestPictures {
    public static func random(_ spec: ModeSpec, seed: UInt64) -> ModePicture {
        var generator = SeededGenerator(seed: seed)
        var picture = ModePicture(spec: spec)
        let values = UInt8(spec.maps.count)
        let cellWidth = 8 / spec.pixelWidth

        // A character mode draws each cell from a set of characters: its fixed
        // set, or random ones up to its limit.
        var characters: [[UInt8]] = []
        switch spec.pixels {
        case .bitmap:
            break
        case .characters(.fixed(let set)):
            characters = (0..<set.count / 8).map { code in
                (0..<8).flatMap { line in
                    (0..<cellWidth).map { column in
                        let shift = 8 - (column + 1) * spec.bitsPerPixel
                        return (set[code * 8 + line] >> shift) & (values - 1)
                    }
                }
            }
        case .characters(.own(let limit)):
            characters = (0..<limit).map { _ in
                (0..<cellWidth * 8).map { _ in UInt8.random(in: 0..<values, using: &generator) }
            }
        }
        for cell in 0..<C64Frame.cellCount {
            let character = characters.isEmpty ? nil : characters.randomElement(using: &generator)!
            for line in 0..<8 {
                for column in 0..<cellWidth {
                    let pixel = (cell / 40 * 8 + line) * spec.width + cell % 40 * cellWidth + column
                    picture.pixels[pixel] =
                        character?[line * cellWidth + column] ?? UInt8.random(in: 0..<values, using: &generator)
                }
            }
        }

        for (index, map) in spec.maps.enumerated() {
            var shared: [C64Color] = []
            if case .shared(let count) = map.values {
                shared = (0..<count).map { _ in randomColor(using: &generator) }
            }
            picture.colors[index] = picture.colors[index].map { _ in
                switch map.values {
                case .any: randomColor(using: &generator)
                case .firstEight: randomColor(below: 8, using: &generator)
                case .shared: shared.randomElement(using: &generator)!
                }
            }
        }
        picture.borderColor = randomColor(using: &generator)
        return picture
    }

    private static func randomColor(below limit: UInt8 = 16, using generator: inout SeededGenerator) -> C64Color {
        C64Color(rawValue: UInt8.random(in: 0..<limit, using: &generator))!
    }
}
