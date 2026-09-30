extension C64Frame {
    /// Where exported programs put the VIC-II's 16 KB: the bank at $C000,
    /// where the VIC-II sees no character ROM and which a program loaded at
    /// $0801 never reaches.
    static let exportBank = 0xC000

    /// The frame as a program: a .prg file that loads at $0801, runs with
    /// RUN, shows the picture, and resets the C64 when a key is pressed.
    ///
    /// The program is the viewer in C64/viewer.s, followed by its parameters
    /// and the frame's data. The viewer copies each block of data into place,
    /// so the file holds only the memory the picture uses.
    public func prg() -> [UInt8] {
        struct Block {
            var destination: Int
            var bytes: [UInt8]
            /// The value for $01 during the copy: RAM under the I/O area is
            /// only writable with the I/O area switched out.
            var memoryConfiguration: UInt8
        }

        var blocks: [Block] = []
        for range in Self.merged(usedMemory) {
            // Split where the I/O area begins and ends, at $D000 and $E000.
            var start = range.lowerBound
            while start < range.upperBound {
                let end = [0x1000, 0x2000, range.upperBound].filter { $0 > start }.min()!
                let underIO = (0x1000..<0x2000).contains(start)
                blocks.append(
                    Block(
                        destination: Self.exportBank + start, bytes: Array(memory[start..<end]),
                        memoryConfiguration: underIO ? 0x34 : 0x37))
                start = end
            }
        }
        // Hires bitmaps take both colours from the video matrix.
        if mode != .hiresBitmap {
            blocks.append(Block(destination: 0xD800, bytes: colorRAM, memoryConfiguration: 0x37))
        }

        let viewer = DisplayPrograms.viewer
        var parameters: [UInt8] = [
            mode.controlRegister1, mode.controlRegister2, memoryPointers, borderColor.rawValue,
        ]
        parameters += backgroundColors.map(\.rawValue)
        parameters.append(0)  // $dd00 bits for the bank at $C000
        parameters.append(UInt8(blocks.count))

        var address = 0x0801 + viewer.count + parameters.count + 7 * blocks.count
        var data: [UInt8] = []
        for block in blocks {
            for value in [address, block.destination, block.bytes.count] {
                parameters += [UInt8(value & 0xFF), UInt8(value >> 8)]
            }
            parameters.append(block.memoryConfiguration)
            data += block.bytes
            address += block.bytes.count
        }
        // The viewer reads its data with BASIC's ROM in place.
        precondition(address <= 0xA000, "The picture's data must end below $A000")
        return [0x01, 0x08] + viewer + parameters + data
    }

    /// Ranges sorted and joined where they overlap or touch.
    private static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
