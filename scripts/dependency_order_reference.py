"""Reference and fixture generator for e.algo.schedule.dependency_order (L018).

  python scripts/dependency_order_reference.py

topo_order() is a literal transcription of petcow's src/engine/order.rs (Kahn, a ready set sorted by logical id,
`target[` set matching, unknown/self/cycle refusals), written independently of the Neper code. The six hand
cases are petcow's own tests; the random graphs are seeded. Writes
tests/selfhost/fixtures/link/algo_schedule_order/src/main.e from scripts/dependency_order_fixture_template.e.
"""
import pathlib
import random
from collections import deque


def topo_order(nodes):
    """nodes: list of (id, [deps]). Returns ('O', order) | ('U', node, dep) | ('S', node, dep) | ('C', stuck)."""
    n = len(nodes)

    def resolve(target):
        bracket = target + '['
        return [i for i, (lid, _) in enumerate(nodes) if lid == target or lid.startswith(bracket)]

    adj = [[] for _ in range(n)]
    indegree = [0] * n
    for i, (lid, deps) in enumerate(nodes):
        for d, dep in enumerate(deps):
            targets = resolve(dep)
            if not targets:
                return ('U', i, d)
            for t in targets:
                if t == i:
                    return ('S', i, d)
                adj[t].append(i)
                indegree[i] += 1
    ready = [i for i in range(n) if indegree[i] == 0]
    ready.sort(key=lambda i: nodes[i][0].encode())
    queue = deque(ready)
    order = []
    while queue:
        node = queue.popleft()
        order.append(node)
        newly = []
        for nxt in adj[node]:
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                newly.append(nxt)
        newly.sort(key=lambda i: nodes[i][0].encode())
        queue.extend(newly)
    if len(order) != n:
        return ('C', [i for i in range(n) if i not in order])
    return ('O', order)


def line(nodes):
    text = ' '.join('%s:%s' % (lid, ','.join(deps)) for lid, deps in nodes)
    result = topo_order(nodes)
    if result[0] == 'O':
        tail = 'O ' + ' '.join(map(str, result[1]))
    elif result[0] in 'US':
        tail = '%s %d %d' % result
    else:
        tail = 'C ' + ' '.join(map(str, result[1]))
    return 'G %s = %s' % (text, tail.strip())


def hand_cases():
    yield [('a', []), ('b', ['a']), ('c', ['b'])]
    yield [('a', []), ('b', ['a']), ('c', ['a']), ('d', ['b', 'c'])]
    yield [('z', []), ('a', []), ('m', [])]
    yield [('a', ['b']), ('b', ['a'])]
    yield [('a', ['ghost'])]
    yield [('subnet[0]', []), ('subnet[1]', []), ('app', ['subnet'])]


IDS = ['a', 'b', 'c', 'd', 'm', 'z', 'app', 'vpc', 'vpc[a]', 'vpc[b]', 'subnet[0]', 'subnet[1]', 'subnet[10]', 'sub', 'net', 'B', 'a1']
TARGETS = IDS + ['subnet', 'vpc', 'ghost', 'sub', 'su']


def random_graph(rng):
    n = rng.randint(2, 12)
    ids = [rng.choice(IDS) for _ in range(n)] if rng.random() < 0.3 else rng.sample(IDS, n)
    kind = rng.random()
    nodes = []
    for i, lid in enumerate(ids):
        deps = []
        for _ in range(rng.randint(0, 3)):
            if kind < 0.5:
                # acyclic: only earlier nodes, plus a rare unknown target
                if i:
                    earlier = ids[rng.randrange(i)]
                    # now and then the set a bracketed id belongs to ('subnet' for 'subnet[0]')
                    deps.append(earlier.split('[')[0] if '[' in earlier and rng.random() < 0.5 else earlier)
                if rng.random() < 0.02:
                    deps.append('ghost')
            else:
                deps.append(rng.choice(TARGETS))
        nodes.append((lid, deps))
    return nodes


def main():
    rng = random.Random(1809)
    lines = [line(g) for g in hand_cases()]
    kinds = {'O': 0, 'U': 0, 'S': 0, 'C': 0}
    for _ in range(500):
        text = line(random_graph(rng))
        lines.append(text)
    for text in lines:
        kinds[text.split(' = ')[1][0]] += 1
    assert all(kinds.values()), kinds
    template = (pathlib.Path(__file__).resolve().parent / 'dependency_order_fixture_template.e').read_text(encoding='utf-8')
    chunks = []
    for i in range(0, len(lines), 50):
        chunks.append('"' + '\\n'.join(lines[i:i + 50]) + '\\n"')
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    let verdict_%d = run(a, vectors_%d())\n    if verdict_%d != 0u8 { os.exit(i32(verdict_%d)) }\n' % (i, i, i, i) for i in range(len(chunks)))
    out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs).replace('    //__VECTOR_CALLS__\n', calls)
    target = pathlib.Path(__file__).resolve().parent.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'algo_schedule_order' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8', newline='\n')
    print('wrote', len(lines), 'cases', kinds)


main()
