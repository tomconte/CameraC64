/// DEFLATE (RFC 1951), as PNG uses it: a full decompressor, and a compressor
/// that only encodes runs of repeated bytes, which suits C64 pictures well.
enum Deflate {
    enum Error: Swift.Error {
        case truncated
        case invalid(String)
    }

    // MARK: Decompression

    /// Reads bits, least significant first.
    private struct BitReader {
        let bytes: [UInt8]
        var position = 0

        mutating func bit() throws(Error) -> Int {
            guard position >> 3 < bytes.count else { throw .truncated }
            let value = Int(bytes[position >> 3] >> (position & 7)) & 1
            position += 1
            return value
        }

        mutating func bits(_ count: Int) throws(Error) -> Int {
            var value = 0
            for index in 0..<count {
                value |= try bit() << index
            }
            return value
        }

        mutating func alignToByte() {
            position = (position + 7) & ~7
        }
    }

    /// A canonical Huffman code: how many codes each length has, and the
    /// symbols in code order.
    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []

        init(lengths: [Int]) {
            for length in lengths {
                counts[length] += 1
            }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<16 {
                offsets[length] = offsets[length - 1] + counts[length - 1]
            }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }

        func decode(_ reader: inout BitReader) throws(Error) -> Int {
            var code = 0
            var first = 0
            var index = 0
            for length in 1..<16 {
                code |= try reader.bit()
                let count = counts[length]
                if code - count < first {
                    return symbols[index + code - first]
                }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            throw .invalid("bad Huffman code")
        }
    }

    private static let lengthBase = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227,
        258,
    ]
    private static let lengthExtra = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ]
    private static let distanceBase = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097,
        6145, 8193, 12289, 16385, 24577,
    ]
    private static let distanceExtra = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
    ]

    private static let fixedLiterals = Huffman(
        lengths: Array(repeating: 8, count: 144) + Array(repeating: 9, count: 112) + Array(repeating: 7, count: 24)
            + Array(repeating: 8, count: 8))
    private static let fixedDistances = Huffman(lengths: Array(repeating: 5, count: 30))

    static func inflate(_ bytes: [UInt8]) throws(Error) -> [UInt8] {
        var reader = BitReader(bytes: bytes)
        var output: [UInt8] = []
        var isLast = false
        while !isLast {
            isLast = try reader.bit() == 1
            switch try reader.bits(2) {
            case 0:
                reader.alignToByte()
                let start = reader.position >> 3
                guard start + 4 <= bytes.count else { throw .truncated }
                let length = Int(bytes[start]) | Int(bytes[start + 1]) << 8
                guard start + 4 + length <= bytes.count else { throw .truncated }
                output += bytes[start + 4..<start + 4 + length]
                reader.position = (start + 4 + length) << 3
            case 1:
                try inflateBlock(&reader, literals: fixedLiterals, distances: fixedDistances, into: &output)
            case 2:
                let (literals, distances) = try readDynamicCodes(&reader)
                try inflateBlock(&reader, literals: literals, distances: distances, into: &output)
            default:
                throw .invalid("bad block type")
            }
        }
        return output
    }

    private static func readDynamicCodes(_ reader: inout BitReader) throws(Error) -> (Huffman, Huffman) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeLengthCount = try reader.bits(4) + 4
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengths[order[index]] = try reader.bits(3)
        }
        let lengthCode = Huffman(lengths: codeLengths)
        var lengths: [Int] = []
        while lengths.count < literalCount + distanceCount {
            let symbol = try lengthCode.decode(&reader)
            switch symbol {
            case 0...15:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last else { throw .invalid("repeat with no length") }
                lengths += Array(repeating: previous, count: try reader.bits(2) + 3)
            case 17:
                lengths += Array(repeating: 0, count: try reader.bits(3) + 3)
            default:
                lengths += Array(repeating: 0, count: try reader.bits(7) + 11)
            }
        }
        guard lengths.count == literalCount + distanceCount else { throw .invalid("too many code lengths") }
        return (
            Huffman(lengths: Array(lengths[..<literalCount])), Huffman(lengths: Array(lengths[literalCount...]))
        )
    }

    private static func inflateBlock(
        _ reader: inout BitReader, literals: Huffman, distances: Huffman, into output: inout [UInt8]
    ) throws(Error) {
        while true {
            let symbol = try literals.decode(&reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let lengthIndex = symbol - 257
                guard lengthIndex < lengthBase.count else { throw .invalid("bad length") }
                let length = lengthBase[lengthIndex] + (try reader.bits(lengthExtra[lengthIndex]))
                let distanceIndex = try distances.decode(&reader)
                guard distanceIndex < distanceBase.count else { throw .invalid("bad distance") }
                let distance = distanceBase[distanceIndex] + (try reader.bits(distanceExtra[distanceIndex]))
                guard distance <= output.count else { throw .invalid("distance too far back") }
                let start = output.count - distance
                for offset in 0..<length {
                    output.append(output[start + offset])
                }
            }
        }
    }

    // MARK: Compression

    /// Writes bits, least significant first.
    private struct BitWriter {
        var bytes: [UInt8] = []
        var buffer = 0
        var count = 0

        mutating func write(_ value: Int, _ bits: Int) {
            buffer |= value << count
            count += bits
            while count >= 8 {
                bytes.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                count -= 8
            }
        }

        /// Huffman codes go most significant bit first.
        mutating func writeCode(_ code: Int, _ bits: Int) {
            var reversed = 0
            for index in 0..<bits {
                reversed |= ((code >> index) & 1) << (bits - 1 - index)
            }
            write(reversed, bits)
        }

        mutating func finish() -> [UInt8] {
            if count > 0 {
                bytes.append(UInt8(buffer & 0xFF))
            }
            return bytes
        }
    }

    /// Compresses with the fixed Huffman codes, encoding each run of 3 or
    /// more repeated bytes as a copy of the byte before it.
    static func deflate(_ bytes: [UInt8]) -> [UInt8] {
        var writer = BitWriter()
        writer.write(1, 1)  // the last block
        writer.write(1, 2)  // fixed codes
        var position = 0
        while position < bytes.count {
            var run = 0
            if position > 0 {
                while run < 258 && position + run < bytes.count && bytes[position + run] == bytes[position - 1] {
                    run += 1
                }
            }
            if run >= 3 {
                let index = lengthBase.lastIndex { $0 <= run }!
                writeLiteral(257 + index, &writer)
                writer.write(run - lengthBase[index], lengthExtra[index])
                writer.writeCode(0, 5)  // distance 1
                position += run
            } else {
                writeLiteral(Int(bytes[position]), &writer)
                position += 1
            }
        }
        writeLiteral(256, &writer)
        return writer.finish()
    }

    private static func writeLiteral(_ symbol: Int, _ writer: inout BitWriter) {
        switch symbol {
        case 0...143: writer.writeCode(0x30 + symbol, 8)
        case 144...255: writer.writeCode(0x190 + symbol - 144, 9)
        case 256...279: writer.writeCode(symbol - 256, 7)
        default: writer.writeCode(0xC0 + symbol - 280, 8)
        }
    }
}
