#!/usr/bin/env python3
"""Write neperos/src/zones_test.e (C146): the world clock's city rules (neperos/src/zones.e, POSIX TZ rules over
e.tz) against Python's zoneinfo: every city in January and July 2026, and for each city with daylight time the
second before and the second after each 2026 transition. Every check has its own exit code."""
import datetime as dt
from pathlib import Path
from zoneinfo import ZoneInfo

CITIES = [
    "UTC", "Europe/London", "Europe/Paris", "Africa/Cairo", "Europe/Moscow", "Asia/Dubai", "Asia/Kolkata",
    "Asia/Singapore", "Asia/Tokyo", "Australia/Sydney", "Pacific/Auckland", "Pacific/Honolulu",
    "America/Los_Angeles", "America/Chicago", "America/New_York", "America/Sao_Paulo",
]
UTC = dt.timezone.utc


def offset_minutes(zone, seconds):
    moment = dt.datetime.fromtimestamp(seconds, UTC).astimezone(ZoneInfo(zone))
    return int(moment.utcoffset().total_seconds() // 60)


def transitions(zone, year):
    start = int(dt.datetime(year, 1, 1, tzinfo=UTC).timestamp())
    end = int(dt.datetime(year + 1, 1, 1, tzinfo=UTC).timestamp())
    found = []
    previous = offset_minutes(zone, start)
    t = start
    while t < end:
        nxt = t + 3600
        now = offset_minutes(zone, nxt)
        if now != previous:
            lo, hi = t, nxt
            while hi - lo > 1:
                mid = (lo + hi) // 2
                if offset_minutes(zone, mid) == previous:
                    lo = mid
                else:
                    hi = mid
            found.append(hi)
            previous = now
        t = nxt
    return found


def main():
    checks = []
    for city, zone in enumerate(CITIES):
        for month in (1, 7):
            seconds = int(dt.datetime(2026, month, 15, 12, tzinfo=UTC).timestamp())
            checks.append((city, seconds, offset_minutes(zone, seconds)))
        for moment in transitions(zone, 2026):
            checks.append((city, moment - 1, offset_minutes(zone, moment - 1)))
            checks.append((city, moment, offset_minutes(zone, moment)))
    out = []
    out.append("// The world clock's city rules (neperos/src/zones.e) against Python's zoneinfo (written by\n")
    out.append("// scripts/gen_zones_test.py): every city in January and July 2026, and the second before and after each\n")
    out.append("// 2026 transition of the cities with daylight time. Every check has its own exit code.\n")
    out.append("use e.os\nuse e.mem\nuse zones\n\n")
    out.append("fn main(a: *mem.Arena, args: []str) -> err {\n")
    for number, (city, seconds, expected) in enumerate(checks, start=1):
        sign = "0i64 - " if expected < 0 else ""
        out.append("    if zones.offset_minutes(%dusize, %di64) != %s%di64 { os.exit(%d) }\n" % (city, seconds, sign, abs(expected), number))
    out.append("    ret ok\n}\n")
    dest = Path(__file__).resolve().parent.parent / "neperos" / "src" / "zones_test.e"
    dest.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", dest, "checks", len(checks))


main()
