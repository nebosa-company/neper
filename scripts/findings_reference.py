"""Reference and fixture generator for e.algo.findings (L024).

  python scripts/findings_reference.py

A transcription of petcow's src/scan.rs `stable_id`, `finding_id`, `tool_key` and `merge_owned` into Python
dictionaries (Option<String> is None or a str), with its own tests (src/scan.rs:881 onward) as the first cases, then
seeded random cases of recorded and reported findings. Each merge case also records whether merging the same report
into the result a second time leaves it unchanged (`idem`): it does except in the contrived case of two reports
of one finding that disagree. Writes tests/selfhost/fixtures/link/algo_findings/src/main.e from
scripts/findings_fixture_template.e.
"""
import json
import pathlib
import random

NATIVE = 'petcow-native'
KEYS = ['id', 'tool', 'state', 'severity', 'rule', 'description', 'solution', 'justification', 'expires', 'detection_time', 'last_update']


def stable_id(parts):
    h = 0xcbf29ce484222325
    for i, p in enumerate(parts):
        if i:
            h ^= ord('|')
            h = h * 0x100000001b3 & 0xFFFFFFFFFFFFFFFF
        for b in p.encode('utf-8'):
            h ^= b
            h = h * 0x100000001b3 & 0xFFFFFFFFFFFFFFFF
    return '%016x' % h


def tool_key(tool):
    return tool.split(' (')[0].strip()


def finding_id(resource, tool, rule):
    return stable_id([resource, tool_key(tool), rule])


def merge_owned(base, existing, reported, now, owner):
    out = []
    by_id = {}
    for f in existing:
        if f['id'] is not None:
            by_id[f['id']] = f
    reported_ids = set()
    for r in reported:
        fid = finding_id(base, r['tool'], r['rule'])
        reported_ids.add(fid)
        prev = by_id.get(fid)
        if prev is not None:
            changed = prev['description'] != r['description'] or prev['severity'] != r['severity']
            out.append({
                'id': fid, 'tool': r['tool'], 'state': prev['state'], 'severity': r['severity'], 'rule': r['rule'],
                'description': r['description'], 'solution': prev['solution'] if prev['solution'] is not None else r['solution'],
                'justification': prev['justification'], 'expires': prev['expires'], 'detection_time': prev['detection_time'],
                'last_update': now if changed else prev['last_update']})
        else:
            out.append({
                'id': fid, 'tool': r['tool'], 'state': 'open', 'severity': r['severity'], 'rule': r['rule'],
                'description': r['description'], 'solution': r['solution'], 'justification': None, 'expires': None,
                'detection_time': now, 'last_update': now})
    for e in existing:
        if e['id'] is not None and e['id'] in reported_ids:
            continue
        if e['id'] is not None and e['tool'].startswith(owner) and e['state'] == 'open':
            f = dict(e)
            f['state'] = 'fixed'
            f['last_update'] = now
            if f['solution'] is None:
                f['solution'] = 'no longer reported'
            out.append(f)
        else:
            out.append(dict(e))
    out.sort(key=lambda f: (f['tool'].encode(), (f['rule'] or '').encode(), f['description'].encode()))
    return out


def ordered(f):
    return {k: f[k] for k in KEYS}


def case(base, existing, reported, now, owner):
    out = merge_owned(base, existing, reported, now, owner)
    again = merge_owned(base, out, reported, now, owner)
    reported_lines = [{'tool': r['tool'], 'rule': r['rule'], 'severity': r['severity'], 'description': r['description'], 'solution': r['solution']} for r in reported]
    body = {'base': base, 'now': now, 'owner': owner, 'existing': [ordered(f) for f in existing], 'reported': reported_lines,
            'out': [ordered(f) for f in out], 'idem': again == out}
    return 'M ' + json.dumps(body, separators=(',', ':'), ensure_ascii=False)


def mk(base, tool, rule, state='open', severity='high', description='d', **kw):
    return {'id': finding_id(base, tool, rule) if kw.get('has_id', True) else None, 'tool': tool, 'state': state, 'severity': severity,
            'rule': rule, 'description': description, 'solution': kw.get('solution'), 'justification': kw.get('justification'),
            'expires': kw.get('expires'), 'detection_time': kw.get('detection_time', 'T0'), 'last_update': kw.get('last_update', 'T0')}


def rep(rule, severity='high', description='d', tool=NATIVE + ' (0.4.2)', solution='fix it'):
    return {'tool': tool, 'rule': rule, 'severity': severity, 'description': description, 'solution': solution}


