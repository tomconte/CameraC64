#!/usr/bin/env python3
"""Draws the camera screen's elements as SVG files, in the spirit of the 2013 artwork.

The 2013 artwork is at tag legacy-1.2, in examples/SimplePhotoFilter/SimplePhotoFilter/. Each element is
redrawn from it here, with its sizes and colours written down, so that the files can be edited by hand in
Inkscape or any other SVG editor (design/README.md).

Usage: python3 design/make_svgs.py [name ...]
Writes design/svg/<name>.svg for each name given, or every file. Once a file has been edited by hand,
that file is the one to keep: regenerate only the files whose drawing changed here.
"""

import base64
import math
import pathlib
import re
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


def text(x, y, words, size, colour, stretch=1.0, **extra):
    """Words in the labels' font. With `stretch` below 1 they are narrowed, as the app's condensed
    labels are where space is short."""
    if stretch != 1:
        extra["transform"] = f"matrix({num(stretch)} 0 0 1 {num(x)} {num(y)})"
        x = y = 0
    return (f'<text {attrs(x=x, y=y, font_family=LABEL_FONT, font_weight=700, font_size=size, fill=colour, **extra)}>'
            f"{words}</text>")


# Helvetica Bold's widths, which FreeSans Bold shares, in thousandths of the size: to centre words with
# something beside them.
WIDTHS = dict(zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ&", (
    722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667,
    944, 667, 667, 611, 722)))


def text_width(words, size, stretch=1.0):
    return sum(WIDTHS[letter] for letter in words.replace("&amp;", "&")) * size / 1000 * stretch


def engraved(x, y, words, size, colour, **extra):
    """Words pressed into the case: a lighter copy just below them catches the light."""
    return "\n".join([
        text(x, y + 0.5, words, size, "#EFE8DA", fill_opacity=0.8, **extra),
        text(x, y, words, size, colour, **extra),
    ])


def document(width, height, comment, defs, *layers):
    body = "\n".join(indent(layer) for layer in layers)
    # Only the mockups hold pictures, linked as xlink:href, which every editor reads.
    xlink = ' xmlns:xlink="http://www.w3.org/1999/xlink"\n    ' if "xlink:" in body else ""
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f"<!-- {comment} 1 unit = 1 point. No filters: every effect is an ordinary shape. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg"{xlink} xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"\n'
        f'     width="{num(width)}" height="{num(height)}" viewBox="0 0 {num(width)} {num(height)}">\n'
        "  <defs>\n" + indent(indent("\n".join(defs))) + "\n  </defs>\n"
        + body + "\n</svg>\n")


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


