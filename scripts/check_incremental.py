"""Assert the incremental decisions a build manifest records (D363).

Usage: python scripts/check_incremental.py MANIFEST module=decision:reason ...
"""
import json, sys
m = json.load(open(sys.argv[1], encoding='utf-8'))
want = dict(a.split('=') for a in sys.argv[2:])
got = {e['module']: (e['decision'], e['reason']) for e in m['incremental']}
for name, expected in want.items():
    decision, reason = expected.split(':')
    if got.get(name) != (decision, reason):
        print('incremental decision for %s: expected %s, got %s' % (name, expected, got.get(name)))
        sys.exit(1)
if any(name not in got for name in want):
    sys.exit(1)
