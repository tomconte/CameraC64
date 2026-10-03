/// The VIC-II video chip, as far as drawing a frame goes.
///
/// It follows Christian Bauer's description of the chip (plan, section 18):
/// for each 8 × 8 cell, the chip reads a byte of the video matrix and a
/// colour from the colour RAM, then one byte of graphics for each of the
/// cell's 8 lines, and the mode decides how those bytes become colours.
public enum VICII {
    /// Draws a frame the way the VIC-II displays it: `Screen.width` ×
    /// `Screen.height` pixels, border included.
    public static func render(_ frame: C64Frame) -> IndexedImage {
        var image = IndexedImage(width: Screen.width, height: Screen.height, fill: frame.borderColor)
        let background = frame.backgroundColors.map(\.rawValue)
        frame.visibleMemory.withUnsafeBufferPointer { memory in
            image.pixels.withUnsafeMutableBufferPointer { pixels in
                for cell in 0..<C64Frame.cellCount {
                    let screenByte = memory[frame.screenAddress + cell]
                    let color = frame.colorRAM[cell] & 0x0F
                    let left = Screen.windowX + cell % 40 * 8
                    let top = Screen.windowY + cell / 40 * 8
                    for line in 0..<8 {
                        let row = (top + line) * Screen.width + left
                        switch frame.mode {
                        case .standardText:
                            let bits = memory[frame.graphicsAddress + Int(screenByte) * 8 + line]
                            drawHires(bits, zero: background[0], one: color, into: pixels, at: row)
                        case .multicolorText:
                            let bits = memory[frame.graphicsAddress + Int(screenByte) * 8 + line]
                            if color & 0x08 == 0 {
                                drawHires(bits, zero: background[0], one: color, into: pixels, at: row)
                            } else {
                                let colors = (background[0], background[1], background[2], color & 0x07)
                                drawMulticolor(bits, colors, into: pixels, at: row)
                            }
                        case .extendedColorText:
                            let bits = memory[frame.graphicsAddress + Int(screenByte & 0x3F) * 8 + line]
                            drawHires(bits, zero: background[Int(screenByte >> 6)], one: color, into: pixels, at: row)
                        case .hiresBitmap:
                            let bits = memory[frame.graphicsAddress + cell * 8 + line]
                            drawHires(bits, zero: screenByte & 0x0F, one: screenByte >> 4, into: pixels, at: row)
                        case .multicolorBitmap:
                            let bits = memory[frame.graphicsAddress + cell * 8 + line]
                            let colors = (background[0], screenByte >> 4, screenByte & 0x0F, color)
                            drawMulticolor(bits, colors, into: pixels, at: row)
                        }
                    }
                }
            }
        }
        return image
    }

    /// Eight pixels, one per bit, most significant bit on the left.
    private static func drawHires(
        _ bits: UInt8, zero: UInt8, one: UInt8, into pixels: UnsafeMutableBufferPointer<UInt8>, at start: Int
    ) {
        for pixel in 0..<8 {
            pixels[start + pixel] = bits & (0x80 >> pixel) == 0 ? zero : one
        }
    }

    /// Four double-wide pixels, one per pair of bits: colours for 00, 01, 10
    /// and 11.
    private static func drawMulticolor(
        _ bits: UInt8, _ colors: (UInt8, UInt8, UInt8, UInt8), into pixels: UnsafeMutableBufferPointer<UInt8>,
        at start: Int
    ) {
        for pair in 0..<4 {
            let color =
                switch (bits >> (6 - 2 * pair)) & 0x03 {
                case 0: colors.0
                case 1: colors.1
                case 2: colors.2
                default: colors.3
                }
            pixels[start + 2 * pair] = color
            pixels[start + 2 * pair + 1] = color
        }
    }
}
