/// A picture in 8-bit sRGB: a photo for the converter, or what a display
/// model shows.
public struct RGBImage: Hashable, Sendable {
    /// The order of each pixel's bytes. A fourth byte, if any, is ignored.
    public enum Layout: Hashable, Sendable {
        case rgb
        case rgba
        /// As camera frames come.
        case bgra

        public var bytesPerPixel: Int { self == .rgb ? 3 : 4 }

        /// Where red, green and blue are in a pixel's bytes.
        var offsets: (r: Int, g: Int, b: Int) { self == .bgra ? (2, 1, 0) : (0, 1, 2) }
    }

    public let width: Int
    public let height: Int
    public let layout: Layout
    /// Row by row from the top, `layout.bytesPerPixel` bytes per pixel, with
    /// no padding between rows.
    public var bytes: [UInt8] {
        didSet { precondition(bytes.count == width * height * layout.bytesPerPixel, "One pixel per position") }
    }

    public init(width: Int, height: Int, layout: Layout = .rgb, bytes: [UInt8]) {
        precondition(width >= 0 && height >= 0 && bytes.count == width * height * layout.bytesPerPixel)
        self.width = width
        self.height = height
        self.layout = layout
        self.bytes = bytes
    }

    /// A picture in one colour, laid out as `.rgb`.
    public init(width: Int, height: Int, fill: RGB) {
        precondition(width >= 0 && height >= 0)
        self.init(
            width: width, height: height,
            bytes: [UInt8]((0..<width * height).lazy.flatMap { _ in [fill.r, fill.g, fill.b] }))
    }

    public subscript(x: Int, y: Int) -> RGB {
        get {
            let start = (y * width + x) * layout.bytesPerPixel
            let offsets = layout.offsets
            return RGB(bytes[start + offsets.r], bytes[start + offsets.g], bytes[start + offsets.b])
        }
        set {
            let start = (y * width + x) * layout.bytesPerPixel
            let offsets = layout.offsets
            bytes[start + offsets.r] = newValue.r
            bytes[start + offsets.g] = newValue.g
            bytes[start + offsets.b] = newValue.b
        }
    }

    /// The part of the picture inside a rectangle, which must lie within it.
    public func cropped(x: Int, y: Int, width: Int, height: Int) -> RGBImage {
        precondition(x >= 0 && y >= 0 && width >= 0 && height >= 0)
        precondition(x + width <= self.width && y + height <= self.height)
        let size = layout.bytesPerPixel
        var rows: [UInt8] = []
        rows.reserveCapacity(width * height * size)
        for row in y..<y + height {
            let start = (row * self.width + x) * size
            rows.append(contentsOf: bytes[start..<start + width * size])
        }
        return RGBImage(width: width, height: height, layout: layout, bytes: rows)
    }
}

extension IndexedImage {
    /// The picture in a palette's colours, without a display model: as an
    /// emulator shows it with no CRT emulation.
    public func rgbImage(_ palette: C64Palette) -> RGBImage {
        RGBImage(width: width, height: height, bytes: rgb(palette))
    }
}
