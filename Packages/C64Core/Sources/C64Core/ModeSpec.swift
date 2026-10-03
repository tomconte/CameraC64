/// A graphics mode described as data: a grid of pixels, each taking its
/// colour from one of a few colour maps, the limits on those maps, and where
/// the VIC-II finds each of them.
///
/// The converter searches any mode described this way, and one encoder turns
/// its result into C64 memory (`C64Frame.init(_:)`). The idea comes from
/// Retropixels (plan, section 14).
public struct ModeSpec: Hashable, Sendable {
    /// Where the pixels' values live.
    public enum Pixels: Hashable, Sendable {
        /// A bitmap: every pixel is free.
        case bitmap
        /// A character set: each 8 × 8 cell shows one character.
        case characters(Characters)
    }

    /// The characters a character mode can show.
    public enum Characters: Hashable, Sendable {
        /// The picture's own characters, at most this many.
        case own(limit: Int)
        /// A given set, 8 bytes per character as the VIC-II reads them, copied
        /// into RAM.
        case fixed([UInt8])
        /// The C64's own, which the VIC-II reads from the character ROM: a
        /// picture takes all its characters from one of the ROM's two sets.
        case rom
    }

    public var graphicsMode: GraphicsMode
    /// The pixel grid: 320 × 200, or 160 × 200 double-wide pixels.
    public var width: Int
    public var height: Int
    /// How many hires pixels wide a pixel is: 1, or 2 in the multicolour modes.
    public var pixelWidth: Int
    /// In pixel value order: a pixel with value v takes its colour from
    /// `maps[v]`.
    public var maps: [ColorMap]
    public var pixels: Pixels

    public init(
        graphicsMode: GraphicsMode, width: Int, height: Int, pixelWidth: Int, maps: [ColorMap], pixels: Pixels
    ) {
        precondition(maps.count == 2 || maps.count == 4, "Pixels have 1 or 2 bits")
        precondition(width * pixelWidth == 320 && height == 200)
        self.graphicsMode = graphicsMode
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.maps = maps
        self.pixels = pixels
    }

    public var bitsPerPixel: Int { maps.count == 2 ? 1 : 2 }

    /// How many values a map holds: 1 for a global map, one per cell
    /// otherwise.
    public func valueCount(_ map: ColorMap) -> Int {
        switch map.granularity {
        case .global: 1
        case .cell(let cellWidth, let cellHeight): (width / cellWidth) * (height / cellHeight)
        }
    }
}

/// Where a group of pixels finds its colour, and which colours it can hold.
public struct ColorMap: Hashable, Sendable {
    /// Which pixels share a value.
    public enum Granularity: Hashable, Sendable {
        /// The whole picture.
        case global
        /// Each cell of this many pixels of the mode's grid.
        case cell(width: Int, height: Int)
    }

    /// The colours a map can hold.
    public enum Values: Hashable, Sendable {
        /// Any of the 16.
        case any
        /// Colours 0–7.
        case firstEight
        /// Any of a few colours that the whole picture shares.
        case shared(count: Int)
    }

    /// Where the VIC-II reads the colour from.
    public enum Storage: Hashable, Sendable {
        /// Background colour register n, $D021 + n.
        case backgroundColor(Int)
        /// The high or low nibble of the cell's byte in the video matrix.
        case screenHighNibble
        case screenLowNibble
        /// The cell's colour RAM.
        case colorRAM
        /// One of the four background registers, chosen by the top two bits
        /// of the cell's character code (extended colour mode).
        case extendedBackground
    }

    public var granularity: Granularity
    public var values: Values
    public var storage: Storage

    public init(_ granularity: Granularity, _ values: Values, _ storage: Storage) {
        self.granularity = granularity
        self.values = values
        self.storage = storage
    }

    public func allows(_ color: C64Color) -> Bool {
        values != .firstEight || color.rawValue < 8
    }
}

extension ModeSpec {
    /// Hires bitmap: 320 × 200 pixels, 2 colours in each 8 × 8 cell.
    public static let hires = ModeSpec(
        graphicsMode: .hiresBitmap, width: 320, height: 200, pixelWidth: 1,
        maps: [
            ColorMap(.cell(width: 8, height: 8), .any, .screenLowNibble),
            ColorMap(.cell(width: 8, height: 8), .any, .screenHighNibble),
        ], pixels: .bitmap)

