import C64Core
import Testing

/// The colours of the 8 pixels on one line of a cell, left to right.
private func cellLine(_ image: IndexedImage, column: Int, row: Int, line: Int) -> [C64Color] {
    (0..<8).map { image[Screen.windowX + column * 8 + $0, Screen.windowY + row * 8 + line] }
}

@Test func borderSurroundsTheDisplayWindow() {
    var frame = C64Frame(mode: .hiresBitmap)
    frame.borderColor = .lightBlue
    let image = VICII.render(frame)
    #expect(image.width == 384 && image.height == 272)
    #expect(image[0, 0] == .lightBlue)
    #expect(image[31, 100] == .lightBlue && image[32, 100] == .black)
    #expect(image[100, 34] == .lightBlue && image[100, 35] == .black)
    #expect(image[351, 234] == .black)
    #expect(image[352, 234] == .lightBlue && image[351, 235] == .lightBlue)
    #expect(image.window.pixels.allSatisfy { $0 == C64Color.black.rawValue })
}

@Test func hiresBitmapTakesTwoColoursFromTheScreen() {
    var frame = C64Frame(mode: .hiresBitmap)
    let cell = 2 * 40 + 1
    frame.memory[frame.graphicsAddress + cell * 8 + 3] = 0b1010_0001
    frame.memory[frame.screenAddress + cell] = 0x72
    let image = VICII.render(frame)
    #expect(
        cellLine(image, column: 1, row: 2, line: 3) == [.yellow, .red, .yellow, .red, .red, .red, .red, .yellow])
    #expect(cellLine(image, column: 1, row: 2, line: 2) == Array(repeating: .red, count: 8))
    #expect(cellLine(image, column: 0, row: 2, line: 3) == Array(repeating: .black, count: 8))
}

@Test func multicolorBitmapHasFourColoursPerCell() {
    var frame = C64Frame(mode: .multicolorBitmap)
    frame.backgroundColors[0] = .blue
    frame.memory[frame.graphicsAddress + 7] = 0b00_01_10_11
    frame.memory[frame.screenAddress] = 0x5E
    frame.colorRAM[0] = C64Color.white.rawValue
    let image = VICII.render(frame)
    #expect(
        cellLine(image, column: 0, row: 0, line: 7) == [
            .blue, .blue, .green, .green, .lightBlue, .lightBlue, .white, .white,
        ])
}

@Test func standardTextDrawsCharactersInTheirColour() {
    var frame = C64Frame(mode: .standardText)
    frame.backgroundColors[0] = .darkGrey
    frame.memory[frame.graphicsAddress + 65 * 8 + 4] = 0b1000_0001
    frame.memory[frame.screenAddress + 39] = 65
    frame.colorRAM[39] = C64Color.lightGreen.rawValue
    let image = VICII.render(frame)
    var expected = Array(repeating: C64Color.darkGrey, count: 8)
    expected[0] = .lightGreen
    expected[7] = .lightGreen
    #expect(cellLine(image, column: 39, row: 0, line: 4) == expected)
}

@Test func multicolorTextMixesHiresAndMulticolorCharacters() {
    var frame = C64Frame(mode: .multicolorText)
    frame.backgroundColors = [.black, .red, .green, .blue]
    frame.memory[frame.graphicsAddress + 1 * 8] = 0b00_01_10_11
    frame.memory[frame.screenAddress + 0] = 1
    frame.memory[frame.screenAddress + 1] = 1
    frame.colorRAM[0] = 0x03  // below 8: hires, in cyan
    frame.colorRAM[1] = 0x0B  // 8 + 3: multicolour, "11" pixels in cyan
    let image = VICII.render(frame)
    #expect(
        cellLine(image, column: 0, row: 0, line: 0) == [.black, .black, .black, .cyan, .cyan, .black, .cyan, .cyan])
    #expect(
        cellLine(image, column: 1, row: 0, line: 0) == [.black, .black, .red, .red, .green, .green, .cyan, .cyan])
}

@Test func extendedColorTextPicksABackgroundPerCharacter() {
    var frame = C64Frame(mode: .extendedColorText)
    frame.backgroundColors = [.black, .red, .green, .blue]
    frame.memory[frame.graphicsAddress + 5 * 8 + 1] = 0b1111_0000
    frame.memory[frame.screenAddress + 40] = 0xC5  // character 5, background 3
    frame.colorRAM[40] = C64Color.yellow.rawValue
    let image = VICII.render(frame)
    #expect(
        cellLine(image, column: 0, row: 1, line: 1) == [
            .yellow, .yellow, .yellow, .yellow, .blue, .blue, .blue, .blue,
        ])
}

@Test func memoryPointersFollowTheLayout() {
    var text = C64Frame(mode: .standardText)
    #expect(text.memoryPointers == 0x02)
    text.screenAddress = 0x0400
    text.graphicsAddress = 0x1000
    #expect(text.memoryPointers == 0x14)
    #expect(text.usedMemory == [0x0400..<0x07E8, 0x1000..<0x1800])

    let bitmap = C64Frame(mode: .multicolorBitmap)
    #expect(bitmap.memoryPointers == 0x08)
    #expect(bitmap.usedMemory == [0x0000..<0x03E8, 0x2000..<0x3F40])
    #expect(C64Frame(mode: .extendedColorText).usedMemory[1] == 0x0800..<0x0A00)
}
