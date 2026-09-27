# Camera C64 — rewrite plan

_Agreed September 2026. This is a living document: update it when decisions change._

## 1. Summary

Camera C64 turns camera shots into Commodore 64 pictures. The 2012–2013 app only imitated the look: its pictures could not exist on a real C64. The rewrite produces **authentic** pictures. Every result is real C64 memory in a real VIC-II graphics mode, obeys every hardware limit, and can be exported as a program that shows the picture on a real C64 or in an emulator.

| Topic | Decision |
|---|---|
| Platform | iPhone, iOS 26+ (iPhone 11 and later), Swift 6, SwiftUI, Xcode 26 |
| Code | Our own implementation. We borrow ideas and MIT-licensed code with credit; no GPL code in the app |
| Licence | Open source, MIT |
| Distribution | Update the existing App Store record (currently "removed from sale"): same bundle ID, version 3.0 |
| Business model | Standard VIC-II modes free; one paid "Advanced modes" unlock; buyers of the 2012 unlock get it free |
| Proof of authenticity | Every mode's exported `.prg` must match our renderer pixel for pixel in the VICE emulator, in CI |
| Legacy code | Tag `legacy-1.2`, commit [`435cf74`](https://github.com/tomconte/CameraC64/tree/435cf74a414ef75b35dc3ea28039a1f8455f8293) |

## 2. The legacy app

### Features to keep

- Live C64-style viewfinder.
- Capture, then discard, share or save.
- Four "monitors": colour, B&W, amber, green. The last three were unlocked by the `AXOLINK_C64_FILTERS` in-app purchase.
- Scanline overlay, flash toggle, front/back camera, CRT power-off animation, retro C64 look.

### How it worked

A GPUImage (OpenGL ES 2) filter chain:

1. The 640×480 camera frame is squeezed by 0.5×0.25.
2. Each pixel is looked up in two 512×512 colour tables giving the nearest and second-nearest colour of Pepto's 2001 palette. A 4×4 ordered-dither threshold picks between them.
3. The result is stretched back up 2×4.

### Why its pictures were not authentic

1. **No per-cell colour limits.** Any pixel could use any of the 16 colours. Real bitmap modes allow 2 colours per 8×8 cell (hires), or 3 plus a shared background per 4×8 cell (multicolour).
2. **Wrong pixel grid.** Effectively 240×160 blocks of 2×4 pixels stretched into a portrait frame, instead of 320×200 or 160×200, and no PAL/NTSC pixel shape.
3. **Colours outside the palette.**
   - `mix()` blended two palette colours ([GPUImage8BitLookupFilter.m:74](https://github.com/tomconte/CameraC64/blob/435cf74a414ef75b35dc3ea28039a1f8455f8293/framework/Source/GPUImage8BitLookupFilter.m#L74)).
   - Every texture was sampled with linear filtering ([GPUImageOutput.m:199](https://github.com/tomconte/CameraC64/blob/435cf74a414ef75b35dc3ea28039a1f8455f8293/framework/Source/GPUImageOutput.m#L199)), so both the lookup and the upscale blended colours.
   - Scanlines were baked in at 80% opacity, and the result was saved as an 80%-quality JPEG ([PhotoViewController.m:380](https://github.com/tomconte/CameraC64/blob/435cf74a414ef75b35dc3ea28039a1f8455f8293/examples/SimplePhotoFilter/SimplePhotoFilter/PhotoViewController.m#L380)).
4. **The mono monitors used 54–75 tints each**, where a C64 on a mono monitor shows only 9 brightness levels.
5. **No C64 file export**, so nothing could be checked on real hardware.

## 3. Principles

1. **The output is C64 memory, not an image.** Converters produce a C64 memory image. Everything the user sees is drawn from it by an emulation of the VIC-II video chip, so the hardware limits hold by construction, including in the live viewfinder.
2. **Prove it.** Automated tests run every exported program in VICE and compare the result pixel for pixel.
3. **Optimise for the chosen display.** Error is measured on the picture as the viewer will see it on the selected monitor (sharp, PAL TV, mono…). The C64 data is equally legal either way.
4. **Measure quality.** A fixed photo set and a metric turn "better" into a number.
5. **Own the core, borrow with credit** (section 14).

## 4. Graphics modes

| Mode | Grid | Limits the converter must obey | Tier |
|---|---|---|---|
| Hires bitmap | 320×200 | 2 colours per 8×8 cell | Free |
| Multicolour bitmap | 160×200, double-wide pixels | 3 free colours per 4×8 cell + 1 global background (`$D021`) | Free |
| Text (PETSCII) | 40×25 characters | ROM character shapes, 1 foreground colour per cell, 1 global background | Free |
| Custom character set (hires, multicolour, extended background) | 320×200 or 160×200 | At most 256 unique 8×8 tiles. Multicolour: per-cell colour 0–7 + 3 global colours. Extended background: 64 tiles, 4 global backgrounds, any foreground | Free |
| Multicolour + per-line background | 160×200 | As multicolour, but the background changes on every line | Paid |
| FLI | 160×200 | 2 screen-memory colours per 4×1 cell; colour memory per 4×8 cell; global background; leftmost 3 character columns unusable (the "FLI bug") | Paid |
| AFLI | 320×200 | 2 colours per 8×1 cell; FLI bug | Paid |
| Interlace multicolour / IFLI | 2 frames | Two pictures swapped every frame (50 Hz on PAL), optionally shifted 1 pixel; the eye sees the average colour, so large brightness differences get a flicker penalty | Paid |
| NUFLI / NUFLIX | 320×200 | AFLI on every 2nd line (2 colours per 8×2) plus 6 double-wide sprites underneath (columns 4–39) whose colours change every other line; sprites also cover the FLI-bug area | Paid, later |
| Sprite layers | — | 8 sprites of 24×21 (hires) or 12×21 (multicolour) pixels, reused down the screen; the time the video chip spends fetching them counts against each line's cycle budget | Paid, later |

Settings shared by every mode:

- **Video standard**: PAL (default) or NTSC. Pixels are about 0.94 as wide as tall on PAL and 0.75 on NTSC. A line takes 63 CPU cycles on PAL and 65 on NTSC, so timing-critical display programs need two variants.
- **Border colour.**
- **Palette**: Colodore (default), Pepto 2001, others (section 8).
- **VIC-II revision**: 9 brightness levels (default) or 5 (earliest chips).

## 5. Architecture

```
CameraC64 app (App/)             SwiftUI · AVFoundation · StoreKit 2 · PhotoKit · SwiftData
 ├─ C64Metal (to come)           Metal kernels: fast path for the live viewfinder,
 │                               tested to give the same output as C64Core
 └─ C64Core (Packages/C64Core)   plain Swift: palettes, modes, converter, renderer,
                                 display models, C64 file formats
C64/                             6502 display programs embedded in exported .prg files
Tools/                           c64conv CLI, VICE comparison tests, quality benchmark
```

### Core data model

- **`ModeSpec`**: a graphics mode described as data, an idea taken from Retropixels.
  - It contains a pixel grid, bits per pixel, and a list of colour maps. Each map has its own granularity (global, per line, or per W×H cell) and allowed values (0–15 or 0–7).
  - It also describes dead zones (the FLI bug), sprite layers and interlace frames.
  - One optimiser and one renderer work for every mode. Adding a mode means describing it and writing its display program.

  ```swift
  // Sketch
  let multicolorFLI = ModeSpec(grid: .init(width: 160, height: 200, pixelWidth: 2), bitsPerPixel: 2,
      maps: [.global(0...15),        // background register ($D021)
             .cell(4, 8, 0...15),    // colour memory
             .cell(4, 1, 0...15),    // screen memory, high nibble
             .cell(4, 1, 0...15)],   // screen memory, low nibble
      deadZone: 12)                  // FLI bug
  ```

- **`C64Frame`**: the memory image. It holds the bitmap or character set, screen memory banks, colour memory, register values, sprite data, per-line register writes, and a second frame for interlace modes.
- **Renderer**: turns a `C64Frame` into palette indices, exactly as the VIC-II displays it with our display programs.
- **`DisplayModel`**: turns palette indices into the RGB picture a viewer sees on the chosen monitor (section 7).
- **Exporters**: `.prg`, `.d64`, Koala, Art Studio, FLI/AFLI formats, PNG.

`C64Core` does not depend on UIKit, SwiftUI or Metal and takes plain pixel buffers, so it builds and tests with `swift test` on a Mac or on Linux.

## 6. Conversion engine

1. **Target.**
   - Crop the photo to the real screen shape: the display window is about 3:2 on PAL and 6:5 on NTSC.
   - Shrink it to the mode's grid by averaging in linear light, so each C64 pixel's target is the true average of the area it covers.
   - Then apply the brightness, contrast, saturation and gamma controls, plus optional sharpening.
2. **Colour distance** is measured in OKLab, a perceptual colour space. Faces and the main subject can optionally be weighted more heavily, using the Vision framework.
3. **Per-pixel cost table**: the distance from every pixel to each of the 16 colours.
4. **Exhaustive per-cell search**, which is optimal for the metric before dithering:
   - Hires: 120 colour pairs per 8×8 cell.
   - Multicolour:
     1. Score all 1,820 four-colour sets once per 4×8 cell.
     2. For each background candidate, keep each cell's best set containing it.
     3. The background with the lowest total wins, and each cell takes its best set containing that background.
   - FLI: for each 4×8 cell, try each of the 16 colour-memory values, with the best screen-memory pair on each line.
   - AFLI: 120 pairs per 8×1 strip.

   ```
   cost[p][c]  = distance(oklab(pixel p), oklab(colour c))           // 32,000 pixels × 16 colours
   for each cell, each 4-colour set S (1,820):
       score = Σ over the cell's 32 pixels of  min over c in S of cost[p][c]
       for each colour b in S:  best[cell][b] = min(best[cell][b], (score, S))
   background = the b with the lowest  Σ over cells of best[cell][b].score
   each cell  → best[cell][background].S
   ```

   A full multicolour screen is about 58 million small comparisons, which should take a few milliseconds on an iPhone GPU.
5. **Dithering-aware scoring.** A pixel can also be matched by mixing two of the set's colours, as in Yliluoma's ordered dithering for arbitrary palettes. Mixes are computed in linear light and compared in OKLab. The penalty for visible texture comes from the display model.
6. **Dithering.**
   - The viewfinder uses ordered dithering with a pattern fixed to the screen, so it stays stable between frames.
   - Captured photos use error diffusion restricted to each cell's colours, alternating "choose colours ↔ dither" two or three times.
7. **Harder modes** (interlace, NUFLI): there are too many combinations to try them all. Start from the per-cell solution and re-optimise one setting at a time until nothing improves.
8. **Live viewfinder.** A cell keeps the previous frame's colours unless the new ones are clearly better, which prevents flicker. Heavier modes may use a faster draft search in the viewfinder; its result is still legal C64 memory.
9. **Mono monitors** run the same search on brightness only. Within a group of equally bright colours, the converter picks whichever is legal for that cell (e.g. 0–7 in colour memory).

## 7. Display models ("monitors")

CRTs blend colours, and C64 artists exploit it:

- **Horizontally**, a TV carries colour at about 1.3 MHz while hires pixels run at about 7.9 MHz, so neighbouring pixels' colours smear together. Brightness stays sharper, especially on a monitor fed separate brightness and colour signals.
- **Vertically (PAL only)**, the PAL delay line averages each line's colour with the line above.
- **Only colour blends, not brightness.**
  - Two colours with the same brightness blend into a new, flicker-free tint. A colour paired with the grey of the same brightness gives a softer version of it.
  - With different brightness, the pattern stays visible as texture.
  - The 7 same-brightness pairs are blue/brown, red/dark grey, purple/orange, grey/light blue, green/light red, cyan/light grey and yellow/light green. The earliest chips have more.

The display model is used in two places: in the converter's mixing cost, and in the preview and "as on TV" export. The preview therefore shows what the picture was optimised for.

It works in the brightness/colour signal space the VIC-II outputs, which is the space the Colodore model is defined in:

1. blur colour horizontally
2. on PAL, average colour with the previous line
3. soften brightness on composite
4. convert to RGB

| Preset | Model |
|---|---|
| Sharp | No blending: HDMI output, emulators without CRT emulation |
| PAL TV (default) | Composite: colour blur, delay line, softened brightness |
| Commodore monitor | Separate brightness and colour: sharper brightness, delay line |
| NTSC TV | Colour blur, no delay line |
| Mono: green, amber, B&W | Brightness only |

The presets replace the old app's tints and are free. Scanlines, bloom, curvature and the power-off animation form a presentation layer on top. The model is an approximation, since real TVs vary. It is checked against VICE's PAL/CRT emulation and a real CRT, not by pixel-exact tests.

## 8. Palettes

- **Colodore** (Pepto, 2017) is the default. We implement the published algorithm, including its brightness, contrast and saturation settings.
- **Pepto 2001** is the palette the legacy app used; it is already in `C64Core`.
- Others can be added as needed, e.g. VICE's palettes.

## 9. Output and export

- **Pixel-exact PNG** at integer scale with square pixels. It is always kept in the gallery and available for export, and is never saved as JPEG.
- **"As on TV" image**, with the real pixel shape and the display model applied. This is what gets shared by default.
- **Interlace modes** export the blended picture plus the two frames, or an animated PNG at 50 Hz.
- **C64 files**:
  - a self-running `.prg` for every mode
  - a `.d64` disk image
  - Koala (`.kla`) and Art Studio (`.art`)
  - FLI/AFLI formats
- **Save and share**: saving to Photos (add-only), and the share sheet with custom file types.
- **Send to C64**: owners of an Ultimate 64, C64 Ultimate or Ultimate-II+ can send the `.prg` over Wi-Fi, through the device's REST API (`POST /v1/runners:run_prg`).

## 10. Verification and quality

- **Unit tests** (Swift Testing) for `C64Core`.
- **VICE golden tests.** For each mode:
  1. Export a `.prg`.
  2. Run `x64sc -autostart <prg> -limitcycles <n> -exitscreenshot <png>`, with CRT emulation off and a known palette.
  3. Map the screenshot back to palette indices, and require an exact match with our renderer. Interlace modes check two consecutive frames.

  These run on GitHub Actions macOS runners, which are free for public repositories, with VICE installed from Homebrew.
- **GPU = CPU.** The Metal kernels must give bit-identical results to `C64Core`.
- **Quality benchmark.**
  - A fixed photo set (faces, landscapes, low light, high contrast), scored after the display model, with side-by-side sheets.
  - Baselines: image64's CLI for the standard modes, NUFLIX Studio for NUFLI.
  - It runs on every converter change.
- **Real hardware spot checks**: an Ultimate 64 or C64 Ultimate, and a CRT for the display models.

## 11. The app

| Legacy feature | New app |
|---|---|
| Live C64 viewfinder | Metal viewfinder drawn from real C64 memory, 30–60 fps |
| Colour / B&W / amber / green monitors (paid) | Monitor presets (display models), free |
| Scanlines baked into the JPEG | CRT layer for display and sharing only; the pixel-exact PNG is always kept |
| Power-off animation, retro UI | SwiftUI and Metal shaders, new artwork |
| Flash, front/back camera | Same, plus lens and zoom |
| Discard / share / save | Same, plus C64 export and "send to C64" |
| In-app purchase | StoreKit 2; the old purchase is honoured |
| — | Photo-library import, mode picker, a strip showing the photo in every mode after capture, re-editing later (the gallery keeps the original photo, the settings and the C64 memory) |

**Screens**:
- **Camera**: viewfinder, mode and monitor pickers, shutter, flash, lens.
- **Review**: mode strip, tone controls, export.
- **Gallery.**
- **Settings**: video standard, palette, chip revision, border.
- **Store.**

**Platform**:
- On iPhone 16 and later, the Camera Control button cycles modes or monitors (`AVCaptureIndexPicker`).
- Standard iOS 26 styling for the gallery, settings and store; a custom C64/CRT look for the camera screen.
- **Privacy**: no analytics SDK (MetricKit for diagnostics), a privacy manifest, and camera and photo-add usage strings.

## 12. Monetization and App Store

- **Free**:
  - camera and gallery
  - all standard VIC-II modes: hires, multicolour, text/PETSCII, custom character sets
  - every monitor preset and every export
- **Paid**: one non-consumable "Advanced modes" unlock.
  - At launch: per-line background, FLI, AFLI, interlace/IFLI.
  - Later: NUFLI, sprite layers and future modes.
- **Earlier buyers**: the legacy `AXOLINK_C64_FILTERS` purchase unlocks "Advanced modes", checked through StoreKit 2's `Transaction.currentEntitlements`.
- **Open source with a paid unlock**: anyone can build the app with everything unlocked. The App Store purchase pays for convenience and supports the project.

Restoring the listing (the record still exists, confirmed September 2026):

1. Use the legacy bundle ID. The 2013 project builds as `com.camerac64`, derived from its target name; check that it matches the record.
2. Create version 3.0 (the last version shipped was 1.2) and upload a build.
3. Refresh the metadata (screenshots, App Privacy details, age rating, description) and add the new in-app purchase.
4. Submit. After approval, make the app available again under Pricing and Availability.

Until then, TestFlight cannot install builds of the removed-from-sale record. Development builds therefore go to a separate dev app, `com.camerac64.dev` (see [CI.md](CI.md)).

## 13. Tech stack

- **Language and tools**: Swift 6 language mode, SwiftUI, Swift Testing, Xcode 26, `swift format` for linting.
- **Target**: iOS 26 deployment target, iPhone only for now.
- **Project file**: generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. The `.xcodeproj` is not committed.
- **Apple frameworks**:
  - AVFoundation: `AVCaptureSession`, a video data output for the viewfinder, `AVCapturePhotoOutput` for stills.
  - Metal: compute kernels and `MTKView`, plus SwiftUI shader effects.
  - Vision, StoreKit 2, PhotoKit/PhotosUI, SwiftData, MetricKit.
- **6502 display programs**: written for KickAssembler (NUFLIX's display programs use its syntax) or ca65. They are assembled in CI and bundled as templates that the app fills with picture data.
- **No third-party runtime dependencies.**

## 14. Borrowing policy and sources

Rules:

- Ideas, hardware facts, file layouts and algorithms are free to use from anywhere. GPL code may be read to understand behaviour, but never copied.
- MIT code may be copied if its copyright notice is kept in the file and listed in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md), which the app shows in its acknowledgements.
- MPL-2.0 code may only be used as separate files, with any changes to them published.

| Project | Licence (checked September 2026) | What we take |
|---|---|---|
| [Retropixels](https://github.com/micheldebree/retropixels) | MIT | The mode-as-colour-maps idea behind `ModeSpec` |
| [NUFLIX Studio](https://github.com/cobbpg/nuflix-studio) | MIT | Its NUFLI/NUFLIX display programs (PAL and NTSC templates); a port of its layered optimiser and code generator; re-optimising a cell on edit; live preview in VICE through its binary monitor |
| [image64](https://github.com/nschneir/image64) | MIT | Ideas: preview drawn from the exported bytes, fixed tie-breaks, the self-relocating `.prg` layout. Its CLI is a benchmark baseline |
| [VICE](https://vice-emu.sourceforge.io/) | GPL-2.0-or-later | Test oracle and behaviour reference only; never shipped |
| [VirtualC64](https://github.com/dirkwhoffmann/virtualc64) | App GPL-3.0; emulator core MPL-2.0; CPU emulator (Peddle) MIT | Not needed; the only realistic option if we ever embed a real emulator |
| [C-swifty4](https://github.com/Sephiroth87/C-swifty4) | MIT | Avoid: unmaintained since 2020, and it ships Commodore's ROMs |
| [Colodore](https://www.colodore.com/), [Pepto](https://www.pepto.de/projects/colorvic/) | Published algorithm | Palette model |

## 15. Repository layout

```
README.md, LICENSE, THIRD_PARTY_NOTICES.md
project.yml               XcodeGen spec → CameraC64.xcodeproj (generated, not committed)
App/Sources/              the SwiftUI app
App/Resources/            asset catalog
App/Tests/                app tests
Packages/C64Core/         the core library and its tests
C64/                      6502 display programs
Tools/                    c64conv CLI, VICE comparison tests, quality benchmark
docs/                     this plan and design notes
```

## 16. Milestones

0. **Repository reset** (done):
   - legacy code tagged and removed, this plan, project skeleton
   - CI on GitHub Actions: Linux for `C64Core`, a macOS runner for the app
   - TestFlight uploads from CI, with Apple's cloud signing (first build uploaded September 2026)
   - Swift installed automatically in Claude Code web sessions, and a `CLAUDE.md` with the technical ways of working
1. **Foundation**:
   - `C64Core` palettes (Colodore), `ModeSpec` and `C64Frame`, and the renderer for the standard modes.
   - Koala, Art Studio, `.prg` and `.d64` writers.
   - The `c64conv` CLI and the VICE golden tests in CI.
2. **Converter**:
   - Hires and multicolour search, dithering-aware scoring, error diffusion, display models, and the quality benchmark.
   - Then the Metal kernels, verified identical.
3. **App at feature parity**:
   - camera and viewfinder
   - capture, review, save, share and export
   - gallery, monitors and CRT layer
   - photo import, and StoreKit 2 with the legacy entitlement

   Then release 3.0 on the restored listing.
4. **Advanced modes**, one at a time, each with its display program and VICE tests:
   1. per-line background
   2. FLI and AFLI
   3. interlace and IFLI
   4. NUFLI
   5. sprite layers

   The free character-set modes slot in alongside.

Later ideas: a constraint-aware pixel touch-up editor, an in-app emulator view, a Mac app.

## 17. Risks and open issues

- **Character ROM.** PETSCII mode needs the ROM character shapes, which are still under copyright. Either license them or offer only our own character sets.
- **Name and trademark.** The Commodore brand is active again (C64 Ultimate). Check "Camera C64" and the icon before resubmitting.
- **PAL/NTSC timing.** FLI and NUFLI display programs are timed to the exact cycle and need both variants. Ship PAL first.
- **Interlace preview.** iPhone screens can't refresh at exactly 50 Hz, so the preview shows the blended picture. The `.prg` is the real thing.
- **Display models are approximate.** They are validated against VICE and a CRT, not pixel for pixel.
- **NUFLI.** Aim to match NUFLIX Studio, not beat it.
- **Viewfinder performance** in heavier modes on the oldest supported iPhones: use the draft search in the viewfinder and the full search on capture.

## 18. References

- Christian Bauer, *The MOS 6567/6569 video controller (VIC-II) and its application in the Commodore 64* (1996): the reference for VIC-II timing, bad lines and FLI.
- [Codebase64](https://codebase64.org/): FLI, AFLI and raster routines.
- [NUFLI – C64-Wiki](https://www.c64-wiki.com/wiki/NUFLI); [Pushing the Boundaries of C64 Graphics with NUFLIX](https://cobbpg.github.io/articles/nuflix.html)
- [Colodore](https://www.colodore.com/); [Pepto: calculating the VIC-II palette](https://www.pepto.de/projects/colorvic/)
- [Old VIC-II colors and color blending](https://ilesj.wordpress.com/2016/03/30/old-vic-ii-colors-and-color-blending/); [Luma-driven graphics on the Commodore 64](https://kodiak64.com/blog/luma-driven-graphics-on-c64)
- [VICE testbench](https://vice-emu.pokefinder.org/wiki/Testbench)
- [Ultimate REST API](https://1541u-documentation.readthedocs.io/en/latest/api/api_calls.html)
- [Restore an app to the App Store](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/restore-an-app-to-the-app-store/); [App Store Improvements](https://developer.apple.com/support/app-store-improvements)
