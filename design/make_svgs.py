#!/usr/bin/env python3
"""Draws the camera screen's elements as SVG files, in the spirit of the 2013 artwork.

The 2013 artwork is at tag legacy-1.2, in examples/SimplePhotoFilter/SimplePhotoFilter/. Each element is
redrawn from it here, with its sizes and colours written down, so that the files can be edited by hand in
Inkscape or any other SVG editor (design/README.md).

Usage: python3 design/make_svgs.py [name ...]
Writes design/svg/<name>.svg for each name given, or every file. Once a file has been edited by hand,
that file is the one to keep: regenerate only the files whose drawing changed here.
"""

import pathlib
import sys

OUT = pathlib.Path(__file__).resolve().parent / "svg"
LABEL_FONT = "FreeSans, Helvetica, Arial, sans-serif"


# MARK: - SVG


def num(value):
    """A number as SVG writes it, without trailing zeros."""
    return f"{round(value, 3):g}"


def attrs(**values):
    """SVG attributes from keyword arguments, with underscores for hyphens."""
    return " ".join(
        f'{key.replace("_", "-")}="{num(v) if isinstance(v, (int, float)) else v}"' for key, v in values.items())


def indent(text):
    return "\n".join("  " + line if line else line for line in text.splitlines())


def rect(x, y, w, h, r, **style):
    return f"<rect {attrs(x=x, y=y, width=w, height=h, rx=r, **style)}/>"


def capsule(x, y, w, h, **style):
    return rect(x, y, w, h, h / 2, **style)


def circle(cx, cy, r, **style):
    return f"<circle {attrs(cx=cx, cy=cy, r=r, **style)}/>"


def ellipse(cx, cy, rx, ry, **style):
    return f"<ellipse {attrs(cx=cx, cy=cy, rx=rx, ry=ry, **style)}/>"


def path(d, **style):
    return f'<path d="{d}" {attrs(**style)}/>'.replace(" />", "/>")


def rounded_path(x, y, w, h, r):
    """A rounded rectangle as path data, for compound paths."""
    return (f"M{num(x + r)} {num(y)} H{num(x + w - r)} A{num(r)} {num(r)} 0 0 1 {num(x + w)} {num(y + r)} "
            f"V{num(y + h - r)} A{num(r)} {num(r)} 0 0 1 {num(x + w - r)} {num(y + h)} H{num(x + r)} "
            f"A{num(r)} {num(r)} 0 0 1 {num(x)} {num(y + h - r)} V{num(y + r)} "
            f"A{num(r)} {num(r)} 0 0 1 {num(x + r)} {num(y)} Z")


def group(id_, label, *children, layer=False, **extra):
    """A named group; Inkscape shows a `layer` as a layer."""
    mode = ' inkscape:groupmode="layer"' if layer else ""
    more = f" {attrs(**extra)}" if extra else ""
    return f'<g id="{id_}"{mode} inkscape:label="{label}"{more}>\n' + indent("\n".join(children)) + "\n</g>"


def stops(*entries):
    """Gradient stops from (offset, colour) or (offset, colour, opacity)."""
    out = []
    for offset, colour, *opacity in entries:
        more = f' stop-opacity="{num(opacity[0])}"' if opacity else ""
        out.append(f'  <stop offset="{num(offset)}" stop-color="{colour}"{more}/>')
    return "\n".join(out)


def linear(id_, *entries, x1=0, y1=0, x2=0, y2=1, user=False):
    """A linear gradient: down its shape by default, or with `user`, between points of the drawing."""
    units = ' gradientUnits="userSpaceOnUse"' if user else ""
    return (f'<linearGradient id="{id_}" {attrs(x1=x1, y1=y1, x2=x2, y2=y2)}{units}>\n'
            + stops(*entries) + "\n</linearGradient>")


def radial(id_, *entries, cx=0.5, cy=0.5, r=0.5):
    return f'<radialGradient id="{id_}" {attrs(cx=cx, cy=cy, r=r)}>\n' + stops(*entries) + "\n</radialGradient>"


def clip(id_, d):
    return f'<clipPath id="{id_}">\n  <path d="{d}"/>\n</clipPath>'


def text(x, y, words, size, colour, **extra):
    return (f'<text {attrs(x=x, y=y, font_family=LABEL_FONT, font_weight=700, font_size=size, fill=colour, **extra)}>'
            f"{words}</text>")


