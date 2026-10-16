#!/usr/bin/env python3
"""Generate lib/e/fmt/css/ua.e from lib/e/fmt/css/ua.css and ua_quirks.css (the user agent style sheets).

The CSS stays plain files to edit; this writes them as Neper functions that build the text, because a string literal
ends at the end of its line. Run after editing either:  python scripts/gen_css_ua.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSS = ROOT / "lib" / "e" / "fmt" / "css" / "ua.css"
QUIRKS = ROOT / "lib" / "e" / "fmt" / "css" / "ua_quirks.css"
OUT = ROOT / "lib" / "e" / "fmt" / "css" / "ua.e"


def literal(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + escaped + '"'


def pushes(lines):
    return "\n".join(f"    try str.push(&b, {literal(line + chr(10))})" for line in lines)


def main() -> None:
    lines = [line.rstrip() for line in CSS.read_text(encoding="utf-8").splitlines() if line.strip()]
    qlines = [line.rstrip() for line in QUIRKS.read_text(encoding="utf-8").splitlines() if line.strip()]
    size = sum(len(l) + 1 for l in lines) + 64
    qsize = size + sum(len(l) + 1 for l in qlines)
    OUT.write_text(f"""// The user agent style sheets (tracker 1.13f), generated from ua.css and ua_quirks.css by scripts/gen_css_ua.py -- edit
// those, not this file.
//
// `source` is the ordinary sheet's text; `rules` loads it into the cascade's rule list at the user agent origin (user agent
// rules rank under every author rule whatever their order). A document in quirks mode takes `rules_for(.., true)`: the same
// sheet followed by the quirks-only rules.

use e.fmt.css.sheet as sheet
use e.mem
use e.str

fn source(a: *mem.Arena) -> (str, err) {{
    var b = try str.builder(a, {size})
{pushes(lines)}
    ret (str.done(&b), ok)
}}

fn rules(a: *mem.Arena, env: sheet.MediaEnv) -> (sheet.Loaded, err) {{
    let text = try source(a)
    let (loaded, e) = sheet.parse_sheet(a, env, text)
    ret (loaded, e)
}}

fn quirks_source(a: *mem.Arena) -> (str, err) {{
    var b = try str.builder(a, {qsize})
{pushes(lines)}
{pushes(qlines)}
    ret (str.done(&b), ok)
}}

fn rules_for(a: *mem.Arena, env: sheet.MediaEnv, quirks: bool) -> (sheet.Loaded, err) {{
    if !quirks {{
        let (plain, pe) = rules(a, env)
        ret (plain, pe)
    }}
    let text = try quirks_source(a)
    let (loaded, e) = sheet.parse_sheet(a, env, text)
    ret (loaded, e)
}}
""", encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(lines)} + {len(qlines)} lines of CSS)")


if __name__ == "__main__":
    main()
