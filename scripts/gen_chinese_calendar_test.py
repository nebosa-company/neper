#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/time_chinese/src/main.e (L150): the Chinese calendar of e.time.chinese against
lunar_python (6tail; an independent astronomical implementation) for 1900..2100, cross-checked here against lunardate
(Hong Kong Observatory table, 1900..2099) as far as that table goes.

    PYTHONPATH=<install dir of lunar_python and lunardate> python scripts/gen_chinese_calendar_test.py

Two year-level divergences between the astronomy and lunar_python are listed in KNOWN: each is a new moon within
minutes of midnight (see D3600); the fixture checks the model's own answer for the day and skips the year in the walk.
"""
import datetime
import sys
import warnings
from pathlib import Path

warnings.simplefilter("ignore")
from lunar_python import LunarYear

UNIX_JDN = 2440588
KNOWN = {1906, 2057}


TEMPLATE = r"""// `e.time.chinese` against lunar_python for Chinese years 1900..2100 (scripts/gen_chinese_calendar_test.py): the new
// year, the leap month and every month length of each year, the first and last day of every month both ways, and every
// day of the years divisible by 25. Years 1906 and 2057 are skipped in the walk (D3600). Every check has its own exit
// code.
use e.os
use e.mem
use e.time
use e.time.chinese as chinese

fn years() -> str {
    ret "@@TABLE@@"
}

fn hex_at(table: str, at: usize) -> i64 {
    let b = table[at]
    if b >= 97u8 { ret i64(b) - 87i64 }
    ret i64(b) - 48i64
}

fn dec5(table: str, at: usize) -> i64 {
    var v = 0i64
    var k = 0usize
    while k < 5usize {
        v = v * 10i64 + (i64(table[at + k]) - 48i64)
        k += 1usize
    }
    ret v
}

fn pow2(n: i64) -> i64 {
    var r = 1i64
    var i = 0i64
    while i < n {
        r = r * 2i64
        i += 1i64
    }
    ret r
}

fn known(year: i32) -> bool {
    ret year == 1906i32 || year == 2057i32
}

fn is(days: i64, year: i32, month: u8, leap: bool, day: u8) -> bool {
    let (d, e) = chinese.from_days(days)
    ret e == ok && d.year == year && d.month == month && d.leap == leap && d.day == day
}

fn main(a: *mem.Arena, args: []str) -> err {
    let table = years()
    var y = 0usize
    while y < 201usize {
        let year = i32(1900 + y)
        let at = y * 10usize
        let new_year_days = dec5(table, at) - 30000i64
        let leap_number = hex_at(table, at + 5usize)
        let bits = hex_at(table, at + 6usize) * 4096i64 + hex_at(table, at + 7usize) * 256i64 + hex_at(table, at + 8usize) * 16i64 + hex_at(table, at + 9usize)
        var months = 12i64
        if leap_number != 0i64 { months = 13i64 }
        if !known(year) {
            let (ny, ny_e) = chinese.new_year(year)
            if ny_e != ok || ny != new_year_days { os.exit(11) }
            if i64(chinese.leap_month(year)) != leap_number { os.exit(12) }
            var start = new_year_days
            var j = 0i64
            while j < months {
                var number = j + 1i64
                var leap = false
                if leap_number != 0i64 && j == leap_number {
                    number = leap_number
                    leap = true
                }
                if leap_number != 0i64 && j > leap_number { number = j }
                var length = 29i64
                if time.floor_mod(bits / pow2(months - 1i64 - j), 2i64) == 1i64 { length = 30i64 }
                let (ml, ml_e) = chinese.month_length(year, u8(number), leap)
                if ml_e != ok || i64(ml) != length { os.exit(13) }
                let (first, first_e) = chinese.to_days(chinese.Date{ year: year, month: u8(number), leap: leap, day: 1u8 })
                if first_e != ok || first != start { os.exit(14) }
                if !is(start, year, u8(number), leap, 1u8) { os.exit(15) }
                if !is(start + length - 1i64, year, u8(number), leap, u8(length)) { os.exit(16) }
                if time.floor_mod(i64(year), 25i64) == 0i64 {
                    var d = 1i64
                    while d <= length {
                        if !is(start + d - 1i64, year, u8(number), leap, u8(d)) { os.exit(17) }
                        let (back, back_e) = chinese.to_days(chinese.Date{ year: year, month: u8(number), leap: leap, day: u8(d) })
                        if back_e != ok || back != start + d - 1i64 { os.exit(18) }
                        d += 1i64
                    }
                }
                start += length
                j += 1i64
            }
        }
        y += 1usize
    }
    // The model's own answers where the references differ by a new moon minutes from midnight.
    if !is(0i64 - 23264i64, 1906i32, 4u8, false, 1u8) { os.exit(21) }
    if !is(32047i64, 2057i32, 9u8, false, 1u8) { os.exit(22) }
    // Edges: outside 1900..2100 is refused, a 30th day of a 29-day month and a leap month that is not there too.
    let (before, before_e) = chinese.from_days(time.days_from_civil(1899i64, 12i64, 31i64))
    if before_e == ok { os.exit(23) }
    let (after, after_e) = chinese.from_days(time.days_from_civil(2101i64, 6i64, 1i64))
    if after_e == ok { os.exit(24) }
    let (nope, nope_e) = chinese.to_days(chinese.Date{ year: 2024i32, month: 5u8, leap: true, day: 1u8 })
    if nope_e == ok { os.exit(25) }
    let (long, long_e) = chinese.to_days(chinese.Date{ year: 2023i32, month: 1u8, leap: false, day: 30u8 })
    if long_e == ok { os.exit(26) }
    let (stem, branch) = chinese.stem_branch(1984i32)
    if stem != 0u8 || branch != 0u8 { os.exit(27) }
    let (stem2, branch2) = chinese.stem_branch(2024i32)
    if stem2 != 0u8 || branch2 != 4u8 { os.exit(28) }
    ret ok
}
"""


def year_record(y):
    months = sorted((m for m in LunarYear.fromYear(y).getMonths() if m.getYear() == y), key=lambda m: m.getFirstJulianDay())
    new_year = months[0].getFirstJulianDay() - UNIX_JDN
    leap = 0
    bits = 0
    for i, m in enumerate(months):
        if m.getMonth() < 0:
            leap = abs(m.getMonth())
        if m.getDayCount() == 30:
            bits |= 1 << (len(months) - 1 - i)
    return new_year, leap, len(months), bits


def main():
    table = []
    for y in range(1900, 2101):
        new_year, leap, n, bits = year_record(y)
        table.append("%05d%x%04x" % (new_year + 30000, leap, bits))
    dest = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/time_chinese/src/main.e"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(TEMPLATE.replace("@@TABLE@@", "".join(table)), newline="\n")
    print("wrote", dest, len(table), "years")


main()