def engraved(x, y, words, size, colour, **extra):
    """Words pressed into the case: a lighter copy just below them catches the light."""
    return "\n".join([
        text(x, y + 0.5, words, size, "#EFE8DA", fill_opacity=0.8, **extra),
        text(x, y, words, size, colour, **extra),
    ])


def document(width, height, comment, defs, *layers):
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f"<!-- {comment} 1 unit = 1 point. No filters: every effect is an ordinary shape. -->\n"
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"\n'
        f'     width="{num(width)}" height="{num(height)}" viewBox="0 0 {num(width)} {num(height)}">\n'
        "  <defs>\n" + indent(indent("\n".join(defs))) + "\n  </defs>\n"
        + "\n".join(indent(layer) for layer in layers) + "\n</svg>\n")


def backdrop(width, height, fill, what="Boîtier"):
    """The surface an element sits on, in a layer to hide before exporting the element alone."""
    return group("backdrop", f"{what} (référence, à masquer)", rect(0, 0, width, height, 0, fill=fill), layer=True)


def shade_band(frame, shape, colour, opacity):
    """Everything in `frame` but `shape`: clipped to a hollow, a shadow along its edge."""
    return path(f"{frame} {shape}", fill_rule="evenodd", fill=colour, fill_opacity=opacity)


# MARK: - The case


CASE = linear(
    "case-light",
    (0, "#A9926C"), (0.083, "#CFC1A8"), (0.167, "#D5C9B2"), (0.5, "#C8BDA5"), (0.833, "#BCB097"),
    (0.917, "#A39783"), (0.944, "#7A7162"), (0.972, "#595347"), (1, "#4A453C"))
# Where keys and lamps sit: a panel pressed into the case.
PANEL = "#CBBFA6"


# MARK: - The capture key


# The key, 135 x 72 points as the 2013 file at @1x: its face, and the edge that shows below it.
KEY_X, KEY_Y, KEY_W, KEY_H = 10.5, 12.0, 118.8, 38.5
FRAME = "M0 0 H135 V72 H0 Z"
LENS_X, LENS_Y = 69.6, 31.7


def camera(dy=0.0):
    """The camera on the capture key, as path data, `dy` points down."""
    points = [
        ("M", 55.5, 20), ("H", 63.3), ("V", 19.3), ("Q", 63.3, 16.6, 66, 16.6), ("H", 73.1),
        ("Q", 75.8, 16.6, 75.8, 19.3), ("V", 20), ("H", 83.5), ("Q", 87.5, 20, 87.5, 24), ("V", 40),
        ("Q", 87.5, 44, 83.5, 44), ("H", 55.5), ("Q", 51.5, 44, 51.5, 40), ("V", 24), ("Q", 51.5, 20, 55.5, 20),
    ]
    out = []
    for command, *values in points:
        if command == "H":
            out.append(f"H{num(values[0])}")
        elif command == "V":
            out.append(f"V{num(values[0] + dy)}")
        else:
            moved = [v + dy if i % 2 else v for i, v in enumerate(values)]
            out.append(command + " ".join(num(v) for v in moved))
    return " ".join(out) + " Z"


def engraved_camera(dy, light, hollow_gradient, ring, ring_light):
    """The camera pressed into the key: its hollow over a lighter copy shifted down, under darker bands
    along its top, and the raised ring of its lens, which casts its shadow down."""
    lens_y = LENS_Y + dy
    return group(
        "camera", "Icône gravée",
        group("camera-light", "Lumière sous le creux", path(camera(dy + 0.7), fill=light, fill_opacity=0.9)),
        group("camera-hollow", "Creux", path(camera(dy), fill=f"url(#{hollow_gradient})")),
        group("camera-shade", "Ombre dans le creux",
              shade_band(FRAME, camera(dy + 1.1), "#3E2614", 0.45),
              shade_band(FRAME, camera(dy + 0.55), "#3E2614", 0.5),
              clip_path="url(#hollow-clip)"),
        group("lens", "Objectif",
              group("lens-shadow", "Ombre portée de la bague", *(
                  circle(LENS_X, lens_y + 1, 8.25, fill="none", stroke="#2A160A", stroke_opacity=0.25,
                         stroke_width=width)
                  for width in (4, 3, 2))),
              group("lens-ring", "Bague", circle(LENS_X, lens_y, 8.25, fill="none", stroke=ring, stroke_width=2)),
              group("lens-highlight", "Reflet de la bague",
                    circle(LENS_X, lens_y - 0.5, 8.25, fill="none", stroke=ring_light, stroke_opacity=0.9,
                           stroke_width=1))),
        layer=True)


