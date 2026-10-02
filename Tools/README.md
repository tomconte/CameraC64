# Developer tools

A Swift package on top of C64Core, for Linux and macOS, with no other dependencies.

## c64conv

```sh
swift run --package-path Tools c64conv convert photo.png -o picture.prg  # a photo in multicolour, made for a TV
swift run --package-path Tools c64conv convert photo.png -o tv.png --mode hires --monitor tv --scale 2
swift run --package-path Tools c64conv testcard multicolor -o card.prg   # a random picture that obeys the mode's limits
swift run --package-path Tools c64conv render picture.kla -o picture.png --scale 2
swift run --package-path Tools c64conv export picture.kla -o picture.d64 # .prg, .d64, .kla/.koa, .art or .png
swift run --package-path Tools c64conv vice card.prg -o screen.png       # what VICE shows
swift run -c release --package-path Tools c64conv benchmark -o report    # the quality benchmark
swift run -c release --package-path Tools c64conv speed                  # how long a viewfinder frame takes here
```

`speed` times each stage of a viewfinder frame on this machine, as the app's speed benchmark does on a phone (plan, section 10). `convert` takes a PNG photo and writes the picture by the output's extension: a C64 file, or a `.png` of the picture as its monitor shows it (`--monitor tv`, `monitor`, `sharp`, `bw`, `green` or `amber`). `--dithering` goes from 0 to 1, and `--neutral` turns the automatic tones off. The other commands read Koala (`.kla`, `.koa`) and Art Studio (`.art`) files.

## Quality benchmark

`c64conv benchmark` converts a fixed set of photos in hires and multicolour, each for four monitors (sharp, TV, Commodore monitor, black and white), and scores every picture as its monitor shows it (plan, section 10).

- **Photos**: a chart of every hue at every lightness, the app's sample picture, and ten photos from Kodak's Lossless True Color Image Suite, listed with their SHA-256 in `Benchmark/photos.txt`: faces, landscapes, high contrast, fine detail, and one darkened by 2.5 stops for low light. Kodak released them for unrestricted use; `Benchmark/get-photos.sh` downloads them into `Benchmark/photos/`, which git ignores.
- **Score**: the mean OKLab distance, times 100, between the picture as shown and the photo, after blurring both as the eye does from a phone's viewing distance, brightness by 1 pixel and colour by 2, as in S-CIELAB. Lower is better; about 2 is just noticeable. For the black-and-white monitor, only lightness counts.
- **Baseline**: `Benchmark/scores.txt` holds the current scores. The benchmark fails if a picture scores more than 2% worse, or the mean more than 0.5%. After a change that is meant to alter the pictures, run it with `--update-baseline` and commit the new scores with the change.
- **Report**: `-o <directory>` writes `index.html`, with every picture next to its photo, at the PAL pixel shape. `--summary <file>` adds the score table in Markdown, as CI does for its job summary.
- **image64**: with [image64](https://github.com/nschneir/image64)'s command-line tool on the `PATH` or in `$IMAGE64` (macOS only), the benchmark also scores its pictures, with its default settings, from the same 320 × 200 pictures. CI's macOS job builds a fixed version of it for the comparison.

CI runs the benchmark on every push. Its Linux job checks the scores, and keeps the report as a download on the run's page.

## VICE comparison tests

`swift test --package-path Tools` runs the tools' tests. Where VICE's `x64sc` is found, it also runs each exported program in VICE and requires the screen to match the renderer pixel for pixel, border included (plan, section 10):

- every standard mode, with random pictures
- the converter's pictures of the benchmark's chart, in hires and multicolour
- memory layouts under the I/O area and the KERNAL
- PETSCII with VICE's own character ROM, read at test time
- a `.d64` loaded through an emulated 1541

`x64sc` is looked for in `$X64SC`, on the `PATH`, then in Homebrew's and `/opt/vice`'s `bin`. On a Mac, `brew install vice`. On Linux, `install-vice.sh` builds it without a user interface into `/opt/vice`. With `VICE_TEST_OUTPUT=<directory>`, a mismatch leaves both screens there as PNGs. `VICE_SEEDS=<n>` checks n random pictures per mode instead of 2.

VICE is GPL software: the tests only run it, and nothing of it is copied into this repository or the app.
