import Foundation
import Testing

@testable import C64Core

/// PETSCII converters, shared by the tests: making one takes a while in a
/// debug build.
private enum Converters {
    static let tv = make(.tv)
    static let sharp = make(.sharp)
    static let blackAndWhite = make(.blackAndWhite)
    static let graphicsTV = make(.tv, .graphics)
    static let graphicsSharp = make(.sharp, .graphics)
    static let graphicsBlackAndWhite = make(.blackAndWhite, .graphics)

    private static func make(_ display: DisplayModel, _ characters: CharacterROM.Selection = .all) -> Converter {
        Converter(spec: .petscii, settings: Converter.Settings(display: display, petsciiCharacters: characters))
    }

    static func converter(for display: DisplayModel, characters: CharacterROM.Selection = .all) -> Converter {
        switch (display, characters) {
        case (.sharp, .all): sharp
        case (.blackAndWhite, .all): blackAndWhite
        case (_, .all): tv
        case (.sharp, .graphics): graphicsSharp
        case (.blackAndWhite, .graphics): graphicsBlackAndWhite
        case (_, .graphics): graphicsTV
        }
    }
}

/// Which of the character ROM's sets a frame shows.
private func characterSet(of frame: C64Frame) -> CharacterROM.Set? {
    CharacterROM.Set.allCases.first { $0.address == frame.graphicsAddress }
}

/// The graphics characters' codes, as a frame's screen holds them.
private let graphicsCodes = Set(CharacterROM.Selection.graphics.codes(in: .upperCase).map(UInt8.init))

@Test func convertsPETSCII() {
    #expect(Converter.supports(.petscii))
    #expect(!Converter.supports(.text(characters: CharacterROM.Set.upperCase.characters)))
    let target = gradient(for: .petscii)
    let conversion = Converters.tv.convert(target)
    #expect(conversion.picture.spec == .petscii)
    #expect(conversion.frame.seesCharacterROM && characterSet(of: conversion.frame) != nil)
    #expect(VICII.render(conversion.frame).window == conversion.picture.image())
    #expect(conversion == Converters.tv.convert(target))
}

