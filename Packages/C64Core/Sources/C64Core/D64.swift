/// A 1541 floppy disk image (.d64) holding program files.
///
/// The layout follows the 1541's DOS: 35 tracks, the BAM and the directory
/// on track 18, and files spread from track 17 outwards with an interleave
/// of 10 sectors, as the DOS writes them.
public struct D64Image: Hashable, Sendable {
    /// A program file on the disk.
    public struct File: Hashable, Sendable {
        /// Up to 16 characters; see `PETSCII.encode`.
        public var name: String
        /// The .prg file's contents, load address included.
        public var contents: [UInt8]

        public init(name: String, contents: [UInt8]) {
            self.name = name
            self.contents = contents
        }
    }

    public enum Error: Swift.Error, Hashable {
        /// The files need more than the disk's 664 free blocks.
        case diskFull
        /// More than the directory's 144 entries.
        case directoryFull
    }

    public static let size = 174_848

    /// Up to 16 characters, shown at the top of the directory.
    public var name: String
    /// The disk ID: 2 characters.
    public var id: String
    public var files: [File]

    public init(name: String, id: String = "64", files: [File]) {
        self.name = name
        self.id = id
        self.files = files
    }

    /// The image file's bytes.
    public func bytes() throws(Error) -> [UInt8] {
        var disk = Disk()
        let directoryTrack = 18
        disk.use(track: directoryTrack, sector: 0)

        var entries: [[UInt8]] = []
        for file in files {
            let (track, sector, blocks) = try disk.write(file.contents)
            var entry = [UInt8](repeating: 0, count: 32)
            entry[2] = 0x82  // a closed program file
            entry[3] = UInt8(track)
            entry[4] = UInt8(sector)
            entry.replaceSubrange(5..<21, with: PETSCII.padded(file.name, to: 16))
            entry[30] = UInt8(blocks & 0xFF)
            entry[31] = UInt8(blocks >> 8)
            entries.append(entry)
        }

        // The directory: 8 entries per sector, from sector 1 with an
        // interleave of 3, and at least one sector even when empty.
        let directorySectors = [1, 4, 7, 10, 13, 16, 2, 5, 8, 11, 14, 17, 3, 6, 9, 12, 15, 18]
        let sectorCount = max(1, (entries.count + 7) / 8)
        guard sectorCount <= directorySectors.count else { throw .directoryFull }
        for index in 0..<sectorCount {
            let sector = directorySectors[index]
            disk.use(track: directoryTrack, sector: sector)
            let start = Disk.offset(track: directoryTrack, sector: sector)
            let isLast = index == sectorCount - 1
            for (slot, entry) in entries.dropFirst(index * 8).prefix(8).enumerated() {
                disk.bytes.replaceSubrange(start + slot * 32..<start + slot * 32 + 32, with: entry)
            }
            disk.bytes[start] = isLast ? 0 : UInt8(directoryTrack)
            disk.bytes[start + 1] = isLast ? 0xFF : UInt8(directorySectors[index + 1])
        }

        // The BAM: which sectors are free, and the disk's name and ID.
        let bam = Disk.offset(track: directoryTrack, sector: 0)
        disk.bytes[bam] = UInt8(directoryTrack)
        disk.bytes[bam + 1] = 1
        disk.bytes[bam + 2] = 0x41  // DOS version "A"
        for track in 1...Disk.trackCount {
            let free = disk.free[track - 1]
            var bits = 0
            for (sector, isFree) in free.enumerated() where isFree {
                bits |= 1 << sector
            }
            let entry = bam + 4 * track
            disk.bytes[entry] = UInt8(free.filter { $0 }.count)
            disk.bytes[entry + 1] = UInt8(bits & 0xFF)
            disk.bytes[entry + 2] = UInt8((bits >> 8) & 0xFF)
            disk.bytes[entry + 3] = UInt8(bits >> 16)
        }
        // Name, padding, ID, padding, DOS type "2A", padding.
        let header = PETSCII.padded(name, to: 16) + [0xA0, 0xA0] + PETSCII.padded(id, to: 2) + [0xA0, 0x32, 0x41]
        disk.bytes.replaceSubrange(bam + 0x90..<bam + 0xA7, with: header)
        disk.bytes.replaceSubrange(bam + 0xA7..<bam + 0xAB, with: [0xA0, 0xA0, 0xA0, 0xA0])
        return disk.bytes
    }
}

