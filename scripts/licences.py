#!/usr/bin/env python3
"""Writes the Licences screen's list from the packages Serafin builds with.

Reads Packages/SerafinKit/Package.resolved for each package and its exact version, finds the package's checkout,
and writes its licence and notice texts to SerafinFeatures' Licences.json. Run it after any change to the packages:

    swift package --package-path Packages/SerafinKit resolve
    python3 scripts/licences.py

A test checks that the list names every package in Package.resolved at its pinned version.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOLVED = ROOT / "Packages/SerafinKit/Package.resolved"
CHECKOUTS = ROOT / "Packages/SerafinKit/.build/checkouts"
OUTPUT = ROOT / "Packages/SerafinKit/Sources/SerafinFeatures/Resources/Licences.json"

# The names people know each package by.
NAMES = {
    "jellyfin-sdk-swift": "Jellyfin SDK for Swift",
    "get": "Get",
    "nuke": "Nuke",
    "swift-atomics": "Swift Atomics",
    "swift-collections": "Swift Collections",
    "swift-nio": "SwiftNIO",
    "swift-nio-transport-services": "SwiftNIO Transport Services",
    "swift-system": "Swift System",
}


def licence_name(text):
    if "Mozilla Public License Version 2.0" in text:
        return "MPL-2.0"
    if "Apache License" in text and "Version 2.0" in text:
        return "Apache-2.0"
    if "MIT License" in text or "Permission is hereby granted, free of charge" in text:
        return "MIT"
    sys.exit(f"Unrecognised licence: {text[:80]!r}")


def checkout(identity):
    for folder in CHECKOUTS.iterdir():
        if folder.name.lower() == identity:
            return folder
    sys.exit(f"No checkout for {identity}; run `swift package --package-path Packages/SerafinKit resolve` first")


def read_first(folder, stems):
    for path in sorted(folder.iterdir()):
        if path.is_file() and path.name.split(".")[0].upper() in stems:
            return path.read_text(encoding="utf-8").strip()
    return None


def main():
    pins = json.loads(RESOLVED.read_text())["pins"]
    packages = []
    for pin in sorted(pins, key=lambda pin: NAMES.get(pin["identity"], pin["identity"]).lower()):
        folder = checkout(pin["identity"])
        text = read_first(folder, {"LICENSE", "LICENCE"})
        if text is None:
            sys.exit(f"No licence file in {folder}")
        packages.append({
            "identity": pin["identity"],
            "name": NAMES.get(pin["identity"], pin["identity"]),
            "version": pin["state"]["version"],
            "url": pin["location"].removesuffix(".git"),
            "licence": licence_name(text),
            "text": text,
            "notice": read_first(folder, {"NOTICE"}),
        })
    OUTPUT.write_text(json.dumps(packages, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(packages)} packages to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
