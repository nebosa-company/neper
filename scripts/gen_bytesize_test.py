"""Generate tests/selfhost/fixtures/link/text_bytesize/src/main.e (L135, D2801).

Reference: go-humanize's documented examples (README: `ParseBytes("42 MB")` 42000000,
`"42 mib"` 44040192, `Bytes(82854982)` "83 MB", `IBytes(82854982)` "79 MiB") plus a Python model
of the same rules in exact `fractions.Fraction` arithmetic (parse: floor(number * unit);
format: largest unit not above the count, tenths rounded half up, `%.0f` half to even).
"""
import math
import random
import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(138)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'text_bytesize' / 'src' / 'main.e'
MAX = (1 << 64) - 1

SCALE = {'': 1, 'b': 1}
for i, p in enumerate('kmgtpe', 1):
    for name in (p, p + 'b'):
        SCALE[name] = 1000 ** i
    for name in (p + 'i', p + 'ib'):
        SCALE[name] = 1024 ** i


def model_parse(text):
    t = text.strip(' ')
    i = 0
    while i < len(t) and t[i].isdigit():
        i += 1
    if i == 0:
        return None
    whole = t[:i]
    frac = ''
    if i < len(t) and t[i] == '.':
        j = i + 1
        while j < len(t) and t[j].isdigit():
            j += 1
        if j == i + 1:
            return None
        frac = t[i + 1:j]
        i = j
    unit = t[i:].strip(' ').lower()
    if unit not in SCALE:
        return None
    value = int(whole) * SCALE[unit]
    if value > MAX:
        return 'O'
    if frac:
        value += (Fraction(int(frac[:18]), 10 ** len(frac[:18])) * SCALE[unit]).__floor__()
    if value > MAX:
        return 'O'
    return value


def model_format(n, iec):
    if n < 10:
        return '%d B' % n
    base = 1024 if iec else 1000
    e = 0
    while e < 6 and n >= base ** (e + 1):
        e += 1
    names = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB'] if iec else ['B', 'kB', 'MB', 'GB', 'TB', 'PB', 'EB']
    unit = base ** e
    val10 = (Fraction(n * 10, unit) + Fraction(1, 2)).__floor__()
    whole, tenth = divmod(val10, 10)
    if val10 < 100:
        return '%d.%d %s' % (whole, tenth, names[e])
    if tenth > 5 or (tenth == 5 and whole % 2 == 1):
        whole += 1
    return '%d %s' % (whole, names[e])


lines = []
texts = ['42', '42 MB', '42 mib', '1.5 GiB', '1.5 KB', '1.5 B', '0', '0.0', '1k', '1K', '1 Ki', '2kib', ' 7 MB ', '10mb', '1e', '1 E', '1.5 E',
         '18446744073709551615', '18446744073709551615b', '18446744073709551616', '18 EB', '19 EB', '16 EiB', '15.99 EiB', '.5 MB', '5. MB', '-1', '+1',
         '', ' ', 'MB', '1 xb', '1 kbb', '1 k b', '12 345', '1.2.3', '0.000000001 GB', '1.123456789012345678901 KB', '3.14159 MiB', '999999999999999999 k']
texts += ['%s%s%s' % (random.choice(['', '0', '1', '12', '1234', '99999']) or '7', random.choice(['', '.5', '.25', '.999', '.000001', '.1']),
                    random.choice(['', ' ', '']) + random.choice(list(SCALE) + [n.upper() for n in SCALE])) for _ in range(200)]
for t in texts:
    r = model_parse(t)
    hx = t.encode().hex() or '-'
    if r is None:
        lines.append('P %s => I' % hx)
    elif r == 'O':
        lines.append('P %s => O' % hx)
    else:
        lines.append('P %s => %d' % (hx, r))
nums = [0, 1, 9, 10, 99, 100, 999, 1000, 1023, 1024, 1025, 9999, 10000, 99999, 999999, 1000000, 82854982, 1048575, 1048576, 1500000, 1536 * 1024,
        10 ** 9, 10 ** 12 + 5 * 10 ** 11, 2 ** 40, 2 ** 50, 2 ** 60, 10 ** 18, 18446744073709551615, 9500, 9950, 9949, 10500, 11500, 12500]
nums += [random.getrandbits(random.randint(1, 64)) for _ in range(150)]
for n in nums:
    for iec in (False, True):
        lines.append('F %d %d => %s' % (n, 1 if iec else 0, model_format(n, iec).replace(' ', '_')))
# README anchors
assert model_parse('42 MB') == 42000000 and model_parse('42 mib') == 44040192
assert model_format(82854982, False) == '83 MB' and model_format(82854982, True) == '79 MiB'

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    if s.len == 1usize && s[0usize] == 45u8 { ret 0usize }
    var i = 0usize
    while i + 1usize < s.len {
        out[i / 2usize] = hexval(s[i]) * 16u8 + hexval(s[i + 1usize])
        i += 2usize
    }
    ret s.len / 2usize
}

fn u64dec(s: str) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < s.len {
        v = v * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

fn check_line(line: str) -> u8 {
    var buf: [128]u8 = zero
    var out: [64]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    if kind[0usize] == 80u8 {
        let (in_hex, p1) = tok(line, p0)
        let (arrow, p2) = tok(line, p1)
        let (want, p3) = tok(line, p2)
        let n = unhex(in_hex, buf[0usize..128usize])
        let (got, got_error) = bytesize.parse(buf[0usize..n])
        if want[0usize] == 73u8 {
            if got_error != bytesize.Invalid { ret 1u8 }
            ret 0u8
        }
        if want[0usize] == 79u8 {
            if got_error != bytesize.Overflow { ret 2u8 }
            ret 0u8
        }
        if got_error != ok { ret 3u8 }
        if got != u64dec(want) { ret 4u8 }
        ret 0u8
    }
    let (count_text, p1) = tok(line, p0)
    let (iec_text, p2) = tok(line, p1)
    let (arrow, p3) = tok(line, p2)
    let (want, p4) = tok(line, p3)
    let (got, got_error) = bytesize.format(u64dec(count_text), iec_text[0usize] == 49u8, out[0usize..64usize])
    if got_error != ok { ret 11u8 }
    // the vector spells the space as '_'
    if got.len != want.len { ret 12u8 }
    var i = 0usize
    while i < got.len {
        var c = got[i]
        if c == 32u8 { c = 95u8 }
        if c != want[i] { ret 13u8 }
        i += 1usize
    }
    ret 0u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    var tiny: [3]u8 = zero
    let (_, small) = bytesize.format(5000000u64, false, tiny[0usize..3usize])
    if small != bytesize.TooSmall { os.exit(101i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("text bytesize ok")
    ret ok
}
'''

src = ('// e.text.bytesize against go-humanize\'s documented examples and an exact-arithmetic Python model of its\n'
       '// rules (D2801). P parse (I invalid, O overflow), F format (space written _). Generated by\n'
       '// scripts/gen_bytesize_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.text.bytesize\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
