#!/usr/bin/env python3
"""Writes the accent colours people can choose in Settings into SerafinDesign's Theme.xcassets.

Each colour is a hue in OKLCH, made as colourful as sRGB allows at four set luminances, so every choice is as
readable as Serafin's default violet (the AccentFallback colour set, which this script leaves alone):

- light: 5.6:1 on white, so white text sits on it and it reads as text on the light background;
- dark: between 4.5:1 on black and 4.5:1 under white text, so it does both on the dark background;
- light with Increase Contrast: 9:1 on white;
- dark with Increase Contrast: 7:1 on black.

Run it after changing a hue: python3 scripts/accents.py
"""
import json
import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Packages/SerafinKit/Sources/SerafinDesign/Resources/Theme.xcassets"

# Name, OKLCH hue in degrees, and the most chroma to use. Graphite has none.
ACCENTS = [
    ("Indigo", 272, 0.20),
    ("Blue", 258, 0.20),
    ("Sky", 238, 0.16),
    ("Cyan", 215, 0.14),
    ("Teal", 190, 0.13),
    ("Mint", 168, 0.14),
    ("Green", 145, 0.17),
    ("Olive", 120, 0.15),
    ("Amber", 80, 0.15),
    ("Orange", 55, 0.18),
    ("Red", 28, 0.21),
    ("Crimson", 10, 0.21),
    ("Pink", 355, 0.20),
    ("Magenta", 330, 0.22),
    ("Purple", 310, 0.22),
    ("Graphite", 0, 0.0),
]

# Relative luminance for each appearance, matching the default violet's.
TARGETS = {
    ("light", False): 0.137,
    ("dark", False): 0.179,
    ("light", True): 0.066,
    ("dark", True): 0.315,
}


def oklch_to_linear(lightness, chroma, hue):
    a = chroma * math.cos(math.radians(hue))
    b = chroma * math.sin(math.radians(hue))
    l_ = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (lightness - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (
        4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
        -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
        -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_,
    )


def luminance(linear):
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def in_gamut(linear):
    return all(-1e-6 <= c <= 1 + 1e-6 for c in linear)


def lightness_for(target, chroma, hue):
    low, high = 0.0, 1.0
    for _ in range(60):
        middle = (low + high) / 2
        if luminance(oklch_to_linear(middle, chroma, hue)) < target:
            low = middle
        else:
            high = middle
    return (low + high) / 2


def colour(target, hue, most_chroma):
    """The most colourful in-gamut colour of `hue` at luminance `target`, as linear RGB."""
    chroma = most_chroma
    while chroma > 0:
        linear = oklch_to_linear(lightness_for(target, chroma, hue), chroma, hue)
        if in_gamut(linear):
            return linear
        chroma -= 0.002
    return oklch_to_linear(lightness_for(target, 0, hue), 0, hue)


def encode(linear_component):
    c = min(max(linear_component, 0), 1)
    srgb = 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return round(srgb * 255)


def entry(rgb, appearances):
    value = {
        "color": {
            "color-space": "srgb",
            "components": {
                "alpha": "1.000",
                "red": f"0x{rgb[0]:02X}",
                "green": f"0x{rgb[1]:02X}",
                "blue": f"0x{rgb[2]:02X}",
            },
        },
        "idiom": "universal",
    }
    if appearances:
        value["appearances"] = appearances
    return value


def main():
    dark = {"appearance": "luminosity", "value": "dark"}
    high = {"appearance": "contrast", "value": "high"}
    for name, hue, chroma in ACCENTS:
        rgbs = {key: tuple(encode(c) for c in colour(target, hue, chroma)) for key, target in TARGETS.items()}
        contents = {
            "colors": [
                entry(rgbs[("light", False)], None),
                entry(rgbs[("dark", False)], [dark]),
                entry(rgbs[("light", True)], [high]),
                entry(rgbs[("dark", True)], [dark, high]),
            ],
            "info": {"author": "xcode", "version": 1},
        }
        folder = ASSETS / f"Accent{name}.colorset"
        folder.mkdir(exist_ok=True)
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2, separators=(",", " : ")) + "\n")
        print(name, " ".join("#%02X%02X%02X" % rgbs[key] for key in TARGETS))


if __name__ == "__main__":
    main()
