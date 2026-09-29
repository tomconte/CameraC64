# Camera C64 — user experience

_Agreed September 2026. This is a living document: update it when decisions change. What the app does and why is in [REWRITE_PLAN.md](REWRITE_PLAN.md)._

## 1. Principles

1. **The screen shows the whole C64 picture at its true shape.** It is never cropped to fill the phone, stretched or rotated. The 2013 app filled a 3:4 portrait frame with tall 2×4 blocks, which is roughly a multicolour screen turned on its side.
2. **The picture is upright when you shoot.** A phone photo taken sideways is fixed later by an orientation tag, but C64 memory has none. So the TV turns to stay upright whichever way the phone is held.
3. **Shoot now, decide later.** The gallery keeps the original photo, the settings and the C64 memory, so mode, monitor, framing, tones and border can all change after the shot. The camera screen's choices are only starting points, which keeps that screen simple.

## 2. The picture's shape

- A C64 picture is 320×200 pixels, each 0.94 as wide as tall on PAL, so the picture is 3:2. With the border a TV shows around it (384×272 pixels, as in VICE), it is about 4:3.
- The camera captures in the sensor's native 4:3 format, not 16:9, and the app crops the centre to 3:2:
  - With the phone held sideways, the crop uses 89% of the frame.
  - With the phone held upright, the frame is 3:4 and the crop is a band using 50% of it: the same scene, 1.33× closer. The 0.5× lens and zoom make up for it.
- Zoom costs almost nothing here: at 4×, a 12 MP photo still has 3 camera pixels per C64 pixel.
- The crop can be moved and zoomed after the shot. Photos imported from the library, which come in any shape, always open in this framing step, centred on faces.

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
- At launch, a short CRT warm-up while the camera starts, so it costs no time.
- Without a camera (permission denied, or the Simulator): static, with "Import a photo" and "Allow camera" buttons.

## 4. Taking a picture

1. **Shoot.** The viewfinder runs the same conversion as the shot, so it shows what the shot will be. The shot converts the full-resolution photo, which is a little cleaner than a video frame. The finished picture fills in cell by cell on a cleared screen, in the order the C64 stores it. For the harder modes, such as IFLI and NUFLI, this also covers the seconds their extra passes take.
2. **Review.** The TV holds the finished picture, and the controls below switch to review (section 5). The capture key becomes the way back to the camera. It is one screen in two states, not a new screen.
3. **Keep.** Every shot goes into the app's gallery. Nothing goes to Photos unless the user asks, or turns on a setting. Delete replaces the 2013 app's discard.

With Reduce Motion on, the warm-up and the fill-in are skipped.

## 5. Controls

**Camera**:

- Shutter: the capture key, the volume buttons, and a click of the Camera Control.
- Mode dial: swipe on the TV, or slide on the Camera Control. Real names (Hires, Multicolour, PETSCII, FLI…), each with a one-line description. Paid modes show a lock.
- Monitor bank: TV, Commodore monitor, Sharp, B&W, Amber, Green.
- The last picture, which opens the gallery.
- Flash, front/back camera, zoom (pinch, plus the lens buttons), the CRT switch (scanlines, glow and curvature; presentation only), settings.
- Tap to focus and expose; drag to set exposure, which matters a lot with only 9 brightness levels.

**Review**, after a shot or when a picture is opened from the gallery:

- Mode strip: the photo in every mode. Paid modes show their result with a lock; tapping one opens the store.
- Monitor bank. Changing the monitor converts the picture again, for that monitor.
- Share, Save to Photos, Edit, Send to C64, Delete.
  - Edit: framing, tones (automatic by default), border colour, and C64 file export (`.prg` first).
  - Send to C64 appears once an Ultimate is set up. Its first use triggers iOS's local-network permission prompt.
- Press and hold the TV to see the original photo. Pinch to see the pixels, with an optional grid of colour cells.
- The capture key goes back to the camera.

**Settings**: palette, chip revision, saving every shot to Photos, the Ultimate's address, Camera Control behaviour, restoring the purchase, acknowledgements.

## 6. What gets shared and exported

- **As on TV**, shared by default: the real pixel shape, the monitor's display model, the CRT layer when it is on, and the border, so about 4:3. The border makes it read as a C64 screen at a glance.
- **Pixel-exact PNG**: square pixels, so 8:5, 7% wider than a PAL TV shows it. It is meant for C64 tools.
- **C64 files**: see the plan, section 9.
- A picture made for a mono monitor is still colour data: its `.prg` shows odd colours on a colour TV. Warn at export, or have the converter prefer greys where it can.
- Idea: with the Sharp monitor, the as-on-TV image could stay pixel-exact by drawing each C64 pixel as a 15×16 block, which is 0.9375 as wide as tall, within 0.2% of PAL.

## 7. Look

- For now the camera screen is drawn in code: flat SwiftUI shapes in the 2013 app's colours (beige case, dark monitor, keys with LEDs).
- Its appearance lives in a few reusable styles (key, LED, case, TV), so a detailed skin can replace them later without touching layout or behaviour: gradients and shadows, Metal shaders for plastic and light, vector images for the badge.
- The 2013 artwork is the reference. It is at tag `legacy-1.2`, in `examples/SimplePhotoFilter/SimplePhotoFilter/`.
- C64-style text needs a font we have the rights to (see the character ROM in the plan, section 17).
- The gallery, settings and store use standard iOS 26 styling.
