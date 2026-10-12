#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/time_calendars_persian_uq/src/main.e (L150): the Persian (33-year arithmetic) and
Umm al-Qura calendars of e.time.calendars against convertdate.persian (1278..1502 AP, where the rule and the astronomical
calendar agree) and hijridate (1343..1500 AH).

    PYTHONPATH=<install dir of convertdate and hijridate> python scripts/gen_persian_uq_test.py
    python scripts/gen_persian_uq_test.py --table      # the hex table of lib/e/time/calendars.e
"""
import datetime
import random
import sys
import warnings
from pathlib import Path

warnings.simplefilter("ignore")
random.seed(1502)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "selfhost" / "fixtures" / "link" / "time_calendars_persian_uq" / "src" / "main.e"


def table():
    import hijridate.ummalqura as u
    ms = u.MONTH_STARTS
    out = ""
    for y in range(158):
        m = 0
        for k in range(12):
            i = y * 12 + k
            m = (m << 2) | (ms[i + 1] - ms[i] - 28)
        out += "%06x" % m
    return out


def unix_days_gregorian(y, m, d):
    return datetime.date(y, m, d).toordinal() - 719163


def num(day):
    return ("0i64 - %di64" % -day) if day < 0 else "%di64" % day


def main():
    if "--table" in sys.argv:
        print(table())
        return
    from convertdate import persian
    import hijridate.ummalqura as u
    from hijridate import Gregorian, Hijri

    cases = []  # (cal, days, y, m, d)
    # Persian: sampled days 1899..2321 CE, the end of each month in a few years, and the ends of years
    for _ in range(150):
        day = random.randint(unix_days_gregorian(1900, 1, 1), unix_days_gregorian(2120, 1, 1))
        y, m, d = persian.from_gregorian(*datetime.date.fromordinal(day + 719163).timetuple()[:3])
        cases.append(("Persian", day, y, m, d))
    for y in (1278, 1299, 1370, 1399, 1403, 1404, 1408, 1450, 1500):
        for m in (1, 6, 7, 11, 12):
            for d in (1, persian.month_length(y, m)):
                g = persian.to_gregorian(y, m, d)
                cases.append(("Persian", unix_days_gregorian(*g), y, m, d))
    # Umm al-Qura: sampled days over the whole table and the first and last day of it
    lo = unix_days_gregorian(1924, 8, 1)
    hi = unix_days_gregorian(2077, 11, 16)
    for _ in range(250):
        day = random.randint(lo, hi)
        g = datetime.date.fromordinal(day + 719163)
        h = Gregorian(g.year, g.month, g.day).to_hijri()
        cases.append(("UmmAlQura", day, h.year, h.month, h.day))
    for day in (lo, hi):
        g = datetime.date.fromordinal(day + 719163)
        h = Gregorian(g.year, g.month, g.day).to_hijri()
        cases.append(("UmmAlQura", day, h.year, h.month, h.day))
    lengths = []
    for y in (1343, 1344, 1350, 1389, 1400, 1445, 1446, 1500):
        for m in range(1, 13):
            lengths.append((y, m, u.MONTH_STARTS[(y - 1343) * 12 + m] - u.MONTH_STARTS[(y - 1343) * 12 + m - 1]))
    # the years of a 33-year cycle that are leap, and each year's length from the day count of its 1 Farvardin
    leap33 = [y for y in range(1403, 1403 + 33) if persian.leap(y)]

    out = ["// `e.time.calendars` Persian (33-year arithmetic) and Umm al-Qura against convertdate and hijridate\n",
           "// (scripts/gen_persian_uq_test.py): %d date/day-count pairs both ways, month lengths and leap years. Every check\n" % len(cases),
           "// has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.time\nuse e.time.calendars as calendars\n\n",
           "fn expect(cal: calendars.Calendar, days: i64, year: i32, month: u8, day: u8) -> bool {\n",
           "    let (date, e) = calendars.from_days(cal, days)\n",
           "    if e != ok || date.year != year || date.month != month || date.day != day { ret false }\n",
           "    let (back, be) = calendars.to_days(cal, date)\n",
           "    ret be == ok && back == days\n}\n\n",
           "fn len_is(cal: calendars.Calendar, year: i32, month: u8, want: u8) -> bool {\n",
           "    let (n, e) = calendars.days_in_month(cal, year, month)\n",
           "    ret e == ok && n == want\n}\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    n = 0

    def emit(cond):
        nonlocal n
        n += 1
        out.append("    if %s { os.exit(%d) }\n" % (cond, n))

    for cal, day, y, m, d in cases:
        emit("!expect(.%s, %s, %di32, %du8, %du8)" % (cal, num(day), y, m, d))
    for y, m, ln in lengths:
        emit("!len_is(.UmmAlQura, %di32, %du8, %du8)" % (y, m, ln))
    for m in range(1, 13):
        want = 31 if m <= 6 else 30
        emit("!len_is(.Persian, 1399i32, %du8, %du8)" % (m, want))
    emit("!len_is(.Persian, 1399i32, 12u8, 30u8)")
    emit("!len_is(.Persian, 1400i32, 12u8, 29u8)")
    for y in range(1403, 1403 + 33):
        emit("%scalendars.is_leap_year(.Persian, %di32)" % ("!" if y in leap33 else "", y))
    # the table's ends and refusals
    emit("calendars.year_ok(.UmmAlQura, 1342i32) || calendars.year_ok(.UmmAlQura, 1501i32) || !calendars.year_ok(.UmmAlQura, 1343i32) || !calendars.year_ok(.UmmAlQura, 1500i32)")
    out.append("    let (before, before_e) = calendars.from_days(.UmmAlQura, %s)\n" % num(lo - 1))
    emit("before_e == ok")
    out.append("    let (after, after_e) = calendars.from_days(.UmmAlQura, %s)\n" % num(hi + 1))
    emit("after_e == ok")
    out.append("    let (zero_year, zero_e) = calendars.days_in_month(.Persian, 0i32, 1u8)\n")
    emit("zero_e == ok")
    emit("!calendars.valid(.Persian, time.Date{ year: 1403i32, month: 12u8, day: 30u8 })")
    emit("calendars.valid(.Persian, time.Date{ year: 1404i32, month: 12u8, day: 30u8 })")
    out.append("    let (nowruz, nowruz_e) = calendars.from_iso(.Persian, time.Date{ year: 2024i32, month: 3u8, day: 20u8 })\n")
    emit("nowruz_e != ok || nowruz.year != 1403i32 || nowruz.month != 1u8 || nowruz.day != 1u8")
    out.append("    let (bumped, bumped_e) = calendars.add_months(.Persian, time.Date{ year: 1403i32, month: 6u8, day: 31u8 }, 1i64)\n")
    emit("bumped_e != ok || bumped.month != 7u8 || bumped.day != 30u8")
    out.append("    let (shifted, shifted_e) = calendars.convert(.Persian, .UmmAlQura, time.Date{ year: 1403i32, month: 1u8, day: 1u8 })\n")
    g = datetime.date(2024, 3, 20)
    h = Gregorian(g.year, g.month, g.day).to_hijri()
    emit("shifted_e != ok || shifted.year != %di32 || shifted.month != %du8 || shifted.day != %du8" % (h.year, h.month, h.day))
    out.append("    ret ok\n}\n")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote %d checks" % n)


main()
