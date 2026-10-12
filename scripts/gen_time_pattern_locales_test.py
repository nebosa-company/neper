#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/time_pattern_locales/src/main.e (L150, D3601): e.time.pattern's
format_locale and parse_locale against Babel's CLDR formatter for 27 languages.

Babel renders each date-time with the CLDR pattern equivalent to the Neper one (dddd = EEEE, ddd = EEE, tt = a);
F lines are format checks, P lines parse the text back and must give the same fields.

    PYTHONPATH=<Babel install dir> python scripts/gen_time_pattern_locales_test.py
"""
import datetime
import random
import sys
from pathlib import Path

from babel.dates import format_datetime

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(3601)
TAGS = ['en', 'fr', 'de', 'es', 'it', 'pt', 'nl', 'sv', 'da', 'nb', 'fi', 'pl', 'cs', 'hu', 'ro', 'ru', 'uk', 'tr',
        'el', 'ja', 'zh', 'ko', 'id', 'vi', 'ar', 'he', 'hi']
PATTERNS = [('dddd, d MMMM yyyy HH:mm:ss', 'EEEE, d MMMM yyyy HH:mm:ss', False),
            ('ddd d MMM yy hh:mm tt', 'EEE d MMM yy hh:mm a', True),
            ('MMMM', 'MMMM', False), ('MMM/dd', 'MMM/dd', False), ('dddd', 'EEEE', False), ('h:mm t', 'h:mm', None)]
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'time_pattern_locales' / 'src' / 'main.e'

lines = []
for tag in TAGS:
    for neper, cldr, two_digit_year in PATTERNS:
        if cldr == 'h:mm':
            continue
        for _ in range(4):
            y = random.randint(1930, 2029) if two_digit_year else random.randint(1900, 2100)
            base = datetime.date(y, 1, 1) + datetime.timedelta(random.randint(0, 364))
            dt = datetime.datetime(base.year, base.month, base.day, random.randint(0, 23), random.randint(0, 59),
                                   random.randint(0, 59))
            want = format_datetime(dt, cldr, locale=tag)
            lines.append('F|%s|%d|%d|%d|%d|%d|%d|%s|%s' % (tag, dt.year, dt.month, dt.day, dt.hour, dt.minute,
                                                          dt.second, neper, want))
            if neper in ('dddd, d MMMM yyyy HH:mm:ss', 'ddd d MMM yy hh:mm tt', 'MMM/dd'):
                lines.append('P|%s|%s|%s|%d|%d|%d|%d|%d|%d' % (tag, neper, want, dt.year, dt.month, dt.day, dt.hour,
                                                                dt.minute, dt.second))
# English through the locale entry points is the invariant behaviour, an unknown tag and a regional tag.
lines.append('E|zz|MMMM')
lines.append('E|xx-YY|dddd')
lines.append('F|fr-CA|2024|3|5|14|7|9|dddd d MMMM|mardi 5 mars')
lines.append('F|DE_at|2024|3|5|14|7|9|dddd d MMMM|Dienstag 5 März')

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn bar(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] != 124u8 { p += 1usize }
    let piece = line[at..p]
    if p < line.len { p += 1usize }
    ret (piece, p)
}

fn same_dt(v: calendar.DateTime, y: i64, mo: i64, d: i64, h: i64, mi: i64, s: i64) -> bool {
    ret i64(v.date.year) == y && i64(v.date.month) == mo && i64(v.date.day) == d && i64(v.time.hour) == h && i64(v.time.minute) == mi && i64(v.time.second) == s
}

fn check_line(line: str) -> u8 {
    var buf: [128]u8 = zero
    let (kind, p0) = bar(line, 0usize)
    let (tag, p1) = bar(line, p0)
    if kind[0usize] == 69u8 {
        let pat = line[p1..line.len]
        var v: calendar.DateTime = zero
        v.date.year = 2000i32
        v.date.month = 1u8
        v.date.day = 1u8
        let (_, e) = pattern_api.format_locale(tag, pat, v, buf[0usize..128usize])
        if e == ok { ret 1u8 }
        let (_, pe) = pattern_api.parse_locale(tag, pat, "x")
        if pe == ok { ret 2u8 }
        ret 0u8
    }
    if kind[0usize] == 70u8 {
        let (ys, p2) = bar(line, p1)
        let (ms, p3) = bar(line, p2)
        let (ds, p4) = bar(line, p3)
        let (hs, p5) = bar(line, p4)
        let (mis, p6) = bar(line, p5)
        let (ss, p7) = bar(line, p6)
        let (pat, p8) = bar(line, p7)
        let want = line[p8..line.len]
        var v: calendar.DateTime = zero
        v.date.year = i32(dec(ys))
        v.date.month = u8(dec(ms))
        v.date.day = u8(dec(ds))
        v.time.hour = u8(dec(hs))
        v.time.minute = u8(dec(mis))
        v.time.second = u8(dec(ss))
        let (got, got_error) = pattern_api.format_locale(tag, pat, v, buf[0usize..128usize])
        if got_error != ok { ret 11u8 }
        if !text_is(got, want) {
            let shown = io.print(got)
            if shown != ok { ret 12u8 }
            ret 12u8
        }
        ret 0u8
    }
    // P: parse the text back.
    let (pat, p2) = bar(line, p1)
    let (text, p3) = bar(line, p2)
    let (ys, p4) = bar(line, p3)
    let (ms, p5) = bar(line, p4)
    let (ds, p6) = bar(line, p5)
    let (hs, p7) = bar(line, p6)
    let (mis, p8) = bar(line, p7)
    let ss = line[p8..line.len]
    let (got, got_error) = pattern_api.parse_locale(tag, pat, text)
    if got_error != ok { ret 21u8 }
    var year = dec(ys)
    var mo = dec(ms)
    var d = dec(ds)
    if pat.len < 6usize || pat[0usize] != 100u8 {
        // `MMM/dd` has no year: the template's 2000-01-01 supplies it and the weekday is not read.
        if i64(got.date.month) != mo || i64(got.date.day) != d { ret 22u8 }
        ret 0u8
    }
    if pat[pat.len - 1usize] == 116u8 {
        // `yy`: 00-29 are 20xx and 30-99 are 19xx, the dates are 1930..2029; the pattern has no seconds.
        if !same_dt(got, year, mo, d, dec(hs), dec(mis), 0i64) { ret 23u8 }
        ret 0u8
    }
    if !same_dt(got, year, mo, d, dec(hs), dec(mis), dec(ss)) { ret 24u8 }
    ret 0u8
}
'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("time pattern locales ok")
    ret ok
}
'''

src = ('// e.time.pattern format_locale and parse_locale against Babel (CLDR) for 27 languages (D3601): F lines format a\n'
       '// date-time, P lines parse the same text back, E lines are refusals. Generated by\n'
       '// scripts/gen_time_pattern_locales_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.time\nuse e.time.calendar\nuse e.time.pattern as pattern_api\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
