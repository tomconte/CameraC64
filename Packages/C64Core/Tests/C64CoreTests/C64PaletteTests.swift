import C64Core
import Testing

@Test func sixteenColoursWithHardwareIndices() {
    #expect(C64Color.allCases.count == 16)
    #expect(C64Color.black.rawValue == 0)
    #expect(C64Color.lightGrey.rawValue == 15)
}

@Test func sevenPairsShareTheirBrightness() {
    let byRank = Dictionary(grouping: C64Color.allCases, by: \.lumaRank)
    #expect(byRank.count == 9)
    #expect(byRank.values.filter { $0.count == 2 }.count == 7)
}

/// The brightness ranks must agree with the palette data: colours of equal
/// rank have (nearly) the same luma, and a higher rank is always brighter.
@Test func pepto2001AgreesWithLumaRanks() {
    func luma(_ c: RGB) -> Double {
        0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b)
    }
    let palette = C64Palette.pepto2001
    let byRank = Dictionary(grouping: C64Color.allCases, by: \.lumaRank)
    var brightestSoFar = -1.0
    for rank in 0...8 {
        let lumas = (byRank[rank] ?? []).map { luma(palette[$0]) }
        guard let darkest = lumas.min(), let brightest = lumas.max() else {
            Issue.record("No colour has luma rank \(rank)")
            continue
        }
        #expect(brightest - darkest < 2)
        #expect(darkest > brightestSoFar)
        brightestSoFar = brightest
    }
}
