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
    /// Where the VIC-II sees the character ROM in banks 0 and 2, as offsets
    /// from the start of the bank.
    public static let characterROMArea = 0x1000..<0x2000

    public let mode: GraphicsMode
    /// The RAM the VIC-II reads from: 16 KB, as offsets from the start of
    /// its bank. Exported programs place it in a bank without the character
    /// ROM, unless the frame uses the ROM.
    public var memory: [UInt8] {
        didSet { precondition(memory.count == Self.memorySize, "The VIC-II reads 16 KB") }
    }
    /// The colour RAM: one colour (0–15) for each of the 1,000 cells.
    public var colorRAM: [UInt8] {
        didSet { precondition(colorRAM.count == Self.cellCount, "The colour RAM has 1,000 cells") }
    }
    /// Where the video matrix (screen memory) starts: a multiple of $400.
    /// `relocate(screen:graphics:)` moves it.
    public private(set) var screenAddress: Int
    /// Where the character set starts, a multiple of $800, or the bitmap,
    /// $0000 or $2000. `relocate(screen:graphics:)` moves it.
    public private(set) var graphicsAddress: Int
    public var borderColor: C64Color
    /// Background colours 0–3 ($D021–$D024). Every mode uses the first; the
    /// multicolour and extended colour modes use more.
    public var backgroundColors: [C64Color] {
        didSet { precondition(backgroundColors.count == 4, "The VIC-II has 4 background colours") }
    }
    /// Whether the VIC-II sees the character ROM at $1000–$1FFF, as it does in
    /// banks 0 and 2, rather than the RAM there. PETSCII pictures take their
    /// characters from it, so their programs hold only the video matrix and
    /// the colours.
    public let seesCharacterROM: Bool

    /// A frame with blank memory, black colours and the usual layout: the
    /// screen at $0000 and the character set at $0800, or the bitmap at $2000.
    public init(mode: GraphicsMode) {
        self.init(
            mode: mode, memory: Array(repeating: 0, count: Self.memorySize),
            colorRAM: Array(repeating: 0, count: Self.cellCount), screenAddress: 0x0000,
            graphicsAddress: mode.isBitmap ? 0x2000 : 0x0800, borderColor: .black,
            backgroundColors: Array(repeating: .black, count: 4))
    }

    /// A text frame with blank memory and black colours that shows one of the
    /// character ROM's sets, laid out as the C64 itself has it: the screen at
    /// $0400 and the set at $1000 or $1800.
    public init(characterSet: CharacterROM.Set) {
        self.init(
            mode: .standardText, memory: Array(repeating: 0, count: Self.memorySize),
            colorRAM: Array(repeating: 0, count: Self.cellCount), screenAddress: 0x0400,
            graphicsAddress: characterSet.address, borderColor: .black,
            backgroundColors: Array(repeating: .black, count: 4), seesCharacterROM: true)
    }

    public init(
        mode: GraphicsMode, memory: [UInt8], colorRAM: [UInt8], screenAddress: Int, graphicsAddress: Int,
        borderColor: C64Color, backgroundColors: [C64Color], seesCharacterROM: Bool = false
    ) {
        precondition(memory.count == Self.memorySize, "The VIC-II reads 16 KB")
        precondition(colorRAM.count == Self.cellCount, "The colour RAM has 1,000 cells")
        precondition(backgroundColors.count == 4, "The VIC-II has 4 background colours")
        Self.checkLayout(mode, screen: screenAddress, graphics: graphicsAddress)
        self.mode = mode
        self.memory = memory
        self.colorRAM = colorRAM
        self.screenAddress = screenAddress
        self.graphicsAddress = graphicsAddress
        self.borderColor = borderColor
        self.backgroundColors = backgroundColors
        self.seesCharacterROM = seesCharacterROM
    }

    /// Moves the video matrix and the character set or bitmap to other
    /// addresses, with their contents, so the picture stays the same. Memory
    /// the picture does not use is cleared. Where the VIC-II sees the
    /// character ROM, the graphics stay where they are, and the video matrix
    /// cannot move into the ROM.
    public mutating func relocate(screen: Int, graphics: Int) {
        Self.checkLayout(mode, screen: screen, graphics: graphics)
        precondition(!seesCharacterROM || graphics == graphicsAddress, "Characters in the ROM stay where they are")
        let newScreen = screen..<screen + Self.cellCount
        let newGraphics = graphics..<graphics + graphicsSize
        precondition(!newScreen.overlaps(newGraphics), "The video matrix and the graphics would overlap")
        precondition(
            !seesCharacterROM || !newScreen.overlaps(Self.characterROMArea),
            "The video matrix would be under the character ROM")
        let oldScreen = screenAddress..<screenAddress + Self.cellCount
        var moved = [UInt8](repeating: 0, count: Self.memorySize)
        for range in usedMemory {
            let offset = oldScreen.contains(range.lowerBound) ? screen - screenAddress : graphics - graphicsAddress
            moved.replaceSubrange(range.lowerBound + offset..<range.upperBound + offset, with: memory[range])
        }
        memory = moved
        screenAddress = screen
        graphicsAddress = graphics
    }

    private static func checkLayout(_ mode: GraphicsMode, screen: Int, graphics: Int) {
        precondition(screen & 0x3FF == 0 && (0..<memorySize).contains(screen), "The video matrix starts every $400")
        if mode.isBitmap {
            precondition(graphics == 0x0000 || graphics == 0x2000, "A bitmap starts at $0000 or $2000")
        } else {
            precondition(graphics & 0x7FF == 0 && (0..<memorySize).contains(graphics), "Characters start every $800")
        }
    }

    /// $D018: where the VIC-II finds the video matrix and the character set
    /// or bitmap.
    public var memoryPointers: UInt8 {
        UInt8(screenAddress >> 10) << 4 | UInt8(graphicsAddress >> 11) << 1
    }

    /// How many bytes of graphics the mode reads: a bitmap, or a set of
    /// characters.
    private var graphicsSize: Int {
        switch mode {
        case .hiresBitmap, .multicolorBitmap: 8000
        case .standardText, .multicolorText: 256 * 8
        case .extendedColorText: 64 * 8
        }
    }

    /// The parts of `memory` the VIC-II reads for this frame, as ranges of
    /// offsets: the video matrix and the graphics, except what it reads from
    /// the character ROM instead. Nothing else in `memory` changes the
    /// picture.
    public var usedMemory: [Range<Int>] {
        let ranges = [screenAddress..<screenAddress + Self.cellCount, graphicsAddress..<graphicsAddress + graphicsSize]
        guard seesCharacterROM else { return ranges }
        let rom = Self.characterROMArea
        return ranges.flatMap { range in
            let below = range.lowerBound..<max(range.lowerBound, min(range.upperBound, rom.lowerBound))
            let above = min(range.upperBound, max(range.lowerBound, rom.upperBound))..<range.upperBound
            return [below, above].filter { !$0.isEmpty }
        }
    }

    /// The 16 KB as the VIC-II sees them: `memory`, with the character ROM at
    /// $1000–$1FFF if the frame sees it there.
    public var visibleMemory: [UInt8] {
        guard seesCharacterROM else { return memory }
        var visible = memory
        visible.replaceSubrange(Self.characterROMArea, with: CharacterROM.bytes)
        return visible
    }
}
