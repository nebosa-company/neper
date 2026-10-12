"""Generate tests/selfhost/fixtures/link/tz_winzones/src/main.e (L150, D2800).

Reference: tzlocal's CLDR windows_tz tables (the module's own source is generated from
them, so the sampled rows prove the lookup, not the data), plus hand-known mappings and
the Windows `tzutil /l` id list of the generating host (every id there must be mapped).
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tzlocal.windows_tz import win_tz, tz_win  # noqa: E402
import fixture_common as fc  # noqa: E402

random.seed(152)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'tz_winzones' / 'src' / 'main.e'

lines = []
for k, v in sorted(win_tz.items()):
    lines.append('W|%s|%s' % (k, v))
reverse = sorted((k, v) for k, v in tz_win.items() if k and v)
for k, v in random.sample(reverse, 150):
    lines.append('I|%s|%s' % (k, v))
for k, v in random.sample(sorted(win_tz.items()), 25):
    lines.append('W|%s|%s' % (k.upper(), v))
    lines.append('W|%s|%s' % (k.lower(), v))
hand = [
    ('Pacific Standard Time', 'America/Los_Angeles'), ('Eastern Standard Time', 'America/New_York'),
    ('GMT Standard Time', 'Europe/London'), ('W. Europe Standard Time', 'Europe/Berlin'),
    ('Tokyo Standard Time', 'Asia/Tokyo'), ('India Standard Time', 'Asia/Calcutta'),
    ('AUS Eastern Standard Time', 'Australia/Sydney'), ('UTC', 'Etc/UTC'),
]
for w, i in hand:
    lines.append('H|%s|%s' % (w, i))
lines.extend(['N|Not A Zone', 'N|', 'N|Pacific Standard Tim', 'N|Pacific Standard Time ', 'M|Nowhere/Land', 'M|', 'M|America/Los_Angele'])

# Territory rows (T|id|TT|iana): every row of scripts/tz_winzones_territories.txt, extracted from .NET's
# TryConvertWindowsIdToIanaId over every AA..ZZ (so a territory with no row answered the 001 default there),
# a lower-case spelling, a few of the territories that have no row, and an empty and the 001 territory.
territory = [l for l in (ROOT / 'scripts' / 'tz_winzones_territories.txt').read_text(encoding='utf-8').split(chr(10)) if l]
have = set()
for row in territory:
    left, iana = row.split('=')
    name, tt = left.split('|')
    have.add((name, tt))
    lines.append('T|%s|%s|%s' % (name, tt, iana))
for row in random.sample(territory, 25):
    left, iana = row.split('=')
    name, tt = left.split('|')
    lines.append('T|%s|%s|%s' % (name.lower(), tt.lower(), iana))
for name in random.sample(sorted(win_tz), 40):
    tt = random.choice(['FR', 'DE', 'JP', 'BR', 'AU', 'IN', 'ZA', 'NZ', 'EG', 'CL', 'AR'])
    if (name, tt) not in have:
        lines.append('T|%s|%s|%s' % (name, tt, win_tz[name]))
    lines.append('T|%s||%s' % (name, win_tz[name]))
    lines.append('T|%s|001|%s' % (name, win_tz[name]))
lines.append('X|Not A Zone|CA|')
vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn bar(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] != 124u8 { p += 1usize }
    let piece = line[at..p]
    if p < line.len { p += 1usize }
    ret (piece, p)
}

fn check_line(line: str) -> u8 {
    let (kind, p0) = bar(line, 0usize)
    let (first, p1) = bar(line, p0)
    let second = line[p1..line.len]
    let k = kind[0usize]
    if k == 87u8 || k == 72u8 {
        let (got, got_error) = winzones.iana_for_windows(first)
        if got_error != ok { ret 1u8 }
        if !text_is(got, second) { ret 2u8 }
        if k == 72u8 {
            let (back, back_error) = winzones.windows_for_iana(second)
            if back_error != ok { ret 3u8 }
            if !text_is(back, first) { ret 4u8 }
        }
        ret 0u8
    }
    if k == 73u8 {
        let (got, got_error) = winzones.windows_for_iana(first)
        if got_error != ok { ret 11u8 }
        if !text_is(got, second) { ret 12u8 }
        ret 0u8
    }
    if k == 84u8 {
        let (tt, p2) = bar(line, p1)
        let want = line[p2..line.len]
        let (got, got_error) = winzones.iana_for_windows_in(first, tt)
        if got_error != ok { ret 31u8 }
        if !text_is(got, want) { ret 32u8 }
        ret 0u8
    }
    if k == 88u8 {
        let (tt, p2) = bar(line, p1)
        let (_, e) = winzones.iana_for_windows_in(first, tt)
        if e != winzones.NotFound { ret 33u8 }
        ret 0u8
    }
    if k == 78u8 {
        let (_, e) = winzones.iana_for_windows(first)
        if e != winzones.NotFound { ret 21u8 }
        ret 0u8
    }
    if k == 77u8 {
        let (_, e) = winzones.windows_for_iana(first)
        if e != winzones.NotFound { ret 22u8 }
        ret 0u8
    }
    ret 99u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    if winzones.windows_zone_count() != %dusize { os.exit(101i32) }
    if winzones.iana_name_count() != %dusize { os.exit(102i32) }
    if winzones.territory_row_count() != %dusize { os.exit(103i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("tz windows ok")
    ret ok
}
''' % (len([1 for k, v in win_tz.items() if k and v]), len(reverse), len(territory))

src = ('// e.tz.winzones: the Windows id to IANA map, sampled both ways, with case folding, refusals (D2800) and the territory rows (D3601).\n'
       '// Generated by scripts/gen_tz_winzones_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.tz.winzones\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
