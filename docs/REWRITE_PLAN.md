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
3. **Optimise for the chosen display.** Error is measured on the picture as the viewer will see it on the selected monitor (sharp, TV, mono…). The C64 data is equally legal either way.
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

Shared by every mode:

- **Video standard**: PAL only. Pixels are about 0.94 as wide as tall, a line takes 63 CPU cycles and the screen refreshes at 50 Hz.
  - Most C64 art and screenshots are PAL: the demo and art scenes are mostly European, and VICE emulates a PAL machine by default.
  - NTSC would need a second picture shape (6:5, with pixels 0.75 as wide as tall), a second palette and TV model, and a second version of every cycle-timed display program.
  - Programs for the standard modes still run on NTSC machines; those for FLI, NUFLI and the other cycle-timed modes do not display correctly there.
- **Border colour**: chosen per picture, automatic by default (it matches the picture's edges).
- **Palette**: Colodore (default), Pepto 2001, others (section 8).
- **VIC-II revision**: 9 brightness levels (default) or 5 (earliest chips).

## 5. Architecture

```
CameraC64 app (App/)             SwiftUI · AVFoundation · StoreKit 2 · PhotoKit · SwiftData
 └─ C64Core (Packages/C64Core)   plain Swift: palettes, modes, converter, renderer,
                                 display models, C64 file formats
C64/                             6502 display programs embedded in exported .prg files
Tools/                           c64conv CLI, VICE comparison tests, quality benchmark
```

There is one converter, and it runs on the CPU. The viewfinder and the shot both use it, so the viewfinder shows what the shot will produce. A Metal version of the search comes only if the speed benchmark calls for one (section 10).

### Core data model

- **`ModeSpec`**: a graphics mode described as data, an idea taken from Retropixels.
  - It has a pixel grid (320×200, or 160×200 double-wide pixels) and colour maps in pixel value order: a pixel with value v takes its colour from map v, as the VIC-II's bit patterns do.
  - Each map has a granularity (global or per W×H cell, later per line), its allowed colours (any, 0–7, or one of a few shared by the picture), and where the VIC-II reads it: a background register, a nibble of the video matrix, the colour RAM, or the extended colour mode's background selector.
  - Character modes add a limit on their own characters (256, or 64 in extended colour mode), or a fixed set such as the character ROM's.
  - Later modes will add dead zones (the FLI bug), sprite layers and interlace frames.
  - One encoder turns any `ModePicture` (the converter's result: every pixel's value and every map's colours) into a `C64Frame`, and rejects pictures that break the mode's limits. One optimiser will search any mode. Adding a mode means describing it and writing its display program.

  ```swift
  static let multicolor = ModeSpec(
      graphicsMode: .multicolorBitmap, width: 160, height: 200, pixelWidth: 2,
      maps: [
          ColorMap(.global, .any, .backgroundColor(0)),                   // 00: $D021
          ColorMap(.cell(width: 4, height: 8), .any, .screenHighNibble),  // 01
          ColorMap(.cell(width: 4, height: 8), .any, .screenLowNibble),   // 10
          ColorMap(.cell(width: 4, height: 8), .any, .colorRAM),          // 11
      ], pixels: .bitmap)
  ```

- **`C64Frame`**: the memory image: the 16 KB the VIC-II reads, the colour RAM, the graphics mode, the memory pointers (`$D018`), and the border and background colours.
  - It holds RAM only, never the character ROM. A PETSCII frame instead says that the VIC-II sees the ROM's characters at `$1000`–`$1FFF`, where the C64 shows them in banks 0 and 2, and keeps its own memory out of that area.
  - Later modes will add sprite data, per-line register writes, and a second frame for interlace.
- **Renderer** (`VICII`): turns a `C64Frame` into colour indices exactly as the VIC-II displays it with our display programs: 25 rows of 40 columns, no scrolling, and the border, over the 384×272 area VICE shows with normal borders.
- **`DisplayModel`**: turns colour indices into the RGB picture a viewer sees on the chosen monitor (section 7).
- **Exporters**: `.prg`, `.d64`, Koala, Art Studio, FLI/AFLI formats, PNG.
- **Display programs**: `C64/viewer.s` shows a frame in any standard mode.
  - The `.prg` holds a `SYS` line, the viewer, its parameters, and only the memory the picture uses, so a multicolour picture takes about 10 KB, like a Koala file.
  - The viewer copies each block into the bank at `$C000`. There the VIC-II sees no character ROM, and a program loaded at `$0801` cannot overlap it.
  - A PETSCII picture goes into the bank at `$8000` instead, where the VIC-II sees the C64's own character ROM at `$9000`, so its file holds only the character codes and colours, about 2 KB.
  - It then sets the registers, and resets the C64 when a key is pressed.

`C64Core` does not depend on UIKit, SwiftUI or Metal and takes plain pixel buffers, so it builds and tests with `swift test` on a Mac or on Linux.

## 6. Conversion engine

1. **Target.**
   - Crop the photo to the real screen shape: the display window is about 3:2 (see [UX.md](UX.md) for how the camera frames it).
   - Shrink it to the mode's grid by averaging in linear light, so each C64 pixel's target is the true average of the area it covers.
   - Then apply the brightness, contrast, saturation and gamma controls, plus optional sharpening, on OKLab's lightness and colourfulness. Automatic tones, the default, first stretch the darkest and brightest 0.5% of the pixels to black and white, by at most 2.5 times.
2. **Colour distance** is measured in OKLab, a perceptual colour space. Faces and the main subject can optionally be weighted more heavily, using the Vision framework.
3. **Per-pixel cost table**: the squared distance from every pixel to each of the 16 colours, and to each pair's mixes (step 5), as 16-bit numbers.
4. **Exhaustive per-cell search**, which is optimal for the metric before dithering:
   - Hires: 120 colour pairs per 8×8 cell.
   - Multicolour:
     1. Score all 1,820 four-colour sets once per 4×8 cell.
     2. For each background candidate, keep each cell's best set containing it.
     3. The background with the lowest total wins, and each cell takes its best set containing that background.
   - PETSCII: for each background, each 8×8 cell tries the 256 characters of a character set in each of the other 15 colours, and the background with the lowest total wins, as in multicolour. Both character sets are tried, and the better one kept.
     - The characters' patterns are PETSCII's only dithering, so they are judged by how they look from a distance through the monitor. Pixel by pixel, many would score alike, and the search would pick noisy ones.
     - A cell's error is the squared OKLab distance between the cell as the monitor shows it and its target, both blurred as the eye sees them, within the cell: brightness by 1 pixel and colour by 2, as in the quality benchmark.
     - Done plainly, that is about 30 times the work of hires. Instead, the converter first fits each cell's target with a small linear model: its lightness as a constant plus a multiple of the character's pattern, blurred as the monitor and the eye blur brightness, and its colour likewise, with the pattern blurred as they blur colour. Scoring a character in a pair of colours then takes 6 multiplications, 2 on a black-and-white monitor, and the 512 characters of both sets have only 153 different patterns, counting a character and its inverse as one.
     - The model picks the set and the background. Each cell's character and colour are then exact: a bound on how far the model can be off rules out all but about a dozen of the cell's 3,840 choices, and those are scored exactly. So every cell gets the best character and colour for the chosen set and background, which the tests check by trying them all.
     - Judged this way, about half the cells take letters, digits or punctuation, which makes pictures look like BBS art. A setting keeps to the graphics characters instead, for the classic PETSCII look: the 64 of the upper case set (`$40`–`$7F`), the space, and their reverses, 130 characters with 60 patterns. Those pictures score about 8% worse in the quality benchmark, and convert in half the time.
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

   With mixes (step 5), each set takes the minimum over its 6 pairs, which include the single colours, so a full multicolour screen takes up to 350 million small comparisons, fewer as sets share pairs. The loops run over plain buffers, which the compiler vectorises, a row of cells per core: with the cost table, a conversion takes about 20 ms on four 2.1 GHz Xeon cores. The speed benchmark measures the phones (section 10).
5. **Dithering-aware scoring.** A pixel can also be matched by mixing two of the set's colours, as in Yliluoma's ordered dithering for arbitrary palettes: a 4×4 Bayer pattern gives 15 mixes per pair, from 1/16 to 15/16.
   - A mix is what the monitor shows of the pattern, averaged in linear light, as the eye does from a distance. On a sharp display that is the two colours mixed in linear light. A TV blends colour before its gamma, so the mix differs, and the converter uses the TV's.
   - Its cost adds the texture the pattern leaves on that monitor, as the mean squared OKLab distance of its pixels from the mix, times 1 minus the dithering setting. On a TV, colours of the same brightness mix with almost no texture.
   - Dithering defaults to 0.85, chosen with the quality benchmark: its score improves up to 0.95, but close up such pictures start to scatter stray dots.
6. **Dithering** is ordered, with a pattern fixed to the screen, in the viewfinder and in the shot alike.
   - It stays stable from frame to frame, it is the classic C64 look, and the scoring in step 5 is designed around it.
   - Error diffusion restricted to each cell's colours may come later as an optional look in Edit, if the quality benchmark shows a clear gain.
7. **Harder modes** (interlace, NUFLI, custom character sets): there are too many combinations to try them all. Start from the per-cell solution and re-optimise one setting at a time until nothing improves. The viewfinder shows the starting solution; the shot runs the refinement passes.
8. **Live viewfinder.** The viewfinder runs the same converter as the shot, on video frames. A cell keeps the previous frame's colours, and in PETSCII its character, unless the new ones are clearly better, which prevents flicker: unless the new best set scores more than a twelfth lower, and the background unless the new one's total is more than a thirty-second lower. The margins will be tuned on real video in milestone 3.
9. **Mono monitors** run the same search on brightness only, with one colour per brightness, so 9 instead of 16. Within a group of equally bright colours, the converter picks a grey where there is one, so the picture also looks right on a colour TV, and otherwise whichever is legal for that cell (e.g. 0–7 in colour memory).
10. **Border**: the colour most common along the picture's edges, unless the user picks one.

## 7. Display models ("monitors")

CRTs blend colours, and C64 artists exploit it:

- **Horizontally**, a TV carries colour at about 1.3 MHz while hires pixels run at about 7.9 MHz, so neighbouring pixels' colours smear together. Brightness stays sharper, especially on a monitor fed separate brightness and colour signals.
- **Vertically**, the PAL delay line averages each line's colour with the line above.
- **Only colour blends, not brightness.**
  - Two colours with the same brightness blend into a new, flicker-free tint. A colour paired with the grey of the same brightness gives a softer version of it.
  - With different brightness, the pattern stays visible as texture.
  - The 7 same-brightness pairs are blue/brown, red/dark grey, purple/orange, grey/light blue, green/light red, cyan/light grey and yellow/light green. The earliest chips have more.

The display model is used in two places: in the converter's mixing cost, and in the preview and "as on TV" export. The preview therefore shows what the picture was optimised for.

It works in the brightness/colour signal space the VIC-II outputs, which is the space the Colodore model is defined in:

1. blur colour horizontally
2. average colour with the previous line (the PAL delay line)
3. soften brightness on composite
4. convert to RGB

| Preset | Model |
|---|---|
| Sharp | No blending: HDMI output, emulators without CRT emulation |
| TV (default) | Composite: colour blur, delay line, softened brightness |
| Commodore monitor | Separate brightness and colour: sharper brightness, delay line |
| Mono: green, amber, B&W | Brightness only, in the phosphor's colour |

The presets replace the old app's tints and are free. Scanlines, bloom, curvature and the power-off animation form a presentation layer on top. The model is an approximation, since real TVs vary. It is checked against VICE's PAL/CRT emulation and a real CRT, not by pixel-exact tests:

- The blurs are Gaussian, as wide as those of VICE's PAL renderer with its default settings: brightness over 3 pixels weighted 1/8, 3/4, 1/8 (a standard deviation of 0.5 pixels), colour over 4 (1.1 pixels). That comparison is with VICE's source: its screenshots are taken before the CRT emulation.
- Palettes other than Colodore's get the signals a PAL monitor would turn into their colours.
- The check against a real CRT is still to do.

## 8. Palettes

- **Colodore** (Pepto, 2017) is the default. We implement the published algorithm, including its brightness, contrast and saturation settings.
  - Its defaults give the published palette.
  - VICE's `colodore.vpl` is the same model at brightness 47 and saturation 70; the tests check both.
- **Pepto 2001** is the palette the legacy app used; it is already in `C64Core`.
- Others can be added as needed, e.g. VICE's palettes.

## 9. Output and export

- **Pixel-exact PNG** at integer scale with square pixels. It is always kept in the gallery and available for export, and is never saved as JPEG.
- **"As on TV" image**, with the real pixel shape, the display model and the border, so about 4:3. This is what gets shared by default.
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
  2. Run `x64sc -autostart <prg> -limitcycles <n> -exitscreenshot <png>`, with CRT emulation off, normal borders, and our palette with VICE's colour settings neutral, so VICE shows each colour exactly.
  3. Map the screenshot back to palette indices, and require an exact match with our renderer over the whole 384×272 screen, border included. Interlace modes check two consecutive frames.

  The standard modes are checked with random pictures (every colour, bit pattern and cell), with memory layouts under the I/O area and the KERNAL, with PETSCII pictures in both character sets shown with the C64's own ROM in place, and with a `.d64` loaded through an emulated 1541. A test also checks that `C64Core`'s character ROM is VICE's.

  They are Swift tests in `Tools/`, which run wherever `x64sc` is found:
  - on GitHub Actions macOS runners, which are free for public repositories, with VICE installed from Homebrew
  - in Claude Code web sessions, after `Tools/install-vice.sh` builds VICE without a user interface
- **Speed benchmark.** A hidden screen in TestFlight builds (Settings, Development) times each mode's conversion on the phone it runs on; `c64conv speed` runs the same measurement elsewhere.
  - It times each stage of a viewfinder frame from a 1920×1440 camera frame: the target, the conversion, the rendering and the display model, for hires, multicolour and PETSCII on a TV, a sharp display and a black-and-white monitor.
  - A viewfinder frame must take well under 33 ms on the oldest supported iPhone (iPhone 11).
  - On an iPhone 17 Pro (6 cores, iOS 27), a colour frame takes 9.5 to 9.9 ms, 7.7 to 7.9 of them in the conversion, and a black-and-white one 4.0 to 4.6 ms, in hires or multicolour. PETSCII is still to be timed on a phone.
  - On four 2.1 GHz Xeon cores, whose times vary more from run to run, a colour frame takes 17 to 27 ms in hires or multicolour and 20 to 32 ms in PETSCII, and a black-and-white one 8 to 13 ms. Making a PETSCII converter takes another 20 to 30 ms, 8 in black and white, for its tables of how the characters look on the monitor.
  - So the converter stays on the CPU for now. The oldest phones are still to be measured: going by published CPU benchmarks, an iPhone 11 is 2.5 to 3 times slower than an iPhone 17 Pro, which would put a colour frame at about 25 to 30 ms. The viewfinder's battery use is measured in milestone 3.
  - If the CPU can't keep up, or drains the battery, a Metal version of that search replaces the CPU one in the viewfinder. It must give bit-identical results to `C64Core`, so the viewfinder still shows what the shot will produce.
- **Quality benchmark** (`c64conv benchmark`, see `Tools/README.md`).
  - A chart of every hue, the app's sample picture, and ten photos from Kodak's Lossless True Color Image Suite: faces, landscapes, high contrast, fine detail, and one darkened by 2.5 stops for low light. They are downloaded, with pinned checksums, rather than kept in the repository.
  - Each picture is scored as its monitor shows it: the mean OKLab distance from the photo after blurring both as the eye does, brightness less than colour, as in S-CIELAB. A page shows every picture next to its photo.
  - `Tools/Benchmark/scores.txt` holds the scores, and CI fails when they get worse, on every push.
  - Baselines: image64's CLI for the standard modes, at a fixed version, on CI's macOS runner; NUFLIX Studio for NUFLI.
  - At the end of milestone 2, image64's pictures, with its default settings (Colodore and Floyd–Steinberg dithering), score 4.35 on average, and ours 3.46.
    - Ours score better on every hires picture, on every monitor, and on the black-and-white monitor, which image64 does not convert for.
    - In multicolour on the colour monitors, the two are about even on the photos: image64 is ahead on four or five of the eleven, depending on the monitor.
  - PETSCII pictures score 5.06 on average, or 5.45 with only the graphics characters, against 3.50 for hires and 3.42 for multicolour: with one colour per cell and fixed characters, they are coarser. image64 has no PETSCII mode, so there is no baseline for it yet.
- **Real hardware spot checks**: an Ultimate 64 or C64 Ultimate, and a CRT for the display models.

## 11. The app

How the app looks and behaves, screen by screen, is in [UX.md](UX.md).

| Legacy feature | New app |
|---|---|
| Live C64 viewfinder | Viewfinder drawn from real C64 memory by the same converter as the shot, at up to 30 fps |
| Colour / B&W / amber / green monitors (paid) | Monitor presets (display models), free |
| Scanlines baked into the JPEG | CRT layer for display and sharing only; the pixel-exact PNG is always kept |
| Power-off animation, retro UI | SwiftUI and Metal shaders; drawn in code first, detailed artwork later |
| Flash, front/back camera | Same, plus lens and zoom |
| Discard / share / save | Every shot is kept in the gallery; share, save to Photos, C64 export, "send to C64" and delete |
| In-app purchase | StoreKit 2; the old purchase is honoured |
| — | Photo-library import, mode picker, a strip showing the photo in every mode after capture, re-editing later (the gallery keeps the original photo, the settings and the C64 memory) |

**Screens**:
- **Camera**: viewfinder, mode and monitor pickers, shutter, flash, lens.
- **Review**: the camera screen after a shot, also opened from the gallery: mode strip, tone controls, export.
- **Gallery.**
- **Settings**: palette, chip revision, and a few app options.
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
  - Metal: SwiftUI shader effects for the CRT layer, and compute kernels only if the speed benchmark calls for them (section 10).
  - Vision, StoreKit 2, PhotoKit/PhotosUI, SwiftData, MetricKit.
- **6502 display programs**: written for ca65 (cc65), which is open source and packaged for apt and Homebrew.
  - `C64/build.sh` assembles them into `C64Core` as Swift byte arrays, which the app fills with picture data, and CI checks that the result is up to date.
  - NUFLIX's display programs use KickAssembler's syntax; they will be ported when milestone 4 needs them.
- **No third-party runtime dependencies.**

## 14. Borrowing policy and sources

Rules:

- Ideas, hardware facts, file layouts and algorithms are free to use from anywhere. GPL code may be read to understand behaviour, but never copied.
- MIT code may be copied if its copyright notice is kept in the file and listed in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md), which the app shows in its acknowledgements.
- MPL-2.0 code may only be used as separate files, with any changes to them published.

| Project | Licence (checked September 2026) | What we take |
|---|---|---|
| [Retropixels](https://github.com/micheldebree/retropixels) | MIT | The mode-as-colour-maps idea behind `ModeSpec` |
| [NUFLIX Studio](https://github.com/cobbpg/nuflix-studio) | MIT | Its NUFLI/NUFLIX display programs (the PAL templates); a port of its layered optimiser and code generator; re-optimising a cell on edit; live preview in VICE through its binary monitor |
| [image64](https://github.com/nschneir/image64) | MIT | Ideas: preview drawn from the exported bytes, fixed tie-breaks, the self-relocating `.prg` layout. Its CLI is a benchmark baseline |
| [VICE](https://vice-emu.sourceforge.io/) | GPL-2.0-or-later | Test oracle and behaviour reference only; never shipped |
| [VirtualC64](https://github.com/dirkwhoffmann/virtualc64) | App GPL-3.0; emulator core MPL-2.0; CPU emulator (Peddle) MIT | Not needed; the only realistic option if we ever embed a real emulator |
| [C-swifty4](https://github.com/Sephiroth87/C-swifty4) | MIT | Avoid: unmaintained since 2020, and it ships Commodore's ROMs |
| [Colodore](https://www.colodore.com/), [Pepto](https://www.pepto.de/projects/colorvic/) | Published algorithm | Palette model |
| Commodore 64 character ROM (901225-01) | None: claimed by Amiga Corporation, licensed to Cloanto; not protected in the US (section 17) | Its character shapes, for PETSCII and the app's C64-style text |

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
docs/                     this plan, the UX (UX.md) and design notes
```

## 16. Milestones

0. **Repository reset** (done):
   - legacy code tagged and removed, this plan, project skeleton
   - CI on GitHub Actions: Linux for `C64Core`, a macOS runner for the app
   - TestFlight uploads from CI, with Apple's cloud signing (first build uploaded September 2026)
   - Swift installed automatically in Claude Code web sessions, and a `CLAUDE.md` with the technical ways of working
1. **Foundation** (done):
   - `C64Core` palettes (Colodore), `ModeSpec` and `C64Frame`, and the renderer for the standard modes.
   - Koala, Art Studio, `.prg` and `.d64` writers, and the standard modes' display program.
   - The `c64conv` CLI and the VICE golden tests in CI.
2. **Converter** (done, but for measuring the oldest phones):
   - Hires and multicolour search, dithering-aware scoring, ordered dithering, display models, and the quality benchmark, in CI.
   - The app shows the sample photo converted in hires and multicolour, through the display models; PETSCII, FLI and AFLI keep sample pictures until their converters come (PETSCII's came in milestone 3).
   - The speed benchmark's screen is in TestFlight builds; its results on real iPhones decide whether any search needs a Metal version. On an iPhone 17 Pro, a colour viewfinder frame takes under 10 ms, so there is none for now (section 10).
3. **App at feature parity**:
   - PETSCII first, since it can all be checked without a phone (done, but for timing it on phones):
     - the character ROM's shapes in `C64Core`, in one file with its own notice (section 17)
     - the converter (section 6)
     - a viewer that leaves the VIC-II on the C64's own character ROM, so exported files hold only character codes and colours
     - PETSCII in the quality and speed benchmarks and the VICE tests, and in the app in place of its sample picture
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

- **Character ROM.** PETSCII mode needs the character ROM's shapes, and so does C64-style text in the app. We ship them, relying on US law (decided October 2026).
  - The character ROM holds no code, only the shapes, so a redrawn copy would be the same bytes. In the US, typefaces can't be copyrighted (37 CFR 202.1(e)), and the Copyright Office treats a bitmap font as data showing a typeface, which can't be registered either.
  - Elsewhere it is less clear. France protects original typographic works (CPI L112-2), and [Cloanto](https://www.c64forever.com/kb/13-122) says the C64 ROMs belong to Amiga Corporation, which licenses them to Cloanto, with no exception for the character ROM. We are asking Cloanto for written permission, which would settle it everywhere.
  - The shapes live in one file in `C64Core`, `CharacterROM.swift`, with their own notice and outside the MIT licence, so they are easy to replace. The KERNAL and BASIC ROMs are code and never enter the repository.
  - Exported files never contain the shapes: PETSCII's viewer points the VIC-II at the C64's own character ROM, in the bank at `$8000`, instead of copying the characters.
- **Name and trademark.** The Commodore brand is active again (C64 Ultimate). Check "Camera C64" and the icon before resubmitting.
- **PAL only.** Owners of NTSC machines can still view the standard modes, but not FLI, NUFLI or the other cycle-timed modes (section 4).
- **Interlace preview.** iPhone screens can't refresh at exactly 50 Hz, so the preview shows the blended picture. The `.prg` is the real thing.
- **Display models are approximate.** They are validated against VICE and a CRT, not pixel for pixel.
- **NUFLI.** Aim to match NUFLIX Studio, not beat it.
- **Viewfinder speed and battery life** on the oldest supported iPhones, with the converter on the CPU. The speed benchmark shows early whether some searches need a Metal version (section 10). An iPhone 17 Pro makes a colour frame in under 10 ms, less than a third of the 33 ms of 30 fps, but keeps all six cores busy while it does; an iPhone 11, with 2 fast and 4 slow cores, may only just keep up.

## 18. References

- Christian Bauer, *The MOS 6567/6569 video controller (VIC-II) and its application in the Commodore 64* (1996): the reference for VIC-II timing, bad lines and FLI.
- [Codebase64](https://codebase64.org/): FLI, AFLI and raster routines.
- [NUFLI – C64-Wiki](https://www.c64-wiki.com/wiki/NUFLI); [Pushing the Boundaries of C64 Graphics with NUFLIX](https://cobbpg.github.io/articles/nuflix.html)
- [Colodore](https://www.colodore.com/); [Pepto: calculating the VIC-II palette](https://www.pepto.de/projects/colorvic/)
- [Old VIC-II colors and color blending](https://ilesj.wordpress.com/2016/03/30/old-vic-ii-colors-and-color-blending/); [Luma-driven graphics on the Commodore 64](https://kodiak64.com/blog/luma-driven-graphics-on-c64)
- [VICE testbench](https://vice-emu.pokefinder.org/wiki/Testbench)
- [Ultimate REST API](https://1541u-documentation.readthedocs.io/en/latest/api/api_calls.html)
- [Restore an app to the App Store](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/restore-an-app-to-the-app-store/); [App Store Improvements](https://developer.apple.com/support/app-store-improvements)