def capture_label():
    return group(
        "label", "Libellé (écrit par le code dans l’appli)",
        text(LENS_X, 62, "CAPTURE", 8, "#E2D8C4", fill_opacity=0.8, text_anchor="middle"),
        text(LENS_X, 61.5, "CAPTURE", 8, "#776F5F", text_anchor="middle"),
        layer=True)


def capture_key(pressed):
    """The big brown key, up or pressed, as in the 2013 app."""
    if not pressed:
        defs = [
            CASE,
            linear("face-light", (0, "#C6A587"), (1, "#926F51"), y1=12, y2=48.5, user=True),
            linear("rim-light", (0, "#F0D6B8", 0.9), (0.5, "#E0C2A2", 0.35), (1, "#E0C2A2", 0), y1=12, y2=48,
                   user=True),
            linear("hollow-light", (0, "#A28267"), (1, "#84654B"), y1=16.5, y2=44, user=True),
            clip("hollow-clip", camera()),
        ]
        key = group(
            "key", "Touche",
            # The key's shadow falls down, and a little right.
            group("drop-shadow", "Ombre portée", *(
                capsule(KEY_X + 0.4 - 0.6 * g, KEY_Y + 1.3 - 0.15 * g, KEY_W + 1.2 * g, KEY_H + g, fill="#3A2A18",
                        fill_opacity=0.12)
                for g in (0.5, 1.0, 1.5, 2.0))),
            group("edge", "Bord", capsule(11.3, 14, 118, 36.5, fill="#160602")),
            group("face", "Face", capsule(10.5, 12, 118, 36.5, fill="url(#face-light)")),
            group("outline", "Contour",
                  capsule(10.75, 12.25, 117.5, 36, fill="none", stroke="#4E3824", stroke_opacity=0.8,
                          stroke_width=0.5)),
            group("rim", "Reflet", capsule(11.5, 13, 116, 34.5, fill="none", stroke="url(#rim-light)",
                                           stroke_width=0.7)),
            layer=True)
        icon = engraved_camera(0, "#D4B597", "hollow-light", "#AA8A6C", "#CDB396")
        comment = "The capture key, up, redrawn from the 2013 app's capture-up."
    else:
        # Pressed, the face sinks into the hole the key sits in, by about 2 points.
        dy = 2.1
        face = (11.3, 14.2, 117.2, 36.3)
        defs = [
            CASE,
            linear("hole-rim", (0, "#6D675B", 0.9), (0.45, "#6D675B", 0), (1, "#6D675B", 0), y1=12, y2=50.5,
                   user=True),
            linear("face-pressed", (0, "#7F5E41"), (1, "#AD906F"), y1=14.2, y2=50.5, user=True),
            linear("hollow-pressed", (0, "#8F7155"), (1, "#7A5D44"), y1=16.5 + dy, y2=44 + dy, user=True),
            clip("face-clip", rounded_path(*face, face[3] / 2)),
            clip("hollow-clip", camera(dy)),
        ]
        key = group(
            "key", "Touche enfoncée",
            group("hole-lip", "Lèvre sous le trou",
                  capsule(KEY_X, KEY_Y + 0.8, KEY_W, KEY_H, fill="#E6DCCB", fill_opacity=0.85)),
            group("hole", "Trou", capsule(KEY_X, KEY_Y, KEY_W, KEY_H, fill="#1E1208")),
            group("hole-rim", "Bord du trou",
                  capsule(KEY_X + 0.5, KEY_Y + 0.5, KEY_W - 1, KEY_H - 1, fill="none", stroke="url(#hole-rim)",
                          stroke_width=1)),
            group("face", "Face", capsule(*face, fill="url(#face-pressed)")),
            # The hole's edge shades the face's top and left.
            group("face-shade", "Ombre sur la face",
                  shade_band(FRAME, rounded_path(face[0] + 1.0, face[1] + 1.6, face[2], face[3], face[3] / 2),
                             "#1E1208", 0.45),
                  shade_band(FRAME, rounded_path(face[0] + 0.5, face[1] + 0.8, face[2], face[3], face[3] / 2),
                             "#1E1208", 0.4),
                  clip_path="url(#face-clip)"),
            layer=True)
        icon = engraved_camera(dy, "#C4A585", "hollow-pressed", "#A68667", "#C8AC8E")
        comment = "The capture key, pressed, redrawn from the 2013 app's capture-down."
    return document(135, 72, comment, defs, backdrop(135, 72, "url(#case-light)"), key, icon, capture_label())


