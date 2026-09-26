/// The 16 colours of the VIC-II, identified by their 4-bit hardware index.
///
/// The index is what the C64 stores in screen memory, colour memory and the
/// colour registers. What it looks like on screen depends on the palette
/// model and the display (see `C64Palette`).
public enum C64Color: UInt8, CaseIterable, Sendable {
    case black = 0
    case white
    case red
    case cyan
    case purple
    case green
    case blue
    case yellow
    case orange
    case brown
    case lightRed
    case darkGrey
    case grey
    case lightGreen
    case lightBlue
    case lightGrey

    /// Brightness rank from 0 (black) to 8 (white), on the VIC-II revisions
    /// with 9 brightness levels.
    ///
    /// Colours with the same rank have the same brightness, so a PAL display
    /// blends them without visible texture.
    public var lumaRank: Int {
        switch self {
        case .black: 0
        case .blue, .brown: 1
        case .red, .darkGrey: 2
        case .purple, .orange: 3
        case .grey, .lightBlue: 4
        case .green, .lightRed: 5
        case .cyan, .lightGrey: 6
        case .yellow, .lightGreen: 7
        case .white: 8
        }
    }
}
