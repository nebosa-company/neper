#!/usr/bin/env python3
"""Generate lib/e/web/dom_js.e from lib/e/web/js/*.js (the page's DOM and window layer, written in JavaScript).

The files are concatenated in name order inside one function so they share their top-level names; the result is written
as Neper functions that build the text (a string literal ends at its line). Run after editing a file:
    python scripts/gen_web_js.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "lib" / "e" / "web" / "js"
OUT = ROOT / "lib" / "e" / "web" / "dom_js.e"
BACKSLASH = chr(92)
NEWLINE = chr(10)
CHUNK = 250


def literal(text: str) -> str:
    escaped = text.replace(BACKSLASH, BACKSLASH * 2).replace('"', BACKSLASH + '"').replace(NEWLINE, BACKSLASH + "n")
    return '"' + escaped + '"'


def main() -> None:
    lines = ["(function (global) {", "'use strict';"]
    for path in sorted(SRC.glob("*.js")):
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("//"):
                continue
            lines.append(line.rstrip())
    lines.append("})(this);")
    parts = [lines[i:i + CHUNK] for i in range(0, len(lines), CHUNK)]
    size = sum(len(l) + 1 for l in lines) + 64
    out = [
        "// The page's DOM and window layer, generated from js/*.js by scripts/gen_web_js.py -- edit those, not this file.",
        "",
        "use e.mem",
        "use e.str",
        "",
    ]
    for i, part in enumerate(parts):
        out.append(f"fn part{i}(b: *str.Builder) -> err {{")
        for line in part:
            out.append(f"    try str.push(b, {literal(line + NEWLINE)})")
        out.append("    ret ok")
        out.append("}")
        out.append("")
    out.append("fn source(a: *mem.Arena) -> (str, err) {")
    out.append(f"    var b = try str.builder(a, {size})")
    for i in range(len(parts)):
        out.append(f"    try part{i}(&b)")
    out.append("    ret (str.done(&b), ok)")
    out.append("}")
    OUT.write_text(NEWLINE.join(out) + NEWLINE, encoding="utf-8", newline=NEWLINE)
    print(f"{len(lines)} lines in {len(parts)} parts")


main()
