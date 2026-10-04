# Third-party notices

Camera C64 is MIT-licensed. Code borrowed from other projects keeps its original copyright notice, both in the source file and in this list, which the app also shows in its acknowledgements.

No third-party code is included yet, only data: the character ROM's shapes.

## Included

| Material | Licence | Where and how it is used |
|---|---|---|
| Commodore 64 character ROM (901225-01), Commodore's design | None: not protected in the US; claimed by Amiga Corporation, licensed to Cloanto | Its character shapes, in `Packages/C64Core/Sources/C64Core/CharacterROM.swift`, outside the MIT licence: for PETSCII mode, and later the app's C64-style text. Exported programs never contain them: they show PETSCII pictures with the C64's own ROM |

## Planned sources

| Project | Licence | Planned use |
|---|---|---|
| [NUFLIX Studio](https://github.com/cobbpg/nuflix-studio), © 2024 Patai Gergely | MIT | NUFLI/NUFLIX display programs; optimiser ported to Swift |
| [Retropixels](https://github.com/micheldebree/retropixels), © 2015 Michel de Bree | MIT | Ideas only: graphics modes described as colour maps |
| [image64](https://github.com/nschneir/image64), © 2026 image64 contributors | MIT | Ideas only; its CLI as a quality baseline |
| [VICE](https://vice-emu.sourceforge.io/) | GPL-2.0-or-later | Test tool only, run by the tests; never part of the app |
