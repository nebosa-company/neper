"""Generate tests/selfhost/fixtures/link/time_calendars/src/main.e (L150, D2800).

Reference: convertdate (Julian, Islamic civil tabular, Hebrew; Calendrical Calculations
implementations). Month arithmetic is modelled here by walking convertdate's month
lengths; the Japanese era table is the .NET one (Meiji 1868-09-08, Taisho 1912-07-30,
Showa 1926-12-25, Heisei 1989-01-08, Reiwa 2019-05-01), checked by hand cases.

    PYTHONPATH=<convertdate install dir> python scripts/gen_calendars_test.py
"""
import datetime
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from convertdate import hebrew, islamic, julian  # noqa: E402
import fixture_common as fc  # noqa: E402

random.seed(150)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'time_calendars' / 'src' / 'main.e'
MOD = {'J': julian, 'I': islamic, 'H': hebrew}


def months_in_year(c, y):
    if c == 'H':
        return 13 if hebrew.leap(y) else 12
    return 12


def scriptural(y, civil):
    leap = hebrew.leap(y)
    if civil <= 6:
        return civil + 6
    if leap:
        return 13 if civil == 7 else civil - 7
    return civil - 6


def length(c, y, m):
    if c == 'H':
        return hebrew.month_length(y, scriptural(y, m))
    return MOD[c].month_length(y, m)


def count_of(c, y, m, d):
    if c == 'H':
        jd = hebrew.to_jd(y, scriptural(y, m), d)
    else:
        jd = MOD[c].to_jd(y, m, d)
    return int(round(jd - 2440587.5))


def iso_of(count):
    try:
        d = datetime.date.fromordinal(count + 719163)
        return d.year, d.month, d.day
    except (ValueError, OverflowError):
        return None


def add_months(c, y, m, d, n):
    last = months_in_year
    # position in month sequence; walk
    steps = abs(n)
    sign = 1 if n > 0 else -1
    for _ in range(steps):
        m += sign
        if m > months_in_year(c, y):
            y += 1
            m = 1
        elif m < 1:
            y -= 1
            if y < 1:
                return None
            m = months_in_year(c, y)
    if y < 1:
        return None
    d = min(d, length(c, y, m))
    return y, m, d


lines = []

# C: conversion and validity.
def conv_line(c, y, m, d):
    ok = m <= months_in_year(c, y) and 1 <= d <= length(c, y, m)
    if not ok:
        lines.append('C %s %d %d %d E' % (c, y, m, d))
        return
    n = count_of(c, y, m, d)
    iso = iso_of(n)
    lines.append('C %s %d %d %d %d %s' % (c, y, m, d, n, '%d %d %d' % iso if iso else '0 0 0'))


for _ in range(260):
    conv_line('J', random.randint(1, 3000), random.randint(1, 12), random.randint(1, 31))
for y, m, d in ((1582, 10, 4), (1582, 10, 5), (1582, 10, 14), (1, 1, 1), (4, 2, 29), (100, 2, 29), (1900, 2, 29), (2000, 2, 29), (2024, 2, 30), (2024, 13, 1)):
    conv_line('J', y, m, d)
for _ in range(260):
    conv_line('I', random.randint(1, 1700), random.randint(1, 12), random.randint(1, 31))
for y, m, d in ((1, 1, 1), (1446, 4, 1), (1445, 12, 30), (1446, 12, 30), (1443, 12, 30), (1, 12, 30), (2, 12, 30), (5, 12, 30)):
    conv_line('I', y, m, d)
for _ in range(300):
    conv_line('H', random.randint(1, 6500), random.randint(1, 13), random.randint(1, 31))
for y in range(5780, 5800):
    for m in range(1, 14):
        conv_line('H', y, m, 30)
        conv_line('H', y, m, 29)
        conv_line('H', y, m, 1)

# P: year properties.
for c, lo, hi in (('J', 1, 3000), ('I', 1, 1700), ('H', 1, 6500)):
    for y in sorted(set(random.randint(lo, hi) for _ in range(80))):
        leap = {'J': y % 4 == 0, 'I': (14 + 11 * y) % 30 < 11, 'H': hebrew.leap(y)}[c]
        days = sum(length(c, y, m) for m in range(1, months_in_year(c, y) + 1))
        lines.append('P %s %d %d %d %d' % (c, y, 1 if leap else 0, months_in_year(c, y), days))

