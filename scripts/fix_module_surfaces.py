# -*- coding: utf-8 -*-
"""Rewrite docs/module-apis.md catalogue lines to the compiler-checked declarations.

Usage:  python scripts/fix_module_surfaces.py COMPILER [--arch x64] [--os windows]

check_module_surfaces.py reports `catalogue declaration X differs from checked source
Y` when a catalogue line is not the single-line form the compiler resolves (a
multi-line struct, a function whose signature wraps). Each such line is replaced by
the checked form in its module's block. Run after adding a module's catalogue block,
then run check_module_surfaces.py again; a line that is not found exactly once in its
block is reported and left alone.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAIL = re.compile(r"^FAIL: (\S+?)\.([A-Za-z_0-9]+): catalogue declaration `(.*?)` differs from checked source `(.*)`\s*$", re.M)


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    compiler = argv[0]
    arch = argv[argv.index("--arch") + 1] if "--arch" in argv else "x64"
    host = argv[argv.index("--os") + 1] if "--os" in argv else "windows"
    run = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "check_module_surfaces.py"), "--compiler", compiler, "--arch", arch, "--os", host],
        capture_output=True, text=True, cwd=ROOT)
    fixes = FAIL.findall(run.stdout + run.stderr)
    path = ROOT / "docs" / "module-apis.md"
    text = path.read_text(encoding="utf-8")
    fixed = skipped = 0
    for module, name, catalogue, checked in fixes:
        start = text.find("### `%s`" % module)
        if start < 0:
            skipped += 1
            continue
        end = text.find("### `", start + 5)
        end = len(text) if end < 0 else end
        block = text[start:end]
        needle = "\n" + catalogue + "\n"
        if block.count(needle) != 1:
            print("not found once: %s.%s" % (module, name))
            skipped += 1
            continue
        text = text[:start] + block.replace(needle, "\n" + checked + "\n", 1) + text[end:]
        fixed += 1
    path.write_text(text, encoding="utf-8", newline="\n")
    print("fixed %d catalogue line(s), left %d" % (fixed, skipped))
    return 0 if skipped == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
