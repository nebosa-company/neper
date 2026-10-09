"""Reference and fixture generator for e.algo.privacy.padme_ceil (L004).

  python scripts/padme_reference.py

Padme (Nikitin et al., PURBs, 2019): E = floor(log2 L), S = floor(log2 E) + 1, clear the last E - S bits by
rounding up. This script states the same thing a second way -- the smallest m >= L whose low E - S bits are
zero, found by search -- and checks that the closed form agrees for every L below 5000 before it writes
tests/selfhost/fixtures/link/algo_privacy_padme/src/main.e: the pairs (L, padded) for every L below 600, the
boundaries 2^k - 1, 2^k and 2^k + 1 for k = 1..63 and 250 random lengths over all magnitudes, as decimal
lines in strings, plus the lengths whose padded form overflows 64 bits (which must be refused).
"""
import pathlib
import random


def closed_form(length):
    if length < 2:
        return length
    e = length.bit_length() - 1
    if e == 0:
        return length
    s = e.bit_length()
    last = e - s
    mask = (1 << last) - 1
    return (length + mask) & ~mask


def by_search(length):
    if length < 2:
        return length
    e = length.bit_length() - 1
    s = e.bit_length()
    low = e - s
    m = length
    while m & ((1 << low) - 1):
        m += 1
    return m


for n in range(5000):
    assert closed_form(n) == by_search(n), n

U64 = (1 << 64) - 1
rng = random.Random(2254)
lengths = list(range(600))
for k in range(1, 64):
    for v in ((1 << k) - 1, 1 << k, (1 << k) + 1):
        lengths.append(v)
for _ in range(250):
    bits = rng.randrange(1, 64)
    lengths.append(rng.getrandbits(bits) | (1 << (bits - 1)))
ok_lines = []
bad_lines = []
for n in lengths:
    padded = closed_form(n)
    if padded > U64:
        bad_lines.append(str(n))
    else:
        ok_lines.append('%d %d' % (n, padded))
for n in (U64, U64 - 1, 1 << 63 | 1, (1 << 64) - (1 << 56) + 1):
    if closed_form(n) > U64 and str(n) not in bad_lines:
        bad_lines.append(str(n))
assert bad_lines, 'some length must overflow'


def chunk(lines, per):
    return ['"' + '\\n'.join(lines[i:i + per]) + '\\n"' for i in range(0, len(lines), per)]


oks = chunk(ok_lines, 120)
funcs = ''.join('fn pairs_%d() -> str {\n    ret %s\n}\n\n' % (i, c) for i, c in enumerate(oks))
calls = ''.join('    if check_pairs(pairs_%d()) != 0u8 { os.exit(10i32 + %di32) }\n' % (i, i) for i in range(len(oks)))
bad = '"' + '\\n'.join(bad_lines) + '\\n"'

source = '''// `e.algo.privacy.padme_ceil` (Padme length bucketing, L004) against scripts/padme_reference.py, which checks
// the closed form against a search ("the smallest m >= L whose low E - S bits are zero") for every length below
// 5000: every length below 600, the boundaries 2^k - 1, 2^k and 2^k + 1 for k = 1..63 and 250 random lengths,
// the lengths whose padded form overflows 64 bits (refused as Invalid), and the properties over every length to
// 200000 -- at least the length, idempotent, monotone, overhead at most 12.5% from 2^3 up, and the number of
// distinct padded lengths up to 2^k (a check on the logarithmic growth).
use e.algo.privacy
use e.io
use e.mem
use e.os

fn digits(text: str, at: usize) -> (u64, usize) {
    var v = 0u64
    var p = at
    while p < text.len && text[p] >= 48u8 && text[p] <= 57u8 {
        v = v * 10u64 + u64(text[p] - 48u8)
        p += 1usize
    }
    ret (v, p)
}

// Lines "L padded".
fn check_pairs(text: str) -> u8 {
    var p = 0usize
    while p < text.len {
        let (length, after_length) = digits(text, p)
        let (want, after_want) = digits(text, after_length + 1usize)
        let (got, e) = privacy.padme_ceil(length)
        if e != ok || got != want { ret 1u8 }
        p = after_want + 1usize
    }
    ret 0u8
}

// Lines "L" for lengths that must be refused.
fn check_refused(text: str) -> u8 {
    var p = 0usize
    while p < text.len {
        let (length, after_length) = digits(text, p)
        let (got, e) = privacy.padme_ceil(length)
        if e != privacy.Invalid { ret 1u8 }
        p = after_length + 1usize
    }
    ret 0u8
}

''' + funcs + '''fn refused() -> str {
    ret ''' + bad + '''
}

fn main(a: *mem.Arena, args: []str) -> err {
''' + calls + '''    if check_refused(refused()) != 0u8 { os.exit(30i32) }
    // The properties over every length to 200000.
    var previous = 0u64
    var length = 0u64
    var distinct = 0u64
    var last_seen = 0u64
    while length <= 200000u64 {
        let (padded, e) = privacy.padme_ceil(length)
        if e != ok { os.exit(31i32) }
        if padded < length { os.exit(32i32) }
        let (again, e2) = privacy.padme_ceil(padded)
        if e2 != ok || again != padded { os.exit(33i32) }
        if padded < previous { os.exit(34i32) }
        if length >= 8u64 && (padded - length) * 8u64 > length { os.exit(35i32) }
        if padded != last_seen || distinct == 0u64 {
            distinct += 1u64
            last_seen = padded
        }
        previous = padded
        length += 1u64
    }
    // The 200001 lengths fall into 222 classes (counted by the reference): a few dozen per octave, not 2^k.
    if distinct != 222u64 { os.exit(36i32) }
    try io.print("algo privacy padme ok")
    ret ok
}
'''
target = pathlib.Path(__file__).resolve().parent.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'algo_privacy_padme' / 'src' / 'main.e'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(source, encoding='utf-8', newline='\n')
print('wrote', target.name, len(ok_lines), 'pairs,', len(bad_lines), 'refused')