# MARK: - Monitor keys and their lamps


KEY_SIZE = 30
KEY_RADIUS = 4
LED_RADIUS = 5
KEY_DEFS = [
    linear("key-edge-up", (0, "#A08D6D"), (1, "#7E6A4B"), x2=1),
    linear("key-face-up", (0, "#C8BBA2"), (0.3, "#D3C8B4"), (1, "#DFD7C8")),
    linear("key-rim-up", (0, "#FFFFFF", 0.9), (0.5, "#FFFFFF", 0.35), (1, "#FFFFFF", 0.15)),
    linear("key-edge-down", (0, "#85704D"), (1, "#9E8B67")),
    linear("key-face-down", (0, "#BBA98B"), (0.35, "#CDBFA7"), (1, "#DBD0BD")),
    linear("key-shade-down", (0, "#5B4528", 0.55), (0.3, "#5B4528", 0), (1, "#5B4528", 0)),
]
LED_DEFS = [
    radial("led-dome-off", (0, "#B86400"), (0.55, "#7E4400"), (1, "#4A2800"), cy=0.72, r=0.65),
    radial("led-dome-on", (0, "#FFFFA8"), (0.3, "#FFF000"), (0.65, "#FFB000"), (1, "#E57A00"), cx=0.42, cy=0.42,
           r=0.7),
    radial("led-halo-on", (0, "#FFC21A", 0.6), (0.5, "#FFB000", 0.25), (1, "#FFA000", 0)),
]


def monitor_key(id_, x, y, pressed, s=KEY_SIZE, r=KEY_RADIUS):
    """A cream key whose face, `s` points square at (x, y), sits on a darker edge. Up, it casts a shadow
    and catches the light along its top; pressed, it sinks, and its top is in shadow."""
    if not pressed:
        return group(
            id_, "Touche",
            group(f"{id_}-shadow", "Ombre portée", *(
                rect(x - 1 + 0.6 - 0.5 * g, y - 1 + 1.0 - 0.2 * g, s + 2 + g, s + 2.6 + g, r + 1 + g / 2,
                     fill="#3A2A18", fill_opacity=0.12)
                for g in (0.4, 0.8, 1.2))),
            group(f"{id_}-edge", "Bord", rect(x - 1, y - 1, s + 2, s + 2.6, r + 1, fill="url(#key-edge-up)")),
            group(f"{id_}-face", "Face", rect(x, y, s, s, r, fill="url(#key-face-up)")),
            group(f"{id_}-rim", "Reflet",
                  rect(x + 0.4, y + 0.4, s - 0.8, s - 0.8, r - 0.4, fill="none", stroke="url(#key-rim-up)",
                       stroke_width=0.8)))
    return group(
        id_, "Touche enfoncée",
        group(f"{id_}-edge", "Bord", rect(x - 1, y - 1, s + 2, s + 2.2, r + 1, fill="url(#key-edge-down)")),
        group(f"{id_}-face", "Face", rect(x, y + 0.4, s, s, r, fill="url(#key-face-down)")),
        group(f"{id_}-shade", "Ombre sur la face",
              rect(x + 0.5, y + 0.9, s - 1, s - 1, r - 0.5, fill="none", stroke="url(#key-shade-down)",
                   stroke_width=1.2)))


def led(id_, cx, cy, on, r=LED_RADIUS):
    """An amber lamp under a domed lens, set into the panel: lit, it glows."""
    parts = []
    if on:
        parts.append(group(f"{id_}-halo", "Halo", circle(cx, cy, r * 2.1, fill="url(#led-halo-on)")))
    parts += [
        group(f"{id_}-lip", "Lèvre sous le voyant", circle(cx, cy + 0.6, r + 0.7, fill="#EDE6D9", fill_opacity=0.8)),
        group(f"{id_}-socket", "Douille", circle(cx, cy, r + 0.7, fill="#C08A3A" if on else "#3E2408")),
        group(f"{id_}-dome", "Dôme", circle(cx, cy, r, fill=f"url(#led-dome-{'on' if on else 'off'})")),
        group(f"{id_}-highlight", "Reflet",
              ellipse(cx - 1.1 * r / 4, cy - 1.5 * r / 4, 1.5 * r / 4, 0.9 * r / 4, fill="#FFFFFF",
                      fill_opacity=0.55 if on else 0.28)),
    ]
    return group(id_, "Voyant allumé" if on else "Voyant éteint", *parts)


