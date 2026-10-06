# Camera C64 — user experience

_Agreed September 2026. This is a living document: update it when decisions change. What the app does and why is in [REWRITE_PLAN.md](REWRITE_PLAN.md)._

## 1. Principles

1. **The screen shows the whole C64 picture at its true shape.** It is never cropped to fill the phone, stretched or rotated. The 2013 app filled a 3:4 portrait frame with tall 2×4 blocks, which is roughly a multicolour screen turned on its side.
2. **The picture is upright when you shoot.** A phone photo taken sideways is fixed later by an orientation tag, but C64 memory has none. So the TV turns to stay upright whichever way the phone is held.
3. **A retro camera, not a modern camera app.** Like a Polaroid camera, it holds one shot at a time: no gallery, no importing photos. After the shot, its mode and monitor can still change; then it is shared, saved or sent to a C64, or the next shot replaces it. The camera screen's choices are only starting points, which keeps that screen simple.
4. **The 2013 app's features first, done authentically**, plus C64 files of the pictures. The rest can come in later versions (section 8).

## 2. The picture's shape

- A C64 picture is 320×200 pixels, each 0.94 as wide as tall on PAL, so the picture is 3:2. With the border a TV shows around it (384×272 pixels, as in VICE), it is about 4:3.
- The camera captures in the sensor's native 4:3 format, not 16:9, and the app crops the centre to 3:2:
  - With the phone held sideways, the crop uses 89% of the frame.
  - With the phone held upright, the frame is 3:4 and the crop is a band using 50% of it: the same scene, 1.33× closer. The 0.5× lens and zoom make up for it.
- Zoom costs almost nothing here: at 4×, a 12 MP photo still has 3 camera pixels per C64 pixel.
- Moving and zooming the crop after the shot, and photos from the library, which come in any shape, are for later versions (section 8).

## 3. The camera screen

A TV above a C64, as in the 2013 app, but with a TV of the right shape.

**Portrait**, from top to bottom:

1. a top bar: flash, the CRT switch, the app's badge, settings
2. the TV, across the full width: about 402×304 pt on an iPhone 17, with the picture at 335×224 pt (about 1 pt per C64 pixel)
3. zoom buttons (0.5×, 1×, 2×…)
4. the mode dial
5. the monitor bank
6. the shutter row: the last picture, the capture key, front/back camera

**Landscape: the TV turns in place.**

- The screen keeps its portrait layout, as Apple's Camera app does. The controls stay where they are, and their icons and labels turn upright.
- The TV turns to stay upright and grows to nearly the phone's height: about 516×390 pt on an iPhone 17, with the picture at 430×287 pt (1.3 pt per C64 pixel). The zoom buttons move onto its border.
- With the phone turned one way the controls are on the right; turned the other way, they are on the left.
- The screen follows how the phone is held even when rotation lock is on, as the Camera app does. The whole app can therefore stay in portrait.

**What the TV shows**:

- The live picture, drawn from real C64 memory through the chosen monitor, with its border. The border colour is automatic: it matches the picture's edges.
- At launch, a short CRT warm-up while the camera starts, so it costs no time: it ends with the camera's first frame.
- Tapping the badge switches the TV off, as the 2013 app's power bar did: the picture shrinks to a bright line, then to a dot, and fades, and the camera stops, which saves the battery. Any key, or the badge again, switches it back on, with the warm-up. (Still to come.)
- Without a camera (permission denied, or the Simulator): static, with an "Allow camera" button, which opens the app's page in Settings. Development builds also offer "Import a photo", so that the review can be tried without a camera. While another app or a call has the camera, static with "Camera in use".
- The front camera's pictures are mirrored, as a mirror shows the scene, in the viewfinder and the shot alike, so the shot is what the viewfinder showed.

## 4. Taking a picture

1. **Shoot.** The viewfinder runs the same conversion as the shot, so it shows what the shot will be. The shot converts the full-resolution photo, which is a little cleaner than a video frame. The finished picture fills in cell by cell on a cleared screen, in the order the C64 stores it. For the harder modes, such as IFLI and NUFLI, this also covers the seconds their extra passes take.
2. **Review.** The TV holds the finished picture, and the controls below switch to review (section 5). The capture key becomes the way back to the camera. It is one screen in two states, not a new screen.
3. **Keep it, or not.** The app holds one shot at a time. Until the next shot, or until the app is closed, the last picture in the shutter row opens it again. To keep it, share it, save it to Photos or send it to a C64; Delete discards it, as in the 2013 app. Nothing goes to Photos unless the user asks, or turns on a setting.

With Reduce Motion on, the warm-up and the fill-in are skipped.

## 5. Controls

**Camera**:

