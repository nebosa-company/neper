"""Generate tests/selfhost/fixtures/link/time_pattern/src/main.e (L150, D2800).

Reference: an independent Python renderer built on the stdlib `calendar` month and day
name tables and `datetime` fields. Each random pattern is rendered from a random
date-time (F lines), parsed back (P lines, with the template defaults for fields the
pattern lacks), and refusal cases (duplicate fields, 12-hour without a marker, a wrong
weekday, trailing bytes, impossible dates) are listed by hand.
"""
import calendar as pycal
import datetime
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(151)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'time_pattern' / 'src' / 'main.e'
TEMPLATE = (2000, 1, 1, 0, 0, 0, 0)


def render(spec, dt, ns):
    """(text, field, value) for one specifier."""
    if spec == 'yyyy':
        return '%04d' % dt.year, 'year', dt.year
    if spec == 'yy':
        return '%02d' % (dt.year % 100), 'yy', dt.year % 100
    if spec == 'MMMM':
        return pycal.month_name[dt.month], 'month', dt.month
    if spec == 'MMM':
        return pycal.month_abbr[dt.month], 'month', dt.month
    if spec == 'MM':
        return '%02d' % dt.month, 'month', dt.month
    if spec == 'M':
        return str(dt.month), 'month', dt.month
    if spec == 'dddd':
        return pycal.day_name[dt.weekday()], 'weekday', dt.weekday()
    if spec == 'ddd':
        return pycal.day_abbr[dt.weekday()], 'weekday', dt.weekday()
    if spec == 'dd':
        return '%02d' % dt.day, 'day', dt.day
    if spec == 'd':
        return str(dt.day), 'day', dt.day
    if spec == 'HH':
        return '%02d' % dt.hour, 'hour', dt.hour
    if spec == 'H':
        return str(dt.hour), 'hour', dt.hour
    if spec in ('hh', 'h'):
        h = dt.hour % 12 or 12
        return ('%02d' % h if spec == 'hh' else str(h)), 'hour12', h
    if spec == 'mm':
        return '%02d' % dt.minute, 'minute', dt.minute
    if spec == 'm':
        return str(dt.minute), 'minute', dt.minute
    if spec == 'ss':
        return '%02d' % dt.second, 'second', dt.second
    if spec == 's':
        return str(dt.second), 'second', dt.second
    if spec == 'tt':
        return ('PM' if dt.hour >= 12 else 'AM'), 'pm', 1 if dt.hour >= 12 else 0
    if spec == 't':
        return ('P' if dt.hour >= 12 else 'A'), 'pm', 1 if dt.hour >= 12 else 0
    if spec[0] == 'f':
        digits = '%09d' % ns
        return digits[:len(spec)], 'nanos_f', int(digits[:len(spec)].ljust(9, '0'))
    if spec[0] == 'F':
        digits = ('%09d' % ns)[:len(spec)].rstrip('0')
        return digits, 'nanos_f', int((digits).ljust(9, '0'))
    raise ValueError(spec)


def pivot(v):
    return 2000 + v if v < 30 else 1900 + v


GROUPS = [
    ['yyyy', 'yy'], ['MMMM', 'MMM', 'MM', 'M'], ['dd', 'd'], ['dddd', 'ddd'], ['HH', 'H'],
    ['mm', 'm'], ['ss', 's'], ['f', 'ff', 'fff', 'ffffff', 'fffffffff', 'F', 'FF', 'FFF', 'FFFFFFFFF'],
]
SEPS = ['-', '/', '.', ':', ' ', 'T', ', ', "'at'", '" on "', '\\@', '_']


def random_pattern():
    parts = []
    chosen = [g for g in GROUPS if random.random() < 0.55]
    if random.random() < 0.25:
        chosen.append(['hh', 'h'])
    if not chosen:
        chosen = [GROUPS[0]]
    random.shuffle(chosen)
    for i, g in enumerate(chosen):
        spec = random.choice(g)
        if spec in ('hh', 'h'):
            parts.append(('spec', spec))
            parts.append(('lit', ' ' if random.random() < 0.5 else ''))
            parts.append(('spec', random.choice(['tt', 't'])))
        else:
            parts.append(('spec', spec))
        if i + 1 < len(chosen):
            parts.append(('lit', random.choice(SEPS)))
    return parts


def lit_text(sep):
    if sep.startswith("'") or sep.startswith('"'):
        return sep[1:-1]
    if sep.startswith('\\'):
        return sep[1:]
    return sep


def adjacent_specs_collide(parts):
    # two specifiers with no literal between can read ambiguously (digits run together); skip
    prev = None
    for kind, v in parts:
        if kind == 'spec' and prev == 'spec':
            return True
        prev = kind if not (kind == 'lit' and v == '') else prev
    return False


