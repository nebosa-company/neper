#!/usr/bin/env python3
"""Check that every library name docs/algos.md maps an algorithm to exists in lib/e (L249).

A row maps with an arrow and a backticked name. The name resolves when lib/e/<module path>.e (or one of its per-host
variants lib/e/<module path>.<host>.e) declares `name` as a function, type, constant or error. A row that names a compiler
intrinsic says "(the intrinsic's spelling" after the name and is skipped. Exit 1 lists every name that does not resolve.

    python scripts/check_algos_names.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib" / "e"
DOC = ROOT / "docs" / "algos.md"
DECL = re.compile(r"^(?:fn|type|const|error)\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
NAME = re.compile(r"`(e\.[A-Za-z0-9_.]+)`( \(the intrinsic's spelling)?")
cache = {}


def symbols(module_file):
    if module_file in cache:
        return cache[module_file]
    found = set()
    paths = [module_file] + sorted(module_file.parent.glob(module_file.stem + ".*.e"))
    for p in paths:
        if p.exists():
            found |= set(DECL.findall(p.read_text(encoding="utf-8", errors="replace")))
    cache[module_file] = found
    return found


def resolves(name):
    segs = name.split(".")[1:]
    for k in range(len(segs) - 1, 0, -1):
        base = LIB.joinpath(*segs[:k])
        module_file = base.with_suffix(".e")
        if module_file.exists() or any(base.parent.glob(base.name + ".*.e")):
            rest = segs[k:]
            return len(rest) == 1 and rest[0] in symbols(module_file)
    return False


def check(text):
    missing = []
    total = 0
    for number, line in enumerate(text.split("\n"), 1):
        if "→" not in line:
            continue
        for m in NAME.finditer(line.split("→", 1)[1]):
            if m.group(2):
                continue
            total += 1
            if not resolves(m.group(1)):
                missing.append((number, m.group(1)))
    return total, missing


def main():
    total, missing = check(DOC.read_text(encoding="utf-8"))
    if missing:
        for number, name in missing:
            print(f"docs/algos.md:{number}: {name} is not declared in lib/e")
        print(f"{len(missing)} of {total} mapped names do not resolve")
        return 1
    print(f"all {total} mapped names resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
