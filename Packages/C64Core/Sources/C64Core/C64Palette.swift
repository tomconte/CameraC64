/// An sRGB colour with 8-bit channels.
public struct RGB: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// The RGB value shown for each of the 16 C64 colours.
public struct C64Palette: Sendable {
    public let name: String
    /// One entry per `C64Color`, in hardware index order.
    public let colors: [RGB]

    public init(name: String, colors: [RGB]) {
        precondition(colors.count == 16, "A C64 palette has exactly 16 colours")
        self.name = name
        self.colors = colors
    }

    public subscript(color: C64Color) -> RGB {
        colors[Int(color.rawValue)]
    }
}

extension C64Palette {
    /// Pepto's 2001 palette, the one the 2012–2013 app's colour tables used.
    /// Colodore (Pepto, 2017) becomes the default once its model is implemented.
    public static let pepto2001 = C64Palette(name: "Pepto (2001)", colors: [
        RGB(0x00, 0x00, 0x00), // black
        RGB(0xFF, 0xFF, 0xFF), // white
        RGB(0x68, 0x37, 0x2B), // red
        RGB(0x70, 0xA4, 0xB2), // cyan
        RGB(0x6F, 0x3D, 0x86), // purple
        RGB(0x58, 0x8D, 0x43), // green
        RGB(0x35, 0x28, 0x79), // blue
        RGB(0xB8, 0xC7, 0x6F), // yellow
        RGB(0x6F, 0x4F, 0x25), // orange
        RGB(0x43, 0x39, 0x00), // brown
        RGB(0x9A, 0x67, 0x59), // light red
        RGB(0x44, 0x44, 0x44), // dark grey
        RGB(0x6C, 0x6C, 0x6C), // grey
        RGB(0x9A, 0xD2, 0x84), // light green
        RGB(0x6C, 0x5E, 0xB5), // light blue
        RGB(0x95, 0x95, 0x95), // light grey
    ])
}