lines = []
tries = 0
while len([l for l in lines if l.startswith('F|')]) < 260 and tries < 5000:
    tries += 1
    parts = random_pattern()
    if adjacent_specs_collide(parts):
        continue
    pattern = ''.join(v for _, v in parts)
    year = random.randint(1000, 2400) if random.random() < 0.8 else random.randint(1900, 2029)
    try:
        dt = datetime.datetime(year, random.randint(1, 12), random.randint(1, 28),
                               random.randint(0, 23), random.randint(0, 59), random.randint(0, 59))
    except ValueError:
        continue
    ns = random.choice((0, 0, 120000000, 5000000, 999999999, 123456789, 1))
    text, fields = '', {}
    specs = []
    for kind, v in parts:
        if kind == 'spec':
            t, field, val = render(v, dt, ns)
            text += t
            fields[field] = val
            specs.append(v)
        else:
            text += lit_text(v)
    lines.append('F|%d|%d|%d|%d|%d|%d|%d|%s|%s' % (dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, ns, pattern, text))
    # expected parse
    y, mo, d, h, mi, s, n = TEMPLATE
    err = False
    if 'year' in fields: y = fields['year']
    if 'yy' in fields: y = pivot(fields['yy'])
    if 'month' in fields: mo = fields['month']
    if 'day' in fields: d = fields['day']
    if 'minute' in fields: mi = fields['minute']
    if 'second' in fields: s = fields['second']
    if 'nanos_f' in fields: n = fields['nanos_f']
    if 'hour' in fields:
        h = fields['hour']
        if 'hour12' in fields or 'pm' in fields:
            err = True
    elif 'hour12' in fields or 'pm' in fields:
        if 'hour12' in fields and 'pm' in fields:
            h = fields['hour12'] % 12 + 12 * fields['pm']
        else:
            err = True
    try:
        datetime.date(y, mo, d)
    except ValueError:
        err = True
    if 'weekday' in fields and not err:
        if datetime.date(y, mo, d).weekday() != fields['weekday']:
            err = True
    # duplicate fields (random groups cannot repeat a group) are impossible here
    if err:
        lines.append('P|%s|%s|E' % (pattern, text))
    else:
        lines.append('P|%s|%s|%d %d %d %d %d %d %d' % (pattern, text, y, mo, d, h, mi, s, n))

# Case folding and single-digit forms.
more = [
    'P|dd MMMM yyyy|05 march 2024|2024 3 5 0 0 0 0', 'P|dd MMMM yyyy|05 MARCH 2024|2024 3 5 0 0 0 0',
    'P|d/M/yyyy|5/3/2024|2024 3 5 0 0 0 0', 'P|d/M/yyyy|05/03/2024|2024 3 5 0 0 0 0',
    'P|dd/MM/yyyy|5/3/2024|E', 'P|yyyy-MM-dd|24-03-05|E', 'P|yyyy-MM-dd|2024-03-05x|E', 'P|yyyy-MM-dd|2024-13-05|E',
    'P|yyyy-MM-dd|2023-02-29|E', 'P|yyyy-MM-dd|2024-02-29|2024 2 29 0 0 0 0',
    'P|yyyy-MM-dd yyyy|2024-03-05 2024|E', 'P|HH:mm|25:00|E', 'P|HH:mm|23:60|E',
    'P|h:mm tt|12:30 AM|2000 1 1 0 30 0 0', 'P|h:mm tt|12:30 PM|2000 1 1 12 30 0 0', 'P|h:mm tt|1:05 pm|2000 1 1 13 5 0 0',
    'P|h:mm tt|0:30 AM|E', 'P|h:mm tt|13:30 PM|E', 'P|h:mm|1:30|E', 'P|HH:mm tt|01:30 PM|E', 'P|h t|9 a|2000 1 1 9 0 0 0',
    'P|dddd, dd MMM yyyy|Tuesday, 05 Mar 2024|2024 3 5 0 0 0 0', 'P|dddd, dd MMM yyyy|Monday, 05 Mar 2024|E',
    'P|ddd dd|Tue 05|E', 'P|HH:mm:ss.fff|10:20:30.5|E', 'P|HH:mm:ss.FFF|10:20:30.5|2000 1 1 10 20 30 500000000',
    'P|HH:mm:ss.FFF|10:20:30.|2000 1 1 10 20 30 0', 'P|HH:mm:ss.fff|10:20:30.050|2000 1 1 10 20 30 50000000',
    "P|yyyy'T'MM|2024T07|2024 7 1 0 0 0 0", "P|yyyy'T'MM|2024X07|E", "P|yyyy\\TMM|2024T07|2024 7 1 0 0 0 0",
    'P|%d|7|2000 1 7 0 0 0 0', 'P|%M %y|3 24|E', 'P|yy|29|2029 1 1 0 0 0 0', 'P|yy|30|1930 1 1 0 0 0 0', 'P|yy|00|2000 1 1 0 0 0 0',
    'P||2024|E', 'P||x|E', "P|'abc|abc|E", 'P|yyy|202|E', 'P|MMMMM|March|E', 'P|ffffffffff|1234567890|E',
]
lines.extend(more)

