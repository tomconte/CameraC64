import C64Core

/// A small PNG reader and writer: enough to write rendered pictures and to
/// read VICE's screenshots, on Linux as on macOS.
public enum PNG {
    public enum Error: Swift.Error, Equatable {
        case notPNG
        case unsupported(String)
        case corrupt(String)
    }

    /// Writes a picture in a palette's colours, each C64 pixel drawn as a
    /// `scale` × `scale` square.
    public static func encode(_ image: IndexedImage, palette: C64Palette, scale: Int = 1) -> [UInt8] {
        precondition(scale >= 1)
        let width = image.width * scale
        // 4 bits per pixel: one filter byte, then two pixels per byte.
        var raw: [UInt8] = []
        raw.reserveCapacity((width / 2 + 2) * image.height * scale)
        for y in 0..<image.height {
            var row: [UInt8] = [0]
            var pending: UInt8?
            for x in 0..<width {
                let index = image.pixels[y * image.width + x / scale]
                if let high = pending {
                    row.append(high << 4 | index)
                    pending = nil
                } else {
                    pending = index
                }
            }
            if let high = pending {
                row.append(high << 4)
            }
            for _ in 0..<scale {
                raw += row
            }
        }
        let header =
            bigEndian(UInt32(width)) + bigEndian(UInt32(image.height * scale)) + [4, 3, 0, 0, 0]
        let colors = palette.colors.flatMap { [$0.r, $0.g, $0.b] }
        return signature + chunk("IHDR", header) + chunk("PLTE", colors) + chunk("IDAT", zlib(raw))
            + chunk("IEND", [])
    }

