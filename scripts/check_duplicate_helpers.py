#!/usr/bin/env python3
"""Count functions in lib/e whose normalised bodies are identical across modules (L255).

A function is `fn name(params) -> ret { body }`. The key is its parameter list, return type and body with comments
removed and whitespace collapsed, so two helpers with the same name or different names but the same text collide.
Bodies shorter than MIN_BODY characters are ignored: a one-line forwarder is not a duplicated helper.

    python scripts/check_duplicate_helpers.py            check against docs/duplicate-helpers.json (exit 1 if a count rose)
    python scripts/check_duplicate_helpers.py --list     print every group
    python scripts/check_duplicate_helpers.py --update   lower the recorded counts to the current ones
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib" / "e"
BASELINE = ROOT / "docs" / "duplicate-helpers.json"
MIN_BODY = 60
FN = re.compile(r"^fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*(\[[^\]]*\])?\s*\(", re.M)


def strip_comments(text):
    out = []
    i = 0
    in_str = False
    while i < len(text):
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif c == "/" and text[i:i + 2] == "//":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def match_close(text, start, open_ch, close_ch):
    depth = 0
    i = start
    in_str = False
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def functions(path):
    text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    for m in FN.finditer(text):
        paren = text.index("(", m.end() - 1)
        close = match_close(text, paren, "(", ")")
        if close < 0:
            continue
        brace = text.find("{", close)
        if brace < 0:
            continue
        between = text[close + 1:brace]
        if "\n" in between.strip() or ";" in between:
            continue
        end = match_close(text, brace, "{", "}")
        if end < 0:
            continue
        body = " ".join(text[brace + 1:end].split())
        if len(body) < MIN_BODY:
            continue
        params = " ".join(text[paren + 1:close].split())
        yield m.group(1), (params, " ".join(between.split()), body)


def scan():
    groups = {}
    for path in sorted(LIB.rglob("*.e")):
        rel = path.relative_to(ROOT).as_posix()
        for name, key in functions(path):
            groups.setdefault(key, []).append((rel, name))
    dup = {}
    for key, where in groups.items():
        files = {f for f, _ in where}
        if len(files) > 1:
            dup[key] = where
    return dup


def main(argv):
    dup = scan()
    current = {"groups": len(dup), "copies": sum(len(v) - 1 for v in dup.values())}
    if "--list" in argv:
        for key, where in sorted(dup.items(), key=lambda kv: -len(kv[1])):
            print(f"{len(where)} copies, {len(key[2])} chars: " + ", ".join(f"{f}:{n}" for f, n in where))
    if BASELINE.exists():
        base = json.loads(BASELINE.read_text(encoding="utf-8"))
    else:
        base = None
    if "--update" in argv or base is None:
        if base is not None and (current["groups"] > base["groups"] or current["copies"] > base["copies"]):
            print(f"refusing to raise the recorded counts: {current} against {base}")
            return 1
        BASELINE.write_text(json.dumps(current, indent=2) + "\n", encoding="utf-8")
        print(f"recorded {current}")
        return 0
    print(f"duplicate helpers: {current['groups']} groups, {current['copies']} redundant copies (recorded {base['groups']} and {base['copies']})")
    if current["groups"] > base["groups"] or current["copies"] > base["copies"]:
        print("the count rose: use the existing helper (e.str, e.bytes, e.algo.hash, e.text.utf8) instead of adding a copy")
        return 1
    if current["groups"] < base["groups"] or current["copies"] < base["copies"]:
        print("the count fell: run with --update to record it")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
