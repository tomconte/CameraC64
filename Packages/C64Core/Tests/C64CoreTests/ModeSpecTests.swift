import C64Core
import Testing

/// Every standard mode, as the converter will see them.
let standardModes: [(name: String, spec: ModeSpec)] = [
    ("hires", .hires),
    ("multicolour", .multicolor),
    ("text", .text(characters: randomCharacterSet(seed: 64))),
    ("PETSCII", .petscii),
    ("character set", .characterSet),
    ("multicolour character set", .multicolorCharacterSet),
    ("extended colour character set", .extendedColorCharacterSet),
]

/// The core rule's guarantee: a picture encoded into C64 memory looks, on the
/// VIC-II, exactly as its mode says it should.
@Test(arguments: standardModes.indices)
func encodedPicturesRenderAsDescribed(mode: Int) throws {
    for seed in 1...3 {
        let picture = ModePicture.random(standardModes[mode].spec, seed: UInt64(seed))
        let frame = try C64Frame(picture)
        let screen = VICII.render(frame)
        #expect(screen.window == picture.image(), "\(standardModes[mode].name), seed \(seed)")
        #expect(screen[0, 0] == picture.borderColor)
    }
}

@Test func multicolourCellsMatchTheirMaps() {
    let spec = ModeSpec.multicolor
    #expect(spec.bitsPerPixel == 2)
    #expect(spec.maps.map(spec.valueCount) == [1, 1000, 1000, 1000])
    #expect(ModeSpec.hires.bitsPerPixel == 1)
}

@Test func ownCharactersHaveALimit() throws {
    var picture = ModePicture(spec: .extendedColorCharacterSet)
    // 65 different characters: cell n has its first n pixels set.
    for cell in 0...64 {
        for pixel in 0..<cell {
            picture.pixels[cell / 40 * 8 * 320 + cell % 40 * 8 + pixel / 8 * 320 + pixel % 8] = 1
        }
    }
    #expect(throws: ModeEncodingError.tooManyCharacters(count: 65, limit: 64)) {
        try C64Frame(picture)
    }
}

@Test func fixedCharactersMustMatchACell() {
    let blank = [UInt8](repeating: 0, count: 2048)
    var picture = ModePicture(spec: .text(characters: blank))
    picture.pixels[320 * 8 + 3] = 1  // cell 40 is not blank
    #expect(throws: ModeEncodingError.noSuchCharacter(cell: 40)) {
        try C64Frame(picture)
    }
}

/// PETSCII pictures leave their characters in the ROM: the frame sees it,
/// and its memory holds only the video matrix.
@Test(arguments: CharacterROM.Set.allCases)
func petsciiCharactersStayInTheROM(set: CharacterROM.Set) throws {
    let picture = ModePicture.random(.petscii, seed: 4, characterSet: set)
    let frame = try C64Frame(picture)
    #expect(frame.mode == .standardText && frame.seesCharacterROM)
    #expect(frame.screenAddress == 0x0400 && frame.graphicsAddress == set.address)
    #expect(frame.usedMemory == [0x0400..<0x07E8])
    #expect(frame.memory[C64Frame.characterROMArea].allSatisfy { $0 == 0 })
    #expect(VICII.render(frame).window == picture.image())
}

/// A picture takes all its characters from one set: the upper case one if it
/// can.
@Test func petsciiPicturesUseOneSet() throws {
    /// Draws a character of a set into a cell.
    func draw(_ code: Int, of set: CharacterROM.Set, at cell: Int, in picture: inout ModePicture) {
        for line in 0..<8 {
            let byte = set.characters[code * 8 + line]
            for x in 0..<8 {
                picture.pixels[(cell / 40 * 8 + line) * 320 + cell % 40 * 8 + x] = (byte >> (7 - x)) & 1
            }
        }
    }
    var picture = ModePicture(spec: .petscii)
    draw(0, of: .upperCase, at: 3, in: &picture)  // @, in both sets
    #expect(try C64Frame(picture).graphicsAddress == 0x1000)
    draw(1, of: .lowerCase, at: 5, in: &picture)  // a, only in the lower case set
    let lower = try C64Frame(picture)
    #expect(lower.graphicsAddress == 0x1800)
    #expect(lower.screen[3] == 0 && lower.screen[5] == 1)
    draw(65, of: .upperCase, at: 7, in: &picture)  // a spade, only in the upper case set
    #expect(throws: ModeEncodingError.noSuchCharacter(cell: 5)) {
        try C64Frame(picture)
    }
    picture.pixels[320 * 8 * 2 + 4] = 1  // a dot, in neither set
    #expect(throws: ModeEncodingError.noSuchCharacter(cell: 80)) {
        try C64Frame(picture)
    }
}

@Test func multicolourCharactersUseTheFirstEightColours() {
    var picture = ModePicture(spec: .multicolorCharacterSet)
    picture.colors[3][7] = .orange
    #expect(throws: ModeEncodingError.colorNotAllowed(map: 3, index: 7)) {
        try C64Frame(picture)
    }
}

@Test func extendedColourSharesFourBackgrounds() {
    var picture = ModePicture(spec: .extendedColorCharacterSet)
    for cell in 0..<5 {
        picture.colors[0][cell] = C64Color(rawValue: UInt8(cell + 1))!
    }
    #expect(throws: ModeEncodingError.tooManySharedColors(map: 0, count: 6)) {
        try C64Frame(picture)
    }
}

@Test func encodingUsesTheUsualLayout() throws {
    let picture = ModePicture.random(.multicolorCharacterSet, seed: 9)
    let frame = try C64Frame(picture)
    #expect(frame.mode == .multicolorText)
    #expect(frame.screenAddress == 0x0000 && frame.graphicsAddress == 0x0800)
    #expect(frame.colorRAM.allSatisfy { $0 & 0x08 != 0 })
    #expect(Array(frame.backgroundColors[0...2]) == [picture.colors[0][0], picture.colors[1][0], picture.colors[2][0]])
}
