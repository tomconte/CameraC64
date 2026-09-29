/// One of the VIC-II's graphics modes, set by the ECM and BMM bits of $D011
/// and the MCM bit of $D016. The three combinations that only show black are
/// left out.
public enum GraphicsMode: Hashable, Sendable, CaseIterable {
    /// 40 × 25 characters of 8 × 8 pixels from a set of 256, each in one
    /// colour on a shared background.
    case standardText
    /// As standard text, but a character whose colour is 8–15 has 4 × 8
    /// double-wide pixels in 4 colours, 3 of them shared.
    case multicolorText
    /// 64 characters, each with its own colour and one of 4 shared
    /// backgrounds.
    case extendedColorText
    /// 320 × 200 pixels, 2 colours in each 8 × 8 cell.
    case hiresBitmap
    /// 160 × 200 double-wide pixels, 3 colours in each 4 × 8 cell and a
    /// shared background.
    case multicolorBitmap

    /// Whether the mode reads a bitmap rather than a character set.
    public var isBitmap: Bool {
        self == .hiresBitmap || self == .multicolorBitmap
    }

    /// $D011 with the display on, 25 rows and no vertical scroll.
    public var controlRegister1: UInt8 {
        switch self {
        case .standardText, .multicolorText: 0x1B
        case .extendedColorText: 0x5B
        case .hiresBitmap, .multicolorBitmap: 0x3B
        }
    }

    /// $D016 with 40 columns and no horizontal scroll.
    public var controlRegister2: UInt8 {
        switch self {
        case .multicolorText, .multicolorBitmap: 0x18
        case .standardText, .extendedColorText, .hiresBitmap: 0x08
        }
    }
}

/// What the VIC-II displays a picture from: the 16 KB of memory it reads,
/// the colour RAM, and the register values the display program sets.
///
/// Converters produce frames, and every picture shown or exported is rendered
/// from one, so no picture can break the hardware's rules.
///
/// The display always has 25 rows of 40 columns without scrolling: the
/// display programs set that, and the renderer draws exactly that.
public struct C64Frame: Hashable, Sendable {
    public static let memorySize = 0x4000
    public static let cellCount = 1000

    public var mode: GraphicsMode
    /// The 16 KB the VIC-II reads from, as offsets from the start of its
    /// bank. Exported programs place it in a bank without the character ROM.
    public var memory: [UInt8]
    /// The colour RAM: one colour (0–15) for each of the 1,000 cells.
    public var colorRAM: [UInt8]
    /// Where the video matrix (screen memory) starts: a multiple of $400.
    public var screenAddress: Int
    /// Where the character set starts, a multiple of $800, or the bitmap,
    /// $0000 or $2000.
    public var graphicsAddress: Int
    public var borderColor: C64Color
    /// Background colours 0–3 ($D021–$D024). Every mode uses the first; the
    /// multicolour and extended colour modes use more.
    public var backgroundColors: [C64Color]

    /// A frame with blank memory, black colours and the usual layout: the
    /// screen at $0000 and the character set at $0800, or the bitmap at $2000.
    public init(mode: GraphicsMode) {
        self.init(
            mode: mode, memory: Array(repeating: 0, count: Self.memorySize),
            colorRAM: Array(repeating: 0, count: Self.cellCount), screenAddress: 0x0000,
            graphicsAddress: mode.isBitmap ? 0x2000 : 0x0800, borderColor: .black,
            backgroundColors: Array(repeating: .black, count: 4))
    }

    public init(
        mode: GraphicsMode, memory: [UInt8], colorRAM: [UInt8], screenAddress: Int, graphicsAddress: Int,
        borderColor: C64Color, backgroundColors: [C64Color]
    ) {
        precondition(memory.count == Self.memorySize, "The VIC-II reads 16 KB")
        precondition(colorRAM.count == Self.cellCount, "The colour RAM has 1,000 cells")
        precondition(backgroundColors.count == 4, "The VIC-II has 4 background colours")
        precondition(screenAddress & 0x3FF == 0 && (0..<Self.memorySize).contains(screenAddress))
        if mode.isBitmap {
            precondition(graphicsAddress == 0x0000 || graphicsAddress == 0x2000, "A bitmap starts at $0000 or $2000")
        } else {
            precondition(graphicsAddress & 0x7FF == 0 && (0..<Self.memorySize).contains(graphicsAddress))
        }
        self.mode = mode
        self.memory = memory
        self.colorRAM = colorRAM
        self.screenAddress = screenAddress
        self.graphicsAddress = graphicsAddress
        self.borderColor = borderColor
        self.backgroundColors = backgroundColors
    }

    /// $D018: where the VIC-II finds the video matrix and the character set
    /// or bitmap.
    public var memoryPointers: UInt8 {
        UInt8(screenAddress >> 10) << 4 | UInt8(graphicsAddress >> 11) << 1
    }

    /// The parts of `memory` the VIC-II reads for this frame, as ranges of
    /// offsets. Nothing else in `memory` changes the picture.
    public var usedMemory: [Range<Int>] {
        let screen = screenAddress..<screenAddress + Self.cellCount
        let graphicsSize =
            switch mode {
            case .hiresBitmap, .multicolorBitmap: 8000
            case .standardText, .multicolorText: 256 * 8
            case .extendedColorText: 64 * 8
            }
        return [screen, graphicsAddress..<graphicsAddress + graphicsSize]
    }
}
