#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/time_calendars_african/src/main.e (L150): the Coptic and Ethiopic calendars of
e.time.calendars against convertdate (coptic, ethiopian): the date of days spread over eighteen centuries and the
day count of dates, in both directions, month lengths and leap years.

    PYTHONPATH=<convertdate install dir> python scripts/gen_african_calendars_test.py
"""
import datetime
import random
import sys
from pathlib import Path

from convertdate import coptic


class Ethiopian:
    """convertdate has no Ethiopian module: its year n is the Coptic year n - 276, month and day the same."""

    @staticmethod
    def from_jd(jd):
        y, m, d = coptic.from_jd(jd)
        return (y + 276, m, d)

    @staticmethod
    def to_jd(y, m, d):
        return coptic.to_jd(y - 276, m, d)

    @staticmethod
    def month_length(y, m):
        return coptic.month_length(y - 276, m)


ethiopian = Ethiopian

random.seed(1501)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "selfhost" / "fixtures" / "link" / "time_calendars_african" / "src" / "main.e"


def unix_days(jd):
    return int(round(jd - 2440587.5))


def main():
    cases = []
    # Days since the Unix epoch from 400 CE to 2500 CE, with a fixed density plus the ends of Coptic years.
    for _ in range(260):
        day = random.randint(-575000, 300000)
        jd = day + 2440587.5
        cases.append(("Coptic", day, coptic.from_jd(jd)))
        cases.append(("Ethiopic", day, ethiopian.from_jd(jd)))
    # The five- and six-day month and the day after, in leap and common years.
    for year in (1738, 1739, 1740, 1741, 1742):
        for module, name in ((coptic, "Coptic"), (ethiopian, "Ethiopic")):
            last = module.month_length(year, 13)
            for d in (1, last):
                day = unix_days(module.to_jd(year, 13, d))
                cases.append((name, day, (year, 13, d)))
            nxt = unix_days(module.to_jd(year, 13, last)) + 1
            cases.append((name, nxt, module.from_jd(nxt + 2440587.5)))
    # The Thai Buddhist calendar: the Gregorian date with the year plus 543 (datetime is the reference).
    thai = []
    for _ in range(120):
        day = random.randint(-10000, 40000)
        d = datetime.date.fromordinal(day + 719163)
        thai.append((day, d.year + 543, d.month, d.day))
    lengths = []
    for module, name in ((coptic, "Coptic"), (ethiopian, "Ethiopic")):
        for year in range(1, 12):
            for month in (1, 6, 12, 13):
                lengths.append((name, year, month, module.month_length(year, month)))
    out = ["// `e.time.calendars` Coptic and Ethiopic against convertdate (scripts/gen_african_calendars_test.py): the date\n",
           "// of %d day counts, the count of each date back, month lengths and leap years. Every check has its own exit code.\n" % len(cases),
           "use e.os\nuse e.mem\nuse e.time\nuse e.time.calendars as calendars\n\n",
           "fn expect(cal: calendars.Calendar, days: i64, year: i32, month: u8, day: u8) -> bool {\n",
           "    let (date, e) = calendars.from_days(cal, days)\n",
           "    if e != ok || date.year != year || date.month != month || date.day != day { ret false }\n",
           "    let (back, be) = calendars.to_days(cal, date)\n",
           "    ret be == ok && back == days\n}\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    n = 0

    def check(cond):
        nonlocal n
        n += 1
        out.append("    if %s { os.exit(%d) }\n" % (cond, n))

    for name, day, (y, m, d) in cases:
        cal = ".%s" % name
        sign = "0i64 - " if day < 0 else ""
        out.append("    if !expect(%s, %s%di64, %di32, %du8, %du8) { os.exit(%d) }\n" % (cal, sign, abs(day), y, m, d, n + 1))
        n += 1
    for day, y, m, d in thai:
        sign = "0i64 - " if day < 0 else ""
        out.append("    if !expect(.ThaiBuddhist, %s%di64, %di32, %du8, %du8) { os.exit(%d) }\n" % (sign, abs(day), y, m, d, n + 1))
        n += 1
    out.append("    if !calendars.is_leap_year(.ThaiBuddhist, 2567i32) || calendars.is_leap_year(.ThaiBuddhist, 2566i32) || calendars.is_leap_year(.ThaiBuddhist, 2643i32) { os.exit(%d) }\n" % (n + 1))
    n += 1
    out.append("    let (feb, feb_e) = calendars.days_in_month(.ThaiBuddhist, 2567i32, 2u8)\n    if feb_e != ok || feb != 29u8 { os.exit(%d) }\n" % (n + 1))
    n += 1
    for name, year, month, length in lengths:
        cal = ".%s" % name
        out.append("    let (l%d, le%d) = calendars.days_in_month(%s, %di32, %du8)\n" % (n, n, cal, year, month))
        n += 1
        out.append("    if le%d != ok || l%d != %du8 { os.exit(%d) }\n" % (n - 1, n - 1, length, n))
    for name in ("Coptic", "Ethiopic"):
        out.append("    if !calendars.is_leap_year(.%s, 3i32) || !calendars.is_leap_year(.%s, 1739i32) || calendars.is_leap_year(.%s, 1740i32) { os.exit(%d) }\n" % (name, name, name, n + 1))
        n += 1
    # The epochs: Coptic year 1 month 1 day 1 is 284-08-29 Julian; Ethiopic is 8-08-29 Julian.
    out.append("    let (c1, ce1) = calendars.convert(.Coptic, .Julian, time.Date{ year: 1i32, month: 1u8, day: 1u8 })\n")
    out.append("    if ce1 != ok || c1.year != 284i32 || c1.month != 8u8 || c1.day != 29u8 { os.exit(%d) }\n" % (n + 1))
    n += 1
    out.append("    let (e1, ee1) = calendars.convert(.Ethiopic, .Julian, time.Date{ year: 1i32, month: 1u8, day: 1u8 })\n")
    out.append("    if ee1 != ok || e1.year != 8i32 || e1.month != 8u8 || e1.day != 29u8 { os.exit(%d) }\n" % (n + 1))
    n += 1
    out.append("    let (bad, bade) = calendars.days_in_month(.Coptic, 0i32, 1u8)\n    if bade == ok { os.exit(%d) }\n" % (n + 1))
    n += 1
    out.append("    ret ok\n}\n")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", OUT, "checks", n)


main()
