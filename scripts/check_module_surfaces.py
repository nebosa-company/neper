"""Verify that each implemented module's public declarations are exactly its frozen
surface.

The language has no visibility mechanism (spec section 12): every module-scope
declaration is exported. So a module at `surface:"source"` must declare precisely
what `docs/module-apis.md` fences for it -- an extra declaration is an undeclared
public symbol, and a missing one is a surface that does not exist.

A declaration may be satisfied two ways: written in `lib/e/<path>.e`, or seeded by the
compiler as an intrinsic in `src/resolve.e`. `e.mem` and `e.os` are almost entirely
the second kind.

With ``--compiler``, the checker also asks the compiler to parse, resolve and index
each source module, then compares its checked declarations with the catalogue.

Usage:  python scripts/check_module_surfaces.py [--compiler PATH --os TARGET]
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DECLARATION = re.compile(r'^(?:fn|type|error|const|var)\s+(\w+)', re.M)
DECLARATION_LINE = re.compile(r'^(fn|type|error|const|var)\s+(\w+)')


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


def fenced_declarations():
    """Catalogue declarations keyed by module and (kind, name)."""
    text = (ROOT / 'docs' / 'module-apis.md').read_text(encoding='utf-8')
    declarations = {}
    for match in re.finditer(r'^### `([\w.]+)`\s*\n(.*?)(?=^### |\Z)', text,
                             re.M | re.S):
        module, body = match.group(1), match.group(2)
        for fence in re.finditer(r'```neper\n(.*?)```', body, re.S):
            for line in fence.group(1).splitlines():
                declaration = DECLARATION_LINE.match(line)
                if declaration:
                    declarations.setdefault(module, {})[declaration.groups()] = line
    return declarations


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
    for name in sorted(seeded - fenced - written):
        problems.append('%s: `%s` is seeded as an intrinsic but not in its surface' %
                        (module, name))
    return problems


def normalize_declaration(text):
    return re.sub(r', }', ' }', ' '.join(text.split()))


def compiler_declarations(compiler, module, arch, target_os):
    """Return module-scope declarations from one successful semantic index."""
    path = ROOT / 'lib' / Path(*module.split('.')).with_suffix('.e')
    command = [str(compiler), 'index-file', str(path), str(ROOT), arch, target_os,
               '--json']
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip()
        return None, '%s: compiler semantic index failed%s' % (
            module, ': ' + detail if detail else '')
    try:
        records = [json.loads(line) for line in completed.stdout.splitlines() if line]
    except json.JSONDecodeError as error:
        return None, '%s: compiler semantic index emitted invalid JSON: %s' % (
            module, error)
    module_records = [record for record in records
                      if record.get('record') == 'symbol'
                      and record.get('kind') == 'module'
                      and record.get('name') == module]
    results = [record for record in records if record.get('record') == 'result']
    if len(module_records) != 1 or len(results) != 1 or not results[0].get('ok'):
        return None, '%s: compiler semantic index is incomplete' % module

    module_id = module_records[0]['id']
    source = path.read_bytes()
    declarations = {}
    kind_names = {'module_var': 'var'}
    for record in records:
        if (record.get('record') != 'symbol'
                or record.get('container_id') != module_id):
            continue
        kind = kind_names.get(record['kind'], record['kind'])
        if kind not in {'fn', 'type', 'error', 'const', 'var'}:
            continue
        signature = record.get('signature')
        if kind == 'type':
            span = record.get('span')
            if span:
                signature = source[span['byte_start']:span['byte_end']].decode('utf-8')
        if not signature:
            return None, '%s.%s: compiler omitted its declaration signature' % (
                module, record['name'])
        declarations[(kind, record['name'])] = normalize_declaration(signature)
    return declarations, None


def compare_compiler_declarations(module, fenced, compiled, seeded):
    """Compare exact checked source declarations; seeds currently prove names only."""
    problems = []
    for key, expected in fenced.items():
        kind, name = key
        if name in seeded:
            continue
        actual = compiled.get(key)
        if actual is None:
            problems.append('%s.%s: compiler index has no %s declaration' %
                            (module, name, kind))
        elif actual != normalize_declaration(expected):
            problems.append('%s.%s: catalogue declaration `%s` differs from checked '
                            'source `%s`' %
                            (module, name, normalize_declaration(expected), actual))
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--arch', default='x64')
    parser.add_argument('--os', dest='target_os', choices=('windows', 'linux'))
    args = parser.parse_args(argv)
    if args.compiler and not args.target_os:
        parser.error('--os is required with --compiler')

    plan = json.loads((ROOT / 'docs' / 'modules.json').read_text(encoding='utf-8'))
    modules = plan['modules'] if isinstance(plan, dict) else plan
    surfaces = fenced_surfaces()
    declarations = fenced_declarations()
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
        if args.compiler:
            compiled, failure = compiler_declarations(
                args.compiler, module, args.arch, args.target_os)
            if failure:
                failures.append(failure)
            else:
                failures.extend(compare_compiler_declarations(
                    module, declarations.get(module, {}), compiled,
                    seeded.get(module, set())))
        checked += 1

    for failure in failures:
        print('FAIL: %s' % failure)
    if failures:
        print('%d module(s) checked, %d problem(s)' % (checked, len(failures)))
        return 1
    evidence = ' and compiler-resolved declarations' if args.compiler else ''
    print('PASS: %d implemented module surfaces match their source%s exactly' %
          (checked, evidence))
    return 0


if __name__ == '__main__':
    sys.exit(main())