/// The sectors of a disk being written.
private struct Disk {
    static let trackCount = 35
    static let interleave = 10

    static func sectorsPerTrack(_ track: Int) -> Int {
        switch track {
        case 1...17: 21
        case 18...24: 19
        case 25...30: 18
        default: 17
        }
    }

    static func offset(track: Int, sector: Int) -> Int {
        (1..<track).reduce(0) { $0 + sectorsPerTrack($1) } * 256 + sector * 256
    }

    /// The order files fill the tracks in: outwards from the directory, first
    /// below it, then above.
    static let fileTracks = Array((1...17).reversed()) + Array(19...trackCount)

    var bytes = [UInt8](repeating: 0, count: D64Image.size)
    var free = (1...trackCount).map { Array(repeating: true, count: sectorsPerTrack($0)) }

    mutating func use(track: Int, sector: Int) {
        free[track - 1][sector] = false
    }

    /// Writes a file's contents to free sectors, 254 bytes each, and returns
    /// its first track and sector and how many blocks it takes.
    mutating func write(_ contents: [UInt8]) throws(D64Image.Error) -> (track: Int, sector: Int, blocks: Int) {
        let chunks = stride(from: 0, to: max(contents.count, 1), by: 254).map {
            Array(contents[$0..<min($0 + 254, contents.count)])
        }
        var sectors: [(track: Int, sector: Int)] = []
        var previous: (track: Int, sector: Int)?
        for _ in chunks {
            guard let next = nextFree(after: previous) else { throw .diskFull }
            use(track: next.track, sector: next.sector)
            sectors.append(next)
            previous = next
        }
        for (index, chunk) in chunks.enumerated() {
            let start = Self.offset(track: sectors[index].track, sector: sectors[index].sector)
            if index + 1 < sectors.count {
                bytes[start] = UInt8(sectors[index + 1].track)
                bytes[start + 1] = UInt8(sectors[index + 1].sector)
            } else {
                // The last sector: no next track, and the position of its
                // last byte.
                bytes[start] = 0
                bytes[start + 1] = UInt8(chunk.count + 1)
            }
            bytes.replaceSubrange(start + 2..<start + 2 + chunk.count, with: chunk)
        }
        return (sectors[0].track, sectors[0].sector, sectors.count)
    }

    /// The next free sector: on the same track, `interleave` sectors on if
    /// possible, else on the next track that has room.
    private func nextFree(after previous: (track: Int, sector: Int)?) -> (track: Int, sector: Int)? {
        let startTrack = previous.map { Self.fileTracks.firstIndex(of: $0.track)! } ?? 0
        for trackIndex in startTrack..<Self.fileTracks.count {
            let track = Self.fileTracks[trackIndex]
            let count = Self.sectorsPerTrack(track)
            let first = previous.map { $0.track == track ? ($0.sector + Self.interleave) % count : 0 } ?? 0
            for step in 0..<count {
                let sector = (first + step) % count
                if free[track - 1][sector] {
                    return (track, sector)
                }
            }
        }
        return nil
    }
}

/// PETSCII, the C64's character encoding, as far as file and disk names go.
public enum PETSCII {
    /// Letters become the uppercase letters of the C64's default character
    /// set, and digits, spaces and punctuation stay; anything else becomes
    /// "?".
    public static func encode(_ text: String) -> [UInt8] {
        text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x61...0x7A: UInt8(scalar.value - 0x20)
            case 0x20...0x5A: UInt8(scalar.value)
            default: 0x3F
            }
        }
    }

    /// A name cut or padded to a fixed length, padded with $A0 as the DOS
    /// does.
    static func padded(_ text: String, to length: Int) -> [UInt8] {
        let bytes = encode(text).prefix(length)
        return bytes + Array(repeating: 0xA0, count: length - bytes.count)
    }
}
