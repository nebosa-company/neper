"""Verify that each implemented module's public declarations are exactly its frozen
surface.

The language has no visibility mechanism (spec section 12): every module-scope
declaration is exported. So a module at `surface:"source"` must declare precisely
what `docs/module-apis.md` fences for it -- an extra declaration is an undeclared
public symbol, and a missing one is a surface that does not exist.

A declaration may be satisfied two ways: written in `lib/e/<path>.e`, or seeded by the
compiler as an intrinsic in `src/resolve.e`. `e.mem` and `e.os` are almost entirely
the second kind.

Usage:  python scripts/check_module_surfaces.py     (from the repository root)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DECLARATION = re.compile(r'^(?:fn|type|error|const|var)\s+(\w+)', re.M)


def fenced_surfaces():
    """Every module's declared surface, from the ```neper fences in module-apis.md."""
    text = (ROOT / 'docs' / 'module-apis.md').read_text(encoding='utf-8')
    surfaces = {}
    for match in re.finditer(r'^### `([\w.]+)`\s*\n(.*?)(?=^### |\Z)', text,
                             re.M | re.S):
        module, body = match.group(1), match.group(2)
        names = set()
        for fence in re.finditer(r'```neper\n(.*?)```', body, re.S):
            names |= set(DECLARATION.findall(fence.group(1)))
        if names:
            surfaces.setdefault(module, set()).update(names)
    return surfaces


def seeded_intrinsics():
    """Declarations the compiler supplies rather than the library."""
    text = (ROOT / 'src' / 'resolve.e').read_text(encoding='utf-8')
    seeded = {}
    for module, name in re.findall(r'seed\(r, g, "([\w.]+)", "(\w+)"', text):
        seeded.setdefault(module, set()).add(name)
    return seeded


def source_declarations(module):
    path = ROOT / 'lib' / Path(*module.split('.')).with_suffix('.e')
    if not path.exists():
        return None
    return set(DECLARATION.findall(path.read_text(encoding='utf-8')))


def compare(module, fenced, written, seeded):
    """The whole rule, over sets: what is public must be exactly what is declared."""
    problems = []
    for name in sorted(written - fenced):
        problems.append('%s: `%s` is declared in source but not in its surface; the '
                        'language has no visibility mechanism, so it is a public '
                        'symbol the plan does not know about' % (module, name))
    for name in sorted(fenced - (written | seeded)):
        problems.append('%s: `%s` is in its surface but neither written in source nor '
                        'seeded as an intrinsic' % (module, name))
    return problems


def main():
    plan = json.loads((ROOT / 'docs' / 'modules.json').read_text(encoding='utf-8'))
    modules = plan['modules'] if isinstance(plan, dict) else plan
    surfaces = fenced_surfaces()
    seeded = seeded_intrinsics()

    failures = []
    checked = 0
    for entry in modules:
        if entry.get('surface') != 'source':
            continue
        module = entry['name']
        fenced = surfaces.get(module)
        if fenced is None:
            failures.append('%s: at surface "source" but has no fence in '
                            'docs/module-apis.md' % module)
            continue
        written = source_declarations(module)
        if written is None:
            failures.append('%s: at surface "source" but has no lib/e source' % module)
            continue
        failures.extend(compare(module, fenced, written, seeded.get(module, set())))
        checked += 1

    for failure in failures:
        print('FAIL: %s' % failure)
    if failures:
        print('%d module(s) checked, %d problem(s)' % (checked, len(failures)))
        return 1
    print('PASS: %d implemented module surfaces match their source exactly' % checked)
    return 0


if __name__ == '__main__':
    sys.exit(main())
