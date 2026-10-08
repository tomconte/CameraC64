# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Camera C64 is being rewritten from scratch as an iOS 26 SwiftUI app that turns camera shots into authentic Commodore 64 pictures. What the app does and why is in `docs/REWRITE_PLAN.md`, how it looks and behaves is in `docs/UX.md`, and how CI and TestFlight work is in `docs/CI.md`. This file only covers how to work in the code. The 2012–2013 app lives at tag `legacy-1.2`, not in the tree.

## Commands

`C64Core` and the tools in `Tools/` are plain Swift and build on Linux and macOS:

```sh
swift build --package-path Packages/C64Core
swift test --package-path Packages/C64Core
swift test --package-path Packages/C64Core --filter pepto2001AgreesWithLumaRanks   # a single test
swift test -c release -Xswiftc -enable-testing --package-path Packages/C64Core     # optimised, as CI also runs them
swift test --package-path Tools        # also compares the renderer with VICE, if x64sc is found
swift run --package-path Tools c64conv help
swift run --package-path Tools c64conv convert photo.png -o picture.png --monitor tv --scale 2
Tools/Benchmark/get-photos.sh          # the quality benchmark's photos, once
swift run -c release --package-path Tools c64conv benchmark -o /tmp/report   # quality, against Tools/Benchmark/scores.txt
swift run -c release --package-path Tools c64conv speed                      # how long a viewfinder frame takes here
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
  - on Linux: lint, build and test `C64Core` (in debug and optimised) and the tools, check that `DisplayPrograms.swift` matches the assembly sources, and run the quality benchmark
  - on `macos-26`: the app tests in the iOS Simulator, plus an unsigned device build; the VICE comparison, with Homebrew's VICE; and the benchmark with image64 as a baseline, for comparison only

  After pushing, read the run's results and job logs with the GitHub tools, then fix and push again.
- **Pushing cancels CI:** a new push cancels the in-progress CI run on the same branch. Don't push while waiting on a run whose result you need.
- **TestFlight:** a pushed commit whose message starts with `[testflight]` uploads a TestFlight build of the dev app, `com.camerac64.dev` (`.github/workflows/testflight.yml`). The marker exists because the GitHub integration cannot start workflows by hand (it gets a 403). Uploads to the release app happen only through a manual run with `app: release`.
  - Upload one on your own whenever a change alters the app's UI (what its screens show, or how they behave), so it can be tried on a phone: once CI is green on the change, push a commit whose message starts with `[testflight]`, an empty one if nothing is left to commit. Otherwise, only when asked.
  - Check that the TestFlight run succeeds, and say which build it uploaded.

## Architecture

- **`Packages/C64Core`** holds all C64 logic.
  - Palettes (`Colodore`, Pepto) with each colour's PAL signal, modes described as data (`ModeSpec`, and `ModePicture` with its encoder), `C64Frame`, the renderer (`VICII`), and `.prg`, `.d64`, Koala and Art Studio files.
  - The converter for hires, multicolour and PETSCII: `Target` prepares a photo (crop, linear-light averaging, tones, in `OKLab`), and `Converter` searches every cell's colour sets and dithers, or for PETSCII its characters (`Converter+PETSCII.swift`). `DisplayModel` shows pictures on the monitor presets, and tells the converter how dithered mixes look there. `SpeedBenchmark` times a viewfinder frame.
  - It must keep building and testing on Linux, so no UIKit, SwiftUI, Metal, CoreGraphics or ImageIO; it takes plain pixel buffers (`RGBImage`).
  - Its platform floor (iOS 18, macOS 15) is deliberately lower than the app's.
- **`C64/`** holds the 6502 display programs, written for ca65.
  - `C64/build.sh` assembles them into `C64Core` as `DisplayPrograms.swift`. That file is generated: never edit it, and commit it with the sources.
  - Exported programs copy the VIC-II's memory into the bank at `$C000`, or for PETSCII, which uses the C64's own character ROM, the bank at `$8000`.
- **`Tools/`** is a Swift package on top of `C64Core`: the `c64conv` CLI, a small PNG codec, the quality benchmark (`Tools/Benchmark/`), and the tests that run exported programs in VICE.
- **`App/`** is a thin SwiftUI layer on top of `C64Core`.
  - The Xcode project is generated from `project.yml` by XcodeGen: edit `project.yml` and never commit `CameraC64.xcodeproj`.
  - The app's Info.plist comes from the `INFOPLIST_KEY_` settings in `project.yml`, added to `App/Info.plist`, which holds what those settings cannot say: the C64 files' types and plain HTTP on the local network. The app tests check both.
  - The privacy manifest, `App/Resources/PrivacyInfo.xcprivacy`, declares no tracking, no collected data, and the one API that needs a reason, the user defaults. Code that starts using another of Apple's required-reason APIs (file timestamps, disk space, system boot time, active keyboards) must add it there, as must anything that sends data off the phone other than at the user's request.
  - Settings' acknowledgements show the bundled `LICENSE` and the table in `THIRD_PARTY_NOTICES.md`, so that file keeps one table of three columns. It lists only what the app includes, not what it may borrow later.
  - The app target uses MainActor as its default actor isolation: code that runs anywhere else is marked `nonisolated`, types included.
  - The camera (`App/Sources/Camera/`): `Camera`, an actor whose executor is its own queue, owns the capture session; `Viewfinder` converts frames on another queue; `LiveCamera` is the screen's side of both.
  - Frames come sideways and unmirrored, as AVFoundation sends them by default. `HeldOrientation` says how each camera's frames turn as the phone is held, the front camera's the other way to the back camera's. `Target`'s `ImageOrientation` turns them, and mirrors the front camera's once upright; mirrored first, they would be upside down with the phone upright.
  - Never set the video output's rotation angle: on the iPhone 17's front camera, whose sensor is mounted upright, AVFoundation's default angle is what keeps its frames sideways like every other camera's (plan, section 6). A photo's angle counts from the sensor, so `Camera` adds that default angle to the turn the frames need, with the photo output's sensor orientation compensation turned off.
  - Only a phone can check the camera: the Simulator, and so CI, has none, and shows static. The app tests feed the viewfinder synthetic frames.
  - The controls below the TV must fit on every iPhone iOS 26 runs on. `LayoutTests` measures the review's at each screen size, from the iPhone SE, which takes a tighter layout, to the Pro Max.
  - iOS may stop the capture session while the app is away, when it resets its media services, and leaves it to the app to start it again. So `LiveCamera.start` runs again whenever the app becomes active, an interruption ends, such a reset is reported (`AVCaptureSession.runtimeErrorNotification`) or a shot fails: it checks what the session does (`Camera.activity`), and starts it if it stopped. Never set `LiveCamera.state` to running without asking the session. On a phone, Settings → Developer → Reset Media Services tries it.
  - The badge switches the TV off, and the camera with it (`LiveCamera.switchOff`), which saves the battery. While it is off, `start` leaves the camera off whatever asks: only `switchOn`, from any key, starts it again.
  - The CRT layer (`App/Sources/CRT/`, plan section 7): `CRT.metal` is a SwiftUI shader that fills the TV with the display model's picture as a tube shows it, with scanlines, glow and curvature. `CRTSource` prepares what it reads, off the main actor, and `Afterglow` gives the amber and green monitors their trails in the viewfinder. `Tube` switches the TV off and on as a tube does: the picture closes into a line and a dot, drawn in `CRT.metal` too (`tubeFace`, `tubeGain`), and the TV redraws every frame only while the tube moves. It is presentation only: never in C64 files or the pixel-exact PNG, and never on Sharp. The shared picture as on TV draws it through `ImageRenderer`, which runs SwiftUI shaders as the screen does: `sharedPictureShowsTheCRTLayer` checks that its lines have gaps.
  - Metal doesn't compile on Linux, so only CI's app job checks the shaders: `crtShaderCompiles` and `tubeShadersCompile` fail if they don't compile with the arguments the TV gives them, and `tubeFaceShowsTheLineOnTheGlass` and `closingPictureGainsLight` check what the tube's shaders draw.
- **Core rule:** converters produce C64 memory (a `C64Frame`), and every picture shown or exported is rendered from that memory. Never produce pixels that bypass the renderer; that is how the legacy app ended up with pictures a real C64 could not display.
  - The app's `PictureMaker` (`App/Sources/Pictures/`) does it for each shot's photo: converter, renderer, then the monitor's display model. `Viewfinder` does the same for each camera frame. Each `ShownPicture` keeps the `C64Frame` it is drawn from.
  - The review shares, saves and sends what is made from that frame (`App/Sources/Pictures/`): `SharedFile` makes each file Share offers only when it is shared, `PhotoLibrary` saves the picture as on TV, and `Ultimate` runs the `.prg` on a C64 through the Ultimate's REST API. The Ultimate's password stays in the keychain (`Keychain`), not in the user defaults.
- **Still to come** (plan section 5):
  - converters for the character-set modes
  - a `C64Metal` target, only if the speed benchmark shows the CPU converter can't keep up with the viewfinder (plan section 10); its kernels would have to match `C64Core` bit for bit
  - display programs for the advanced modes in `C64/`

## Conventions and pitfalls

- **Style:** Swift 6 language mode, 4-space indent, 120 columns (`.swift-format`). Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- **Spelling:** identifiers in `C64Core` and `Tools` use American spelling as Swift does (`C64Color`, `multicolor`); comments and docs use British spelling.
- **Fast loops:** the converter's and display models' inner loops are plain loops over `UnsafeMutablePointer` buffers, which the compiler vectorises. Swift's SIMD types, and arrays used inside such loops, were several times slower. Work spreads over the cores with `concurrently` (`Concurrency.swift`); on Linux, `concurrentPerform` takes a `@Sendable` closure, so buffers are shared through `Shared`.
- **Optimised builds:** the app runs `C64Core` optimised, and an optimised build once got display-model lines wrong that the debug tests got right: arrays that started out sharing storage were swapped while blurring. Give each buffer its own memory in such code. CI runs `C64Core`'s tests both ways.
- **Stale builds:** after files are added to `C64Core`, the `Tools` package's build may not see them until `swift package --package-path Tools clean`.
- **Quality benchmark:** a change that alters pictures changes the scores in `Tools/Benchmark/scores.txt`. CI fails if they get worse; when the change is meant, run `c64conv benchmark --update-baseline` and commit the scores with it. The photos come from Kodak's suite on a personal website, which sometimes refuses requests; `get-photos.sh` retries, and CI caches them.
- **VICE** (in `Tools/Sources/C64Tools/VICE.swift`):
  - `x64sc` 3.10 crashes when it logs to a stdout that is not a terminal, so it logs to a file.
  - VICE applies its colour settings even to an external palette. With saturation, contrast, brightness, gamma and tint at 1000, it shows the palette's colours exactly.
  - A `.prg` autostarts with `-autostartprgmode 1`, which puts it straight into memory. VICE's default loads it through an emulated disk, which takes about 30 million cycles.
  - Its screenshots are taken before the CRT emulation (`-VICIIfilter 1`), so they can't check the display models; the blur widths were matched to its PAL renderer's source instead.
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
  - Never copy GPL code (VICE, Frodo, reSID), and never add the KERNAL or BASIC ROMs to the repo.
  - The character ROM is the one exception (plan, section 17). Its shapes are in `C64Core`'s `CharacterROM.swift`, one file with its own notice, outside the MIT licence; keep them there and nowhere else.
