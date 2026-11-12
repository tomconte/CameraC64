# Design

Vector redraws of the camera screen's elements, in the spirit of the 2013 app's artwork (tag `legacy-1.2`, in `examples/SimplePhotoFilter/SimplePhotoFilter/`), to edit by hand in Inkscape or any other SVG editor, and to carry into the app (`docs/UX.md`, section 7).

## The files

| File | What | Size (pt) |
|---|---|---|
| `svg/capture-up.svg`, `svg/capture-down.svg` | The capture key, up and pressed, with its label for reference | 135 × 72, as the 2013 files at @1x |
| `svg/monitor-key-up.svg`, `svg/monitor-key-down.svg` | A monitor key, up, and pressed for the monitor chosen | 36 × 36, the face 30 square |
| `svg/led-off.svg`, `svg/led-on.svg` | A monitor's lamp, off and lit | 22 × 22, the lamp 10 across |
| `svg/monitor-bank.svg` | The camera's monitor bank on an iPhone 17, with the TV chosen: the keys and lamps in place, for reference | 402 × 166 |

## How they are drawn

- 1 unit = 1 point, so sizes read directly.
- No SVG filters. Shadows, bevels and engravings are ordinary shapes: translucent copies, gradients, and bands clipped to a hollow. Every editor keeps them as objects to select and recolour, and so does Xcode's asset catalog.
- Each part is a named group. Inkscape shows the top-level ones as layers, labelled in French.
- Each element sits on the case, or the panel, in a layer marked "référence, à masquer": hide it before exporting the element alone.
- No words in the elements: the app writes its labels. The layers that show them, for reference, are marked "écrit par le code dans l'appli". They use FreeSans, a free Helvetica, where it is installed, and Helvetica or Arial elsewhere.

## Making and editing them

- `python3 design/make_svgs.py` writes every file, and `python3 design/make_svgs.py monitor-bank` one of them. Every size and colour is in the script.
- Once a file has been edited by hand, it is the one to keep: regenerate only the files whose drawing changed in the script.
- A shadow inside a hollow is drawn from shifted copies of its outline, so some outlines are repeated. The camera on the capture key is drawn five times: its hollow, the light below it, the two bands of shadow inside it, and the clip that holds them. Change its shape in the script, or in every copy.
- To render a file: `inkscape design/svg/capture-up.svg --export-type=png --export-dpi=192` for @2x, or 288 for @3x. Hide the reference layer first to export the element alone.
- To compare a file with 2013's: `git show legacy-1.2:examples/SimplePhotoFilter/SimplePhotoFilter/capture-up-568h@2x.png > capture-2013.png`.
