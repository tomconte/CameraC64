# Third-party notices

Camera C64 is MIT-licensed. Code borrowed from other projects keeps its original copyright notice, both in the source file and in this list, which the app also shows in its acknowledgements.

It lists only what the app includes now. Projects that inspired it, or that may be borrowed from later, are in the plan ([docs/REWRITE_PLAN.md](docs/REWRITE_PLAN.md), section 14), and are added here when the app first includes them.

The app bundles this file and shows the table's rows in Settings, under Acknowledgements: keep it one table of three columns.

| Material | Licence | Where and how it is used |
|---|---|---|
| Commodore 64 character ROM (901225-01), Commodore's design | None: not protected in the US; claimed by Amiga Corporation, licensed to Cloanto | Its character shapes, in `Packages/C64Core/Sources/C64Core/CharacterROM.swift`, outside the MIT licence: for the PETSCII and BBS modes. Exported programs never contain them: they show PETSCII pictures with the C64's own ROM |
| [Colodore](https://www.colodore.com/), Philip "Pepto" Timmermann's model of the VIC-II's colours | Published algorithm; no code taken | The C64's colours, computed from the PAL signal in `Packages/C64Core/Sources/C64Core/Colodore.swift` |
