"""Hold `query-batch`'s snapshots to their contract (D1526, H16).

Usage: python scripts/check_batch_snapshots.py COMPILER ROOT ARCH OS WORKDIR [CYCLES]

Writes a one-function program and three edits of it into WORKDIR, then runs two
batches. The soak: CYCLES (10,000 by default) edit/query/revert cycles under the
default budget of two -- one miss, then hits, every answer from its snapshot, the
live arena back at the session baseline, the snapshot storage unchanged. The
eviction batch: an edit past the budget evicts, the evicted key is refused as
stale, an edit that does not check is refused and leaves the current snapshot, and
with every slot pinned an edit is refused. Exit 0 when all hold, 1 otherwise.
"""
import json, os, subprocess, sys

compiler, root, arch, host, work = sys.argv[1:6]
cycles = int(sys.argv[6]) if len(sys.argv) > 6 else 10000
os.makedirs(work, exist_ok=True)
base = 'fn total(a: u32, b: u32) -> u32 {\n    ret a + b\n}\n\nfn main() {}\n'
sources = {
    'm.e': base,
    'alt.e': base.replace('a: u32, b: u32) -> u32', 'a: u64, b: u64) -> u64'),
    'alt2.e': base.replace('a: u32, b: u32) -> u32', 'a: u8, b: u8) -> u8'),
    'alt3.e': base.replace('a: u32, b: u32) -> u32', 'a: u16, b: u16) -> u16'),
    'bad.e': base.replace('ret a + b', 'ret a + missing'),
}
for name, text in sources.items():
    with open(os.path.join(work, name), 'w', newline='\n') as f:
        f.write(text)


def batch(name, lines):
    with open(os.path.join(work, name + '.txt'), 'w', newline='\n') as f:
        f.write(''.join(line + '\n' for line in lines))
    done = subprocess.run([compiler, 'query-batch', 'm.e', root, arch, host, '--json', '--batch', name + '.txt'],
                          cwd=work, capture_output=True, text=True, encoding='utf-8')
    streams, current = [], None
    for line in done.stdout.splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        if record.get('record') == 'header':
            current = {'command': record['command'], 'records': []}
            streams.append(current)
        else:
            current['records'].append(record)
    return streams


def result(stream):
    return [r for r in stream['records'] if r.get('record') == 'result'][-1]


def signature(stream):
    for r in stream['records']:
        if r.get('kind') == 'signature':
            return r['value']


failures = []


def check(name, ok):
    if not ok:
        failures.append(name)


U = {'m': 'fn total(a: u32, b: u32) -> u32', 'alt': 'fn total(a: u64, b: u64) -> u64',
     'alt2': 'fn total(a: u8, b: u8) -> u8'}
soak = batch('soak', ['memory'] + ['edit m.e alt.e', 'context m.total', 'revert m.e', 'context m.total'] * cycles
             + ['snapshots', 'memory'])
contexts = [s for s in soak if s['command'] == 'context' and any(r.get('record') == 'subject' for r in s['records'])]
check('every context answered', len(contexts) == 2 * cycles and all(result(s)['ok'] for s in contexts))
check('each answer from its snapshot', all(signature(s) == (U['alt'] if i % 2 == 0 else U['m']) for i, s in enumerate(contexts)))
snap = result([s for s in soak if s['command'] == 'snapshots'][-1])['data']
check('one miss, then hits, no eviction', snap['misses'] == 1 and snap['hits'] == 2 * cycles - 1 and snap['evictions'] == 0)
memories = [r['data'] for s in soak for r in s['records'] if r.get('record') == 'result' and 'arena_used' in r.get('data', {})]
check('live memory back at the session baseline', len(memories) == 2 and memories[1]['arena_used'] == memories[0]['session_used']
      and memories[1]['queries_completed'] == 2 * cycles)
check('snapshot storage unchanged after the first check',
      len(set(result(s)['data']['snapshot_arena_used'] for s in soak if s['command'] == 'edit')) == 1)

key = result(batch('key', ['edit m.e alt.e'])[0])['data']['snapshot']
ev = batch('evict', ['edit m.e alt.e', 'snapshots', 'edit m.e alt2.e', 'snapshots', 'context m.total', 'use ' + key,
                     'budget 3', 'edit m.e bad.e', 'context m.total',
                     'pin', 'edit m.e alt.e', 'pin', 'edit m.e alt3.e', 'snapshots'])
snaps = [result(s)['data'] for s in ev if s['command'] == 'snapshots']
check('an edit past the budget evicts', snaps[1]['evictions'] == 1 and snaps[1]['misses'] == 2)
ctx = [s for s in ev if s['command'] == 'context' and any(r.get('record') == 'subject' for r in s['records'])]
check('the evicting edit is answered', signature(ctx[0]) == U['alt2'])
stale = [s for s in ev if s['command'] == 'use'][0]
check('an evicted key is refused as stale', not result(stale)['ok'] and 'stale' in json.dumps(stale['records']))
edits = [s for s in ev if s['command'] == 'edit']
check('an edit that does not check is refused', not result(edits[2])['ok'])
check('and the current snapshot stays', signature(ctx[1]) == U['alt2'])
check('a free slot takes the next edit', result(edits[3])['ok'])
check('with every slot pinned an edit is refused', not result(edits[4])['ok'] and 'pinned' in json.dumps(edits[4]['records']))
check('the pinned snapshots stand', snaps[-1]['pinned_count'] == 3 and snaps[-1]['live'] == 3)

if failures:
    print('batch snapshots: ' + '; '.join(failures))
    sys.exit(1)
print('batch snapshots ok: %d cycles, %d hits, 1 miss' % (cycles, snap['hits']))
