/// A picture in a mode, as the converter makes it: each pixel's value, and
/// the colours in each of the mode's colour maps.
public struct ModePicture: Hashable, Sendable {
    public let spec: ModeSpec
    /// Row by row, each pixel's value: the index of the map it takes its
    /// colour from.
    public var pixels: [UInt8]
    /// Each map's colours: one for a global map, and one per cell, row by
    /// row, for a cell map.
    public var colors: [[C64Color]]
    public var borderColor: C64Color

    /// A picture with every pixel 0 and every colour black.
    public init(spec: ModeSpec) {
        self.init(
            spec: spec, pixels: Array(repeating: 0, count: spec.width * spec.height),
            colors: spec.maps.map { Array(repeating: .black, count: spec.valueCount($0)) }, borderColor: .black)
    }

    public init(spec: ModeSpec, pixels: [UInt8], colors: [[C64Color]], borderColor: C64Color) {
        precondition(pixels.count == spec.width * spec.height)
        precondition(colors.count == spec.maps.count)
        precondition(zip(spec.maps, colors).allSatisfy { spec.valueCount($0) == $1.count })
        self.spec = spec
        self.pixels = pixels
        self.colors = colors
        self.borderColor = borderColor
    }

    /// Each pixel's colour as the mode defines it, at 320 × 200 hires pixels.
    public func image() -> IndexedImage {
        var image = IndexedImage(width: Screen.windowWidth, height: Screen.windowHeight)
        for y in 0..<spec.height {
            for x in 0..<spec.width {
                let value = Int(pixels[y * spec.width + x])
                let color: C64Color =
                    switch spec.maps[value].granularity {
                    case .global: colors[value][0]
                    case .cell(let width, let height): colors[value][y / height * (spec.width / width) + x / width]
                    }
                for column in x * spec.pixelWidth..<(x + 1) * spec.pixelWidth {
                    image[column, y] = color
                }
            }
        }
        return image
    }
}

/// Why a picture could not be encoded in its mode.
public enum ModeEncodingError: Error, Hashable {
    /// A map holds a colour it does not allow.
    case colorNotAllowed(map: Int, index: Int)
    /// A map shares more colours than the mode has room for.
    case tooManySharedColors(map: Int, count: Int)
    /// The picture has more distinct characters than the mode allows.
    case tooManyCharacters(count: Int, limit: Int)
    /// A cell's pixels match none of the mode's fixed characters.
    case noSuchCharacter(cell: Int)
}

extension C64Frame {
    /// Encodes a picture into C64 memory, with the usual layout. The picture
    /// must obey its mode's limits.
    public init(_ picture: ModePicture) throws(ModeEncodingError) {
        let spec = picture.spec
        let cellWidth = 8 / spec.pixelWidth
        precondition(picture.pixels.allSatisfy { Int($0) < spec.maps.count }, "A pixel value names a map")
        self.init(mode: spec.graphicsMode)
        borderColor = picture.borderColor

        var screen = [UInt8](repeating: 0, count: Self.cellCount)
        var colors = [UInt8](repeating: 0, count: Self.cellCount)
        var selectors = [UInt8](repeating: 0, count: Self.cellCount)
        for (index, map) in spec.maps.enumerated() {
            let values = picture.colors[index]
            if let bad = values.firstIndex(where: { !map.allows($0) }) {
                throw .colorNotAllowed(map: index, index: bad)
            }
            if case .cell(let width, let height) = map.granularity {
                precondition(width == cellWidth && height == 8, "Only maps with a colour per 8 × 8 cell for now")
            }
            switch map.storage {
            case .backgroundColor(let register):
                backgroundColors[register] = values[0]
            case .screenHighNibble:
                for cell in 0..<Self.cellCount { screen[cell] |= values[cell].rawValue << 4 }
            case .screenLowNibble:
                for cell in 0..<Self.cellCount { screen[cell] |= values[cell].rawValue }
            case .colorRAM:
                // In multicolour text, bit 3 makes a character multicolour.
                let flag: UInt8 = spec.graphicsMode == .multicolorText ? 0x08 : 0
                for cell in 0..<Self.cellCount { colors[cell] = values[cell].rawValue | flag }
            case .extendedBackground:
                var shared: [C64Color] = []
                for cell in 0..<Self.cellCount {
                    if let known = shared.firstIndex(of: values[cell]) {
                        selectors[cell] = UInt8(known)
                    } else {
                        selectors[cell] = UInt8(shared.count)
                        shared.append(values[cell])
                    }
                }
                guard case .shared(let count) = map.values, shared.count <= count else {
                    throw .tooManySharedColors(map: index, count: shared.count)
                }
                for (register, color) in shared.enumerated() {
                    backgroundColors[register] = color
                }
            }
        }

        // Each cell's 8 bytes as the VIC-II reads them: a line of 8 pixels of
        // 1 bit, or 4 pixels of 2 bits, most significant bits on the left.
        let cellBytes = (0..<Self.cellCount).map { cell in
            (0..<8).map { line in
                let start = (cell / 40 * 8 + line) * spec.width + cell % 40 * cellWidth
                return picture.pixels[start..<start + cellWidth].reduce(UInt8(0)) {
                    $0 << spec.bitsPerPixel | $1
                }
            }
        }

        switch spec.pixels {
        case .bitmap:
            bitmap = cellBytes.flatMap { $0 }
        case .characters(let characters):
            var codes: [[UInt8]: Int] = [:]
            var set: [UInt8]
            switch characters {
            case .fixed(let fixed):
                set = fixed
                for code in stride(from: fixed.count / 8 - 1, through: 0, by: -1) {
                    codes[Array(fixed[code * 8..<code * 8 + 8])] = code
                }
                if let missing = cellBytes.firstIndex(where: { codes[$0] == nil }) {
                    throw .noSuchCharacter(cell: missing)
                }
            case .own(let limit):
                set = []
                for bytes in cellBytes where codes[bytes] == nil {
                    codes[bytes] = codes.count
                    set += bytes
                }
                guard codes.count <= limit else { throw .tooManyCharacters(count: codes.count, limit: limit) }
            }
            memory.replaceSubrange(graphicsAddress..<graphicsAddress + set.count, with: set)
            for cell in 0..<Self.cellCount {
                screen[cell] = UInt8(codes[cellBytes[cell]]!) | selectors[cell] << 6
            }
        }
        self.screen = screen
        colorRAM = colors
    }
}