- Shutter: the capture key, the volume buttons, and a click of the Camera Control.
- Mode dial: swipe across the TV. Real names (Hires, Multicolour, PETSCII…), each with a one-line description. PETSCII comes twice: as PETSCII, with only the graphics characters, for the classic PETSCII look, and as BBS, with all of them, whose letters, digits and punctuation make pictures look like BBS art.
- Monitor bank: TV, Commodore monitor, Sharp, B&W, Amber, Green.
- The last picture, which opens it again.
- Flash, front/back camera, zoom (pinch, plus the lens buttons: 0.5×, 1×, 2× and each telephoto lens the phone has), the CRT switch, settings.
- The CRT switch shows the TV's tube: scanlines, glow and curvature, and on the amber and green monitors, a fading trail behind whatever moves in the viewfinder. It is presentation only (plan, section 7). Sharp is a flat screen, so it has none: there, the switch says so.
- Tap to focus and expose; drag up or down to set exposure, which matters a lot with only 9 brightness levels: two stops either way, in thirds. A tap sets it back to the camera's own.

**Review**, after a shot, or when the last picture is opened again:

- Mode strip: the photo in every mode of the dial.
- Monitor bank. Changing the monitor converts the picture again, for that monitor.
- The CRT switch stays in the top bar: it decides whether the picture as on TV, which is shared, shows the tube.
- Share, Save to Photos, Send to C64, Delete.
  - Share opens a menu: the picture as on TV first, then the pixel-exact PNG and the C64 files (section 6). Each opens the share sheet.
  - Save to Photos saves the picture as on TV, as a PNG.
  - Send to C64 appears once an Ultimate is set up. It runs the picture's `.prg` on the Ultimate's C64, through the Ultimate's REST API. Its first use triggers iOS's local-network permission prompt.
  - Delete discards the shot at once, as the 2013 app's Discard did, and goes back to the camera.
- Press and hold the TV to see the original photo.
- The capture key goes back to the camera.

**Settings**: saving every shot to Photos (turning it on asks for permission to add photos), the Ultimate's address and, if it has one, its network password (kept in the keychain), acknowledgements.

## 6. What gets shared and exported

- **As on TV**, shared by default: the real pixel shape, the monitor's display model, the CRT layer when it is on (never with Sharp), and the border, so about 4:3. The border makes it read as a C64 screen at a glance.
- **Pixel-exact PNG**: the 320 × 200 picture without its border, one pixel for each C64 pixel, in the palette's colours whatever the monitor. Its pixels are square, so it is 8:5, 7% wider than a PAL TV shows it. It is meant for C64 tools.
- **C64 files**: a `.prg` that shows the picture, a `.d64` disk image holding it, and for hires and multicolour pictures, their Art Studio and Koala files (plan, section 9).
  - On the disk, named CAMERA C64, the program takes the mode's name, and `LOAD"*",8` then `RUN` shows the picture.
- Files are named after the shot's mode and time, such as "C64 Multicolour 2026-10-06 21.04.12.prg"; the pixel-exact PNG adds "320x200".
- A picture made for a mono monitor is still colour data: its `.prg` shows odd colours on a colour TV. Warn at export, or have the converter prefer greys where it can.
- Idea: with the Sharp monitor, the as-on-TV image could stay pixel-exact by drawing each C64 pixel as a 15×16 block, which is 0.9375 as wide as tall, within 0.2% of PAL.

## 7. Look

- For now the camera screen is drawn in code: flat SwiftUI shapes in the 2013 app's colours (beige case, dark monitor, keys with LEDs).
- Its appearance lives in a few reusable styles (key, LED, case, TV), so a detailed skin can replace them later without touching layout or behaviour: gradients and shadows, Metal shaders for plastic and light, vector images for the badge.
- The 2013 artwork is the reference. It is at tag `legacy-1.2`, in `examples/SimplePhotoFilter/SimplePhotoFilter/`.
- C64-style text can use the character ROM's shapes, which the app includes for PETSCII mode (see the plan, section 17).
- Settings uses standard iOS 26 styling, as the gallery and store will.

## 8. Later

Version 3.0 leaves these out, to stay a simple, retro camera like the 2013 app. Each can come in a later version, some perhaps as part of the paid unlock (plan, section 12).

- **Gallery**: every shot kept, with its photo, settings and C64 memory, so that it can be reopened and changed at any time.
- **Photo import** from the library. Such photos come in any shape, so they open in Adjust's framing, centred on faces.
- **Adjust**: framing, tones and border after the shot. It is a third state of the camera screen, opened from the review, rather than a screen of its own:
  - The panel below the TV swaps for the tones (automatic by default; brightness, contrast, saturation) and the border colour.
  - Pinching and dragging the TV moves and zooms the crop, as if re-aiming the camera. In the review, those gestures stay free for seeing the pixels.
  - The picture redraws as the controls move, at viewfinder speed. Done goes back to the review, and Reset to automatic.
  - Adjustments belong to the shot, so every mode uses them, and the strip stays a fair comparison.
- **Advanced modes**, with the paid unlock: they show a lock in the dial and the strip, and tapping one opens the store.
- **Pinch to see the pixels** in the review, with an optional grid of colour cells.
- **Camera Control**: sliding on it changes the mode or the monitor.
- **More settings**: palette, chip revision, what sliding on the Camera Control changes, and restoring the purchase.
