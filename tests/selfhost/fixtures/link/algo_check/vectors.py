# Expected values for tests/selfhost/fixtures/link/algo_check: an explicit BFS
# that expands states and inserts successors in the same order as
# e.algo.check.explore (initial states first, then per expanded state its
# successors in generation order; the invariant is checked on insertion,
# deadlock on expansion; `transitions` counts every generated successor).

def peterson(s):
    out = []
    for i in range(2):
        other = 1 - i
        t = list(s)
        pc = s[i]
        if pc == 0:
            t[2 + i] = 1; t[i] = 1
        elif pc == 1:
            t[4] = other; t[i] = 2
        elif pc == 2:
            if s[2 + other] == 0 or s[4] == i:
                t[i] = 3
            else:
                continue
        else:
            t[2 + i] = 0; t[i] = 0
        out.append(tuple(t))
    return out

def mutex(s):
    # pc: 0 test (wait for lock == 0), 1 set lock, 2 critical (release).
    out = []
    for i in range(2):
        t = list(s)
        pc = s[i]
        if pc == 0:
            if s[2] != 0:
                continue
            t[i] = 1
        elif pc == 1:
            t[2] = 1; t[i] = 2
        else:
            t[2] = 0; t[i] = 0
        out.append(tuple(t))
    return out

def fork_free(s, j):
    # fork j is philosopher j's left and philosopher (j + 2) % 3's right.
    return s[j] == 0 and s[(j + 2) % 3] != 2

def dining(s):
    out = []
    for i in range(3):
        t = list(s)
        pc = s[i]
        if pc == 0:
            if not fork_free(s, i):
                continue
            t[i] = 1
        elif pc == 1:
            if not fork_free(s, (i + 1) % 3):
                continue
            t[i] = 2
        else:
            t[i] = 0
        out.append(tuple(t))
    return out

def bfs(initial, succ, inv, deadlock, max_depth=0, capacity=None):
    states = []
    parent = []
    depth = []
    seen = {}
    def insert(s, p, d):
        if s in seen:
            return None
        if capacity is not None and len(states) == capacity:
            return 'full'
        seen[s] = len(states)
        states.append(s); parent.append(p); depth.append(d)
        return len(states) - 1
    for s in initial:
        r = insert(s, -1, 0)
        if r == 'full':
            return ('full',)
        if r is not None and not inv(s):
            return ('violated', len(states), 0, r, trace(parent, r))
    head = 0
    transitions = 0
    bounded = False
    while head < len(states):
        if max_depth and depth[head] >= max_depth:
            bounded = True
            break
        succs = succ(states[head])
        transitions += len(succs)
        if not succs and deadlock:
            return ('deadlock', len(states), transitions, head, trace(parent, head))
        for t in succs:
            r = insert(t, head, depth[head] + 1)
            if r == 'full':
                return ('full',)
            if r is not None and not inv(t):
                return ('violated', len(states), transitions, r, trace(parent, r), states)
        head += 1
    return ('bounded' if bounded else 'safe', len(states), transitions, max(depth))

def trace(parent, i):
    out = []
    while i != -1:
        out.append(i); i = parent[i]
    return out[::-1]

print('peterson', bfs([(0,) * 5], peterson, lambda s: not (s[0] == 3 and s[1] == 3), True))
print('peterson depth 3', bfs([(0,) * 5], peterson, lambda s: not (s[0] == 3 and s[1] == 3), False, 3))
print('peterson capacity 10', bfs([(0,) * 5], peterson, lambda s: True, False, 0, 10))
r = bfs([(0, 0, 0)], mutex, lambda s: not (s[0] == 2 and s[1] == 2), False)
print('mutex', r[:4], 'trace length', len(r[4]), [r[5][i] for i in r[4]])
r = bfs([(0, 0, 0)], dining, lambda s: True, True)
print('dining', r[:4], 'trace length', len(r[4]))

# The BMC counter: 4 bits, x -> x + 1 mod 16 except 11 -> 0.
def step(x):
    return 0 if x == 11 else (x + 1) % 16

def first_reach(bad, k):
    x = 0
    for j in range(k + 1):
        if x == bad:
            return j
        x = step(x)
    return None

def induction_depth(bad, k):
    # Smallest m such that no path of m good states is followed by a bad one.
    for m in range(1, k + 2):
        ends = {x for x in range(16) if x != bad}   # last states of good paths of length 1
        for _ in range(m - 1):
            ends = {step(x) for x in ends if step(x) != bad}
        if not any(step(x) == bad for x in ends):
            return m
    return None

def path(n):
    xs = [0]
    for _ in range(n):
        xs.append(step(xs[-1]))
    return xs

print('bmc 11 up to 15', first_reach(11, 15), 'trace', path(first_reach(11, 15)))
print('bmc 11 up to 10', first_reach(11, 10))
print('bmc 13 up to 15', first_reach(13, 15))
print('induction 13 up to 5', induction_depth(13, 5))
print('induction 11 up to 12', induction_depth(11, 12), 'reach', first_reach(11, 12))