def monitor_key(id_, x, y, pressed, w=KEY_SIZE, h=KEY_SIZE, r=KEY_RADIUS):
    """A cream key whose face, `w` by `h` points at (x, y), sits on a darker edge. Up, it casts a shadow
    and catches the light along its top; pressed, it sinks, and its top is in shadow."""
    if not pressed:
        return group(
            id_, "Touche",
            group(f"{id_}-shadow", "Ombre portée", *(
                rect(x - 1 + 0.6 - 0.5 * g, y - 1 + 1.0 - 0.2 * g, w + 2 + g, h + 2.6 + g, r + 1 + g / 2,
                     fill="#3A2A18", fill_opacity=0.12)
                for g in (0.4, 0.8, 1.2))),
            group(f"{id_}-edge", "Bord", rect(x - 1, y - 1, w + 2, h + 2.6, r + 1, fill="url(#key-edge-up)")),
            group(f"{id_}-face", "Face", rect(x, y, w, h, r, fill="url(#key-face-up)")),
            group(f"{id_}-rim", "Reflet",
                  rect(x + 0.4, y + 0.4, w - 0.8, h - 0.8, r - 0.4, fill="none", stroke="url(#key-rim-up)",
                       stroke_width=0.8)))
    return group(
        id_, "Touche enfoncée",
        group(f"{id_}-edge", "Bord", rect(x - 1, y - 1, w + 2, h + 2.2, r + 1, fill="url(#key-edge-down)")),
        group(f"{id_}-face", "Face", rect(x, y + 0.4, w, h, r, fill="url(#key-face-down)")),
        group(f"{id_}-shade", "Ombre sur la face",
              rect(x + 0.5, y + 0.9, w - 1, h - 1, r - 0.5, fill="none", stroke="url(#key-shade-down)",
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


# MARK: - The other keys


def mix(a, b, t):
    """The colour `t` of the way from `a` to `b`, both written "#RRGGBB"."""
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(p + (q - p) * t):02X}" for p, q in zip(ca, cb))


def gear():
    """A gear's teeth, as strokes from its ring outwards."""
    teeth = []
    for k in range(8):
        cos, sin = [(1, 0), (0.7071, 0.7071), (0, 1), (-0.7071, 0.7071), (-1, 0), (-0.7071, -0.7071), (0, -1),
                    (0.7071, -0.7071)][k]
        teeth.append(f"M{num(5.6 * cos)} {num(5.6 * sin)} L{num(8 * cos)} {num(8 * sin)}")
    return "M4.4 0 A4.4 4.4 0 1 1 -4.4 0 A4.4 4.4 0 1 1 4.4 0 " + " ".join(teeth)


# The icons pressed into the keys, centred on (0, 0) in a box 20 points across, with the width of their
# strokes. Share is the 2013 app's; Delete is its Discard's cross.
ICONS = {
    "share": ("M-2 -4 H-7 V6 H7 V2 M-3.5 2.5 C-3.5 -3 0 -4.5 5 -4.5 M2.5 -8 L6.5 -4.5 L2.5 -1", 2.5),
    "save": ("M-3.5 -2 H-7 V6 H7 V-2 H3.5 M0 -8.5 V2.5 M-3.5 -1 L0 2.5 L3.5 -1", 2.5),
    "send": ("M0 -0.5 V7 M0 -3 h0.01 M-2.69 -5.69 A3.8 3.8 0 0 0 -2.69 -0.31 M2.69 -5.69 A3.8 3.8 0 0 1 2.69 -0.31 "
             "M-5.36 -7.5 A7 7 0 0 0 -5.36 1.5 M5.36 -7.5 A7 7 0 0 1 5.36 1.5", 2.3),
    "delete": ("M-5.5 -5.5 L5.5 5.5 M5.5 -5.5 L-5.5 5.5", 3.2),
    "flip": ("M-5 -2.5 H-2.5 L-1.5 -4 H1.5 L2.5 -2.5 H5 V4 H-5 Z M1.7 0.7 A1.7 1.7 0 1 1 -1.7 0.7 "
             "A1.7 1.7 0 1 1 1.7 0.7 M-8.37 -1.28 A8.5 8.5 0 0 1 6.01 -5.81 M5.75 -8.8 L6.01 -5.81 L3.02 -6.07 "
             "M8.37 1.68 A8.5 8.5 0 0 1 -6.01 6.21 M-5.75 9.2 L-6.01 6.21 L-3.02 6.47", 1.7),
    "settings": (gear(), 2.2),
    "flash": ("M2.5 -8.5 L-4.5 1.5 H2 L-2.5 8.5", 2.6),
    "crt": ("M-7 -2.5 H7 V6.5 H-7 Z M-3 -8 L0 -2.5 L3 -8", 2.1),
}


def engraved_icon(id_, name, x, y, groove, shadow, light, scale=1.0):
    """An icon pressed into a key, drawn as strokes centred on (x, y): a light copy just below it catches
    the light, and a narrower copy shifted down leaves the top of its groove in shadow."""
    d, weight = ICONS[name]
    style = {"fill": "none", "stroke_linecap": "round", "stroke_linejoin": "round"}
    return group(
        id_, "Icône gravée",
        group(f"{id_}-light", "Lumière sous la gravure",
              path(d, stroke=light, stroke_width=weight, transform="translate(0 0.6)", **style)),
        group(f"{id_}-shadow", "Ombre de la gravure", path(d, stroke=shadow, stroke_width=weight, **style)),
        group(f"{id_}-groove", "Gravure",
              path(d, stroke=groove, stroke_width=weight - 0.8, transform="translate(0 0.4)", **style)),
        transform=f"translate({num(x)} {num(y)}) scale({num(scale)})", layer=True)


# The review's actions, as the 2013 app's coloured keys: Share green and Delete red, as its Share and
# Discard were, and the two new actions in the badge's rainbow blue and orange.
ACTIONS = {
    "share": ("Partager", "#6BCB56", "#3C9A25", "#0E3A06"),
    "save": ("Enregistrer dans Photos", "#6FB6EA", "#2C74B8", "#0B2C4E"),
    "send": ("Envoyer au C64", "#F5B550", "#CC7A1C", "#4A2606"),
    "delete": ("Supprimer", "#D25050", "#A31F1F", "#230000"),
}


def action_key(name, pressed):
    """A coloured key for one of the review's actions, 52 by 42 points and nearly oval as in 2013, built
    as the capture key is: up, its face sits on a dark edge and casts a shadow; pressed, it sinks into the
    hole it sits in."""
    label, top, bottom, edge = ACTIONS[name]
    x, y, w, h, r = 4, 4, 52, 42, 18
    middle = mix(top, bottom, 0.5)
    groove, shadow, light = mix(middle, "#000000", 0.25), mix(middle, "#000000", 0.55), mix(top, "#FFFFFF", 0.3)
    hole = (x, y, w + 0.8, h + 2)
    if not pressed:
        defs = [
            linear("face", (0, top), (1, bottom)),
            linear("rim", (0, mix(top, "#FFFFFF", 0.55), 0.9), (0.5, mix(top, "#FFFFFF", 0.4), 0.35),
                   (1, mix(top, "#FFFFFF", 0.4), 0)),
        ]
        key = group(
            "key", "Touche",
            group("drop-shadow", "Ombre portée", *(
                rect(x + 0.4 - 0.6 * g, y + 1.3 - 0.15 * g, w + 0.8 + 1.2 * g, h + 2 + g, r + g / 2, fill="#3A2A18",
                     fill_opacity=0.12)
                for g in (0.5, 1.0, 1.5, 2.0))),
            group("edge", "Bord", rect(x + 0.8, y + 2, w, h, r, fill=edge)),
            group("face", "Face", rect(x, y, w, h, r, fill="url(#face)")),
            group("outline", "Contour",
                  rect(x + 0.25, y + 0.25, w - 0.5, h - 0.5, r - 0.25, fill="none", stroke=mix(bottom, "#000000", 0.5),
                       stroke_opacity=0.8, stroke_width=0.5)),
            group("rim", "Reflet",
                  rect(x + 1, y + 1, w - 2, h - 2, r - 1, fill="none", stroke="url(#rim)", stroke_width=0.7)),
            layer=True)
        icon = engraved_icon("icon", name, x + w / 2, y + h / 2 - 0.5, groove, shadow, light, 1.15)
    else:
        dy = 2.1
        face = (x + 0.8, y + 2.2, w - 0.8, h - 0.2)
        frame = f"M0 0 H{num(w + 8)} V{num(h + 10)} H0 Z"
        defs = [
            linear("hole-rim", (0, "#6D675B", 0.9), (0.45, "#6D675B", 0), (1, "#6D675B", 0)),
            linear("face-pressed", (0, mix(bottom, "#000000", 0.4)), (1, mix(bottom, "#000000", 0.05))),
            clip("face-clip", rounded_path(*face, r)),
        ]
        key = group(
            "key", "Touche enfoncée",
            group("hole-lip", "Lèvre sous le trou", rect(hole[0], hole[1] + 0.8, hole[2], hole[3], r, fill="#E6DCCB",
                                                       fill_opacity=0.85)),
            group("hole", "Trou", rect(*hole, r, fill="#1E1208")),
            group("hole-rim", "Bord du trou",
                  rect(hole[0] + 0.5, hole[1] + 0.5, hole[2] - 1, hole[3] - 1, r - 0.5, fill="none",
                       stroke="url(#hole-rim)", stroke_width=1)),
            group("face", "Face", rect(*face, r, fill="url(#face-pressed)")),
            group("face-shade", "Ombre sur la face",
                  shade_band(frame, rounded_path(face[0] + 1.0, face[1] + 1.6, face[2], face[3], r), "#1E1208", 0.45),
                  shade_band(frame, rounded_path(face[0] + 0.5, face[1] + 0.8, face[2], face[3], r), "#1E1208", 0.4),
                  clip_path="url(#face-clip)"),
            layer=True)
        icon = engraved_icon("icon", name, x + w / 2 + 0.4, y + h / 2 - 0.5 + dy, mix(groove, "#000000", 0.3),
                             mix(shadow, "#000000", 0.3), mix(light, "#000000", 0.25), 1.15)
    state = "pressed" if pressed else "up"
    return document(w + 8, h + 10, f"The review's {label} key, {state}, 52 by 42 points.", defs,
                    backdrop(w + 8, h + 10, PANEL_CASE, "Boîtier"), key, icon)


# The case where the review's and the shutter's keys sit.
PANEL_CASE = "#D3C7AF"
CREAM_ICON = ("#B9AB8F", "#857358", "#FBF8F2")


def cream_key(file_id, comment, w, h, r, pressed, icon=None, icon_y=None, scale=1.0, lamp=False):
    """A cream key like the monitor keys, `w` by `h` points, with an icon pressed into it, and, where the
    app puts one, a lamp below it, for reference."""
    x, y = 4, 4
    layers = [backdrop(w + 8, h + 10, PANEL_CASE, "Boîtier"),
              group("key", "Touche", monitor_key("key-body", x, y, pressed, w, h, r), layer=True)]
    if icon:
        groove, shadow, light = CREAM_ICON
        dy = 0.4 if pressed else 0
        cy = (icon_y if icon_y is not None else y + h / 2) + dy
        layers.append(engraved_icon("icon", icon, x + w / 2, cy, groove, shadow, light, scale))
    defs = [*KEY_DEFS]
    if lamp:
        defs += LED_DEFS
        layers.append(group("lamp", "Voyant (posé par le code)",
                            led("lamp-led", x + w / 2, y + h - 8 + (0.4 if pressed else 0), False, r=3), layer=True))
    return document(w + 8, h + 10, comment, defs, *layers)


def toggle(on):
    """The 2013 app's switch, for flash and the CRT layer: a knob that slides along a track, green when
    on and red when off, set into a slot in the case."""
    width, height = 50, 22
    track_top, track_bottom = ("#2C6420", "#339F1E") if on else ("#4A1010", "#8E1B1B")
    track_middle = "#49B534" if on else "#A82222"
    knob_x = 37.5 if on else 12.5
    defs = [
        linear("slot", (0, "#BFB096"), (1, "#DCD1BC")),
        linear("track", (0, track_top), (0.35, track_middle), (1, track_bottom)),
        linear("track-shade", (0, "#000000", 0.45), (0.4, "#000000", 0), (1, "#000000", 0)),
        radial("knob", (0, "#FBF8F1"), (0.7, "#E7DFCF"), (1, "#C9BEA8"), cx=0.42, cy=0.35, r=0.65),
    ]
    layers = [
        backdrop(width, height, PANEL_CASE, "Boîtier"),
        group("slot", "Fente",
              group("slot-lip", "Lèvre", capsule(2, 2.8, 46, 18, fill="#EFE7D8")),
              group("slot-recess", "Creux", capsule(2, 2, 46, 18, fill="url(#slot)")),
              layer=True),
        group("track", "Glissière, " + ("verte, allumée" if on else "rouge, éteinte"),
              group("track-edge", "Bord", capsule(5.5, 5.5, 39, 11, fill="#153110" if on else "#3E0B0B")),
              group("track-face", "Glissière", capsule(6, 6, 38, 10, fill="url(#track)")),
              group("track-shade", "Ombre", capsule(6, 6, 38, 10, fill="url(#track-shade)")),
              layer=True),
        group("knob", "Bouton",
              group("knob-shadow", "Ombre portée", *(
                  circle(knob_x + 0.6, 11.9 + 0.2 * g, 6.3 + g, fill="#2A1C0E", fill_opacity=0.14)
                  for g in (0.4, 0.9, 1.4))),
              group("knob-body", "Bouton", circle(knob_x, 11, 6.3, fill="url(#knob)")),
              group("knob-outline", "Contour", circle(knob_x, 11, 6.1, fill="none", stroke="#9C8E74", stroke_width=0.5)),
              group("knob-highlight", "Reflet",
                    path(f"M{num(knob_x - 4.2)} 9.4 A4.6 4.6 0 0 1 {num(knob_x + 3)} 7.4", fill="none", stroke="#FFFFFF",
                         stroke_opacity=0.8, stroke_width=0.8, stroke_linecap="round")),
              layer=True),
    ]
    state = "on" if on else "off"
    return document(width, height, f"The switch for flash and the CRT layer, {state}, as in the 2013 app.", defs,
                    *layers)


def zoom_button(pressed):
    """A zoom button on the TV's border: a dark round key, 34 points across. The app writes its value
    on it, lit for the zoom chosen."""
    size, cx, r = 40, 20, 17
    if not pressed:
        defs = [linear("zoom-face", (0, "#3E3A35"), (1, "#1F1D1A")),
                linear("zoom-rim", (0, "#8A8378", 0.9), (0.5, "#8A8378", 0.2), (1, "#8A8378", 0))]
        button = group(
            "zoom", "Bouton de zoom",
            group("zoom-shadow", "Ombre portée", *(
                circle(cx + 0.3, cx + 1 + 0.2 * g, r + g, fill="#000000", fill_opacity=0.18) for g in (0.4, 0.9, 1.4))),
            group("zoom-face", "Face", circle(cx, cx, r, fill="url(#zoom-face)")),
            group("zoom-rim", "Reflet", circle(cx, cx, r - 0.6, fill="none", stroke="url(#zoom-rim)", stroke_width=0.8)),
            layer=True)
    else:
        defs = [linear("zoom-face", (0, "#151413"), (1, "#2A2723")),
                linear("zoom-shade", (0, "#000000", 0.7), (0.35, "#000000", 0), (1, "#000000", 0))]
        button = group(
            "zoom", "Bouton de zoom enfoncé",
            group("zoom-face", "Face", circle(cx, cx + 0.5, r, fill="url(#zoom-face)")),
            group("zoom-shade", "Ombre sur la face",
                  circle(cx, cx + 0.5, r - 0.7, fill="none", stroke="url(#zoom-shade)", stroke_width=1.4)),
            layer=True)
    state = "pressed" if pressed else "up"
    return document(size, size, f"A zoom button, {state}, on the TV's border.", defs,
                    backdrop(size, size, "#1C1B19", "Bordure de la télé"), button)


def last_picture_frame():
    """The frame round the last picture, 56 points square: a cream mount, its window shaded along the
    top. The app puts the picture in the window."""
    size, x, w, r = 64, 4, 56, 8
    defs = [linear("window-shade", (0, "#000000", 0.55), (0.3, "#000000", 0), (1, "#000000", 0))]
    layers = [
        backdrop(size, size, PANEL_CASE, "Boîtier"),
        group("frame", "Cadre",
              group("frame-shadow", "Ombre portée", *(
                  rect(x + 0.4 - 0.5 * g, x + 1.2 - 0.2 * g, w + g, w + 0.8 + g, r + g / 2, fill="#3A2A18",
                       fill_opacity=0.12)
                  for g in (0.4, 0.8, 1.2))),
              group("frame-mount", "Passe-partout", rect(x, x, w, w, r, fill="#F5F0E4", stroke="#B4A88E",
                                                          stroke_width=0.6)),
              layer=True),
        group("window", "Fenêtre (la photo, posée par le code)",
              rect(x + 3, x + 3, w - 6, w - 6, r - 2, fill="#2B2925"),
              rect(x + 3, x + 3, w - 6, w - 6, r - 2, fill="none", stroke="url(#window-shade)", stroke_width=1.6),
              layer=True),
    ]
    return document(size, size, "The frame round the last picture, 56 points square.", defs, *layers)


# MARK: - The badge


def glyph(id_, label, d, weight, cap="butt"):
    """A letter drawn as a thick stroke along its middle, white over a dark brown outline: its weight and
    shape change with the stroke's width and the path's points."""
    style = {"fill": "none", "stroke_linecap": cap, "stroke_linejoin": "round"}
    return group(
        id_, label,
        path(d, stroke="#3E3022", stroke_width=weight + 0.8, **style),
        path(d, stroke="#FFFFFF", stroke_width=weight, **style))


def letters_camera(x):
    """"Camera" from `x`, as in the 2013 badge: a tall, round C, then rounded lowercase."""
    # The C: 9.7 points high, from 5.3 to 15, and 6.5 wide, drawn 2 thick.
    big_c = (f"M{num(x + 6.5)} 6.3 H{num(x + 4.6)} A3.6 3.85 0 0 0 {num(x + 1)} 10.15 "
             f"A3.6 3.85 0 0 0 {num(x + 4.6)} 14 H{num(x + 6.5)}")
    # Lowercase: 4.1 points high, from 7.8 to 11.9, drawn 1.35 thick.
    weight = 1.35
    half = weight / 2
    top, bottom, middle, rx, ry = 7.8 + half, 11.9 - half, 9.85, 1.9, 1.375

    def a(left):
        """A two-storey a, as in the 2013 badge: a hook over a small bowl, and a stem on the right."""
        stem = left + 5 - half
        hook = f"M{num(left + 0.9)} {num(top + 0.4)} A1.7 1 0 0 1 {num(stem)} {num(top + 1)} V{num(bottom)}"
        bowl_x, bowl_y, bowl_rx, bowl_ry = left + half + 1.65, bottom - 0.8, 1.65, 0.8
        bowl = (f"M{num(bowl_x - bowl_rx)} {num(bowl_y)} A{num(bowl_rx)} {num(bowl_ry)} 0 1 0 {num(bowl_x + bowl_rx)} "
                f"{num(bowl_y)} A{num(bowl_rx)} {num(bowl_ry)} 0 1 0 {num(bowl_x - bowl_rx)} {num(bowl_y)}")
        return f"{hook} {bowl}"

    def m(left):
        x0, step, arch = left + half, 3, top + ry
        return (f"M{num(x0)} {num(bottom)} V{num(arch)} A1.5 {num(ry)} 0 0 1 {num(x0 + step)} {num(arch)} "
                f"V{num(bottom)} M{num(x0 + step)} {num(arch)} A1.5 {num(ry)} 0 0 1 {num(x0 + 2 * step)} {num(arch)} "
                f"V{num(bottom)}")

    def e(left):
        cx = left + half + rx
        return (f"M{num(cx - rx)} {num(middle)} H{num(cx + rx)} "
                f"A{num(rx)} {num(ry)} 0 1 0 {num(cx + rx * 0.7071)} {num(middle + ry * 0.7071)}")

    def r(left):
        x0 = left + half
        return (f"M{num(x0)} {num(bottom)} V{num(top)} M{num(x0)} {num(top + 1.5)} "
                f"A1.5 1.5 0 0 1 {num(x0 + 1.5)} {num(top)} H{num(x0 + 2.4)}")

    # Each letter's left edge: a is 5 wide, e 5.15, m 7.35 and r 3.75, with 0.6 between them.
    left = x + 7.8
    return [
        glyph("letter-big-c", "C", big_c, 2),
        glyph("letter-a", "a", a(left), weight, "round"),
        glyph("letter-m", "m", m(left + 5.6), weight, "round"),
        glyph("letter-e", "e", e(left + 13.55), weight, "round"),
        glyph("letter-r", "r", r(left + 19.3), weight, "round"),
        glyph("letter-a2", "a", a(left + 23.65), weight, "round"),
    ]


def glyph_shape(id_, label, d):
    """A letter drawn as a filled shape, white over a dark brown outline. Its holes are subpaths."""
    return group(
        id_, label,
        path(d, fill="#3E3022", fill_rule="evenodd", stroke="#3E3022", stroke_width=0.8, stroke_linejoin="round"),
        path(d, fill="#FFFFFF", fill_rule="evenodd"))


def letters_c64(x):
    """"C64" from `x`, in squarish capitals 7 points high, from 6 to 13, as in the 2013 badge: their
    upright strokes are 2.4 thick and the others 1.7 to 1.9, with corners rounder outside than in."""
    c = (f"M{num(x + 9)} 6 H{num(x + 2.8)} A2.8 2.8 0 0 0 {num(x)} 8.8 V10.2 A2.8 2.8 0 0 0 {num(x + 2.8)} 13 "
         f"H{num(x + 9)} V11.1 H{num(x + 3.3)} A0.9 0.9 0 0 1 {num(x + 2.4)} 10.2 V8.8 "
         f"A0.9 0.9 0 0 1 {num(x + 3.3)} 7.9 H{num(x + 9)} Z")
    # The 6: an arm over a notch open to the right, then a bowl with a small hole.
    s = x + 10.2
    six = (f"M{num(s + 9)} 6 H{num(s + 2.8)} A2.8 2.8 0 0 0 {num(s)} 8.8 V10.2 A2.8 2.8 0 0 0 {num(s + 2.8)} 13 "
           f"H{num(s + 6.6)} A2.4 2.4 0 0 0 {num(s + 9)} 10.6 V9.4 A0.9 0.9 0 0 0 {num(s + 8.1)} 8.5 "
           f"H{num(s + 2.4)} V7.7 H{num(s + 9)} Z "
           f"M{num(s + 2.9)} 10.2 H{num(s + 6.1)} A0.5 0.5 0 0 1 {num(s + 6.6)} 10.7 V10.8 "
           f"A0.5 0.5 0 0 1 {num(s + 6.1)} 11.3 H{num(s + 2.9)} A0.5 0.5 0 0 1 {num(s + 2.4)} 10.8 V10.7 "
           f"A0.5 0.5 0 0 1 {num(s + 2.9)} 10.2 Z")
    # The 4: a diagonal from the top of its stem down to the bar, round a small triangular hole.
    f = x + 20.4
    four = (f"M{num(f + 7.6)} 6 V9.6 H{num(f + 8.6)} V11.3 H{num(f + 7.6)} V13 H{num(f + 5.2)} V11.3 "
            f"H{num(f + 0.6)} A0.6 0.6 0 0 1 {num(f)} 10.7 V10.4 L{num(f + 4.6)} 6 Z "
            f"M{num(f + 3.72)} 9.6 H{num(f + 5.2)} V8.19 Z")
    return [glyph_shape("letter-c", "C", c), glyph_shape("letter-6", "6", six), glyph_shape("letter-4", "4", four)]


def badge():
    """The "Camera C64" badge from the 2013 app's title bar: white letters and rainbow stripes on a taupe
    capsule set into the bar. The letters are drawn as strokes, so no font is needed."""
    width, height = 128, 20
    stripes = [("red", "#FF0000", "#FF0009"), ("orange", "#FA6603", "#FF6700"), ("yellow", "#FAC703", "#FFDD00"),
               ("green", "#1DB60C", "#00D800"), ("blue", "#1D9AD3", "#00C8FF")]
    defs = [
        linear("bar-light", (0, "#FCF3E2"), (0.25, "#F8EFDE"), (0.5, "#D9CCB6"), (0.85, "#CDC4B3"), (0.95, "#9B9281"),
               (1, "#6A6150")),
        *(linear(f"stripe-{name}", (0, upper), (1, lower)) for name, upper, lower in stripes),
    ]
    layers = [
        group("backdrop", "Barre de titre (référence, à masquer)",
              rect(0, 0, width, height, 0, fill="url(#bar-light)"), layer=True),
        group("badge", "Badge",
              group("badge-lip", "Liseré", capsule(2.5, 1.5, 122, 17, fill="#E4DBCA")),
              group("badge-capsule", "Capsule", capsule(4, 3, 119, 14, fill="#6E6359")),
              layer=True),
        group("stripes", "Bandes arc-en-ciel", *(
            group(f"stripe-{name}", name.capitalize(),
                  rect(48.5, 5.5 + 2 * index, 38.5, 1, 0, fill=f"url(#stripe-{name})"))
            for index, (name, _, _) in enumerate(stripes)), layer=True),
        group("words", "Lettres", group("word-camera", "Camera", *letters_camera(7.5)),
              group("word-c64", "C64", *letters_c64(90.5)), layer=True),
    ]
    return document(width, height, "The Camera C64 badge, redrawn from the 2013 app's title bar.", defs, *layers)


# MARK: - Mockups


PICTURES = pathlib.Path(__file__).resolve().parent / "pictures"
# The TV's shape: the C64's screen, 384 by 272 pixels each 0.936 as wide as tall, as the app's TVGeometry.
TV_ASPECT = 384 * 0.936 / 272
INK = "#857558"
# How much narrower the app's condensed labels are than FreeSans Bold.
NARROW = 0.84


def embed(doc, prefix, x, y, scale=1.0, drop=("backdrop",)):
    """Another file's drawing placed at (x, y) and scaled: its ids take a prefix, so that two keys'
    gradients keep apart, and the reference layers named in `drop` go."""
    defs = doc[doc.index("<defs>") + len("<defs>"):doc.index("</defs>")]
    body = doc[doc.index("</defs>") + len("</defs>"):doc.rindex("</svg>")]
    for id_ in drop:
        start = body.find(f'<g id="{id_}"')
        if start >= 0:
            # Reference layers hold only shapes and words, no groups.
            body = body[:start] + body[body.index("</g>", start) + len("</g>"):]
    text = f"<defs>{defs}</defs>{body}".replace(' inkscape:groupmode="layer"', "")
    text = re.sub(r'id="([^"]+)"', lambda m: f'id="{prefix}-{m.group(1)}"', text)
    text = re.sub(r"url\(#([^)]+)\)", lambda m: f"url(#{prefix}-{m.group(1)})", text)
    lines = "\n".join(line.strip() for line in text.splitlines() if line.strip())
    return (f'<g id="{prefix}" transform="translate({num(x)} {num(y)}) scale({num(scale)})">\n'
            + indent(lines) + "\n</g>")


def picture_data(name):
    """A converted picture, from design/pictures, as a data URL, so that each mockup holds its pictures."""
    return "data:image/png;base64," + base64.b64encode((PICTURES / name).read_bytes()).decode()


def picture(x, y, w, h, name, **extra):
    return (f'<image {attrs(x=x, y=y, width=w, height=h, preserveAspectRatio="none", **extra)} '
            f'xlink:href="{picture_data(name)}"/>')


def window(id_, x, y, w, h, r, name, clip_defs):
    """A picture's display window in (x, y, w, h), cut from the whole screen and clipped to a rounded
    rectangle; the clip joins `clip_defs`."""
    clip_defs.append(clip(f"{id_}-clip", rounded_path(x, y, w, h, r)))
    sx, sy = w / 320, h / 200
    return group(id_, "Photo (posée par le code)",
                 picture(x - 32 * sx, y - 35 * sy, 384 * sx, 272 * sy, name), clip_path=f"url(#{id_}-clip)")


def tv_screen(id_, x, y, w, h, name, defs):
    """The TV: the C64 picture, border included, with a sketch of what the app's CRT shader draws over
    it: scanlines, a darker edge, and the tube's rounded corners."""
    line = h / 272
    corner = 0.04 * h * 3
    defs += [
        f'<pattern id="{id_}-scanlines" {attrs(x=x, y=y, width=4, height=line)} patternUnits="userSpaceOnUse">\n'
        f'  {rect(0, line * 0.55, 4, line * 0.45, 0, fill="#000000", fill_opacity=0.28)}\n</pattern>',
        radial(f"{id_}-vignette", (0, "#000000", 0), (0.65, "#000000", 0), (1, "#000000", 0.5), r=0.72),
    ]
    tube = f"M{num(x)} {num(y)} H{num(x + w)} V{num(y + h)} H{num(x)} Z {rounded_path(x, y, w, h, corner)}"
    return group(
        id_, "Télé (l’image et l’effet CRT sont calculés par l’appli)",
        rect(x, y, w, h, 0, fill="#000000"),
        picture(x, y, w, h, name),
        rect(x, y, w, h, 0, fill=f"url(#{id_}-scanlines)"),
        rect(x, y, w, h, 0, fill=f"url(#{id_}-vignette)"),
        path(tube, fill_rule="evenodd", fill="#0C0B0A"),
        layer=True)


def recess(id_, x, y, w, h, r=8):
    """A panel pressed into the case, as the monitor bank's."""
    return group(
        id_, "Panneau",
        group(f"{id_}-lip", "Lèvre", rect(x + 0.6, y + 0.8, w, h, r, fill="#EAE2D3", fill_opacity=0.9)),
        group(f"{id_}-recess", "Creux", rect(x, y, w, h, r, fill=PANEL)),
        group(f"{id_}-shade", "Ombre",
              rect(x + 0.8, y + 0.8, w - 1.6, h - 1.6, r - 0.8, fill="none", stroke="url(#panel-shade)",
                   stroke_width=1.6)))


# The C64's vent, the grooves along the back of its case.
VENT_GROOVE = "#867861"
VENT_LIGHT = "#FBF5EA"
# The Dynamic Island, on the screen of an iPhone 17 held upright, and the screen itself.
ISLAND = (138, 11, 126, 37, 18.5)
SCREEN = (0, 0, 402, 874, 55)


def corner_inset(radius, depth):
    """How far in a rounded corner of `radius` is, `depth` from the end of its curve."""
    depth = min(max(depth, 0), radius)
    return radius - math.sqrt(radius * radius - depth * depth)


def left_out(cutout, top, bottom, margin):
    """The span a groove from `top` to `bottom` leaves out round a rounded rectangle (x, y, w, h, r),
    `margin` from it, or None."""
    x, y, w, h, r = cutout
    x0, y0, x1, y1, radius = x - margin, y - margin, x + w + margin, y + h + margin, r + margin
    if bottom <= y0 or top >= y1:
        return None
    # Where the groove is nearest the cutout's middle, the cutout is widest.
    level = min(max((y0 + y1) / 2, top), bottom)
    inset = corner_inset(radius, max(y0 + radius - level, level - (y1 - radius)))
    return x0 + inset, x1 - inset


def kept_in(frame, top, bottom, margin):
    """The span a groove from `top` to `bottom` keeps inside a rounded rectangle, `margin` in from it."""
    x, y, w, h, r = frame
    x0, y0, x1, y1, radius = x + margin, y + margin, x + w - margin, y + h - margin, max(r - margin, 0)
    # Where the groove is nearest a corner, the frame is narrowest.
    depth = max(y0 + radius - top, bottom - (y1 - radius))
    inset = corner_inset(radius, depth) if depth > 0 else 0
    return x0 + inset, x1 - inset


def vent(id_, x0, x1, y0, y1, pitch=6.5, cutouts=(), margin=5.0, frame=SCREEN, edge=10.0, groove=2.3, light=1.0,
         shortest=14.0):
    """The vent along the back of the C64's case: grooves `pitch` apart across (x0, x1), from y0 to y1,
    each a dark groove over a line of light. They stop short of each cutout, a rounded rectangle
    (x, y, w, h, r) round an element, as the C64's stop round its badge and its power lamp, and
    `edge` in from the screen's edge. Pieces shorter than `shortest` are left out."""
    lights, grooves = [], []
    y = y0
    while y + groove + light <= y1 + 0.001:
        top, bottom = y, y + groove + light
        inside = kept_in(frame, top, bottom, edge)
        spans = [(max(x0, inside[0]), min(x1, inside[1]))]
        spans = [span for span in spans if span[1] - span[0] >= shortest]
        for cutout in cutouts:
            cut = left_out(cutout, top, bottom, margin)
            if cut is not None:
                spans = [piece for start, end in spans
                         for piece in ((start, min(end, cut[0])), (max(start, cut[1]), end))
                         if piece[1] - piece[0] >= shortest]
        for start, end in spans:
            grooves.append(rect(start, y, end - start, groove, groove / 2, fill=VENT_GROOVE))
            lights.append(rect(start, y + groove, end - start, light, light / 2, fill=VENT_LIGHT, fill_opacity=0.9))
        y += pitch
    return group(id_, "Évent", group(f"{id_}-light", "Lumière sous les rainures", *lights),
                 group(f"{id_}-grooves", "Rainures", *grooves), layer=True)


def zoom_buttons(cx, cy, lit=1):
    """The zoom buttons, .5, 1x and 2, centred on (cx, cy), with the app's values written on them."""
    parts = []
    for index, (value, dx) in enumerate(((".5", -44), ("1×", 0), ("2", 44))):
        parts.append(embed(zoom_button(False), f"zoom-{index}", cx + dx - 20, cy - 20))
        parts.append(text(cx + dx, cy + 4.3, value, 12, "#F4B23C" if index == lit else "#E9E3D5",
                          text_anchor="middle"))
    return group("zoom", "Zoom", *parts, layer=True)


def phone(width, height, comment, defs, *layers):
    """A mockup on the case as an iPhone 17 shows it, upright or held sideways with its top to the left:
    its screen's corners, its Dynamic Island and its home indicator."""
    if height > width:
        island = rect(138, 11, 126, 37, 18.5, fill="#000000")
        indicator = rect(134, 861, 134, 5, 2.5, fill="#1C1B19")
    else:
        island = rect(11, 138, 37, 126, 18.5, fill="#000000")
        indicator = rect(861, 134, 5, 134, 2.5, fill="#1C1B19")
    defs = [*defs, clip("screen-clip", rounded_path(0, 0, width, height, 55))]
    return document(
        width, height, comment, defs,
        group("screen", "Écran",
              group("case", "Boîtier", rect(0, 0, width, height, 0, fill="url(#mock-case)"), layer=True),
              *layers,
              group("phone", "iPhone (référence, à masquer)", island, indicator, layer=True),
              layer=True, clip_path="url(#screen-clip)"))


def mockup_defs():
    return [
        linear("mock-case", (0, "#D6CAB3"), (1, "#C6BBA3")),
        linear("mock-title", (0, "#FBF2E1"), (0.55, "#E6DAC6"), (1, "#D2C5AD")),
        linear("panel-shade", (0, "#6E5A3E", 0.45), (0.25, "#6E5A3E", 0), (1, "#6E5A3E", 0)),
        *KEY_DEFS,
        *LED_DEFS,
    ]


def title_bar(stage):
    """The top of the screen with the phone upright, where the C64 has its vent: grooves across it,
    round the Dynamic Island, the badge, the flash and CRT switches, and settings."""
    cutouts = [ISLAND, (139.5, 75.5, 122, 17, 8.5), (279, 72, 79, 24, 12), (364, 69, 30, 31, 7)]
    if stage == "live":
        # The flash switch and the badge share one clearing: the gap between them is too short for grooves.
        cutouts.append((8, 72, 253.5, 24, 12))
    parts = [
        rect(0, 0, 402, 106, 0, fill="url(#mock-title)"),
        vent("title-vent", 0, 402, 9, 98, cutouts=cutouts, shortest=36),
        rect(0, 104.8, 402, 0.6, 0, fill="#9B9281"),
        rect(0, 105.4, 402, 0.6, 0, fill="#6A6150"),
        embed(badge(), "badge", 137, 74),
        engraved(302, 88, "CRT", 10, INK, text_anchor="end"),
        embed(toggle(True), "crt-switch", 306, 73),
        embed(cream_key("settings", "", 30, 30, 7, False, "settings", scale=0.75), "settings", 360, 65),
    ]
    if stage == "live":
        parts += [engraved(12, 88, "FLASH", 10, INK), embed(toggle(False), "flash-switch", 48, 73)]
    return group("title-bar", "Barre de titre", *parts, layer=True)


def mode_dial():
    names = (("HIRES", 90), ("MULTICOLOUR", 171), ("PETSCII", 260.5), ("BBS", 317.5))
    parts = []
    for name, cx in names:
        chosen = name == "MULTICOLOUR"
        parts.append(engraved(cx, 481, name, 13, "#3E3528" if chosen else INK, text_anchor="middle"))
        parts.append(led(f"dial-{name.lower()}", cx, 491, chosen, r=2.5))
    return group("mode-dial", "Modes", *parts, layer=True)


def last_picture(x, y, clips):
    """The last picture in its frame, its top-left corner at (x, y)."""
    return group("last-picture", "Dernière photo",
                 embed(last_picture_frame(), "frame", x - 4, y - 4),
                 window("last-photo", x + 3, y + 3, 50, 50, 6, "multicolour-tv.png", clips), layer=True)


def portrait(stage):
    """The camera screen with the phone upright, live or in a review, on an iPhone 17."""
    width, height = 402, 874
    tv_height = width / TV_ASPECT
    defs = mockup_defs()
    clips = []
    # The vent behind the shutter row, round the last picture, the capture key and its label, the flip
    # key, and the home indicator.
    shutter = [(28, 757.7, 56, 58, 8), (117.8, 758.7, 166.3, 54, 27), (134, 861, 134, 5, 2.5)]
    if stage == "live":
        shutter += [(172, 816.5, 58, 14, 7), (318, 757.7, 56, 58, 12)]
    else:
        shutter.append((134, 817, 134, 15, 7.5))
    layers = [
        title_bar(stage),
        tv_screen("tv", 0, 106, width, tv_height, "multicolour-tv.png", defs),
        vent("shutter-vent", 0, width, 662 if stage == "live" else 688, 868, cutouts=shutter),
    ]
    capture_y = 741.9
    if stage == "live":
        layers += [
            zoom_buttons(201, 439.2),
            mode_dial(),
            embed(monitor_bank(), "bank", 0, 498, drop=("backdrop", "case")),
            group("shutter", "Prise de vue",
                  embed(capture_key(pressed=False), "capture", 103.1, capture_y, 1.4),
                  embed(cream_key("flip", "", 56, 56, 12, False, "flip", scale=1.35), "flip", 314, 753.7),
                  layer=True),
        ]
    else:
        strip = []
        modes = (("HIRES", "hires-tv.png"), ("MULTI", "multicolour-tv.png"), ("PETSCII", "petscii-tv.png"),
                 ("BBS", "bbs-tv.png"))
        for index, (name, file) in enumerate(modes):
            x, y = 16 + 88 * index, 426.2
            chosen = name == "MULTI"
            strip += [
                rect(x + 3, y + 3, 72, 48, 3, fill="#1C1B19"),
                window(f"strip-{name.lower()}", x + 3, y + 3, 72, 48, 3, file, clips),
                engraved(x + 39, 495, name, 10, "#3E3528" if chosen else INK, text_anchor="middle",
                         letter_spacing=0.8),
            ]
            if chosen:
                strip.append(rect(x + 1, y + 1, 76, 52, 6, fill="none", stroke="#F4B23C", stroke_width=2))
        monitors = (("tv", "TV", 0, 0), ("mon", "MON", 1, 0), ("sharp", "SHARP", 2, 0), ("bw", "B&amp;W", 0, 1),
                    ("amber", "AMBER", 1, 1), ("green", "GREEN", 2, 1))
        bank = [recess("review-panel", 16, 520, 370, 86), engraved(22, 515, "MONITOR", 9, INK, letter_spacing=1.4)]
        for id_, name, column, row in monitors:
            x, y = 28 + 118 * column, 535 + 36 * row
            chosen = id_ == "tv"
            bank += [monitor_key(f"review-key-{id_}", x, y, chosen, 26, 26, 3.5),
                     led(f"review-led-{id_}", x + 38, y + 13, chosen),
                     engraved(x + 50, y + 17, name, 11, INK)]
        actions = []
        for index, (name, caption) in enumerate((("share", "SHARE"), ("save", "SAVE"), ("send", "SEND TO C64"),
                                                 ("delete", "DELETE"))):
            x = 76 + 66 * index
            actions += [embed(action_key(name, pressed=False), f"action-{name}", x - 4, 614),
                        engraved(x + 26, 674, caption, 9.5, INK, text_anchor="middle", letter_spacing=0.5)]
        layers += [
            group("mode-strip", "Bande des modes", *strip, layer=True),
            group("review-bank", "Moniteurs", *bank, layer=True),
            group("actions", "Actions", *actions, layer=True),
            group("shutter", "Retour à la caméra",
                  embed(capture_key(pressed=False), "capture", 103.1, capture_y, 1.4, drop=("backdrop", "label")),
                  engraved(201, 828, "BACK TO CAMERA", 11, INK, text_anchor="middle", letter_spacing=1.6),
                  layer=True),
        ]
    layers.append(last_picture(28, 757.7, clips))
    state = "live" if stage == "live" else "in a review, after a shot"
    return phone(width, height, f"The camera screen with the phone upright, {state}, on an iPhone 17.",
                 [*defs, *clips], *layers)


def landscape():
    """The camera screen with the phone held sideways, its top to the left, on an iPhone 17: the TV in
    the middle, between two columns of controls."""
    width, height = 874, 402
    tv_width = 530
    tv_height = tv_width / TV_ASPECT
    defs = mockup_defs()
    clips = []
    left = [
        embed(badge(), "badge", 66.4, 12, 0.9),
        engraved(112, 58.5, "FLASH", 9, INK, text_anchor="end"), embed(toggle(False), "flash-switch", 116, 44),
        engraved(112, 86.5, "CRT", 9, INK, text_anchor="end"), embed(toggle(True), "crt-switch", 116, 72),
    ]
    # As the app's: cells 56 by 24, each its lamp and its mode's name.
    for name, x, y in (("HIRES", 66, 106), ("MULTI", 126, 106), ("PETSCII", 66, 134), ("BBS", 126, 134)):
        chosen = name == "MULTI"
        left += [led(f"dial-{name.lower()}", x + 3, y + 12, chosen, r=3),
                 engraved(x + 10, y + 16, name, 11, "#3E3528" if chosen else INK, stretch=NARROW)]
    for id_, name, column, row in (("tv", "TV", 0, 0), ("bw", "B&amp;W", 1, 0), ("mon", "MON", 0, 1),
                                   ("amber", "AMBER", 1, 1), ("sharp", "SHARP", 0, 2), ("green", "GREEN", 1, 2)):
        x, y = 66 + 62 * column, 170 + 50 * row
        chosen = id_ == "tv"
        drop = 0.4 if chosen else 0
        # The lamp, 6 across, 4 from the name, both centred on the key, as the app's label.
        start = x + (54 - 10 - text_width(name, 10, NARROW)) / 2
        left += [embed(cream_key("wide", "", 54, 44, 6, chosen), f"key-{id_}", x - 4, y - 4),
                 led(f"led-{id_}", start + 3, y + 22 + drop, chosen, r=3),
                 text(start + 10, y + 25.5 + drop, name, 10, "#3E3528" if chosen else "#4F4537", stretch=NARROW)]
    right = [
        embed(cream_key("flip", "", 56, 56, 12, False, "flip", scale=1.35), "flip", 727, 8),
        embed(cream_key("settings", "", 30, 30, 7, False, "settings", scale=0.75), "settings", 791, 21),
        embed(capture_key(pressed=False), "capture", 711.6, 171.3, 0.95, drop=("backdrop", "label")),
    ]
    tv_x = 186
    # The vent behind each column, round its elements, the Dynamic Island and the home indicator.
    frame = (0, 0, width, height, 55)
    island = (11, 138, 37, 126, 18.5)
    left_cutouts = [island, (68.65, 13.35, 109.8, 15.3, 7.65), (78, 44, 90, 50, 10), (64, 112, 118, 42, 8),
                    (66, 170, 116, 146, 6)]
    right_cutouts = [(731, 12, 56, 58, 12), (795, 25, 30, 31, 7), (721.6, 182.7, 112.9, 37, 18.3),
                     (750, 332, 56, 58, 8), (861, 134, 5, 134, 2.5)]
    layers = [
        vent("left-vent", 0, tv_x - 6, 8, 394, cutouts=left_cutouts, frame=frame),
        vent("right-vent", tv_x + tv_width + 6, width, 8, 394, cutouts=right_cutouts, frame=frame),
        tv_screen("tv", tv_x, (height - tv_height) / 2, tv_width, tv_height, "multicolour-tv.png", defs),
        zoom_buttons(tv_x + tv_width / 2, (height + tv_height) / 2 - tv_height * 37 / 272 / 2),
        group("left-column", "Colonne de gauche", *left, layer=True),
        group("right-column", "Colonne de droite", *right, layer=True),
        last_picture(750, 332, clips),
    ]
    return phone(width, height, "The camera screen with the phone held sideways, top to the left, on an iPhone 17.",
                 [*defs, *clips], *layers)


# MARK: - Files


FILES = {
    "capture-up": lambda: capture_key(pressed=False),
    "capture-down": lambda: capture_key(pressed=True),
    "monitor-key-up": lambda: monitor_key_file(pressed=False),
    "monitor-key-down": lambda: monitor_key_file(pressed=True),
    "led-off": lambda: led_file(on=False),
    "led-on": lambda: led_file(on=True),
    "monitor-bank": monitor_bank,
    "badge": badge,
    **{f"action-{name}-{state}": (lambda name=name, state=state: action_key(name, state == "down"))
       for name in ACTIONS for state in ("up", "down")},
    **{f"flip-key-{state}": (lambda state=state: cream_key(
        "flip", f"The key that turns the camera round, {state}, 56 points square.", 56, 56, 12, state == "down",
        "flip", scale=1.35)) for state in ("up", "down")},
    **{f"small-key-{icon}-{state}": (lambda icon=icon, state=state: cream_key(
        f"small-{icon}", f"A small key, {state}, 34 by 42 points: {icon}, beside the TV in landscape.", 34, 42, 8,
        state == "down", icon, icon_y=4 + 16, scale=0.9, lamp=icon != "settings"))
       for icon in ("flash", "crt", "settings") for state in ("up", "down")},
    "monitor-key-wide-up": lambda: cream_key(
        "wide", "A monitor key in landscape, up, 54 by 44 points: the app writes its lamp and name on it.", 54, 44, 6,
        False),
    "monitor-key-wide-down": lambda: cream_key(
        "wide", "A monitor key in landscape, pressed, 54 by 44 points: the app writes its lamp and name on it.", 54,
        44, 6, True),
    "toggle-on": lambda: toggle(True),
    "toggle-off": lambda: toggle(False),
    "zoom-button-up": lambda: zoom_button(False),
    "zoom-button-down": lambda: zoom_button(True),
    "last-picture-frame": last_picture_frame,
    "mockup-portrait-live": lambda: portrait("live"),
    "mockup-portrait-review": lambda: portrait("review"),
    "mockup-landscape-live": landscape,
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
