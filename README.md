# Camera C64

An iPhone camera that takes authentic Commodore 64 pictures: real VIC-II graphics modes, every hardware limit respected, and files that run on a real C64.

**Work in progress.** The app is being rewritten from scratch and nothing here is usable yet. See the [rewrite plan](docs/REWRITE_PLAN.md).

The original 2012–2013 app (Objective-C, GPUImage) is preserved at tag `legacy-1.2` ([browse](https://github.com/tomconte/CameraC64/tree/435cf74a414ef75b35dc3ea28039a1f8455f8293)).

## Layout

- `App/`: the iOS app (SwiftUI) and its tests
- `Packages/C64Core/`: the core library (palettes, graphics modes, converter, renderer, C64 file formats)
- `C64/`: 6502 display programs embedded in exported `.prg` files
- `Tools/`: developer tools (VICE comparison tests, quality benchmark)
- `docs/`: plan and design notes

## Building

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate                              # creates CameraC64.xcodeproj from project.yml
open CameraC64.xcodeproj
swift test --package-path Packages/C64Core     # core library tests
swift format lint --strict --recursive Packages App
```

No Mac is needed to work on the project:

- **CI** (`.github/workflows/ci.yml`) lints, builds and tests `C64Core` on Linux, and builds and tests the app in the iOS Simulator on a macOS runner, on every push.
- **Claude Code on the web** installs Swift at the start of each session (`.claude/hooks/session-start.sh`), so `C64Core` can be built and tested there.

Details, including TestFlight setup: [docs/CI.md](docs/CI.md).

## License

MIT, see [LICENSE](LICENSE). Credits for borrowed code are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
