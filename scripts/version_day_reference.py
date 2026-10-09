"""Reference and fixture generator for L020: e.fmt.semver.at_least / cmp_loose and e.time.calendar.iso_day_count / age_days.

  python scripts/version_day_reference.py

at_least is a Python transcription of petcow's `version_at_least` (src/currency.rs), with one change the library
documents: a component number too long for 64 bits saturates (petcow reads it as 0). The day counts come from
Python's `datetime.date.toordinal`, which shares no code with `e.time`'s civil arithmetic. Writes
tests/selfhost/fixtures/link/fmt_semver_loose/src/main.e and tests/selfhost/fixtures/link/time_calendar_iso/src/main.e.
"""
import datetime
import pathlib
import random

U64 = (1 << 64) - 1


def parts(s):
    out = []
    for c in s.split('.'):
        n = 0
        i = 0
        while i < len(c) and c[i] in '0123456789':
            i += 1
        n = min(int(c[:i]) if i else 0, U64)
        out.append((n, c[i:]))
    return out


def at_least(have, want):
    h, w = parts(have), parts(want)
    for i in range(max(len(h), len(w))):
        a = h[i] if i < len(h) else (0, '')
        b = w[i] if i < len(w) else (0, '')
        if a[0] != b[0]:
            return a[0] > b[0]
        if a[1] != b[1]:
            if (a[1] == '') != (b[1] == ''):
                return a[1] == ''
            return a[1].encode() > b[1].encode()
    return True


def civil_count(text):
    if len(text) < 10 or text[4] != '-' or text[7] != '-':
        return None
    digits = text[0:4] + text[5:7] + text[8:10]
    if not all(c in '0123456789' for c in digits):
        return None
    y, m, d = int(text[0:4]), int(text[5:7]), int(text[8:10])
    try:
        return datetime.date(y, m, d).toordinal() - datetime.date(1970, 1, 1).toordinal()
    except ValueError:
        return None


def age(today, then):
    a, b = civil_count(today), civil_count(then)
    if a is None or b is None:
        return 'E'
    return str(a - b)


COMPONENTS = ['0', '1', '2', '9', '10', '17', '27', '04', '1rc1', '2-rc1', '2-rc2', 'x', 'rc', '2b', '-', '10a', '3~', '2-', '00',
              '99999999999999999999999', '18446744073709551615', '18446744073709551616', '4-rc']


def version(rng):
    return '.'.join(rng.choice(COMPONENTS) for _ in range(rng.randint(1, 4)))


def chunked(lines, per):
    return ['"' + '\\n'.join(lines[i:i + per]) + '\\n"' for i in range(0, len(lines), per)]


def write(name, header, lines, check_fn, extra_main, pairs=80):
    chunks = chunked(lines, pairs)
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    source = header + check_fn + '\n' + funcs + '\nfn main(a: *mem.Arena, args: []str) -> err {\n' + extra_main + calls + '    try io.print("%s")\n    ret ok\n}\n'
    return source


COMMON = '''use e.io
use e.mem
use e.os

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn next_token(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] == 32u8 { p += 1usize }
    let start = p
    while p < line.len && line[p] != 32u8 { p += 1usize }
    ret (line[start..p], p)
}

fn run(text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            if !check(text[start..i]) {
                let shown = io.print(text[start..i])
                ret 1u8
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}
'''