/// The search finds the set and background with the lowest total by its
/// model, and each cell's best character and colour for them by the exact
/// error: the same as trying every character it may use, of both sets, in
/// every pair of colours, one by one. The target repeats a few cells, so that
/// trying them all takes little time.
@Test(arguments: [
    (DisplayModel.tv, CharacterROM.Selection.all), (.sharp, .all), (.blackAndWhite, .all), (.tv, .graphics),
    (.blackAndWhite, .graphics),
])
func petsciiSearchFindsTheBestCharacters(display: DisplayModel, characters: CharacterROM.Selection) {
    let converter = Converters.converter(for: display, characters: characters)
    let tables = converter.characterTables!
    let sets = CharacterROM.Set.allCases.filter { !characters.codes(in: $0).isEmpty }
    #expect(tables.sets == sets)
    let count = tables.count
    let gradient = gradient(for: .petscii)
    let blocks = [0, 137, 413, 520, 777, 999]
    var colors = gradient.colors
    for cell in 0..<1000 {
        let block = blocks[cell % blocks.count]
        for pixel in 0..<64 {
            let (x, y) = (pixel % 8, pixel / 8)
            colors[(cell / 40 * 8 + y) * 320 + cell % 40 * 8 + x] =
                gradient.colors[(block / 40 * 8 + y) * 320 + block % 40 * 8 + x]
        }
    }
    let target = Target(width: 320, height: 200, colors: colors)
    let conversion = converter.convert(target)

    // Each block's error for every character of each set in every pair of
    // colours, and its lowest for each set and background.
    let eye = EyeView()
    let sum = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    let correlations = UnsafeMutablePointer<Float>.allocate(capacity: 3 * tables.shapeCount)
    let result = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    defer {
        eye.deallocate()
        sum.deallocate()
        correlations.deallocate()
        result.deallocate()
    }
    func error(_ set: Int, _ code: Int, _ foreground: Int, _ background: Int) -> Float {
        let character = tables.codes[set][code]!
        let slot = character.inverted ? background * count + foreground : foreground * count + background
        Converter.errors(
            tables.terms + character.shape * Converter.CharacterTables.rows * tables.slots, stride: tables.slots,
            slots: slot..<slot + 1, sum: sum, correlation: correlations + character.shape,
            shapeCount: tables.shapeCount, monochrome: display.isMonochrome, into: result)
        return result[0] + sum[3]
    }
    var lowest = [[Float]](repeating: [Float](repeating: .infinity, count: sets.count * count), count: blocks.count)
    for block in blocks.indices {
        eye.see(block, of: target, monochrome: display.isMonochrome, sum: sum)
        eye.correlate(with: tables.basis, shapeCount: tables.shapeCount, into: correlations)
        for (set, characterSet) in sets.enumerated() {
            for code in characters.codes(in: characterSet) {
                for foreground in 0..<count {
                    for background in 0..<count where foreground != background {
                        let value = error(set, code, foreground, background)
                        lowest[block][set * count + background] = min(lowest[block][set * count + background], value)
                    }
                }
            }
        }
    }
    var totals = [Double](repeating: 0, count: sets.count * count)
    for cell in 0..<1000 {
        for choice in totals.indices {
            totals[choice] += Double(lowest[cell % blocks.count][choice])
        }
    }
    let choice = totals.indices.min { totals[$0] < totals[$1] }!
    let background = converter.candidates.firstIndex(of: conversion.picture.colors[0][0])
    #expect(characterSet(of: conversion.frame) == sets[choice / count] && background == choice % count)

    // Each cell takes the character and colour with the lowest exact error:
    // the squared distance between how it looks and how the cell's target
    // looks, to the eye.
    let (chosenSet, chosenBackground) = (choice / count, choice % count)
    let screen = conversion.frame.screen
    let view = UnsafeMutablePointer<Float>.allocate(capacity: 192)
    defer { view.deallocate() }
    for cell in 0..<blocks.count * 2 {
        eye.see(cell % blocks.count, of: target, monochrome: display.isMonochrome, sum: sum)
        view.update(from: eye.seen, count: 192)
        // Infinite for a character the picture may not use.
        func exact(_ code: Int, _ foreground: Int) -> Float {
            guard let character = tables.codes[chosenSet][code] else { return .infinity }
            let look =
                character.inverted
                ? tables.look(character.shape, chosenBackground, foreground, eye: eye)
                : tables.look(character.shape, foreground, chosenBackground, eye: eye)
            return Converter.distance(look, view)
        }
        var lowestExact = Float.infinity
        for code in characters.codes(in: sets[chosenSet]) {
            for foreground in 0..<count where foreground != chosenBackground {
                lowestExact = min(lowestExact, exact(code, foreground))
            }
        }
        let foreground = converter.candidates.firstIndex(of: conversion.picture.colors[1][cell])!
        #expect(exact(Int(screen[cell]), foreground) == lowestExact, "cell \(cell)")
    }
}

/// A PETSCII picture, shown on a sharp display, converts back to itself:
/// the same set and background, and in every cell the same character and
/// colour, or ones that look the same. With only the graphics characters, so
/// does a picture of them.
@Test(arguments: [
    (CharacterROM.Set.upperCase, CharacterROM.Selection.all), (.lowerCase, .all), (.upperCase, .graphics),
])
func petsciiPicturesComeBack(set: CharacterROM.Set, characters: CharacterROM.Selection) throws {
    var picture = ModePicture.random(.petscii, seed: 31, characterSet: set, characters: characters)
    // Cells in the background colour show no character, so keep them out.
    for cell in 0..<1000 where picture.colors[1][cell] == picture.colors[0][0] {
        picture.colors[1][cell] = picture.colors[0][0] == .white ? .black : .white
    }
    let image = picture.image()
    let full = Crop(x: 0, y: 0, width: 320, height: 200)
    let converter = Converters.converter(for: .sharp, characters: characters)
    let conversion = converter.convert(image.rgbImage(.colodore), crop: full, tones: .neutral)
    #expect(conversion.frame.graphicsAddress == set.address)
    #expect(conversion.picture.colors[0][0] == picture.colors[0][0])
    let shown = conversion.picture.image()
    let same = (0..<1000).filter { cell in
        (0..<64).allSatisfy { pixel in
            let (x, y) = (cell % 40 * 8 + pixel % 8, cell / 40 * 8 + pixel / 8)
            return shown[x, y] == image[x, y]
        }
    }
    #expect(same.count == 1000, "\(same.count) cells of 1,000 come back")
}