    /// Multicolour bitmap: 160 × 200 double-wide pixels, 3 colours in each
    /// 4 × 8 cell and a background shared by the whole picture.
    public static let multicolor = ModeSpec(
        graphicsMode: .multicolorBitmap, width: 160, height: 200, pixelWidth: 2,
        maps: [
            ColorMap(.global, .any, .backgroundColor(0)),
            ColorMap(.cell(width: 4, height: 8), .any, .screenHighNibble),
            ColorMap(.cell(width: 4, height: 8), .any, .screenLowNibble),
            ColorMap(.cell(width: 4, height: 8), .any, .colorRAM),
        ], pixels: .bitmap)

    /// PETSCII: text in the C64's own characters, from either set of its
    /// character ROM, one colour in each cell on a shared background.
    public static let petscii = ModeSpec(
        graphicsMode: .standardText, width: 320, height: 200, pixelWidth: 1,
        maps: [
            ColorMap(.global, .any, .backgroundColor(0)),
            ColorMap(.cell(width: 8, height: 8), .any, .colorRAM),
        ], pixels: .characters(.rom))

    /// Text with a given character set, copied into RAM: one colour in each
    /// cell on a shared background.
    public static func text(characters: [UInt8]) -> ModeSpec {
        precondition(characters.count == 256 * 8, "A character set has 256 characters of 8 bytes")
        return ModeSpec(
            graphicsMode: .standardText, width: 320, height: 200, pixelWidth: 1,
            maps: [
                ColorMap(.global, .any, .backgroundColor(0)),
                ColorMap(.cell(width: 8, height: 8), .any, .colorRAM),
            ], pixels: .characters(.fixed(characters)))
    }

    /// The picture's own character set of up to 256 characters, in hires:
    /// one colour in each cell on a shared background.
    public static let characterSet = ModeSpec(
        graphicsMode: .standardText, width: 320, height: 200, pixelWidth: 1,
        maps: [
            ColorMap(.global, .any, .backgroundColor(0)),
            ColorMap(.cell(width: 8, height: 8), .any, .colorRAM),
        ], pixels: .characters(.own(limit: 256)))

    /// The picture's own character set of up to 256 characters, in
    /// multicolour: 3 colours shared by the whole picture and one of colours
    /// 0–7 in each cell.
    public static let multicolorCharacterSet = ModeSpec(
        graphicsMode: .multicolorText, width: 160, height: 200, pixelWidth: 2,
        maps: [
            ColorMap(.global, .any, .backgroundColor(0)),
            ColorMap(.global, .any, .backgroundColor(1)),
            ColorMap(.global, .any, .backgroundColor(2)),
            ColorMap(.cell(width: 4, height: 8), .firstEight, .colorRAM),
        ], pixels: .characters(.own(limit: 256)))

    /// The picture's own set of up to 64 characters in extended colour mode:
    /// any colour in each cell, on one of 4 backgrounds shared by the whole
    /// picture.
    public static let extendedColorCharacterSet = ModeSpec(
        graphicsMode: .extendedColorText, width: 320, height: 200, pixelWidth: 1,
        maps: [
            ColorMap(.cell(width: 8, height: 8), .shared(count: 4), .extendedBackground),
            ColorMap(.cell(width: 8, height: 8), .any, .colorRAM),
        ], pixels: .characters(.own(limit: 64)))
}

extension CharacterROM {
    /// One of the character ROM's two sets of 256 characters. The VIC-II
    /// shows one at a time.
    public enum Set: CaseIterable, Hashable, Sendable {
        /// Upper case letters and graphics: the C64's default.
        case upperCase
        /// Lower and upper case letters, with fewer graphics.
        case lowerCase

        /// The set's 2,048 bytes, 8 per character.
        public var characters: [UInt8] {
            let start = self == .upperCase ? 0 : 0x800
            return Array(CharacterROM.bytes[start..<start + 0x800])
        }

        /// Where the VIC-II sees the set, in a bank that shows the ROM.
        public var address: Int {
            self == .upperCase ? 0x1000 : 0x1800
        }
    }
}
