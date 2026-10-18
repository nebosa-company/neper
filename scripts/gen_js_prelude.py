#!/usr/bin/env python3
"""Generate lib/e/js/prelude.e from lib/e/js/prelude.js (built-ins written in JavaScript, run into every new realm).

The JavaScript stays a plain file to edit; this writes it as a Neper function that builds the text, because a string
literal ends at the end of its line. Run after editing it:  python scripts/gen_js_prelude.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "lib" / "e" / "js" / "prelude.js"
OUT = ROOT / "lib" / "e" / "js" / "prelude.e"
BACKSLASH = chr(92)
NEWLINE = chr(10)


def literal(text: str) -> str:
    escaped = text.replace(BACKSLASH, BACKSLASH * 2).replace('"', BACKSLASH + '"').replace(NEWLINE, BACKSLASH + "n")
    return '"' + escaped + '"'


def generate(name: str, what: str) -> None:
    src = ROOT / "lib" / "e" / "js" / (name + ".js")
    out = ROOT / "lib" / "e" / "js" / (name + ".e")
    if src.exists():
        text = src.read_text(encoding="utf-8")
    else:  # a directory of numbered parts, joined in order
        text = NEWLINE.join(p.read_text(encoding="utf-8") for p in sorted((ROOT / "lib" / "e" / "js" / name).glob("*.js")))
    lines = [line.rstrip() for line in text.splitlines() if line.strip()]
    size = sum(len(l) + 1 for l in lines) + 64
    pushes = NEWLINE.join(f"    try str.push(&b, {literal(line + NEWLINE)})" for line in lines)
    out.write_text(f"""// {what}, generated from {name}.js (or the {name}/ parts) by scripts/gen_js_prelude.py -- edit that, not this file.

use e.mem
use e.str

fn source(a: *mem.Arena) -> (str, err) {{
    var b = try str.builder(a, {size})
{pushes}
    ret (str.done(&b), ok)
}}
""", encoding="utf-8", newline=NEWLINE)


def main() -> None:
    generate("prelude", "The JavaScript-written built-ins")
    generate("temporal", "The Temporal built-ins")
    generate("intl", "The Intl built-ins")


main()
