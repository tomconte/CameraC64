/// A picture made of C64 colours, one per pixel: what the renderer draws,
/// before a display model turns it into RGB.
public struct IndexedImage: Hashable, Sendable {
    public let width: Int
    public let height: Int
    /// Row by row from the top, each pixel a colour's hardware index (0–15).
    public var pixels: [UInt8]

    public init(width: Int, height: Int, fill: C64Color = .black) {
        self.init(width: width, height: height, pixels: Array(repeating: fill.rawValue, count: width * height))
    }

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width >= 0 && height >= 0 && pixels.count == width * height)
        precondition(pixels.allSatisfy { $0 < 16 }, "A C64 colour index is 0–15")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public subscript(x: Int, y: Int) -> C64Color {
        get { C64Color(rawValue: pixels[y * width + x])! }
        set { pixels[y * width + x] = newValue.rawValue }
    }

    /// The part of the picture inside a rectangle, which must lie within it.
    public func cropped(x: Int, y: Int, width: Int, height: Int) -> IndexedImage {
        precondition(x >= 0 && y >= 0 && width >= 0 && height >= 0)
        precondition(x + width <= self.width && y + height <= self.height)
        var rows: [UInt8] = []
        rows.reserveCapacity(width * height)
        for row in y..<y + height {
            let start = row * self.width + x
            rows.append(contentsOf: pixels[start..<start + width])
        }
        return IndexedImage(width: width, height: height, pixels: rows)
    }

    /// The picture in a palette's colours: 3 bytes (red, green, blue) per
    /// pixel, row by row.
    public func rgb(_ palette: C64Palette) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(pixels.count * 3)
        for index in pixels {
            let color = palette.colors[Int(index)]
            bytes.append(color.r)
            bytes.append(color.g)
            bytes.append(color.b)
        }
        return bytes
    }
}

/// The PAL screen, in hires pixels.
public enum Screen {
    /// The area the renderer draws: the display window and the border around
    /// it, as far as a TV shows it. It matches VICE's normal borders.
    public static let width = 384
    public static let height = 272

    /// The display window, where the 320 × 200 picture sits. It starts on
    /// raster line 51, the first visible line being 16.
    public static let windowX = 32
    public static let windowY = 35
    public static let windowWidth = 320
    public static let windowHeight = 200
}

extension IndexedImage {
    /// The display window of a full screen: the picture without its border.
    public var window: IndexedImage {
        precondition(width == Screen.width && height == Screen.height, "Not a full screen")
        return cropped(x: Screen.windowX, y: Screen.windowY, width: Screen.windowWidth, height: Screen.windowHeight)
    }
}
