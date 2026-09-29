# Reference for the AC-2001 checks in src/main.e: AC-3 and AC-2001 run exactly as
# lib/e/algo/csp.e runs them (same FIFO arc queue, same requeue order, same value
# order), counting constraint checks. Instances 0..2 are the fixture's existing
# examples (x < y < z over 4 and 2 values, 4-queens); 3..22 are LCG-generated.
# Prints the Neper literals main.e embeds.

M = 1 << 64

class Lcg:
    def __init__(self, seed):
        self.s = seed
    def r(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) % M
        return self.s >> 33

def ac(dom, n, k, pairs, rel, use_last):
    calls = 0
    arcs = len(pairs)
    def ends(i):
        x, y = pairs[i - i % 2], pairs[i - i % 2 + 1]
        return (y, x) if i % 2 == 1 else (x, y)
    last = [k] * (arcs * k)
    queue = list(range(arcs))
    queued = [1] * arcs
    while queue:
        arc = queue.pop(0)
        queued[arc] = 0
        x, y = ends(arc)
        changed = False
        for a in range(k):
            if not dom[x * k + a]:
                continue
            if use_last:
                old = last[arc * k + a]
                if old != k and dom[y * k + old]:
                    continue
                start = 0 if old == k else old + 1
            else:
                start = 0
            found = k
            for b in range(start, k):
                if dom[y * k + b]:
                    calls += 1
                    if rel[((x * n + y) * k + a) * k + b]:
                        found = b
                        break
            if found == k:
                dom[x * k + a] = 0
                changed = True
            elif use_last:
                last[arc * k + a] = found
        if changed:
            if sum(dom[x * k:(x + 1) * k]) == 0:
                return False, calls
            for j in range(arcs):
                f, t = ends(j)
                if t == x and f != y and not queued[j]:
                    queue.append(j)
                    queued[j] = 1
    return True, calls

def build(n, k, pairs, pred):
    rel = [0] * (n * n * k * k)
    for p in range(0, len(pairs), 2):
        x, y = pairs[p], pairs[p + 1]
        for a in range(k):
            for b in range(k):
                v = 1 if pred(x, y, a, b) else 0
                rel[((x * n + y) * k + a) * k + b] = v
                rel[((y * n + x) * k + b) * k + a] = v
    return rel

def less(x, y, a, b):
    return a < b if x < y else a > b

def queens(x, y, a, b):
    return a != b and abs(x - y) != abs(a - b)

instances = []
chain = [0, 1, 1, 2]
instances.append((3, 4, chain, build(3, 4, chain, less), [1] * 12))
instances.append((3, 2, chain, build(3, 2, chain, less), [1] * 6))
qp = [v for i in range(4) for j in range(i + 1, 4) for v in (i, j)]
instances.append((4, 4, qp, build(4, 4, qp, queens), [1] * 16))
g = Lcg(2001)
for _ in range(20):
    n = 3 + g.r() % 4
    k = 2 + g.r() % 4
    pairs = []
    for i in range(n):
        for j in range(i + 1, n):
            if g.r() % 100 < 60:
                pairs += [i, j]
    rel = [0] * (n * n * k * k)
    for p in range(0, len(pairs), 2):
        x, y = pairs[p], pairs[p + 1]
        for a in range(k):
            for b in range(k):
                v = 1 if g.r() % 100 < 55 else 0
                rel[((x * n + y) * k + a) * k + b] = v
                rel[((y * n + x) * k + b) * k + a] = v
    dom = [0 if g.r() % 6 == 0 else 1 for _ in range(n * k)]
    instances.append((n, k, pairs, rel, dom))

doms, results, c3s, c2s = "", "", [], []
for n, k, pairs, rel, dom in instances:
    d3, d2 = list(dom), list(dom)
    ok3, c3 = ac(d3, n, k, pairs, rel, False)
    ok2, c2 = ac(d2, n, k, pairs, rel, True)
    assert ok3 == ok2 and d3 == d2 and c2 <= c3
    doms += "".join(map(str, d3))
    results += "o" if ok3 else "U"
    c3s.append(c3)
    c2s.append(c2)
assert any(a < b for a, b in zip(c2s, c3s))
print('domains: "%s"' % doms)
print('results: "%s"' % results)
print("ac3:     [%d]usize { %s }" % (len(c3s), ", ".join("%dusize" % c for c in c3s)))
print("ac2001:  [%d]usize { %s }" % (len(c2s), ", ".join("%dusize" % c for c in c2s)))