# Format-only checks of unusual specs.
lines.extend([
    'F|2024|3|5|0|0|0|0|h:mm tt|12:00 AM', 'F|2024|3|5|12|5|9|0|h:mm:s tt|12:05:9 PM', 'F|2024|3|5|13|5|9|0|hh t|01 P',
    'F|2024|3|5|13|5|9|20000000|ss.FFFFFFFFF|09.02', 'F|2024|3|5|13|5|9|0|ss.FFFFFFFFF|09.', 'F|2024|3|5|13|5|9|0|%H|13',
    "F|2024|3|5|13|5|9|0|'it''s'|its", 'F|2024|12|31|23|59|59|999999999|yyyy-MM-ddTHH:mm:ss.fffffffff|2024-12-31T23:59:59.999999999',
    'F|7|1|1|0|0|0|0|yyyy|0007', 'F|2000|1|1|0|0|0|0|yy|00', 'F|2099|1|1|0|0|0|0|yy|99',
])
# Format refusals: bad run length, unterminated quote, trailing escape.
refusals = ['yyy', "'open", 'abc\\', 'MMMMM', 'ddddd', 'HHH', 'ffffffffff']

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn bar(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] != 124u8 { p += 1usize }
    let piece = line[at..p]
    if p < line.len { p += 1usize }
    ret (piece, p)
}

fn same_dt(v: calendar.DateTime, y: i64, mo: i64, d: i64, h: i64, mi: i64, s: i64, n: i64) -> bool {
    ret i64(v.date.year) == y && i64(v.date.month) == mo && i64(v.date.day) == d && i64(v.time.hour) == h && i64(v.time.minute) == mi && i64(v.time.second) == s && i64(v.time.nanos) == n
}

fn check_line(line: str) -> u8 {
    var buf: [128]u8 = zero
    let (kind, p0) = bar(line, 0usize)
    if kind[0usize] == 70u8 {
        let (ys, p1) = bar(line, p0)
        let (ms, p2) = bar(line, p1)
        let (ds, p3) = bar(line, p2)
        let (hs, p4) = bar(line, p3)
        let (mis, p5) = bar(line, p4)
        let (ss, p6) = bar(line, p5)
        let (ns, p7) = bar(line, p6)
        let (pattern, p8) = bar(line, p7)
        let want = line[p8..line.len]
        var v: calendar.DateTime = zero
        v.date.year = i32(dec(ys))
        v.date.month = u8(dec(ms))
        v.date.day = u8(dec(ds))
        v.time.hour = u8(dec(hs))
        v.time.minute = u8(dec(mis))
        v.time.second = u8(dec(ss))
        v.time.nanos = u32(dec(ns))
        let (got, got_error) = pattern_api.format(pattern, v, buf[0usize..128usize])
        if got_error != ok { ret 1u8 }
        if !text_is(got, want) { ret 2u8 }
        ret 0u8
    }
    let (pattern, p1) = bar(line, p0)
    let (source, p2) = bar(line, p1)
    let rest = line[p2..line.len]
    let (got, got_error) = pattern_api.parse(pattern, source)
    if rest[0usize] == 69u8 {
        if got_error == ok { ret 11u8 }
        ret 0u8
    }
    if got_error != ok { ret 12u8 }
    let (y, q1) = tok(rest, 0usize)
    let (mo, q2) = tok(rest, q1)
    let (d, q3) = tok(rest, q2)
    let (h, q4) = tok(rest, q3)
    let (mi, q5) = tok(rest, q4)
    let (s, q6) = tok(rest, q5)
    let (n, q7) = tok(rest, q6)
    if !same_dt(got, dec(y), dec(mo), dec(d), dec(h), dec(mi), dec(s), dec(n)) { ret 13u8 }
    ret 0u8
}

'''

REFUSE = ''.join('    let (_, r%d) = pattern_api.format("%s", at, buf[0usize..64usize])\n    if r%d == ok { os.exit(%di32) }\n' % (i, neper_p, i, 120 + i)
                 for i, neper_p in enumerate(fc.neper_str(r) for r in refusals))

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    var buf: [64]u8 = zero
    var at: calendar.DateTime = zero
    at.date.year = 2024i32
    at.date.month = 3u8
    at.date.day = 5u8
    // Output buffer too small is refused, not truncated.
    let (_, small) = pattern_api.format("yyyy-MM-dd", at, buf[0usize..5usize])
    if small == ok { os.exit(110i32) }
''' + REFUSE + '''    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("time pattern ok")
    ret ok
}
'''

src = ('// e.time.pattern against an independent Python renderer over the stdlib month and weekday\n'
       '// name tables (D2800). F lines format a date-time with a pattern, P lines parse text back (E: refused).\n'
       '// Generated by scripts/gen_time_pattern_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.time\nuse e.time.calendar\nuse e.time.pattern as pattern_api\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors', len(names), 'chunks')
