"""The limits the library declares in source: `ponytail:` comments in lib/e (L253).

A marker names a known ceiling of the code beside it (a global lock, a quadratic scan, a missing encoding) and its upgrade
path. `render_progress.py` renders them as a table in docs/progress.html. Sorted by module and in source order, so two runs agree.
"""
from pathlib import Path


def declared_ceilings(root='lib/e'):
    """{module: [marker text, ...]} for every module that declares a ceiling."""
    base = Path(root)
    by_module = {}
    for path in sorted(base.rglob('*.e')):
        lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
        notes = []
        for number, line in enumerate(lines):
            at = line.find('ponytail:')
            if at < 0 or '//' not in line[:at]:
                continue
            note = line[at + len('ponytail:'):].strip()
            follow = number + 1
            while (follow < len(lines) and lines[follow].lstrip().startswith('//')
                   and 'ponytail:' not in lines[follow] and len(note) < 400):
                note += ' ' + lines[follow].lstrip()[2:].strip()
                follow += 1
            notes.append(note)
        if notes:
            module = 'e.' + '.'.join(path.relative_to(base).with_suffix('').parts)
            by_module[module] = notes
    return by_module
