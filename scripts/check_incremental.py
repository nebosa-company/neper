"""Assert the incremental decisions a build manifest records (D363), and the work it
did (D405): `work.bodies_checked=N`, `work.modules_lowered=N`, `work.functions_lowered=N`.

Usage: python scripts/check_incremental.py MANIFEST module=decision:reason ... work.field=N ...
"""
import json, sys
m = json.load(open(sys.argv[1], encoding='utf-8'))
want = dict(a.split('=') for a in sys.argv[2:])
for name in [n for n in want if n.startswith('work.')]:
    field = name[len('work.'):]
    if str(m.get('work', {}).get(field)) != want[name]:
        print('work.%s: expected %s, got %s' % (field, want[name], m.get('work', {}).get(field)))
        sys.exit(1)
    del want[name]
got = {e['module']: (e['decision'], e['reason']) for e in m['incremental']}
for name, expected in want.items():
    decision, reason = expected.split(':')
    if got.get(name) != (decision, reason):
        print('incremental decision for %s: expected %s, got %s' % (name, expected, got.get(name)))
        sys.exit(1)
if any(name not in got for name in want):
    sys.exit(1)
