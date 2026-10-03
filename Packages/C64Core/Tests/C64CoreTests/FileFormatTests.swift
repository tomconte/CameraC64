import Testing

@testable import C64Core

@Test func koalaFilesRoundTrip() throws {
    let frame = try C64Frame(ModePicture.random(.multicolor, seed: 1))
    let file = frame.koala()
    #expect(file.count == 10_003)
    #expect(file[0] == 0x00 && file[1] == 0x60)
    #expect(file[10_002] == frame.backgroundColors[0].rawValue)
    let read = try C64Frame(koala: file)
    #expect(read.koala() == file)
    #expect(VICII.render(read).window == VICII.render(frame).window)
}

@Test func artStudioFilesRoundTrip() throws {
    var frame = try C64Frame(ModePicture.random(.hires, seed: 2))
    frame.borderColor = .brown
    let file = frame.artStudio()
    #expect(file.count == 9009)
    #expect(file[0] == 0x00 && file[1] == 0x20)
    let read = try C64Frame(artStudio: file)
    #expect(read.artStudio() == file)
    #expect(VICII.render(read) == VICII.render(frame))
}

@Test func shortFilesAreRejected() {
    #expect(throws: PictureFileError.tooShort(needed: 10_003, actual: 9009)) {
        try C64Frame(koala: [UInt8](repeating: 0, count: 9009))
    }
}

/// Runs what the viewer does before it shows the picture: copies each block
/// of the .prg's table into a 64 KB memory, with $D800 standing for the
/// colour RAM.
private func load(_ prg: [UInt8]) -> (memory: [UInt8], registers: [UInt8]) {
    var memory = [UInt8](repeating: 0, count: 0x10000)
    let loadAddress = Int(prg[0]) | Int(prg[1]) << 8
    memory.replaceSubrange(loadAddress..<loadAddress + prg.count - 2, with: prg[2...])
    let parameters = loadAddress + DisplayPrograms.viewer.count
    let blockCount = Int(memory[parameters + 9])
    for block in 0..<blockCount {
        let entry = parameters + 10 + 7 * block
        func word(_ offset: Int) -> Int { Int(memory[entry + offset]) | Int(memory[entry + offset + 1]) << 8 }
        let (source, target, length) = (word(0), word(2), word(4))
        memory.replaceSubrange(target..<target + length, with: memory[source..<source + length])
    }
    return (memory, Array(memory[parameters..<parameters + 9]))
}

@Test(arguments: standardModes.indices)
func programsPutTheFrameInPlace(mode: Int) throws {
    let frame = try C64Frame(ModePicture.random(standardModes[mode].spec, seed: 5))
    let prg = frame.prg()
    #expect(prg[0...1] == [0x01, 0x08])
    // 10 SYS 2061
    #expect(prg[2...13] == [0x0B, 0x08, 0x0A, 0x00, 0x9E, 0x32, 0x30, 0x36, 0x31, 0x00, 0x00, 0x00])

    let (memory, registers) = load(prg)
    // The bank at $8000 if the frame uses the character ROM, else $C000.
    let bank = frame.seesCharacterROM ? 0x8000 : 0xC000
    #expect(frame.exportBank == bank)
    for range in frame.usedMemory {
        #expect(memory[bank + range.lowerBound..<bank + range.upperBound] == frame.memory[range])
    }
    if frame.mode != .hiresBitmap {
        #expect(Array(memory[0xD800..<0xD800 + 1000]) == frame.colorRAM)
    }
    let colors = [frame.borderColor] + frame.backgroundColors
    let pointers = [frame.mode.controlRegister1, frame.mode.controlRegister2, frame.memoryPointers]
    // $DD00's bank bits: 0 for $C000, 1 for $8000.
    #expect(registers == pointers + colors.map(\.rawValue) + [frame.seesCharacterROM ? 1 : 0])
    #expect(prg.count < 13_000)
}

/// A PETSCII program holds the viewer, the video matrix and the colours, and
/// none of the ROM's characters.
@Test func petsciiProgramsHoldOnlyCodesAndColours() throws {
    let frame = try C64Frame(ModePicture.random(.petscii, seed: 7, characterSet: .lowerCase))
    let prg = frame.prg()
    #expect(prg.count == 2 + DisplayPrograms.viewer.count + 10 + 2 * 7 + 1000 + 1000)
    let (memory, _) = load(prg)
    #expect(Array(memory[0x8400..<0x87E8]) == frame.screen)
}

@Test func programsSwitchOutTheIOAreaUnderIt() throws {
    var frame = try C64Frame(ModePicture.random(.characterSet, seed: 6))
    frame.relocate(screen: 0x0000, graphics: 0x1000)  // $D000 once exported
    let prg = frame.prg()
    let (memory, _) = load(prg)
    #expect(memory[0xD000..<0xD800] == frame.memory[0x1000..<0x1800])
}
