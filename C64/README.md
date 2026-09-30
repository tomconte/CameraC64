# C64 display programs

6502 code that runs on the C64: the viewers embedded in exported `.prg` files. They are written for ca65, the assembler of [cc65](https://cc65.github.io/).

- `viewer.s` shows a picture in any standard mode: standard, multicolour and extended colour text, and hires and multicolour bitmaps.
  - The file loads at `$0801` and starts with `SYS 2061`.
  - Its parameters follow the code: the VIC-II's register values, and a table of blocks to copy. The picture's data follows them.
  - It copies each block into the bank at `$C000`, switching the I/O area out for blocks under it, sets the registers, and resets the C64 when a key is pressed.
  - The layout is documented at the top of the file; C64Core's `.prg` writer (`Program.swift`) fills it in.
- `c64.cfg` is the linker configuration: code at `$0801`, written without a load address.
- `build.sh` assembles every program with ca65 and writes them into C64Core as `Packages/C64Core/Sources/C64Core/DisplayPrograms.swift`, so the library builds without an assembler. Run it after editing a program and commit both; CI fails if the generated file is out of date.

The advanced modes' programs (FLI, AFLI, interlace, NUFLI) come with milestone 4 of the [plan](../docs/REWRITE_PLAN.md). Like the standard viewer, they are for PAL machines.
