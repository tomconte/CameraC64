import C64Core
import Testing

/// CRC-32, as zip and PNG compute it.
private func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = crc & 1 == 1 ? crc >> 1 ^ 0xEDB8_8320 : crc >> 1
        }
    }
    return ~crc
}

/// The shapes are those of the C64's character ROM, part 901225-01, whose
/// CRC-32 is well known.
@Test func theCharacterROMIsTheC64s() {
    #expect(CharacterROM.bytes.count == 4096)
    #expect(crc32(CharacterROM.bytes) == 0xEC42_72EE)
    #expect(CharacterROM.Set.upperCase.characters == Array(CharacterROM.bytes[0..<2048]))
    #expect(CharacterROM.Set.lowerCase.characters == Array(CharacterROM.bytes[2048..<4096]))
    // @, the first character of both sets.
    #expect(CharacterROM.bytes[0..<8] == [0x3C, 0x66, 0x6E, 0x6E, 0x60, 0x62, 0x3C, 0x00])
}

/// In each set, the second half shows the first in reverse, but for the
/// reversed @, which differs in one line.
@Test func reversedCharactersAreTheInverseOfTheOthers() {
    for set in CharacterROM.Set.allCases {
        let characters = set.characters
        for code in 0..<128 {
            let inverse = characters[code * 8..<code * 8 + 8].map { ~$0 }
            let reversed = Array(characters[(code + 128) * 8..<(code + 129) * 8])
            #expect((inverse == reversed) == (code != 0), "\(set), code \(code)")
        }
    }
}
