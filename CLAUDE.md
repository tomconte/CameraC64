# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Camera C64 is being rewritten from scratch as an iOS 26 SwiftUI app that turns camera shots into authentic Commodore 64 pictures. What the app does and why is in `docs/REWRITE_PLAN.md`, how it looks and behaves is in `docs/UX.md`, and how CI and TestFlight work is in `docs/CI.md`. This file only covers how to work in the code. The 2012–2013 app lives at tag `legacy-1.2`, not in the tree.

## Commands

`C64Core` and the tools in `Tools/` are plain Swift and build on Linux and macOS:

```sh
swift build --package-path Packages/C64Core
swift test --package-path Packages/C64Core
swift test --package-path Packages/C64Core --filter pepto2001AgreesWithLumaRanks   # a single test
swift test --package-path Tools        # also compares the renderer with VICE, if x64sc is found
swift run --package-path Tools c64conv help
C64/build.sh                           # after editing C64/*.s: reassembles DisplayPrograms.swift
swift format lint --strict --recursive Packages App Tools       # CI fails on any finding
swift format format --in-place --recursive Packages App Tools   # apply the formatting
```

The iOS app needs Xcode, so in Claude Code web sessions (Linux) only CI builds it. On a Mac, run `xcodegen generate` first. CI runs the app tests with:

```sh
xcodebuild test -project CameraC64.xcodeproj -scheme CameraC64 \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

## Working without a Mac

- **Swift and cc65:** web sessions get Swift 6.3.3 and the cc65 assembler from `.claude/hooks/session-start.sh`.
- **VICE:** `Tools/install-vice.sh` builds a headless `x64sc` into `/opt/vice` (a few minutes; the download may need the user's approval). The tools' tests then compare every mode with VICE. With `VICE_TEST_OUTPUT=<dir>`, a mismatch leaves both screens there as PNGs.
- **CI:** every push runs `.github/workflows/ci.yml`:
  - on Linux: lint, build and test `C64Core` and the tools, and check that `DisplayPrograms.swift` matches the assembly sources
  - on `macos-26`: the app tests in the iOS Simulator, plus an unsigned device build; and the VICE comparison, with Homebrew's VICE

  After pushing, read the run's results and job logs with the GitHub tools, then fix and push again.
- **Pushing cancels CI:** a new push cancels the in-progress CI run on the same branch. Don't push while waiting on a run whose result you need.
- **TestFlight:** a pushed commit whose message starts with `[testflight]` uploads a TestFlight build of the dev app, `com.camerac64.dev` (`.github/workflows/testflight.yml`). Only do this when asked. The marker exists because the GitHub integration cannot start workflows by hand (it gets a 403). Uploads to the release app happen only through a manual run with `app: release`.

## Architecture

- **`Packages/C64Core`** holds all C64 logic.
  - Now: palettes (`Colodore`, Pepto), modes described as data (`ModeSpec`, and `ModePicture` with its encoder), `C64Frame`, the renderer (`VICII`), and `.prg`, `.d64`, Koala and Art Studio files.
  - To come: the converter and display models.
  - It must keep building and testing on Linux, so no UIKit, SwiftUI, Metal, CoreGraphics or ImageIO; it takes plain pixel buffers.
  - Its platform floor (iOS 18, macOS 15) is deliberately lower than the app's.
- **`C64/`** holds the 6502 display programs, written for ca65.
  - `C64/build.sh` assembles them into `C64Core` as `DisplayPrograms.swift`. That file is generated: never edit it, and commit it with the sources.
  - Exported programs copy the VIC-II's memory into the bank at `$C000`.
- **`Tools/`** is a Swift package on top of `C64Core`: the `c64conv` CLI, a small PNG codec, and the tests that run exported programs in VICE.
- **`App/`** is a thin SwiftUI layer on top of `C64Core`.
  - The Xcode project is generated from `project.yml` by XcodeGen: edit `project.yml` and never commit `CameraC64.xcodeproj`.
  - The app target uses MainActor as its default actor isolation.
- **Core rule:** converters produce C64 memory (a `C64Frame`), and every picture shown or exported is rendered from that memory. Never produce pixels that bypass the renderer; that is how the legacy app ended up with pictures a real C64 could not display.
  - The one exception is temporary: the camera screen (`App/Sources/Camera/`) is a placeholder that shows sample pictures from `App/Resources/Assets.xcassets/Samples` and tints them for the mono monitors. Replace both with C64Core's converter, renderer and display models once the converter and display models exist (milestone 2).
- **Still to come** (plan section 5):
  - a `C64Metal` target, only if the speed benchmark shows the CPU converter can't keep up with the viewfinder (plan section 10); its kernels would have to match `C64Core` bit for bit
  - display programs for the advanced modes in `C64/`, and the quality benchmark in `Tools/`

## Conventions and pitfalls

- **Style:** Swift 6 language mode, 4-space indent, 120 columns (`.swift-format`). Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- **Spelling:** identifiers in `C64Core` and `Tools` use American spelling as Swift does (`C64Color`, `multicolor`); comments and docs use British spelling.
- **VICE** (in `Tools/Sources/C64Tools/VICE.swift`):
  - `x64sc` 3.10 crashes when it logs to a stdout that is not a terminal, so it logs to a file.
  - VICE applies its colour settings even to an external palette. With saturation, contrast, brightness, gamma and tint at 1000, it shows the palette's colours exactly.
  - A `.prg` autostarts with `-autostartprgmode 1`, which puts it straight into memory. VICE's default loads it through an emulated disk, which takes about 30 million cycles.
- **Pinned Swift version.** Swift 6.3.3 is set in three places that must change together:
  - the `swift:6.3.3-noble` container in `ci.yml`
  - `SWIFT_VERSION` in the session hook
  - `DEVELOPER_DIR` (Xcode 26.6, which ships Swift 6.3.3) in both workflows
- **Versions:**
  - The bundle ID `com.camerac64` belongs to the existing App Store record and must not change. That record is removed from sale, so TestFlight can't install its builds; everyday builds go to a separate dev app, `com.camerac64.dev`, whose bundle ID and name the TestFlight workflow sets at archive time.
  - The app version is `MARKETING_VERSION` in `project.yml`.
  - Build numbers come from the TestFlight workflow and must keep increasing past the app's 2018 build, `20180325001`.
- **TestFlight signing:**
  - The archive stays unsigned, and signing happens only at export, through cloud signing with the App Store Connect API key. Signing the archive on CI makes Xcode create a new certificate on every run.
  - Keep the export step's output unfiltered, so App Store Connect errors stay visible.
- **Borrowed code:**
  - Only from MIT or similarly permissive projects. Keep the original notice in the file and add the project to `THIRD_PARTY_NOTICES.md`.
  - Never copy GPL code (VICE, Frodo, reSID), and never add Commodore ROMs to the repo. Tests that need the character ROM read it from VICE's installation.
