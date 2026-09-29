import C64Core
import C64Tools
import Foundation
import Testing

private let vice = VICE.find()

/// The standard modes, as in the plan's section 4.
private let standardModes: [(name: String, spec: ModeSpec)] = [
    ("hires", .hires),
    ("multicolour", .multicolor),
    ("character set", .characterSet),
    ("multicolour character set", .multicolorCharacterSet),
    ("extended colour character set", .extendedColorCharacterSet),
]

/// Writes a file into a new temporary directory.
func temporaryFile(named name: String, contents: [UInt8]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("c64-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(name)
    try Data(contents).write(to: file)
    return file
}

/// Runs a file in VICE and requires its screen to match the renderer's
/// picture of the frame, pixel for pixel, border included. With
/// $VICE_TEST_OUTPUT set, a mismatch leaves both pictures there as PNGs.
private func expectVICEShows(
    _ frame: C64Frame, running file: URL? = nil, cycles: Int = 4_000_000, _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let program = try file ?? temporaryFile(named: "picture.prg", contents: frame.prg())
    let actual = try #require(vice).screen(running: program, cycles: cycles)
    let expected = VICII.render(frame)
    #expect(actual.width == expected.width && actual.height == expected.height, sourceLocation: sourceLocation)
    let differences = zip(actual.pixels, expected.pixels).enumerated().filter { $0.element.0 != $0.element.1 }
    if let first = differences.first {
        let (x, y) = (first.offset % expected.width, first.offset / expected.width)
        let message: String =
            "\(label): \(differences.count) pixels differ from VICE's, the first at (\(x), \(y)): VICE shows "
            + "\(actual[x, y]), the renderer \(expected[x, y])"
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        if let output = ProcessInfo.processInfo.environment["VICE_TEST_OUTPUT"] {
            let name = label.replacingOccurrences(of: " ", with: "-")
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(PNG.encode(actual, palette: .pepto2001, scale: 2)).write(
                to: directory.appendingPathComponent("\(name)-vice.png"))
            try Data(PNG.encode(expected, palette: .pepto2001, scale: 2)).write(
                to: directory.appendingPathComponent("\(name)-renderer.png"))
        }
    }
}

/// Moves a frame's screen and graphics to other addresses; the picture stays
/// the same.
private func relocated(_ frame: C64Frame, screen: Int, graphics: Int) -> C64Frame {
    var moved = frame
    moved.memory = [UInt8](repeating: 0, count: C64Frame.memorySize)
    let (oldScreen, oldGraphics) = (frame.usedMemory[0], frame.usedMemory[1])
    moved.screenAddress = screen
    moved.graphicsAddress = graphics
    moved.memory.replaceSubrange(graphics..<graphics + oldGraphics.count, with: frame.memory[oldGraphics])
    moved.memory.replaceSubrange(screen..<screen + oldScreen.count, with: frame.memory[oldScreen])
    return moved
}

/// CI's VICE job sets $VICE_REQUIRED, so there a missing VICE fails rather
/// than skipping every comparison.
@Test func viceIsFoundWhereRequired() {
    if ProcessInfo.processInfo.environment["VICE_REQUIRED"] != nil {
        #expect(vice != nil, "VICE's x64sc was not found")
    }
}

@Suite(.enabled(if: vice != nil, "needs VICE's x64sc"))
struct VICETests {
    @Test(arguments: standardModes.indices)
    func standardModesLookTheSameInVICE(mode: Int) throws {
        for seed: UInt64 in 1...2 {
            let frame = try C64Frame(TestPictures.random(standardModes[mode].spec, seed: seed))
            try expectVICEShows(frame, "\(standardModes[mode].name) \(seed)")
        }
    }

    /// PETSCII: text with the C64's own character set, read from VICE's ROM
    /// at test time and copied into RAM.
    @Test func petsciiLooksTheSameInVICE() throws {
        let rom = try #require(vice?.characterROM(), "VICE's character ROM")
        for (name, characters) in [("upper case", rom[0..<2048]), ("lower case", rom[2048..<4096])] {
            let frame = try C64Frame(TestPictures.random(.text(characters: Array(characters)), seed: 7))
            try expectVICEShows(frame, "PETSCII \(name)")
        }
    }

    /// Layouts that put data under the I/O area and the KERNAL ROM once
    /// exported to $C000.
    @Test func otherLayoutsLookTheSameInVICE() throws {
        let hires = try C64Frame(TestPictures.random(.hires, seed: 11))
        try expectVICEShows(relocated(hires, screen: 0x2000, graphics: 0x0000), "hires bitmap at D000")
        let multicolor = try C64Frame(TestPictures.random(.multicolor, seed: 12))
        try expectVICEShows(relocated(multicolor, screen: 0x1C00, graphics: 0x2000), "multicolour screen at DC00")
        let text = try C64Frame(TestPictures.random(.characterSet, seed: 13))
        try expectVICEShows(relocated(text, screen: 0x3C00, graphics: 0x1000), "characters at D000")
        let extended = try C64Frame(TestPictures.random(.extendedColorCharacterSet, seed: 14))
        try expectVICEShows(relocated(extended, screen: 0x0400, graphics: 0x3800), "characters at F800")
    }

    @Test func diskImagesStartTheProgram() throws {
        let frame = try C64Frame(TestPictures.random(.multicolor, seed: 21))
        let disk = try D64Image(name: "CAMERA C64", files: [.init(name: "PICTURE", contents: frame.prg())]).bytes()
        let file = try temporaryFile(named: "picture.d64", contents: disk)
        try expectVICEShows(frame, running: file, cycles: 40_000_000, "disk image")
    }
}