/// With only the graphics characters, a picture takes all its characters from
/// them, in the upper case set, where with all characters it has letters too.
/// In the viewfinder, cells drop the previous frame's other characters.
@Test func petsciiGraphicsPicturesUseOnlyGraphicsCharacters() {
    let target = gradient(for: .petscii)
    let conversion = Converters.graphicsTV.convert(target)
    #expect(characterSet(of: conversion.frame) == .upperCase)
    #expect(conversion.frame.screen.allSatisfy(graphicsCodes.contains))
    #expect(VICII.render(conversion.frame).window == conversion.picture.image())
    #expect(!Converters.tv.convert(target).frame.screen.allSatisfy(graphicsCodes.contains))

    // A picture of letters and graphics in the upper case set, which comes
    // back as it is with all characters.
    var letters = ModePicture.random(.petscii, seed: 5)
    for cell in 0..<1000 where letters.colors[1][cell] == letters.colors[0][0] {
        letters.colors[1][cell] = letters.colors[0][0] == .white ? .black : .white
    }
    let photo = letters.image().rgbImage(.colodore)
    let full = Crop(x: 0, y: 0, width: 320, height: 200)
    let previous = Converters.sharp.convert(photo, crop: full, tones: .neutral)
    #expect(characterSet(of: previous.frame) == .upperCase)
    #expect(previous.frame.screen.filter { !graphicsCodes.contains($0) }.count > 400)
    let next = Converters.graphicsSharp.convert(photo, crop: full, tones: .neutral, keeping: previous)
    #expect(next.frame.screen.allSatisfy(graphicsCodes.contains))
}

/// In the viewfinder, cells keep their character and colour from one frame to
/// the next unless new ones are clearly better.
@Test func petsciiViewfinderFramesKeepTheirCharacters() {
    let converter = Converters.tv
    let target = gradient(for: .petscii)
    let first = converter.convert(target)
    // The same scene with a little noise, as the next video frame.
    var generator = SeededGenerator(seed: 3)
    var next = target
    for index in next.colors.indices {
        next.colors[index].l += Float.random(in: -0.03...0.03, using: &generator)
    }
    func changedCells(_ conversion: Conversion) -> Int {
        (0..<1000).filter { cell in
            conversion.frame.screen[cell] != first.frame.screen[cell]
                || conversion.picture.colors[1][cell] != first.picture.colors[1][cell]
        }.count
    }
    let fresh = changedCells(converter.convert(next))
    let steady = changedCells(converter.convert(next, keeping: first))
    #expect(fresh >= 10)
    #expect(steady <= fresh / 5)

    // In a different scene, most cells take new characters.
    var other = target
    other.colors.reverse()
    #expect(changedCells(converter.convert(other, keeping: first)) >= 800)
}

/// On a monochrome monitor only lightness counts, and each brightness has one
/// colour, a grey where there is one.
@Test func petsciiOnMonochromeMonitorsSeesBrightness() {
    let converter = Converters.blackAndWhite
    #expect(converter.candidates == [.black, .white, .purple, .green, .blue, .yellow, .darkGrey, .grey, .lightGrey])
    let target = gradient(for: .petscii)
    var grey = target
    for index in grey.colors.indices {
        grey.colors[index].a = 0
        grey.colors[index].b = 0
    }
    let conversion = converter.convert(target)
    #expect(conversion == converter.convert(grey))
    let used = Set(conversion.picture.image().pixels.map { C64Color(rawValue: $0)! })
    #expect(used.isSubset(of: Set(converter.candidates)))
}

@Test func petsciiBordersMatchTheEdgesOrTheChoice() {
    let target = gradient(for: .petscii)
    let automatic = Converters.tv.convert(target).picture
    #expect(automatic.borderColor == automatic.image().edgeColor)
    let chosen = Converter(spec: .petscii, settings: Converter.Settings(display: .tv, border: .lightBlue))
    #expect(chosen.convert(target).frame.borderColor == .lightBlue)
}
