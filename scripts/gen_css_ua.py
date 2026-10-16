#!/usr/bin/env python3
"""Generate lib/e/fmt/css/ua.e from lib/e/fmt/css/ua.css (the user agent style sheet).

The CSS stays a plain file to edit; this writes it as a Neper function that builds the text, because a string literal
ends at the end of its line. Run after editing ua.css:  python scripts/gen_css_ua.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSS = ROOT / "lib" / "e" / "fmt" / "css" / "ua.css"
OUT = ROOT / "lib" / "e" / "fmt" / "css" / "ua.e"


def literal(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + escaped + '"'


def main() -> None:
    lines = [line.rstrip() for line in CSS.read_text(encoding="utf-8").splitlines() if line.strip()]
    body = "\n".join(f"    try str.push(&b, {literal(line + chr(10))})" for line in lines)
    OUT.write_text(f"""// The user agent style sheet (tracker 1.13f), generated from ua.css by scripts/gen_css_ua.py -- edit ua.css, not this file.
//
// `source` is its text; `rules` loads it into the cascade's rule list at the user agent origin, in the order `order_start`
// onward (user agent rules rank under every author rule whatever their order).

use e.fmt.css.sheet as sheet
use e.mem
use e.str

fn source(a: *mem.Arena) -> (str, err) {{
    var b = try str.builder(a, {sum(len(l) + 1 for l in lines) + 64})
{body}
    ret (str.done(&b), ok)
}}

fn rules(a: *mem.Arena, env: sheet.MediaEnv) -> (sheet.Loaded, err) {{
    let text = try source(a)
    let (loaded, e) = sheet.parse_sheet(a, env, text)
    ret (loaded, e)
}}
""", encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(lines)} lines of CSS)")


if __name__ == "__main__":
    main()
