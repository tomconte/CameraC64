/// Why a file could not be read as a C64 picture.
public enum PictureFileError: Error, Hashable {
    /// The file is shorter than its format needs.
    case tooShort(needed: Int, actual: Int)
}

extension C64Frame {
    /// The frame as a Koala Painter file (.kla or .koa), the usual format for
    /// multicolour bitmaps: load address $6000, the bitmap, the video matrix,
    /// the colour RAM and the background colour, 10,003 bytes in all.
    public func koala() -> [UInt8] {
        precondition(mode == .multicolorBitmap, "Koala files hold multicolour bitmaps")
        return [0x00, 0x60] + bitmap + screen + colorRAM + [backgroundColors[0].rawValue]
    }

    /// Reads a Koala Painter file. The border takes the background colour,
    /// as the file has none.
    public init(koala file: [UInt8]) throws(PictureFileError) {
        guard file.count >= 10_003 else { throw .tooShort(needed: 10_003, actual: file.count) }
        self.init(mode: .multicolorBitmap)
        bitmap = Array(file[2..<8002])
        screen = Array(file[8002..<9002])
        colorRAM = file[9002..<10_002].map { $0 & 0x0F }
        backgroundColors[0] = C64Color(rawValue: file[10_002] & 0x0F)!
        borderColor = backgroundColors[0]
    }

    /// The frame as an OCP Art Studio file (.art), the usual format for hires
    /// bitmaps: load address $2000, the bitmap, the video matrix and the
    /// border colour, padded to 9,009 bytes.
    public func artStudio() -> [UInt8] {
        precondition(mode == .hiresBitmap, "Art Studio files hold hires bitmaps")
        return [0x00, 0x20] + bitmap + screen + [borderColor.rawValue] + Array(repeating: 0, count: 6)
    }

    /// Reads an OCP Art Studio file.
    public init(artStudio file: [UInt8]) throws(PictureFileError) {
        guard file.count >= 9003 else { throw .tooShort(needed: 9003, actual: file.count) }
        self.init(mode: .hiresBitmap)
        bitmap = Array(file[2..<8002])
        screen = Array(file[8002..<9002])
        borderColor = C64Color(rawValue: file[9002] & 0x0F)!
    }

    /// The 8,000 bytes of a bitmap mode's bitmap.
    public var bitmap: [UInt8] {
        get {
            precondition(mode.isBitmap, "Only the bitmap modes have a bitmap")
            return Array(memory[graphicsAddress..<graphicsAddress + 8000])
        }
        set {
            precondition(mode.isBitmap, "Only the bitmap modes have a bitmap")
            precondition(newValue.count == 8000, "A bitmap has 8,000 bytes")
            memory.replaceSubrange(graphicsAddress..<graphicsAddress + 8000, with: newValue)
        }
    }

    /// The 1,000 bytes of the video matrix (screen memory).
    public var screen: [UInt8] {
        get { Array(memory[screenAddress..<screenAddress + Self.cellCount]) }
        set {
            precondition(newValue.count == Self.cellCount, "The video matrix has 1,000 bytes")
            memory.replaceSubrange(screenAddress..<screenAddress + Self.cellCount, with: newValue)
        }
    }
}