TOOLS = ['petcow-native (0.4.2)', 'petcow-native (0.5.0)', 'petcow-spartan (1)', 'checkov (3.2)', 'semgrep (1.0)', 'manual']
RULES = ['R1', 'R2', 'R3', 'CKV_AWS_18']
STATES = ['open', 'accepted', 'fixed', 'false-positive']
SEVERITIES = ['info', 'low', 'medium', 'high', 'critical']
DESCRIPTIONS = ['d', 'old', 'new', 'a b', 'é']


def main():
    rng = random.Random(2405)
    lines = []
    # stable_id: determinism, order sensitivity, 16 digits; the empty list and empty parts
    assert stable_id(['a', 'b']) == stable_id(['a', 'b']) and stable_id(['a', 'b']) != stable_id(['b', 'a'])
    assert len(stable_id(['logs', 'petcow', 'R1'])) == 16
    assert stable_id([]) == 'cbf29ce484222325'
    for parts in ([], [''], ['', ''], ['a'], ['a', 'b'], ['b', 'a'], ['logs', 'petcow', 'R1'], ['é', '日本', '😀'], ['a|b'], ['a', 'b|c'], ['x'] * 5):
        lines.append('I %s => %s' % (json.dumps(parts, ensure_ascii=False, separators=(',', ':')), stable_id(parts)))
    # petcow's merge tests
    lines.append(case('logs', [], [rep('R1')], 'NOW', NATIVE))
    lines.append(case('logs', [mk('logs', NATIVE + ' (0.4.2)', 'R1', 'accepted', justification='risk accepted SEC-1')], [rep('R1')], 'NOW', NATIVE))
    native = mk('b', NATIVE + ' (1)', 'N1')
    spartan = mk('b', 'petcow-spartan (1)', 'S1')
    lines.append(case('b', [native, spartan], [], 'NOW', 'petcow-spartan'))
    lines.append(case('logs', [mk('logs', NATIVE + ' (0.4.2)', 'R1', severity='low', description='old')], [rep('R1', 'high', 'new')], 'NOW', NATIVE))
    lines.append(case('logs', [mk('logs', NATIVE + ' (0.4.2)', 'R1')], [], 'NOW', NATIVE))
    hand = mk('logs', 'manual', None, 'open', 'low', 'noted by hand', has_id=False)
    hand['rule'] = None
    lines.append(case('logs', [hand], [], 'NOW', NATIVE))
    for _ in range(150):
        base = rng.choice(['logs', 'web', 'db'])
        existing = []
        for _ in range(rng.randint(0, 4)):
            tool = rng.choice(TOOLS)
            rule = rng.choice(RULES)
            has_id = rng.random() < 0.85
            f = mk(base, tool, rule, rng.choice(STATES), rng.choice(SEVERITIES), rng.choice(DESCRIPTIONS), has_id=has_id,
                   solution=rng.choice([None, 'fix it', '']), justification=rng.choice([None, 'because']), expires=rng.choice([None, '2030-01-01']),
                   detection_time='T%d' % rng.randint(0, 3), last_update='U%d' % rng.randint(0, 3))
            if rng.random() < 0.1:
                f['rule'] = None
            if rng.random() < 0.1:
                f['id'] = 'deadbeef%08x' % rng.getrandbits(32)
            existing.append(f)
        reported = []
        for _ in range(rng.randint(0, 4)):
            reported.append(rep(rng.choice(RULES), rng.choice(SEVERITIES), rng.choice(DESCRIPTIONS), rng.choice(TOOLS), rng.choice([None, 'fix it', ''])))
        lines.append(case(base, existing, reported, 'NOW', rng.choice([NATIVE, 'petcow-spartan', 'checkov', 'x'])))
    here = pathlib.Path(__file__).resolve().parent
    chunks = ['"' + '\\n'.join(l.replace('\\', '\\\\').replace('"', '\\"') for l in lines[i:i + 10]) + '\\n"' for i in range(0, len(lines), 10)]
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    template = (here / 'findings_fixture_template.e').read_text(encoding='utf-8')
    out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs).replace('    //__VECTOR_CALLS__\n', calls)
    target = here.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'algo_findings' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8', newline='\n')
    idem = sum(1 for l in lines if l.startswith('M ') and '"idem":true' in l)
    print('wrote', len(lines), 'cases in', len(chunks), 'chunks;', idem, 'idempotent')


main()
