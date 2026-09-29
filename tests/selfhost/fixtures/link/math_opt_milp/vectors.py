"""Reference objectives for the math_opt_milp fixture, from scipy.optimize.milp
(HiGHS) with mip_rel_gap = 0. Prints each fixed instance as the Neper
literals the fixture uses, the expected objectives, and the objectives of the
LCG-generated random instances (the generator mirrors `random_instance` in
src/main.e)."""

import numpy as np
from scipy.optimize import milp, LinearConstraint, Bounds

INF = np.inf


def solve(c, a, rl, ru, lo, hi, integer):
    r = milp(c=np.array(c, float),
             constraints=LinearConstraint(np.array(a, float).reshape(len(rl), len(c)), rl, ru),
             integrality=np.array(integer, int), bounds=Bounds(lo, hi),
             options={"mip_rel_gap": 0.0})
    return r


def lit(xs):
    def one(v):
        if v == INF:
            return "1.0e30f64"
        if v == -INF:
            return "0.0f64 - 1.0e30f64"
        if v < 0:
            return "0.0f64 - %rf64" % float(-v)
        return "%rf64" % float(v)
    return ", ".join(one(v) for v in xs)


FIXED = {
    # max 5x+8y, x+y<=6, 5x+9y<=45: LP 41.25 at (2.25, 3.75), integer 40.
    "classic": dict(c=[-5, -8], a=[1, 1, 5, 9], rl=[-INF, -INF], ru=[6, 45],
                    lo=[0, 0], hi=[INF, INF], integer=[1, 1]),
    # 0/1 knapsack, 10 items.
    "knapsack": dict(c=[-v for v in [15, 10, 9, 5, 12, 7, 11, 8, 6, 13]],
                     a=[7, 5, 4, 3, 6, 4, 6, 5, 3, 7], rl=[-INF], ru=[26],
                     lo=[0] * 10, hi=[1] * 10, integer=[1] * 10),
    # General integers with negative lower bounds and boxes wider than one.
    "general": dict(c=[-3, -2, 4, -1], a=[2, 3, 1, 1, 1, -1, 2, 0, 0, 2, -1, 3],
                    rl=[-INF, -4, 1], ru=[17, 9, INF],
                    lo=[-3, -5, 0, -2], hi=[7, 6, 4, 8], integer=[1, 1, 1, 1]),
    # Two integer and two continuous variables.
    "mixed": dict(c=[-4, -5, -3, -1], a=[3, 2, 1.5, 1, 1, 4, 2, 0.5, 2, 1, 1, 3],
                  rl=[-INF, -INF, 2], ru=[20.5, 17.25, 15],
                  lo=[0, 0, 0, 0], hi=[INF, INF, 3.5, INF], integer=[1, 1, 0, 0]),
    # Equality rows over general integers.
    "equality": dict(c=[2, 3, 1, 4], a=[3, 5, 7, 2, 1, 1, 1, 1],
                     rl=[47, 11], ru=[47, 11], lo=[0] * 4, hi=[INF] * 4, integer=[1] * 4),
    # 4 x 4 assignment.
    "assignment": dict(c=[9, 2, 7, 8, 6, 4, 3, 7, 5, 8, 1, 8, 7, 6, 9, 4],
                       a=[1 if (k // 4 == r) else 0 for r in range(4) for k in range(16)]
                       + [1 if (k % 4 == r) else 0 for r in range(4) for k in range(16)],
                       rl=[1] * 8, ru=[1] * 8, lo=[0] * 16, hi=[1] * 16, integer=[1] * 16),
    # Set cover: 7 elements, 6 sets with costs.
    "cover": dict(c=[3, 2, 4, 3, 2, 5],
                  a=[1, 0, 1, 0, 0, 1,
                     1, 1, 0, 0, 0, 0,
                     0, 1, 0, 1, 0, 0,
                     0, 0, 1, 1, 0, 0,
                     0, 0, 1, 0, 1, 0,
                     1, 0, 0, 0, 1, 1,
                     0, 1, 0, 0, 0, 1],
                  rl=[1] * 7, ru=[INF] * 7, lo=[0] * 6, hi=[1] * 6, integer=[1] * 6),
    # 2x + 2y = 3: the relaxation is feasible, no integer point is.
    "infeasible": dict(c=[1, 1], a=[2, 2], rl=[3], ru=[3], lo=[0, 0], hi=[10, 10], integer=[1, 1]),
    # x - y <= 1 with -x - y minimised.
    "unbounded": dict(c=[-1, -1], a=[1, -1], rl=[-INF], ru=[1], lo=[0, 0], hi=[INF, INF], integer=[1, 1]),
    # Gomory's example: max y, 3x + 2y <= 6, -3x + 2y <= 0.
    "gomory": dict(c=[0, -1], a=[3, 2, -3, 2], rl=[-INF, -INF], ru=[6, 0],
                   lo=[0, 0], hi=[INF, INF], integer=[1, 1]),
}


def lcg(state):
    state = (state * 6364136223846793005 + 1442695040888963407) & (2**64 - 1)
    return state, state >> 33


def random_instance(seed):
    s = seed
    def draw(k):
        nonlocal s
        s, v = lcg(s)
        return v % k
    n = 6 + draw(7)
    m = 3 + draw(5)
    lo, hi, integer, x0 = [], [], [], []
    for j in range(n):
        l = -float(draw(3))
        u = l + 1 + draw(8)
        lo.append(l)
        hi.append(u)
        integer.append(1 if draw(4) != 0 else 0)
        x0.append(l + draw(int(u - l) + 1))
    c = [float(draw(21)) - 10 for _ in range(n)]
    a, rl, ru = [], [], []
    for i in range(m):
        row = [float(draw(13)) - 4 for _ in range(n)]
        a += row
        act = sum(r * x for r, x in zip(row, x0))
        kind = draw(3)
        slack = float(draw(5))
        if kind == 0:
            rl.append(-INF); ru.append(act + slack)
        elif kind == 1:
            rl.append(act - slack); ru.append(INF)
        else:
            rl.append(act - slack); ru.append(act + slack)
    return c, a, rl, ru, lo, hi, integer


if __name__ == "__main__":
    for name, p in FIXED.items():
        r = solve(p["c"], p["a"], p["rl"], p["ru"], p["lo"], p["hi"], p["integer"])
        print("//", name, "status", r.status, "objective", r.fun)
        for key in ("c", "a", "rl", "ru", "lo", "hi"):
            print("    %s: [%d]f64{ %s }" % (key, len(p[key]), lit(p[key])))
    print("// random instances, seed = 1000 + k")
    wanted = []
    for k in range(20):
        c, a, rl, ru, lo, hi, integer = random_instance(1000 + k)
        r = solve(c, a, rl, ru, lo, hi, integer)
        print("// %d n=%d m=%d integer=%d status %d objective %r" % (k, len(c), len(rl), sum(integer), r.status, r.fun))
        wanted.append(r.fun)
    print("    let expected = [20]f64{ %s }" % lit(wanted))