    /// Writes an RGB picture, each pixel drawn as a `scale` × `scale` square,
    /// or `scale` × `scaleY` when given.
    public static func encode(_ image: RGBImage, scale: Int = 1, scaleY: Int? = nil) -> [UInt8] {
        precondition(scale >= 1 && (scaleY ?? 1) >= 1)
        let (width, height) = (image.width * scale, image.height * (scaleY ?? scale))
        // Each row is stored as its differences from the pixel on the left
        // (filter 1), or from the row above when it repeats it (filter 2), so
        // areas of one colour become runs of zeros, which the compressor
        // handles well.
        var raw: [UInt8] = []
        raw.reserveCapacity((width * 3 + 1) * height)
        for y in 0..<image.height {
            var pixels: [UInt8] = []
            pixels.reserveCapacity(width * 3)
            for x in 0..<image.width {
                let color = image[x, y]
                for _ in 0..<scale {
                    pixels += [color.r, color.g, color.b]
                }
            }
            raw.append(1)
            for index in pixels.indices {
                raw.append(index < 3 ? pixels[index] : pixels[index] &- pixels[index - 3])
            }
            for _ in 1..<(scaleY ?? scale) {
                raw.append(2)
                raw += repeatElement(0, count: pixels.count)
            }
        }
        let header = bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 2, 0, 0, 0]
        return signature + chunk("IHDR", header) + chunk("IDAT", zlib(raw)) + chunk("IEND", [])
    }

    /// Reads a PNG file as a picture.
    public static func decodeImage(_ data: [UInt8]) throws(Error) -> RGBImage {
        let (width, height, rgb) = try decode(data)
        return RGBImage(width: width, height: height, bytes: rgb)
    }

    /// Reads a non-interlaced PNG with 8 bits per channel, or indexed colour,
    /// as RGB: 3 bytes per pixel, row by row.
    public static func decode(_ data: [UInt8]) throws(Error) -> (width: Int, height: Int, rgb: [UInt8]) {
        guard data.count > 8, Array(data[0..<8]) == signature else { throw .notPNG }
        var position = 8
        var header: [UInt8] = []
        var palette: [UInt8] = []
        var compressed: [UInt8] = []
        while position + 8 <= data.count {
            let length = Int(readBigEndian(data, position))
            let type = String(decoding: data[position + 4..<position + 8], as: UTF8.self)
            guard position + 12 + length <= data.count else { throw .corrupt("truncated \(type) chunk") }
            let body = Array(data[position + 8..<position + 8 + length])
            switch type {
            case "IHDR": header = body
            case "PLTE": palette = body
            case "IDAT": compressed += body
            default: break
            }
            position += 12 + length
            if type == "IEND" { break }
        }
        guard header.count == 13 else { throw .corrupt("no header") }
        let width = Int(readBigEndian(header, 0))
        let height = Int(readBigEndian(header, 4))
        let (depth, colorType, interlace) = (Int(header[8]), header[9], header[12])
        guard interlace == 0 else { throw .unsupported("interlaced") }
        let channels: Int
        switch (colorType, depth) {
        case (0, 8): channels = 1
        case (2, 8): channels = 3
        case (3, 1), (3, 2), (3, 4), (3, 8): channels = 1
        case (4, 8): channels = 2
        case (6, 8): channels = 4
        default: throw .unsupported("colour type \(colorType) with \(depth) bits")
        }
        guard compressed.count > 6 else { throw .corrupt("no image data") }
        let raw: [UInt8]
        do {
            raw = try Deflate.inflate(Array(compressed[2...]))
        } catch {
            throw .corrupt("bad compressed data")
        }

        let bitsPerPixel = channels * depth
        let stride = (width * bitsPerPixel + 7) / 8
        let pixelBytes = max(1, bitsPerPixel / 8)
        guard raw.count >= (stride + 1) * height else { throw .corrupt("too little image data") }
        var previous = [UInt8](repeating: 0, count: stride)
        var rgb: [UInt8] = []
        rgb.reserveCapacity(width * height * 3)
        for y in 0..<height {
            let start = y * (stride + 1)
            var row = Array(raw[start + 1...start + stride])
            try unfilter(&row, previous: previous, filter: raw[start], pixelBytes: pixelBytes)
            for x in 0..<width {
                switch colorType {
                case 0, 4:
                    let grey = row[x * channels]
                    rgb += [grey, grey, grey]
                case 2, 6:
                    rgb += row[x * channels..<x * channels + 3]
                default:
                    let bit = x * depth
                    let index = Int(row[bit / 8] >> (8 - depth - bit % 8)) & ((1 << depth) - 1)
                    guard index * 3 + 2 < palette.count else { throw .corrupt("colour outside the palette") }
                    rgb += palette[index * 3..<index * 3 + 3]
                }
            }
            previous = row
        }
        return (width, height, rgb)
    }

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static func unfilter(
        _ row: inout [UInt8], previous: [UInt8], filter: UInt8, pixelBytes: Int
    ) throws(Error) {
        for index in row.indices {
            let left = index >= pixelBytes ? Int(row[index - pixelBytes]) : 0
            let up = Int(previous[index])
            let upLeft = index >= pixelBytes ? Int(previous[index - pixelBytes]) : 0
            let predictor: Int
            switch filter {
            case 0: predictor = 0
            case 1: predictor = left
            case 2: predictor = up
            case 3: predictor = (left + up) / 2
            case 4:
                let estimate = left + up - upLeft
                let (toLeft, toUp, toUpLeft) = (abs(estimate - left), abs(estimate - up), abs(estimate - upLeft))
                predictor = toLeft <= toUp && toLeft <= toUpLeft ? left : toUp <= toUpLeft ? up : upLeft
            default: throw .corrupt("bad filter \(filter)")
            }
            row[index] = UInt8(truncatingIfNeeded: Int(row[index]) + predictor)
        }
    }

    private static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typeAndBody = Array(type.utf8) + body
        return bigEndian(UInt32(body.count)) + typeAndBody + bigEndian(crc32(typeAndBody))
    }

    private static func zlib(_ bytes: [UInt8]) -> [UInt8] {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return [0x78, 0x01] + Deflate.deflate(bytes) + bigEndian(b << 16 | a)
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func readBigEndian(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }
}