def monitor_key_file(pressed):
    state = "pressed: its monitor is the one chosen" if pressed else "up"
    key = group("key", "Touche", monitor_key("monitor-key", 3, 3, pressed), layer=True)
    return document(36, 36, f"A monitor key, {state}, 30 points square, as on the camera's bank.", KEY_DEFS,
                    backdrop(36, 36, PANEL, "Panneau"), key)


def led_file(on):
    lamp = group("lamp", "Voyant", led("led", 11, 11, on), layer=True)
    return document(22, 22, f"A monitor's lamp, {'lit' if on else 'off'}, 10 points across.", LED_DEFS,
                    backdrop(22, 22, PANEL, "Panneau"), lamp)


def monitor_bank():
    """The camera's monitor bank with the phone upright, as the app lays it out on an iPhone 17, with the
    TV chosen: a reference for the keys and lamps in place, not an element of its own."""
    width, height = 402, 166
    panel = (24, 18, 354, 134)
    defs = [
        linear("case-bank", (0, "#D6CAB3"), (1, "#C9BEA6")),
        linear("panel-shade", (0, "#6E5A3E", 0.45), (0.25, "#6E5A3E", 0), (1, "#6E5A3E", 0)),
        *KEY_DEFS,
        *LED_DEFS,
    ]
    # Three rows of 38 points, 12 below the panel's top; colour monitors on the left.
    monitors = [
        ("tv", "TV", 0, 0), ("bw", "B&amp;W", 1, 0),
        ("commodore", "MONITOR", 0, 1), ("amber", "AMBER", 1, 1),
        ("sharp", "SHARP", 0, 2), ("green", "GREEN", 1, 2),
    ]
    chosen = "tv"
    keys, lamps, labels = [], [], []
    for id_, name, column, row in monitors:
        x = (38, 207)[column]
        y = panel[1] + 12 + 38 * row + 4
        keys.append(monitor_key(f"key-{id_}", x, y, pressed=id_ == chosen))
        lamps.append(led(f"led-{id_}", x + KEY_SIZE + 10 + LED_RADIUS, y + KEY_SIZE / 2, on=id_ == chosen))
        labels.append(engraved(x + KEY_SIZE + 10 + 2 * LED_RADIUS + 10, y + KEY_SIZE / 2 + 4, name, 11, "#857558"))
    x, y, w, h = panel
    layers = [
        group("case", "Boîtier", rect(0, 0, width, height, 0, fill="url(#case-bank)"), layer=True),
        group("panel", "Panneau",
              group("panel-lip", "Lèvre", rect(x + 0.6, y + 0.8, w, h, 8, fill="#EAE2D3", fill_opacity=0.9)),
              group("panel-recess", "Creux", rect(x, y, w, h, 8, fill=PANEL)),
              group("panel-shade", "Ombre",
                    rect(x + 0.8, y + 0.8, w - 1.6, h - 1.6, 7.2, fill="none", stroke="url(#panel-shade)",
                         stroke_width=1.6)),
              layer=True),
        group("keys", "Touches", *keys, layer=True),
        group("lamps", "Voyants", *lamps, layer=True),
        group("labels", "Libellés (écrits par le code dans l’appli)",
              engraved(x + 6, y - 5, "MONITOR", 9, "#857558", letter_spacing=1.4), *labels, layer=True),
    ]
    return document(width, height, "The monitor bank, as on an iPhone 17, with the TV chosen.", defs, *layers)


# MARK: - Files


FILES = {
    "capture-up": lambda: capture_key(pressed=False),
    "capture-down": lambda: capture_key(pressed=True),
    "monitor-key-up": lambda: monitor_key_file(pressed=False),
    "monitor-key-down": lambda: monitor_key_file(pressed=True),
    "led-off": lambda: led_file(on=False),
    "led-on": lambda: led_file(on=True),
    "monitor-bank": monitor_bank,
}


def main(names):
    unknown = [name for name in names if name not in FILES]
    if unknown:
        sys.exit(f"Unknown file: {', '.join(unknown)}. The files are: {', '.join(FILES)}.")
    OUT.mkdir(exist_ok=True)
    for name in names or FILES:
        target = OUT / f"{name}.svg"
        target.write_text(FILES[name](), encoding="utf-8")
        print(target.relative_to(OUT.parent.parent))


if __name__ == "__main__":
    main(sys.argv[1:])
