#!/usr/bin/env python3
"""Generate favicon.ico, apple-touch-icon.png and site.webmanifest, and write
patch.exe specs that add the icon <link> tags to every docs/**/*.html page.

    build/uv-python/cpython-3.12.13-windows-x86_64-none/python.exe scripts/gen_favicon.py
    build/windows/patch.exe <spec>   (for each spec the script writes)

favicon.ico embeds the existing 512x512 docs/gtm/logo/neper-icon.png as a PNG image
(ICO has no 512 size field: width/height 0 mean 256, and browsers read the PNG's own
size). apple-touch-icon.png is the same 512 icon copied, because the repo has no
image resizer; 512 replaces the ideal 180 and is scaled by iOS.
"""

from __future__ import annotations

import json
import os
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(REPO, "docs")
ICON = os.path.join(DOCS, "gtm", "logo", "neper-icon.png")

TAGS = (
    '<link rel="icon" href="/favicon.ico" sizes="any">\n'
    '<link rel="icon" type="image/svg+xml" href="/gtm/logo/neper-icon.svg">\n'
    '<link rel="apple-touch-icon" href="/apple-touch-icon.png">\n'
    '<link rel="manifest" href="/site.webmanifest">\n'
)


def write_assets() -> None:
    with open(ICON, "rb") as handle:
        png = handle.read()
    width, height = struct.unpack(">II", png[16:24])
    if width != height or width > 256:
        print(f"note: icon is {width}x{height}; ICO stores 256 for >=256")
    entry_size = 0 if width >= 256 else width
    header = struct.pack("<HHH", 0, 1, 1)
    entry = struct.pack("<BBBBHHII", entry_size, entry_size, 0, 0, 1, 32, len(png), 22)
    with open(os.path.join(DOCS, "favicon.ico"), "wb") as handle:
        handle.write(header + entry + png)
    with open(os.path.join(DOCS, "apple-touch-icon.png"), "wb") as handle:
        handle.write(png)
    manifest = {
        "name": "Neper",
        "short_name": "Neper",
        "icons": [
            {"src": "/gtm/logo/neper-icon.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
            {"src": "/apple-touch-icon.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
        ],
        "theme_color": "#145db2",
        "background_color": "#ffffff",
        "display": "browser",
        "start_url": "/",
    }
    with open(os.path.join(DOCS, "site.webmanifest"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")


def page_anchor(rel: str) -> tuple[str, bool]:
    """(anchor line, insert tags after it) whose single occurrence receives the tags."""
    if rel == "get-started.html":
        return "<head>", True
    if rel == "gtm/og/card.html":
        return '<meta name="robots" content="noindex">', True
    return "</head>", False


def write_specs() -> list[str]:
    pages = []
    for root, _dirs, files in os.walk(DOCS):
        for name in files:
            if name.endswith(".html"):
                pages.append(os.path.relpath(os.path.join(root, name), DOCS).replace(os.sep, "/"))
    pages.sort()
    spec_dir = os.path.join(REPO, "build", "seo-favicon-specs")
    os.makedirs(spec_dir, exist_ok=True)
    for old in os.listdir(spec_dir):
        if old.endswith(".spec"):
            os.remove(os.path.join(spec_dir, old))
    specs = []
    for start in range(0, len(pages), 16):
        chunk = pages[start : start + 16]
        parts = []
        for rel in chunk:
            old, after = page_anchor(rel)
            new = (old + "\n" + TAGS.rstrip("\n")) if after else (TAGS + old)
            parts.append(f"@@@ docs/{rel}\n<<<\n{old}\n===\n{new}\n>>>\n")
        path = os.path.join(spec_dir, f"favicon-{start // 16:02d}.spec")
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("".join(parts))
        specs.append(path)
    return specs


def main() -> int:
    write_assets()
    specs = write_specs()
    print(f"wrote docs/favicon.ico, docs/apple-touch-icon.png, docs/site.webmanifest")
    for spec in specs:
        print(spec)
    return 0


if __name__ == "__main__":
    sys.exit(main())
