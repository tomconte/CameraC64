# Design

Vector redraws of the camera screen's elements, in the spirit of the 2013 app's artwork (tag `legacy-1.2`, in `examples/SimplePhotoFilter/SimplePhotoFilter/`), to edit by hand in Inkscape or any other SVG editor, and to carry into the app (`docs/UX.md`, section 7).

## The files

| File | What | Size (pt) |
|---|---|---|
| `svg/capture-up.svg`, `svg/capture-down.svg` | The capture key, up and pressed, with its label for reference | 135 × 72, as the 2013 files at @1x |
| `svg/monitor-key-up.svg`, `svg/monitor-key-down.svg` | A monitor key, up, and pressed for the monitor chosen | 36 × 36, the face 30 square |
| `svg/led-off.svg`, `svg/led-on.svg` | A monitor's lamp, off and lit | 22 × 22, the lamp 10 across |
| `svg/monitor-bank.svg` | The camera's monitor bank on an iPhone 17, with the TV chosen: the keys and lamps in place, for reference | 402 × 166 |
| `svg/badge.svg` | The Camera C64 badge, from the 2013 title bar | 128 × 20, the badge 122 × 17 |
| `svg/action-share-up.svg` and `-down`, and the same for `save`, `send` and `delete` | The review's actions, up and pressed. Share is green and Delete red, as the 2013 app's Share and Discard were; Save takes the badge's rainbow blue, and Send to C64 its orange | 60 × 52, the key 52 × 42 |
| `svg/flip-key-up.svg`, `svg/flip-key-down.svg` | The key that turns the camera round | 64 × 66, the key 56 square |
| `svg/small-key-flash-up.svg` and `-down`, and the same for `crt` and `settings` | The small keys beside the TV in landscape, with the lamp the app puts on flash and CRT, for reference | 42 × 52, the key 34 × 42 |
| `svg/monitor-key-wide-up.svg`, `svg/monitor-key-wide-down.svg` | A monitor key in landscape, on which the app writes the monitor's lamp and name | 62 × 54, the key 54 × 44 |
| `svg/toggle-on.svg`, `svg/toggle-off.svg` | The 2013 app's switch, for flash and the CRT layer | 50 × 22 |
| `svg/zoom-button-up.svg`, `svg/zoom-button-down.svg` | A zoom button on the TV's border, on which the app writes its value | 40 × 40, the button 34 across |
| `svg/last-picture-frame.svg` | The frame round the last picture, whose window the app fills | 64 × 64, the frame 56 square |

### Mockups

The elements put together as the app lays out the camera screen today, on an iPhone 17, to judge the whole before it is coded:

| File | What | Size (pt) |
|---|---|---|
| `svg/mockup-portrait-live.svg` | The phone upright, live: the title bar with the badge, the flash and CRT switches and settings; the TV; zoom, the mode dial and the monitor bank; the last picture, the capture key and the flip key. The C64's vent runs across the top and behind the shutter row | 402 × 874 |
| `svg/mockup-portrait-review.svg` | The phone upright, in a review: the shot in every mode, the monitors, the four actions, and the capture key, which goes back to the camera | 402 × 874 |
| `svg/mockup-landscape-live.svg` | The phone held sideways, its top to the left: the TV between the two columns, the capture key on the right, the vent behind both | 874 × 402 |
| `pictures/*.png` | The app's sample photo as `c64conv` converts it in each mode, as the TV shows it, border included | 384 × 272 |

## How they are drawn

- 1 unit = 1 point, so sizes read directly.
- No SVG filters. Shadows, bevels and engravings are ordinary shapes: translucent copies, gradients, and bands clipped to a hollow. Every editor keeps them as objects to select and recolour, and so does Xcode's asset catalog.
- Each part is a named group. Inkscape shows the top-level ones as layers, labelled in French.
- Each element sits on the case, or the panel, in a layer marked "référence, à masquer": hide it before exporting the element alone.
- No words in the elements: the app writes its labels. The layers that show them, for reference, are marked "écrit par le code dans l'appli". They use FreeSans, a free Helvetica, where it is installed, and Helvetica or Arial elsewhere.
- The grooves on the mockups' case recall the vent along the back of the C64's breadbin case: each is a dark groove over a line of light, and they stop short of each element and of the screen's edge, as the C64's stop round its badge and its power lamp. The script cuts them round each element (`vent`), so after moving an element, regenerate the mockup or cut its grooves by hand.
- The mockups hold copies of the elements, their ids prefixed so that they keep apart, and the pictures as data, so that each file stands alone. Over the TV, a sketch of scanlines, a darker edge and the tube's corners stands for what the app's CRT shader draws. In landscape, the labels are narrowed as the app's condensed ones are.
- The badge's letters are drawn, not typed, so no font is needed. "Camera" is drawn as strokes along the middle of each letter: their width is the letters' weight. "C64" is drawn as filled shapes, as its upright strokes are thicker than the others. Each letter is white over a copy in dark brown, a little wider, which outlines it.

## Making and editing them

- `python3 design/make_svgs.py` writes every file, and `python3 design/make_svgs.py monitor-bank` one of them. Every size and colour is in the script.
- Once a file has been edited by hand, it is the one to keep: regenerate only the files whose drawing changed in the script.
- The mockups are drawn from the script's elements, not from the files in `svg/`, so a hand edit to an element does not reach them. They are for judging the whole, not for keeping.
- The pictures come from the sample photo: `swift run -c release --package-path Tools c64conv convert App/Resources/Assets.xcassets/Samples/SamplePhoto.imageset/sample-photo.png -o design/pictures/multicolour-tv.png --mode multicolor --monitor tv`, and the same with `--mode hires`, `--mode petscii --characters graphics` and, for BBS, `--mode petscii --characters all`.
- A shadow inside a hollow is drawn from shifted copies of its outline, so some outlines are repeated. The camera on the capture key is drawn five times: its hollow, the light below it, the two bands of shadow inside it, and the clip that holds them. Change its shape in the script, or in every copy.
- The other keys' icons are strokes, drawn three times: a light copy shifted down, below the groove; a dark copy, the groove's shadow; and a narrower copy shifted down, in the groove's colour. To change an icon, change its three copies, or its entry in `ICONS` in the script.
- To render a file: `inkscape design/svg/capture-up.svg --export-type=png --export-dpi=192` for @2x, or 288 for @3x. Hide the reference layer first to export the element alone.
- To compare a file with 2013's: `git show legacy-1.2:examples/SimplePhotoFilter/SimplePhotoFilter/capture-up-568h@2x.png > capture-2013.png`.