def main():
    rng = random.Random(2005)
    root = pathlib.Path(__file__).resolve().parent.parent / 'tests' / 'selfhost' / 'fixtures' / 'link'

    # petcow's own assertions
    for have, want, expected in (('10.2', '9.6', True), ('9.6', '10.2', False), ('17.2', '17.2', True), ('17.3', '17.2', True),
                                 ('17.1', '17.2', False), ('1.27', '1.27.4', False), ('1.27.4', '1.27', True),
                                 ('1.2-rc1', '1.2', False), ('1.2', '1.2-rc1', True)):
        assert at_least(have, want) == expected, (have, want)
    pairs = [('10.2', '9.6'), ('9.6', '10.2'), ('17.2', '17.2'), ('17.3', '17.2'), ('17.1', '17.2'), ('1.27', '1.27.4'),
             ('1.27.4', '1.27'), ('1.2-rc1', '1.2'), ('1.2', '1.2-rc1'), ('1.2-rc1', '1.2-rc2'), ('1.2-rc2', '1.2-rc1'), ('2.0.0.1', '2.0.0'),
             ('2.0.0', '2.0.0.0'), ('2.0.0.0', '2.0.0'), ('1.0', '1'), ('1', '1.0.0.0'), ('1.2.3', '1.2.3'), ('0.9', '0.10'), ('rc', '0'), ('x', 'y')]
    for _ in range(600):
        pairs.append((version(rng), version(rng)))
    for _ in range(100):
        v = version(rng)
        pairs.append((v, v))
    vlines = ['V %s %s => %d' % (h, w, 1 if at_least(h, w) else 0) for h, w in pairs]
    header = ('// `e.fmt.semver.at_least` (L020: loose dotted versions compared numerically, a suffix below the release, bytewise\n'
              '// between suffixes, a missing component 0) against scripts/version_day_reference.py, a transcription of petcow\'s\n'
              '// `version_at_least`: its own assertions and %d seeded pairs of dotted versions (suffixes, zero padding, components\n'
              '// past 64 bits, which saturate). The empty string is checked directly. A line is `V have want => 1|0`.\n'
              'use e.fmt.semver\n' % len(pairs))
    check = '''
fn check(line: str) -> bool {
    let (have, after_have) = next_token(line, 2usize)
    let (want, after_want) = next_token(line, after_have)
    let (arrow, after_arrow) = next_token(line, after_want)
    let (result, after_result) = next_token(line, after_arrow)
    let expected = result[0usize] == 49u8
    ret semver.at_least(have, want) == expected
}
'''
    extra = '''    // The empty string is one component, 0.
    if !semver.at_least("", "") { os.exit(100i32) }
    if !semver.at_least("", "0") { os.exit(101i32) }
    if !semver.at_least("1", "") { os.exit(102i32) }
    if semver.at_least("", "1") { os.exit(103i32) }
    if semver.cmp_loose("1.10", "1.9") != 1i32 || semver.cmp_loose("1.9", "1.10") != -1i32 || semver.cmp_loose("2", "2.0") != 0i32 { os.exit(104i32) }
'''
    out = write('semver', header, vlines, None, '', 80) if False else None
    chunks = chunked(vlines, 80)
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    src = header + COMMON + check + '\n' + funcs + '\nfn main(a: *mem.Arena, args: []str) -> err {\n' + extra + calls + '    try io.print("fmt semver loose ok")\n    ret ok\n}\n'
    target = root / 'fmt_semver_loose' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(src, encoding='utf-8', newline='\n')
    print('wrote', target.parent.parent.name, len(vlines), 'pairs')

    # days
    assert age('2026-07-25', '2026-07-01') == '24'
    dates = []
    for _ in range(300):
        y = rng.randint(1, 9999) if rng.random() < 0.3 else rng.randint(1900, 2100)
        m = rng.randint(1, 12)
        d = rng.randint(1, 31)
        text = '%04d-%02d-%02d' % (y, m, d)
        if rng.random() < 0.15:
            text += 'T%02d:%02d:%02dZ' % (rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59))
        dates.append(text)
    hand = ['2026-07-25', '2026-07-01', '2000-02-29', '1900-02-29', '2100-02-29', '2024-02-29', '2023-02-29', '1970-01-01', '1969-12-31',
            '2026-13-01', '2026-00-10', '2026-04-31', '2026-04-30', '2026-7-1', '2026/07/01', '26-07-01', '', '2026-07-0', 'abcd-ef-gh',
            '2026-07-01T00:00:00Z', '0001-01-01', '9999-12-31', '2026-07-01x', '-026-07-01']
    allp = hand + dates
    dlines = []
    for i in range(400):
        t, w = rng.choice(allp), rng.choice(allp)
        dlines.append('D %s %s => %s' % (t or '_', w or '_', age(t, w)))
    for t, w in (('2026-07-25', '2026-07-01'), ('2026-07-01', '2026-07-25'), ('2024-03-01', '2024-02-01'), ('2000-03-01', '1900-03-01'),
                 ('9999-12-31', '0001-01-01'), ('1970-01-01', '1970-01-01')):
        dlines.append('D %s %s => %s' % (t, w, age(t, w)))
    for t in allp:
        dlines.append('D %s 1970-01-01 => %s' % (t or '_', age(t, '1970-01-01')))
    header = ('// `e.time.calendar.iso_day_count` and `age_days` (L020: the first ten bytes of a text as a real YYYY-MM-DD, counted in days\n'
              '// from 1970-01-01, a longer timestamp\'s time ignored) against scripts/version_day_reference.py, whose counts come from\n'
              '// Python\'s `datetime.date.toordinal`: %d pairs of dates, valid and not (month 13, 30 February, 1900 and 2100 not leap, 2000\n'
              '// and 2024 leap, short and malformed text), the age petcow\'s test expects (24 days) and the extremes 0001-01-01 and\n'
              '// 9999-12-31. A line is `D today then => days` or `=> E` for a refusal; `_` stands for the empty text.\n'
              'use e.time.calendar\n' % len(dlines))
    check = '''
fn number(token: str) -> i64 {
    var v = 0i64
    var negative = false
    var i = 0usize
    if token[0usize] == 45u8 {
        negative = true
        i = 1usize
    }
    while i < token.len {
        v = v * 10i64 + i64(token[i] - 48u8)
        i += 1usize
    }
    if negative { ret 0i64 - v }
    ret v
}

fn real(token: str) -> str {
    if token.len == 1usize && token[0usize] == 95u8 { ret "" }
    ret token
}

fn check(line: str) -> bool {
    let (today, after_today) = next_token(line, 2usize)
    let (then, after_then) = next_token(line, after_today)
    let (arrow, after_arrow) = next_token(line, after_then)
    let (result, after_result) = next_token(line, after_arrow)
    let (days, e) = calendar.age_days(real(today), real(then))
    if result[0usize] == 69u8 { ret e == calendar.Invalid }
    ret e == ok && days == number(result)
}
'''
    chunks = chunked(dlines, 100)
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    extra = '''    // Year 0 is a leap year of the proleptic calendar: 0000-02-28 is two days before 0000-03-01, and a year
    // from 0000-03-01 to 0001-03-01 is 365 days (its 29 February came first).
    let (leap, leap_error) = calendar.age_days("0000-03-01", "0000-02-28")
    if leap_error != ok || leap != 2i64 { os.exit(100i32) }
    let (year_zero, year_zero_error) = calendar.age_days("0001-03-01", "0000-03-01")
    if year_zero_error != ok || year_zero != 365i64 { os.exit(102i32) }
    let (one, one_error) = calendar.iso_day_count("1970-01-02")
    if one_error != ok || one != 1i64 { os.exit(101i32) }
'''
    src = header + COMMON + check + '\n' + funcs + '\nfn main(a: *mem.Arena, args: []str) -> err {\n' + extra + calls + '    try io.print("time calendar iso ok")\n    ret ok\n}\n'
    target = root / 'time_calendar_iso' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(src, encoding='utf-8', newline='\n')
    print('wrote', target.parent.parent.name, len(dlines), 'pairs')


main()
