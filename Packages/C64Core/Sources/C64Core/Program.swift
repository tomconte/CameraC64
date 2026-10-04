extension C64Frame {
    /// Where exported programs put the VIC-II's 16 KB: the bank at $C000,
    /// where the VIC-II sees no character ROM, or for a frame that uses the
    /// ROM, the bank at $8000, where it sees the ROM at $9000–$9FFF. A program
    /// loaded at $0801 reaches neither.
    var exportBank: Int {
        seesCharacterROM ? 0x8000 : 0xC000
    }

    /// The frame as a program: a .prg file that loads at $0801, runs with
    /// RUN, shows the picture, and resets the C64 when a key is pressed.
    ///
    /// The program is the viewer in C64/viewer.s, followed by its parameters
    /// and the frame's data. The viewer copies each block of data into place,
    /// so the file holds only the memory the picture uses: for a PETSCII
    /// picture, which the C64 shows with its own character ROM, just the
    /// video matrix and the colours.
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
                let underIO = (0xD000..<0xE000).contains(exportBank + start)
                blocks.append(
                    Block(
                        destination: exportBank + start, bytes: Array(memory[start..<end]),
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
        // $DD00's bits 0-1 select the bank inverted: 0 for $C000, 1 for $8000.
        parameters.append(UInt8(3 - exportBank / 0x4000))
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
        // The viewer reads its data with BASIC's ROM in place, and must not
        // copy over data it has yet to copy.
        precondition(address <= min(0xA000, exportBank), "The picture's data must end below $A000 and the bank")
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
