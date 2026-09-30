import C64Core
import Testing

/// Reads a .d64 back the way the 1541's DOS does.
private struct DiskReader {
    let image: [UInt8]

    func sector(_ track: Int, _ sector: Int) -> ArraySlice<UInt8> {
        let before = (1..<track).reduce(0) { $0 + ($1 <= 17 ? 21 : $1 <= 24 ? 19 : $1 <= 30 ? 18 : 17) }
        let start = (before + sector) * 256
        return image[start..<start + 256]
    }

    /// Follows a chain of sectors, returning each one's track and sector and
    /// the bytes of the whole chain.
    func chain(from track: Int, _ sector: Int) -> (sectors: [(Int, Int)], bytes: [UInt8]) {
        var sectors: [(Int, Int)] = []
        var bytes: [UInt8] = []
        var next = (track, sector)
        while true {
            sectors.append(next)
            let data = self.sector(next.0, next.1)
            let start = data.startIndex
            if data[start] == 0 {
                bytes += data[start + 2...start + Int(data[start + 1])]
                return (sectors, bytes)
            }
            bytes += data[start + 2..<start + 256]
            next = (Int(data[start]), Int(data[start + 1]))
        }
    }

    struct Entry {
        var name: [UInt8]
        var type: UInt8
        var first: (Int, Int)
        var blocks: Int
    }

    var directory: [Entry] {
        var entries: [Entry] = []
        var next = (18, 1)
        while next.0 != 0 {
            let data = sector(next.0, next.1)
            for slot in 0..<8 {
                let entry = data.startIndex + slot * 32
                guard data[entry + 2] != 0 else { continue }
                entries.append(
                    Entry(
                        name: Array(data[entry + 5..<entry + 21]), type: data[entry + 2],
                        first: (Int(data[entry + 3]), Int(data[entry + 4])),
                        blocks: Int(data[entry + 30]) | Int(data[entry + 31]) << 8))
            }
            next = (Int(data[data.startIndex]), Int(data[data.startIndex + 1]))
        }
        return entries
    }

    /// The blocks free on every track but the directory's, as DOS reports.
    var blocksFree: Int {
        let bam = sector(18, 0)
        return (1...35).filter { $0 != 18 }.reduce(0) { $0 + Int(bam[bam.startIndex + 4 * $1]) }
    }

    func isFree(_ track: Int, _ sector: Int) -> Bool {
        let bam = self.sector(18, 0)
        return bam[bam.startIndex + 4 * track + 1 + sector / 8] & (1 << (sector % 8)) != 0
    }
}

@Test func diskHoldsItsFiles() throws {
    let picture = try C64Frame(ModePicture.random(.multicolor, seed: 3)).prg()
    let small: [UInt8] = [0x01, 0x08, 0x60]
    let image = try D64Image(
        name: "Camera c64", id: "64",
        files: [.init(name: "picture", contents: picture), .init(name: "tiny", contents: small)]
    ).bytes()
    #expect(image.count == 174_848)

    let disk = DiskReader(image: image)
    let bam = disk.sector(18, 0)
    #expect(Array(bam[bam.startIndex..<bam.startIndex + 3]) == [18, 1, 0x41])
    #expect(
        Array(bam[bam.startIndex + 0x90..<bam.startIndex + 0xAB]) == PETSCII.encode("CAMERA C64") + [
            0xA0, 0xA0, 0xA0, 0xA0, 0xA0, 0xA0, 0xA0, 0xA0, 0x36, 0x34, 0xA0, 0x32, 0x41, 0xA0, 0xA0, 0xA0, 0xA0,
        ])

    let entries = disk.directory
    #expect(entries.count == 2)
    var used = 0
    for (entry, contents) in zip(entries, [picture, small]) {
        #expect(entry.type == 0x82)
        let chain = disk.chain(from: entry.first.0, entry.first.1)
        #expect(chain.bytes == contents)
        #expect(chain.sectors.count == entry.blocks)
        #expect(entry.blocks == (contents.count + 253) / 254)
        #expect(chain.sectors.allSatisfy { !disk.isFree($0.0, $0.1) })
        used += entry.blocks
    }
    #expect(entries[0].name == PETSCII.encode("PICTURE") + Array(repeating: 0xA0, count: 9))
    // Files start next to the directory and skip 10 sectors at a time.
    let first = disk.chain(from: entries[0].first.0, entries[0].first.1).sectors
    #expect(first[0] == (17, 0) && first[1] == (17, 10) && first[2] == (17, 20))
    #expect(disk.blocksFree == 664 - used)
    #expect(!disk.isFree(18, 0) && !disk.isFree(18, 1) && disk.isFree(18, 2))
}

@Test func emptyDiskHasADirectory() throws {
    let disk = DiskReader(image: try D64Image(name: "EMPTY", files: []).bytes())
    #expect(disk.directory.isEmpty)
    #expect(disk.blocksFree == 664)
}

@Test func diskRefusesWhatDoesNotFit() {
    #expect(throws: D64Image.Error.diskFull) {
        try D64Image(name: "FULL", files: [.init(name: "BIG", contents: Array(repeating: 1, count: 170_000))]).bytes()
    }
    let files = (0..<145).map { D64Image.File(name: "F\($0)", contents: [0x01, 0x08]) }
    #expect(throws: D64Image.Error.directoryFull) {
        try D64Image(name: "MANY", files: files).bytes()
    }
}

@Test func namesBecomePETSCII() {
    #expect(PETSCII.encode("Hello, C64!") == [0x48, 0x45, 0x4C, 0x4C, 0x4F, 0x2C, 0x20, 0x43, 0x36, 0x34, 0x21])
    #expect(PETSCII.encode("é_") == [0x3F, 0x3F])
}
