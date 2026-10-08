# Camera C64

An iPhone camera that takes authentic Commodore 64 pictures: real VIC-II graphics modes, every hardware limit respected, and files that run on a real C64.

**Work in progress.** The app is being rewritten from scratch. The converter works, for hires, multicolour and PETSCII: `c64conv convert` turns a photo into a C64 picture, and the app's viewfinder shows what the camera sees, converted live, and takes shots, which can be shared as pictures or C64 files, saved to Photos, or sent to a C64 with an Ultimate. See the [rewrite plan](docs/REWRITE_PLAN.md).

The original 2012–2013 app (Objective-C, GPUImage) is preserved at tag `legacy-1.2` ([browse](https://github.com/tomconte/CameraC64/tree/435cf74a414ef75b35dc3ea28039a1f8455f8293)).

## Layout

- `App/`: the iOS app (SwiftUI) and its tests
- `Packages/C64Core/`: the core library (palettes, graphics modes, converter, renderer, C64 file formats)
- `C64/`: 6502 display programs embedded in exported `.prg` files
- `Tools/`: developer tools: the `c64conv` command-line tool, the quality benchmark, and the tests that compare the renderer with the VICE emulator
- `docs/`: plan and design notes
- `site/`: the website, [c64camera.com](https://c64camera.com): the support page and the privacy policy

## Building

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate                              # creates CameraC64.xcodeproj from project.yml
open CameraC64.xcodeproj
swift test --package-path Packages/C64Core     # core library tests
swift test --package-path Tools                # tools; with VICE installed, the VICE comparison too
swift format lint --strict --recursive Packages App Tools
```

No Mac is needed to work on the project:

- **CI** (`.github/workflows/ci.yml`) lints, builds and tests `C64Core` and the tools on Linux, and on macOS runners builds and tests the app in the iOS Simulator and compares the renderer with VICE, on every push.
- **Claude Code on the web** installs Swift and cc65 at the start of each session (`.claude/hooks/session-start.sh`), so `C64Core` and the tools can be built and tested there; `Tools/install-vice.sh` adds VICE for the comparison tests.

Details, including TestFlight setup: [docs/CI.md](docs/CI.md).

## License

MIT, see [LICENSE](LICENSE), except for the character ROM's shapes in `Packages/C64Core/Sources/C64Core/CharacterROM.swift`, which have their own notice. Credits for borrowed code are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
