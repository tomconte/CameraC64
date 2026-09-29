import C64Core
import Testing

/// Colours written as 24-bit hex values, in hardware index order.
private func palette(_ hex: [UInt32]) -> [RGB] {
    hex.map { RGB(UInt8($0 >> 16), UInt8(($0 >> 8) & 0xFF), UInt8($0 & 0xFF)) }
}

@Test func colodoreDefaultsGiveThePublishedPalette() {
    let published = palette([
        0x000000, 0xFFFFFF, 0x813338, 0x75CEC8, 0x8E3C97, 0x56AC4D, 0x2E2C9B, 0xEDF171,
        0x8E5029, 0x553800, 0xC46C71, 0x4A4A4A, 0x7B7B7B, 0xA9FF9F, 0x706DEB, 0xB2B2B2,
    ])
    #expect(C64Palette.colodore.colors == published)
}

/// VICE's `colodore.vpl` is Colodore with other knob settings, so it checks
/// that the knobs work as on colodore.com.
@Test func colodoreKnobsReproduceVICEsColodorePalette() {
    let vice = palette([
        0x000000, 0xFFFFFF, 0x96282E, 0x5BD6CE, 0x9F2DAD, 0x41B936, 0x2724C4, 0xEFF347,
        0x9F4815, 0x5E3500, 0xDA5F66, 0x474747, 0x787878, 0x91FF84, 0x6864FF, 0xAEAEAE,
    ])
    #expect(Colodore(brightness: 47, contrast: 100, saturation: 70).palette.colors == vice)
}

/// Colours of equal luma rank share their brightness signal exactly, and a
/// higher rank is always brighter.
@Test(arguments: LumaLevels.allCases)
func colodoreLumaFollowsTheChip(levels: LumaLevels) {
    let model = Colodore(lumaLevels: levels)
    let lumas = Set(C64Color.allCases.map { model.signal($0).y })
    #expect(lumas.count == levels.rawValue)
    if levels == .nine {
        for a in C64Color.allCases {
            for b in C64Color.allCases {
                #expect((a.lumaRank < b.lumaRank) == (model.signal(a).y < model.signal(b).y))
            }
        }
    }
}

@Test func earliestChipsShareMoreBrightness() {
    let model = Colodore(lumaLevels: .five)
    #expect(model.signal(.red).y == model.signal(.blue).y)
    #expect(model.signal(.green).y == model.signal(.grey).y)
    #expect(model.signal(.cyan).y == model.signal(.yellow).y)
}

@Test func noSaturationGivesGreys() {
    for color in Colodore(saturation: 0).palette.colors {
        #expect(color.r == color.g && color.g == color.b)
    }
}

@Test func brightnessKnobBrightensEveryColour() {
    let dim = Colodore(brightness: 30).palette
    let bright = Colodore(brightness: 70).palette
    for color in C64Color.allCases where color != .white {
        #expect(Int(bright[color].g) > Int(dim[color].g))
    }
}
