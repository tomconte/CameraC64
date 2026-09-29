# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Camera C64 is being rewritten from scratch as an iOS 26 SwiftUI app that turns camera shots into authentic Commodore 64 pictures. What the app does and why is in `docs/REWRITE_PLAN.md`, how it looks and behaves is in `docs/UX.md`, and how CI and TestFlight work is in `docs/CI.md`. This file only covers how to work in the code. The 2012–2013 app lives at tag `legacy-1.2`, not in the tree.

## Commands

`C64Core` is plain Swift and builds on Linux and macOS:

```sh
swift build --package-path Packages/C64Core
swift test --package-path Packages/C64Core
swift test --package-path Packages/C64Core --filter pepto2001AgreesWithLumaRanks   # a single test
swift format lint --strict --recursive Packages App       # CI fails on any finding
swift format format --in-place --recursive Packages App   # apply the formatting
```

The iOS app needs Xcode, so in Claude Code web sessions (Linux) only CI builds it. On a Mac, run `xcodegen generate` first. CI runs the app tests with:

```sh
xcodebuild test -project CameraC64.xcodeproj -scheme CameraC64 \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

## Working without a Mac

- **Swift:** web sessions get Swift 6.3.3 from `.claude/hooks/session-start.sh`.
- **CI:** every push runs `.github/workflows/ci.yml`:
  - on Linux: lint, build and test `C64Core`
  - on `macos-26`: the app tests in the iOS Simulator, plus an unsigned device build

  After pushing, read the run's results and job logs with the GitHub tools, then fix and push again.
- **Pushing cancels CI:** a new push cancels the in-progress CI run on the same branch. Don't push while waiting on a run whose result you need.
- **TestFlight:** a pushed commit whose message starts with `[testflight]` uploads a TestFlight build of the dev app, `com.camerac64.dev` (`.github/workflows/testflight.yml`). Only do this when asked. The marker exists because the GitHub integration cannot start workflows by hand (it gets a 403). Uploads to the release app happen only through a manual run with `app: release`.

## Architecture

- **`Packages/C64Core`** holds all C64 logic: palettes, graphics modes, converter, renderer, display models and file formats.
  - It must keep building and testing on Linux, so no UIKit, SwiftUI, Metal, CoreGraphics or ImageIO; it takes plain pixel buffers.
  - Its platform floor (iOS 18, macOS 15) is deliberately lower than the app's.
- **`App/`** is a thin SwiftUI layer on top of `C64Core`.
  - The Xcode project is generated from `project.yml` by XcodeGen: edit `project.yml` and never commit `CameraC64.xcodeproj`.
  - The app target uses MainActor as its default actor isolation.
- **Core rule:** converters produce C64 memory (a `C64Frame`), and every picture shown or exported is rendered from that memory. Never produce pixels that bypass the renderer; that is how the legacy app ended up with pictures a real C64 could not display.
  - The one exception is temporary: the camera screen (`App/Sources/Camera/`) is a placeholder that shows sample pictures from `App/Resources/Assets.xcassets/Samples` and tints them for the mono monitors. Replace both with C64Core's renderer and display models as soon as they exist.
- **Still to come** (plan section 5):
  - a `C64Metal` target, only if the speed benchmark shows the CPU converter can't keep up with the viewfinder (plan section 10); its kernels would have to match `C64Core` bit for bit
  - 6502 display programs in `C64/`
  - VICE comparison tests and a `c64conv` CLI in `Tools/`

## Conventions and pitfalls

- **Style:** Swift 6 language mode, 4-space indent, 120 columns (`.swift-format`). Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
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
  - Never copy GPL code (VICE, Frodo, reSID), and never add Commodore ROMs to the repo.
