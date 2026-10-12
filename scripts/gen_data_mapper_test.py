"""Oracle for tests/selfhost/fixtures/link/data_mapper (L139, D2761).

An independent Python model of the documented name rules and integer range rules. It reads the
`path_score(...)` and `conv_is[G, F](...)` vectors out of the fixture and recomputes each one,
so the numbers in the fixture are the model's, not copies of the implementation's. Exit 1 on
any mismatch. With --emit it prints a fresh table of name vectors instead.
"""
import re
import sys
from pathlib import Path

FIXTURE = Path(__file__).resolve().parent.parent / 'tests/selfhost/fixtures/link/data_mapper/src/main.e'

BITS = {'i8': (8, True), 'u8': (8, False), 'i16': (16, True), 'u16': (16, False),
        'i32': (32, True), 'u32': (32, False), 'i64': (64, True), 'u64': (64, False)}


def norm(s):
    return s.replace('_', '').lower()


def score(dest, want, renamed, depth, a, b, c):
    segs = [x for x in (a, b, c)][:depth]
    if renamed:
        return 4 if want.split('.') == segs else 0
    if depth == 1:
        if dest == a:
            return 3
        return 2 if norm(dest) == norm(a) else 0
    return 1 if norm(dest) == ''.join(norm(s) for s in segs) else 0


def fits(v, ty):
    bits, signed = BITS[ty]
    lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
    return lo <= v <= hi


def lit(tok):
    m = re.match(r'^(-?\d+)(?:[iu]\d+)$', tok)
    return int(m.group(1))


def main():
    src = FIXTURE.read_text(encoding='utf-8')
    bad = 0
    n = 0
    for m in re.finditer(r'mapper\.path_score\("([^"]*)", "([^"]*)", (true|false), (\d)usize, "([^"]*)", "([^"]*)", "([^"]*)"\) != (\d)u32', src):
        dest, want, renamed, depth, a, b, c, expect = m.groups()
        got = score(dest, want, renamed == 'true', int(depth), a, b, c)
        n += 1
        if got != int(expect):
            bad += 1
            print('MISMATCH name', m.group(0), 'model says', got)
    for m in re.finditer(r'conv_is\[(\w+), (\w+)\]\(a, (-?\d+\w+), (true|false), (-?\d+)i64\)', src):
        g, f, val, want_ok, want = m.groups()
        v = lit(val)
        ok = fits(v, g)
        n += 1
        if ok != (want_ok == 'true') or (ok and v != int(want)):
            bad += 1
            print('MISMATCH range', m.group(0), 'model says', ok)
    print('checked', n, 'vectors,', bad, 'mismatches')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