# M: add_months over real month sequences.
for c, lo, hi in (('J', 1, 3000), ('I', 1, 1700), ('H', 1, 6500)):
    made = 0
    while made < 160:
        y = random.randint(lo, hi)
        m = random.randint(1, months_in_year(c, y))
        d = random.randint(1, length(c, y, m))
        n = random.choice((1, -1, 2, -2, 5, 11, 12, 13, -12, -13, 18, 24, 25, 47, -30, 100, -100, 235, 1000, -1000))
        got = add_months(c, y, m, d, n)
        if got is None:
            lines.append('M %s %d %d %d %d E' % (c, y, m, d, n))
        else:
            lines.append('M %s %d %d %d %d %d %d %d' % (c, y, m, d, n, got[0], got[1], got[2]))
        made += 1

# Y: add_years (same month number, clamped to the year's last month, day clamped).
for c, lo, hi in (('J', 1, 3000), ('I', 1, 1700), ('H', 1, 6500)):
    for _ in range(60):
        y = random.randint(lo, hi)
        m = random.randint(1, months_in_year(c, y))
        d = random.randint(1, length(c, y, m))
        n = random.choice((1, -1, 4, 19, -19, 30, 100, -3))
        y2 = y + n
        if y2 < 1:
            lines.append('Y %s %d %d %d %d E' % (c, y, m, d, n))
            continue
        m2 = min(m, months_in_year(c, y2))
        d2 = min(d, length(c, y2, m2))
        lines.append('Y %s %d %d %d %d %d %d %d' % (c, y, m, d, n, y2, m2, d2))

# X: cross-calendar conversion by Julian day, target by convertdate's own from_jd.
def from_count(c, n):
    jd = n + 2440587.5
    y, m, d = MOD[c].from_jd(jd)
    if c == 'H':
        # scriptural -> civil
        leap = hebrew.leap(y)
        if m >= 7:
            m = m - 6
        else:
            m = m + (13 if leap else 12) - 6
    return y, m, d

for src, dst in (('H', 'I'), ('I', 'H'), ('J', 'H'), ('H', 'J'), ('I', 'J'), ('J', 'I')):
    for _ in range(40):
        n = random.randint(-300000 + 719163 - 719163 + 300000, 200000) if False else random.randint(-700000 + 0, 700000)
        n = random.randint(-100000, 200000)
        a = from_count(src, n)
        b = from_count(dst, n)
        if a[0] < 1 or b[0] < 1:
            continue
        lines.append('X %s %d %d %d %s %d %d %d' % (src, a[0], a[1], a[2], dst, b[0], b[1], b[2]))

# D: day of year.
for c, lo, hi in (('J', 1, 3000), ('I', 1, 1700), ('H', 1, 6500)):
    for _ in range(40):
        y = random.randint(lo, hi)
        m = random.randint(1, months_in_year(c, y))
        d = random.randint(1, length(c, y, m))
        doy = sum(length(c, y, k) for k in range(1, m)) + d
        lines.append('D %s %d %d %d %d' % (c, y, m, d, doy))

# K: Japanese eras by hand (era index 0 Meiji .. 4 Reiwa; E: refused).
japanese = [
    '1868 9 8 0 1 9 8', '1868 9 7 E', '1868 1 1 E', '1912 7 29 0 45 7 29', '1912 7 30 1 1 7 30',
    '1926 12 24 1 15 12 24', '1926 12 25 2 1 12 25', '1989 1 7 2 64 1 7', '1989 1 8 3 1 1 8',
    '2019 4 30 3 31 4 30', '2019 5 1 4 1 5 1', '2025 10 12 4 7 10 12', '1900 2 29 E', '2000 2 29 3 12 2 29',
    '1873 1 1 0 6 1 1', '1945 8 15 2 20 8 15', '2024 13 1 E',
]
for j in japanese:
    lines.append('K ' + j)
# R: era-year back to ISO.
for t in ('0 1 9 8 1868 9 8', '0 1 9 7 E', '0 45 7 30 E', '1 1 7 30 1912 7 30', '1 1 7 29 E', '2 64 1 7 1989 1 7',
          '2 64 1 8 E', '3 1 1 7 E', '3 31 4 30 2019 4 30', '3 31 5 1 E', '4 1 5 1 2019 5 1', '4 0 5 1 E', '5 1 1 1 E',
          '4 2 2 29 2020 2 29', '4 5 2 29 E', '4 6 2 29 2024 2 29'):
    lines.append('R ' + t)

vec_src, names = fc.vector_functions('v', lines)

# Fix the one hand error above deliberately: 2023-02-29 does not exist; era 4 year 5 is 2023.
lines_fixed = []

