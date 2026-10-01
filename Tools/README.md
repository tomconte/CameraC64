# Developer tools

A Swift package on top of C64Core, for Linux and macOS, with no other dependencies.

## c64conv

```sh
swift run --package-path Tools c64conv testcard multicolor -o card.prg   # a random picture that obeys the mode's limits
swift run --package-path Tools c64conv render picture.kla -o picture.png --scale 2
swift run --package-path Tools c64conv export picture.kla -o picture.d64 # .prg, .d64, .kla/.koa, .art or .png
swift run --package-path Tools c64conv vice card.prg -o screen.png       # what VICE shows
```

It reads Koala (`.kla`, `.koa`) and Art Studio (`.art`) files. Converting photos comes with the converter (milestone 2 of the [plan](../docs/REWRITE_PLAN.md)).

## VICE comparison tests

`swift test --package-path Tools` runs the tools' tests. Where VICE's `x64sc` is found, it also runs each exported program in VICE and requires the screen to match the renderer pixel for pixel, border included (plan, section 10):

- every standard mode, with random pictures
- memory layouts under the I/O area and the KERNAL
- PETSCII with VICE's own character ROM, read at test time
- a `.d64` loaded through an emulated 1541

`x64sc` is looked for in `$X64SC`, on the `PATH`, then in Homebrew's and `/opt/vice`'s `bin`. On a Mac, `brew install vice`. On Linux, `install-vice.sh` builds it without a user interface into `/opt/vice`. With `VICE_TEST_OUTPUT=<directory>`, a mismatch leaves both screens there as PNGs. `VICE_SEEDS=<n>` checks n random pictures per mode instead of 2.

VICE is GPL software: the tests only run it, and nothing of it is copied into this repository or the app.

## To come

The quality benchmark: a fixed photo set converted and scored (milestone 2).
