"""One program, five languages. Neper's line count anchors the size at ~100k LOC;
every other language expresses the SAME program however its own idioms read.

leaf_i(x) = (x * 7 + 13 + i) % 1009      -- 64-bit, max 1009, never overflows
group_g() = sum of leaf_{g*100+j}(j) for j in 0..100
main()    = sum of all group_g(), printed as a decimal

Neper writes 4 lines per leaf, 105 per group and G+5 for main -- 506*G + 5 -- so
G=198 is ~100k. (Before D246 fixed `ret (expr) op y`, the modulo needed a line of
its own: 5 lines per leaf, and the same program cost measurably more.)
"""
LEAF_PER_GROUP = 100
GROUPS = 198                      # 19,800 leaves -> 100,193 Neper lines
CURVE = [2, 20, 99, 198]          # ~1k, ~10k, ~50k, ~100k Neper lines

def expected(groups: int = GROUPS) -> int:
    total = 0
    for g in range(groups):
        for j in range(LEAF_PER_GROUP):
            total += (j * 7 + 13 + g * LEAF_PER_GROUP + j) % 1009
    return total