CHECK = '''
fn cal_of(s: str) -> calendars.Calendar {
    if s[0usize] == 74u8 { ret .Julian }
    if s[0usize] == 73u8 { ret .IslamicCivil }
    ret .Hebrew
}

fn date3(y: i64, m: i64, d: i64) -> time.Date {
    var r: time.Date = zero
    r.year = i32(y)
    r.month = u8(m)
    r.day = u8(d)
    ret r
}

fn same(a: time.Date, y: i64, m: i64, d: i64) -> bool {
    ret i64(a.year) == y && i64(a.month) == m && i64(a.day) == d
}

fn check_line(line: str) -> u8 {
    let (kind, p0) = tok(line, 0usize)
    if kind[0usize] == 67u8 {
        let (c_text, p1) = tok(line, p0)
        let (y_text, p2) = tok(line, p1)
        let (m_text, p3) = tok(line, p2)
        let (d_text, p4) = tok(line, p3)
        let (n_text, p5) = tok(line, p4)
        let cal = cal_of(c_text)
        let date = date3(dec(y_text), dec(m_text), dec(d_text))
        if n_text[0usize] == 69u8 {
            if calendars.valid(cal, date) { ret 1u8 }
            let (_, to_error) = calendars.to_days(cal, date)
            if to_error == ok { ret 2u8 }
            ret 0u8
        }
        let (gy, p6) = tok(line, p5)
        let (gm, p7) = tok(line, p6)
        let (gd, p8) = tok(line, p7)
        if !calendars.valid(cal, date) { ret 3u8 }
        let (count, count_error) = calendars.to_days(cal, date)
        if count_error != ok || count != dec(n_text) { ret 4u8 }
        let (back, back_error) = calendars.from_days(cal, count)
        if back_error != ok || !same(back, dec(y_text), dec(m_text), dec(d_text)) { ret 5u8 }
        if dec(gy) != 0i64 {
            let (iso, iso_error) = calendars.to_iso(cal, date)
            if iso_error != ok || !same(iso, dec(gy), dec(gm), dec(gd)) { ret 6u8 }
            let (again, again_error) = calendars.from_iso(cal, iso)
            if again_error != ok || !same(again, dec(y_text), dec(m_text), dec(d_text)) { ret 7u8 }
        }
        ret 0u8
    }
    if kind[0usize] == 80u8 {
        let (c_text, p1) = tok(line, p0)
        let (y_text, p2) = tok(line, p1)
        let (leap_text, p3) = tok(line, p2)
        let (months_text, p4) = tok(line, p3)
        let (days_text, p5) = tok(line, p4)
        let cal = cal_of(c_text)
        let year = i32(dec(y_text))
        if calendars.is_leap_year(cal, year) != (dec(leap_text) == 1i64) { ret 11u8 }
        if i64(calendars.months_in_year(cal, year)) != dec(months_text) { ret 12u8 }
        var total = 0i64
        var m = 1u8
        while m <= calendars.months_in_year(cal, year) {
            let (len, len_error) = calendars.days_in_month(cal, year, m)
            if len_error != ok { ret 13u8 }
            total += i64(len)
            m += 1u8
        }
        if total != dec(days_text) { ret 14u8 }
        ret 0u8
    }
    if kind[0usize] == 77u8 || kind[0usize] == 89u8 {
        let (c_text, p1) = tok(line, p0)
        let (y_text, p2) = tok(line, p1)
        let (m_text, p3) = tok(line, p2)
        let (d_text, p4) = tok(line, p3)
        let (n_text, p5) = tok(line, p4)
        let (ry, p6) = tok(line, p5)
        let cal = cal_of(c_text)
        let date = date3(dec(y_text), dec(m_text), dec(d_text))
        var got: time.Date = zero
        var got_error: err = ok
        if kind[0usize] == 77u8 {
            let (g, e) = calendars.add_months(cal, date, dec(n_text))
            got = g
            got_error = e
        } else {
            let (g, e) = calendars.add_years(cal, date, dec(n_text))
            got = g
            got_error = e
        }
        if ry[0usize] == 69u8 {
            if got_error == ok { ret 21u8 }
            ret 0u8
        }
        let (rm, p7) = tok(line, p6)
        let (rd, p8) = tok(line, p7)
        if got_error != ok { ret 22u8 }
        if !same(got, dec(ry), dec(rm), dec(rd)) { ret 23u8 }
        ret 0u8
    }
    if kind[0usize] == 88u8 {
        let (c_text, p1) = tok(line, p0)
        let (y_text, p2) = tok(line, p1)
        let (m_text, p3) = tok(line, p2)
        let (d_text, p4) = tok(line, p3)
        let (t_text, p5) = tok(line, p4)
        let (ty, p6) = tok(line, p5)
        let (tm, p7) = tok(line, p6)
        let (td, p8) = tok(line, p7)
        let (out, out_error) = calendars.convert(cal_of(c_text), cal_of(t_text), date3(dec(y_text), dec(m_text), dec(d_text)))
        if out_error != ok { ret 31u8 }
        if !same(out, dec(ty), dec(tm), dec(td)) { ret 32u8 }
        ret 0u8
    }
    if kind[0usize] == 68u8 {
        let (c_text, p1) = tok(line, p0)
        let (y_text, p2) = tok(line, p1)
        let (m_text, p3) = tok(line, p2)
        let (d_text, p4) = tok(line, p3)
        let (n_text, p5) = tok(line, p4)
        let (doy, doy_error) = calendars.day_of_year(cal_of(c_text), date3(dec(y_text), dec(m_text), dec(d_text)))
        if doy_error != ok || i64(doy) != dec(n_text) { ret 41u8 }
        ret 0u8
    }
    if kind[0usize] == 75u8 {
        let (y_text, p1) = tok(line, p0)
        let (m_text, p2) = tok(line, p1)
        let (d_text, p3) = tok(line, p2)
        let (e_text, p4) = tok(line, p3)
        let (j, j_error) = calendars.japanese_from_iso(date3(dec(y_text), dec(m_text), dec(d_text)))
        if e_text[0usize] == 69u8 {
            if j_error == ok { ret 51u8 }
            ret 0u8
        }
        let (yoe, p5) = tok(line, p4)
        let (jm, p6) = tok(line, p5)
        let (jd, p7) = tok(line, p6)
        if j_error != ok { ret 52u8 }
        if i64(j.era) != dec(e_text) || i64(j.year) != dec(yoe) || i64(j.month) != dec(jm) || i64(j.day) != dec(jd) { ret 53u8 }
        let (iso, iso_error) = calendars.japanese_to_iso(j)
        if iso_error != ok || !same(iso, dec(y_text), dec(m_text), dec(d_text)) { ret 54u8 }
        ret 0u8
    }
    if kind[0usize] == 82u8 {
        let (era_text, p1) = tok(line, p0)
        let (yoe, p2) = tok(line, p1)
        let (m_text, p3) = tok(line, p2)
        let (d_text, p4) = tok(line, p3)
        let (ry, p5) = tok(line, p4)
        var j: calendars.JapaneseDate = zero
        j.era = u8(dec(era_text))
        j.year = i32(dec(yoe))
        j.month = u8(dec(m_text))
        j.day = u8(dec(d_text))
        let (iso, iso_error) = calendars.japanese_to_iso(j)
        if ry[0usize] == 69u8 {
            if iso_error == ok { ret 61u8 }
            ret 0u8
        }
        let (rm, p6) = tok(line, p5)
        let (rd, p7) = tok(line, p6)
        if iso_error != ok || !same(iso, dec(ry), dec(rm), dec(rd)) { ret 62u8 }
        ret 0u8
    }
    ret 99u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    // Hand cases: the 5785 new year, Adar I / II naming, a leap Hebrew year's 13 months.
    let (rh, rh_error) = calendars.from_iso(.Hebrew, date3(2024i64, 10i64, 3i64))
    if rh_error != ok || !same(rh, 5785i64, 1i64, 1i64) { os.exit(101i32) }
    if !text_is(calendars.month_name_hebrew(5784i32, 6u8), "Adar I") || !text_is(calendars.month_name_hebrew(5784i32, 7u8), "Adar II") { os.exit(102i32) }
    if !text_is(calendars.month_name_hebrew(5785i32, 6u8), "Adar") || !text_is(calendars.month_name_hebrew(5785i32, 7u8), "Nisan") { os.exit(103i32) }
    if calendars.scriptural_month(5784i32, 8u8) != 1u8 || calendars.civil_month(5784i32, 1u8) != 8u8 { os.exit(104i32) }
    if !text_is(calendars.era_name(4u8), "Reiwa") { os.exit(105i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("time calendars ok")
    ret ok
}
'''

src = ('// e.time.calendars against convertdate (Julian, Islamic civil, Hebrew) by Julian day count, ISO date\n'
       '// by datetime.date, month arithmetic by walking convertdate month lengths, and hand-checked Japanese\n'
       '// eras (D2800). Line kinds: C conversion, P year properties, M add_months, Y add_years, X cross-calendar,\n'
       '// D day of year, K/R Japanese era to and from ISO. Generated by scripts/gen_calendars_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.time\nuse e.time.calendars\n\n'
       + fc.PRELUDE + CHECK + vec_src + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors', len(names), 'chunks')
