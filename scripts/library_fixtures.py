"""The deferred-library fixture manifest (D1529, H11/SL).

A `surface:"partial"` module is a library whose catalogue is not yet wholly
delivered. For each one the manifest records, from the repository itself:

- `pending`: the catalogue declarations its source does not yet deliver (neither
  written in `lib/e` nor seeded by the compiler) -- what later work owes;
- `fixtures`: the executable link fixtures under `tests/selfhost/fixtures/link` whose
  sources `use` it -- the runtime evidence it already has;
- `schedule` and `milestone` from `docs/modules.json`.

`--write` regenerates `docs/library-fixtures.json`. Without it the script checks
that the committed manifest is the one the repository produces now, that every
partial module is in it, that every fixture it names exists and imports the
module, and that every module with delivered declarations has at least one
fixture: a delivered API with no executable evidence fails. Exit 0 when all hold.

Usage: python scripts/library_fixtures.py [--write]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
import check_module_surfaces as surfaces  # noqa: E402

MANIFEST = ROOT / 'docs' / 'library-fixtures.json'
FIXTURES = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link'
USE = re.compile(r'^use\s+([\w.]+)', re.M)


def fixture_imports():
    """Module name -> the link fixtures whose sources use it."""
    users = {}
    for fixture in sorted(p for p in FIXTURES.iterdir() if p.is_dir()):
        modules = set()
        for source in fixture.rglob('*.e'):
            modules.update(USE.findall(source.read_text(encoding='utf-8', errors='replace')))
        for module in modules:
            users.setdefault(module, []).append(fixture.name)
    return users


def build():
    plan = json.loads((ROOT / 'docs' / 'modules.json').read_text(encoding='utf-8'))
    fenced = surfaces.fenced_surfaces()
    seeded = surfaces.seeded_intrinsics()
    users = fixture_imports()
    entries = []
    for module in plan['modules']:
        if module.get('surface') != 'partial':
            continue
        name = module['name']
        written = surfaces.source_declarations(name) or set()
        catalogue = fenced.get(name, set())
        delivered = catalogue & (written | seeded.get(name, set()))
        entries.append({
            'module': name,
            'milestone': module.get('milestone'),
            'schedule': module.get('schedule'),
            'catalogue': len(catalogue),
            'delivered': len(delivered),
            'pending': sorted(catalogue - delivered),
            'fixtures': users.get(name, []),
        })
    return {'schema': 'neper-library-fixtures', 'version': 1,
            'modules': entries}


def main(argv):
    manifest = build()
    text = json.dumps(manifest, indent=1) + '\n'
    if '--write' in argv:
        MANIFEST.write_text(text, encoding='utf-8', newline='\n')
        print('wrote %s: %d partial modules' % (MANIFEST.relative_to(ROOT), len(manifest['modules'])))
        return 0
    problems = []
    if not MANIFEST.exists() or MANIFEST.read_text(encoding='utf-8') != text:
        problems.append('docs/library-fixtures.json is not what the repository produces; '
                        'run python scripts/library_fixtures.py --write')
    for entry in manifest['modules']:
        for fixture in entry['fixtures']:
            if not (FIXTURES / fixture).is_dir():
                problems.append('%s: fixture %s does not exist' % (entry['module'], fixture))
        if entry['delivered'] and not entry['fixtures']:
            problems.append('%s: %d delivered declarations and no executable fixture uses it'
                            % (entry['module'], entry['delivered']))
    for problem in problems:
        print('FAIL: %s' % problem)
    if problems:
        return 1
    pending = sum(len(e['pending']) for e in manifest['modules'])
    evidenced = sum(1 for e in manifest['modules'] if e['fixtures'])
    print('PASS: %d partial modules, %d with executable fixtures, %d declarations pending'
          % (len(manifest['modules']), evidenced, pending))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
