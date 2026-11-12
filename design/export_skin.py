#!/usr/bin/env python3
"""Puts the camera screen's elements into the app, as vector images in its asset catalog.

Each file in design/svg that the app draws is copied into App/Resources/Assets.xcassets/Skin without its
reference layers: the surface it sits on, and the words and lamps the app draws itself. Xcode keeps SVG
images as vectors, so they stay sharp at every size. The files in design/svg are the ones to edit: run
this again after changing one.

Usage: python3 design/export_skin.py          writes the images
       python3 design/export_skin.py --check  fails if they differ from design/svg, as CI does
"""

import json
import pathlib
import re
import shutil
import sys
import xml.etree.ElementTree as ET

DESIGN = pathlib.Path(__file__).resolve().parent
SKIN = DESIGN.parent / "App" / "Resources" / "Assets.xcassets" / "Skin"
SVG = "http://www.w3.org/2000/svg"
INKSCAPE = "http://www.inkscape.org/namespaces/inkscape"

# The elements the app draws, by their files' names in design/svg.
NAMES = [
    *(f"capture-{state}" for state in ("up", "down")),
    *(f"monitor-key-{state}" for state in ("up", "down")),
    *(f"monitor-key-wide-{state}" for state in ("up", "down")),
    *(f"settings-key-{state}" for state in ("up", "down")),
    *(f"flip-key-{state}" for state in ("up", "down")),
    *(f"action-{name}-{state}" for name in ("share", "save", "send", "delete") for state in ("up", "down")),
    *(f"zoom-button-{state}" for state in ("up", "down")),
    *(f"toggle-{state}" for state in ("on", "off")),
    *(f"led-{state}" for state in ("on", "off")),
    "badge",
    "last-picture-frame",
]

# Layers there for reference only, by their labels: what the element sits on, and what the app draws.
REFERENCE = re.compile(r"\((référence|écrits? par le code|posé par le code)")
# What Xcode's SVG support leaves out, or what has no place in an element.
UNSUPPORTED = ("text", "filter", "mask", "image", "pattern", "style", "foreignObject")

ET.register_namespace("", SVG)


def stripped(name):
    """The element's drawing, without its reference layers or Inkscape's own attributes."""
    root = ET.fromstring((DESIGN / "svg" / f"{name}.svg").read_text(encoding="utf-8"))
    for parent in list(root.iter()):
        for child in list(parent):
            if REFERENCE.search(child.get(f"{{{INKSCAPE}}}label", "")):
                parent.remove(child)
    for element in root.iter():
        for key in [key for key in element.attrib if key.startswith(f"{{{INKSCAPE}}}")]:
            del element.attrib[key]
        tag = element.tag.rpartition("}")[2]
        if tag in UNSUPPORTED:
            sys.exit(f"design/svg/{name}.svg: the app cannot draw its <{tag}>; keep it in a reference layer.")
    ET.indent(root, space="  ")
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f"<!-- Written by design/export_skin.py from design/svg/{name}.svg: edit that file instead. -->\n"
        + ET.tostring(root, encoding="unicode") + "\n")


def contents(images=None):
    """An asset catalog folder's Contents.json, as Xcode writes it."""
    value = {"info": {"author": "xcode", "version": 1}}
    if images is not None:
        value = {"images": images, **value, "properties": {"preserves-vector-representation": True}}
    return json.dumps(value, indent=2, separators=(",", " : ")) + "\n"


def wanted():
    """Every file the Skin folder should hold, by its path in it."""
    files = {"Contents.json": contents()}
    for name in NAMES:
        files[f"{name}.imageset/Contents.json"] = contents([{"filename": f"{name}.svg", "idiom": "universal"}])
        files[f"{name}.imageset/{name}.svg"] = stripped(name)
    return files


def main(arguments):
    files = wanted()
    present = {str(path.relative_to(SKIN)) for path in SKIN.rglob("*") if path.is_file()} if SKIN.exists() else set()
    if arguments == ["--check"]:
        stale = sorted(path for path, text in files.items()
                       if path not in present or (SKIN / path).read_text(encoding="utf-8") != text)
        extra = sorted(present - set(files))
        if stale or extra:
            sys.exit("The app's skin differs from design/svg: run python3 design/export_skin.py. "
                     f"Out of date: {', '.join(stale) or 'none'}. Not in design/svg: {', '.join(extra) or 'none'}.")
        return
    if arguments:
        sys.exit(__doc__)
    for folder in SKIN.glob("*.imageset"):
        if folder.name.removesuffix(".imageset") not in NAMES:
            shutil.rmtree(folder)
    for path, text in files.items():
        (SKIN / path).parent.mkdir(parents=True, exist_ok=True)
        (SKIN / path).write_text(text, encoding="utf-8")
    print(f"Wrote {len(NAMES)} images to {SKIN.relative_to(DESIGN.parent)}.")


if __name__ == "__main__":
    main(sys.argv[1:])
