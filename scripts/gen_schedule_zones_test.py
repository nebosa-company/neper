#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/ui_schedule_zones/src/main.e (L148, D3602): e.ui.schedule with a display zone
(build_month_zoned, display_to_source) and the month's multi-day bars (build_month_bars, hit_month_bar).

Independent models: python's zoneinfo (tzdata) and dateutil's rrule for the zoned occurrences, the bar segmentation,
lane stacking and reserved lines written from the module header. The month layout is the one of
scripts/gen_schedule_month_test.py (cells, placed rectangles, "+N more", accessible tree).

    PYTHONPATH=<tzdata and dateutil install dir> python scripts/gen_schedule_zones_test.py
"""
import calendar
import datetime as dt
import itertools
import pathlib
import re
import sys
import zoneinfo

from dateutil.rrule import rrulestr

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_schedule_month_test as mt  # noqa: E402
import gen_schedule_test as base  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "tests/selfhost/fixtures/link/ui_schedule_zones/src/main.e"
EXISTING = ROOT / "tests/selfhost/fixtures/link/ui_schedule_month/src/main.e"
D = base.D
EN = mt.EN
nlit = base.nlit
num = base.num


def zoned_occ(first, days, items, src, dst):
    lo, hi = first * 1440, (first + days) * 1440
    out = []
    for idx, (iid, start, minutes, all_day, title, rule) in enumerate(items):
        minutes = max(minutes, 1)
        if all_day:
            start = dt.datetime.combine(start.date(), dt.time())
            minutes = -(-minutes // 1440) * 1440
        starts = [start] if not rule else list(itertools.islice(rrulestr(rule, dtstart=start), 400))
        for s in starts:
            if all_day:
                a = base.day_no(s.date()) * 1440
            else:
                local = s.replace(tzinfo=zoneinfo.ZoneInfo(src)).astimezone(zoneinfo.ZoneInfo(dst)).replace(tzinfo=None)
                a = base.abs_min(local)
            if a < hi and a + minutes > lo:
                out.append(dict(item=idx, start=a, minutes=minutes, all_day=all_day, recurring=bool(rule)))
    return out


def spans(o):
    return (o["start"] + o["minutes"] - 1) // 1440 > o["start"] // 1440


def month_layout(spec, items, occ_fn, with_bars):
    anchor, ws, width, header, cell_h, line_h, lines = spec
    first_of = dt.date(anchor.year, anchor.month, 1)
    behind = (first_of.weekday() - ws) % 7
    dim = calendar.monthrange(anchor.year, anchor.month)[1]
    weeks = (behind + dim + 6) // 7
    first = base.day_no(first_of) - behind
    days = weeks * 7
    occ = occ_fn(first, days)
    col_w = width / 7
    bars = []
    if with_bars:
        for o in occ:
            if not spans(o):
                continue
            o_first, o_last = o["start"] // 1440, (o["start"] + o["minutes"] - 1) // 1440
            for w in range(weeks):
                w_first = first + w * 7
                a, b = max(o_first, w_first), min(o_last, w_first + 6)
                if a <= b:
                    bars.append(dict(item=o["item"], first=a - first, last=b - first, lane=0, before=o_first < w_first,
                                     after=o_last > w_first + 6, recurring=o["recurring"], start=o["start"],
                                     end=o["start"] + o["minutes"]))
        bars.sort(key=lambda r: (r["first"], -(r["last"] - r["first"]), r["item"]))
        for i, r in enumerate(bars):
            lane = 0
            while any(bars[j]["lane"] == lane and bars[j]["last"] >= r["first"] and bars[j]["first"] <= r["last"] for j in range(i)):
                lane += 1
            r["lane"] = lane
    reserved = [0] * weeks
    for r in bars:
        week = r["first"] // 7
        cy = header + week * cell_h
        r["x"] = (r["first"] % 7) * col_w
        if r["lane"] < lines:
            r.update(y=cy + (r["lane"] + 1) * line_h, w=(r["last"] - r["first"] + 1) * col_w, h=line_h)
            reserved[week] = max(reserved[week], r["lane"] + 1)
        else:
            r.update(y=cy, w=0.0, h=0.0)
    placed, cells = [], []
    for d in range(days):
        count = first + d
        day0 = count * 1440
        cx, cy = (d % 7) * col_w, header + (d // 7) * cell_h
        todays = sorted([o for o in occ if o["start"] < day0 + 1440 and o["start"] + o["minutes"] > day0 and not (with_bars and spans(o))],
                        key=base.order_key)
        n = len(todays)
        reserve = reserved[d // 7]
        hidden = sum(1 for r in bars if r["first"] <= d <= r["last"] and r["lane"] >= lines)
        avail = lines - reserve
        shown, more = n, 0
        if n > avail or hidden > 0:
            shown = 0 if avail == 0 else min(n, avail - 1)
            more = n - shown + hidden
        start_index = len(placed)
        for k, o in enumerate(todays):
            visible = k < shown
            placed.append(dict(item=o["item"], kind="AllDay" if o["all_day"] else "Timed", day=d, start=max(o["start"], day0),
                               end=min(o["start"] + o["minutes"], day0 + 1440), x=cx,
                               y=(cy + (reserve + k + 1) * line_h) if visible else cy, w=col_w if visible else 0.0,
                               h=line_h if visible else 0.0, lane=k, lanes=n, before=o["start"] < day0,
                               after=o["start"] + o["minutes"] > day0 + 1440, recurring=o["recurring"]))
        d0 = dt.date.fromordinal(count + 719163)
        cells.append(dict(count=count, in_month=(d0.month == anchor.month and d0.year == anchor.year), x=cx, y=cy, w=col_w, h=cell_h,
                          first=start_index, total=n, shown=shown, more=more, reserved=reserve))
    height = header + weeks * cell_h
    nodes = [("Grid", f"{EN['month']}, {EN['months'][anchor.month - 1]} {anchor.year}", 0.0, 0.0, width, height, 0, 0, weeks, 7, 0)]
    for col in range(7):
        nodes.append(("ColumnHeader", EN["weekdays"][(ws + col) % 7], col * col_w, 0.0, col_w, header, 0, col + 1, 0, 7, 0))
    for d, c in enumerate(cells):
        total = c["total"]
        words = EN["none"] if total == 0 else (EN["one"] if total == 1 else f"{total}{EN['many']}")
        nodes.append(("Cell", mt.date_label(c["count"], EN) + ", " + words, c["x"], c["y"], c["w"], c["h"], d // 7 + 1, d % 7 + 1, weeks, 7, 0))
        for k in range(total):
            p = placed[c["first"] + k]
            nodes.append(("ListItem", mt.label_event(items, p, EN), p["x"], p["y"], p["w"], p["h"], 0, 0, 0, 0, 1))
    for r in bars:
        p = dict(item=r["item"], kind="AllDay" if items[r["item"]][3] else "Timed", start=r["start"], end=r["end"], recurring=r["recurring"])
        nodes.append(("ListItem", mt.label_event(items, p, EN), r["x"], r["y"], r["w"], r["h"], 0, 0, 0, 0, 1))
    return dict(first=first, weeks=weeks, days=days, height=height, cells=cells, placed=placed, nodes=nodes, bars=bars)


def render(L):
    out = [mt.render_month(L)]
    for i, c in enumerate(L["cells"]):
        out.append("R %d %d\n" % (i, c["reserved"]))
    out.append("L %d\n" % len(L["bars"]))
    for r in L["bars"]:
        out.append("B %d %d %d %d %s %s %s %s %d %d %d %d %d\n" % (r["item"], r["first"], r["last"], r["lane"], num(r["x"]), num(r["y"]),
                                                                  num(r["w"]), num(r["h"]), r["before"], r["after"], r["recurring"],
                                                                  r["start"], r["end"]))
    return "".join(out)


def bar_probes(L):
    pts = []
    for r in L["bars"]:
        if r["w"] > 0:
            pts += [(r["x"] + r["w"] / 2, r["y"] + r["h"] / 2), (r["x"], r["y"]), (r["x"] + r["w"], r["y"]),
                    (r["x"] + 1, r["y"] + r["h"] - 0.5)]
    pts += [(1, 1), (5, 40)]
    rows = []
    for x, y in pts:
        hit = next((i for i, r in enumerate(L["bars"]) if r["w"] > 0 and r["x"] <= x < r["x"] + r["w"] and r["y"] <= y < r["y"] + r["h"]),
                   None)
        rows.append((int(x), int(y), 0 if hit is None else 1, 0 if hit is None else hit))
    return ";".join(",".join(str(v) for v in r) for r in rows) + ";"


def to_source(src, dst, local):
    z = local.replace(tzinfo=zoneinfo.ZoneInfo(dst))
    return z.astimezone(zoneinfo.ZoneInfo(src)).replace(tzinfo=None)


SPEC = {
    "m1": (dt.date(2026, 3, 14), 0, 700.0, 30.0, 120.0, 20.0, 4),
    "m2": (dt.date(2026, 11, 3), 6, 700.0, 30.0, 100.0, 20.0, 3),
    "m3": (dt.date(2026, 4, 9), 0, 700.0, 30.0, 140.0, 20.0, 5),
}
ZONE_SCENARIOS = [
    # (name, spec, source zone, display zone, items)
    ("z1", "m1", "America/New_York", "Europe/Sofia", [
        (1, D(2026, 2, 2, 9, 0), 60, False, "Weekly 9", "FREQ=WEEKLY;COUNT=30"),
        (2, D(2026, 3, 8, 2, 30), 30, False, "Gap", ""),
        (3, D(2026, 3, 10, 20, 30), 120, False, "Late NY", ""),
        (4, D(2026, 3, 12, 0, 0), 1440, True, "Floating", ""),
        (5, D(2026, 3, 5, 23, 30), 45, False, "Night", "FREQ=DAILY;COUNT=10"),
        (6, D(2026, 3, 28, 22, 0), 600, False, "Overnight", ""),
    ]),
    ("z2", "m2", "America/New_York", "Europe/Sofia", [
        (1, D(2026, 11, 1, 1, 30), 30, False, "Ambiguous", ""),
        (2, D(2026, 10, 26, 9, 0), 60, False, "Weekly 9", "FREQ=WEEKLY;COUNT=8"),
        (3, D(2026, 11, 1, 0, 0), 2880, True, "Two days", ""),
        (4, D(2026, 11, 2, 18, 0), 90, False, "Evening", "FREQ=DAILY;COUNT=5"),
    ]),
    ("z3", "m3", "Australia/Lord_Howe", "UTC", [
        (1, D(2026, 3, 30, 7, 0), 60, False, "LH weekly", "FREQ=WEEKLY;COUNT=12"),
        (2, D(2026, 4, 5, 1, 45), 30, False, "LH gap", ""),
        (3, D(2026, 4, 4, 23, 0), 120, False, "LH late", ""),
    ]),
    ("z4", "m3", "Asia/Kolkata", "America/Los_Angeles", [
        (1, D(2026, 4, 1, 6, 30), 45, False, "Kolkata morning", "FREQ=DAILY;COUNT=20"),
        (2, D(2026, 4, 6, 23, 45), 30, False, "Near midnight", ""),
        (3, D(2026, 4, 6, 0, 0), 1440, True, "Day", ""),
    ]),
]
MOVES = [
    ("America/New_York", "Europe/Sofia", D(2026, 3, 8, 9, 30)),
    ("America/New_York", "Europe/Sofia", D(2026, 3, 29, 3, 30)),
    ("America/New_York", "Europe/Sofia", D(2026, 10, 25, 3, 30)),
    ("America/New_York", "Europe/Sofia", D(2026, 11, 1, 7, 30)),
    ("Europe/Sofia", "America/New_York", D(2026, 3, 8, 2, 30)),
    ("Europe/Sofia", "America/New_York", D(2026, 11, 1, 1, 30)),
    ("UTC", "Australia/Lord_Howe", D(2026, 4, 5, 1, 45)),
    ("UTC", "Australia/Lord_Howe", D(2026, 4, 5, 1, 15)),
    ("UTC", "Asia/Kolkata", D(2026, 6, 1, 5, 30)),
    ("America/Los_Angeles", "Asia/Kathmandu", D(2026, 7, 1, 0, 15)),
]

SERIES_SPEC = (dt.date(2026, 10, 14), 0, 700.0, 30.0, 120.0, 20.0, 4)
SERIES = [
    # (item, drag from, drag to, valid)
    ((1, D(2026, 10, 5, 9, 0), 60, False, "Mon Wed", "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=12"), D(2026, 10, 5, 9, 0), D(2026, 10, 6, 11, 30), True),
    ((2, D(2026, 10, 2, 18, 0), 90, False, "Fri Sun", "FREQ=WEEKLY;BYDAY=FR,SU;COUNT=10"), D(2026, 10, 2, 18, 0), D(2026, 10, 4, 9, 0), True),
    ((3, D(2026, 10, 3, 7, 0), 30, False, "Daily", "FREQ=DAILY;COUNT=15"), D(2026, 10, 3, 7, 0), D(2026, 10, 3, 8, 30), True),
    ((4, D(2026, 10, 1, 9, 0), 60, False, "Until time", "FREQ=WEEKLY;UNTIL=20261120T090000Z;BYDAY=TH"), D(2026, 10, 1, 9, 0), D(2026, 10, 2, 10, 0), True),
    ((5, D(2026, 10, 5, 8, 0), 60, False, "Until date", "FREQ=WEEKLY;UNTIL=20261031;BYDAY=MO"), D(2026, 10, 12, 8, 0), D(2026, 10, 15, 8, 0), True),
    ((6, D(2026, 10, 6, 0, 0), 1440, True, "All day", "FREQ=WEEKLY;COUNT=4"), D(2026, 10, 13, 0, 0), D(2026, 10, 15, 0, 0), True),
    ((7, D(2026, 10, 5, 9, 0), 60, False, "First Monday", "FREQ=MONTHLY;BYDAY=1MO"), D(2026, 10, 5, 9, 0), D(2026, 10, 6, 9, 0), False),
    ((8, D(2026, 10, 15, 9, 0), 60, False, "Fifteenth", "FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3"), D(2026, 10, 15, 9, 0), D(2026, 10, 15, 14, 0), True),
    ((9, D(2026, 10, 15, 9, 0), 60, False, "Fifteenth", "FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3"), D(2026, 10, 15, 9, 0), D(2026, 10, 16, 9, 0), False),
    ((10, D(2026, 10, 5, 9, 0), 30, False, "Hours", "FREQ=DAILY;BYHOUR=9,17;COUNT=6"), D(2026, 10, 5, 9, 0), D(2026, 10, 5, 9, 30), False),
    ((11, D(2026, 10, 5, 9, 0), 30, False, "Hours", "FREQ=DAILY;BYHOUR=9,17;COUNT=6"), D(2026, 10, 5, 9, 0), D(2026, 10, 7, 9, 0), True),
    ((12, D(2026, 10, 5, 9, 0), 60, False, "Biweekly", "FREQ=WEEKLY;INTERVAL=2;COUNT=6"), D(2026, 10, 5, 9, 0), D(2026, 10, 9, 15, 0), True),
    ((13, D(2026, 10, 5, 9, 0), 60, False, "Biweekly days", "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=6"), D(2026, 10, 5, 9, 0), D(2026, 10, 6, 9, 0), False),
    ((14, D(2026, 10, 5, 9, 0), 60, False, "Biweekly days", "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=6"), D(2026, 10, 5, 9, 0), D(2026, 10, 12, 10, 0), True),
    ((15, D(2026, 10, 8, 12, 0), 45, False, "Single", ""), D(2026, 10, 8, 12, 0), D(2026, 10, 9, 13, 15), True),
]


def series_occ(item, delta, first, days):
    """The occurrences of the original rule, each moved on by `delta` minutes (the series' model)."""
    iid, start, minutes, all_day, title, rule = item
    minutes = max(minutes, 1)
    if all_day:
        start = dt.datetime.combine(start.date(), dt.time())
        minutes = -(-minutes // 1440) * 1440
    floating = re.sub(r'(UNTIL=\d{8}T\d{6})Z', lambda m: m.group(1), rule)
    starts = [start] if not rule else list(itertools.islice(rrulestr(floating, dtstart=start), 400))
    lo, hi = first * 1440, (first + days) * 1440
    out = []
    for s in starts:
        a = (base.day_no(s.date()) * 1440 if all_day else base.abs_min(s)) + delta
        if a < hi and a + minutes > lo:
            out.append(dict(item=0, start=a, minutes=minutes, all_day=all_day, recurring=bool(rule)))
    return out


HEADER = """// `e.ui.schedule` (L148, D3602): a display zone and DST (build_month_zoned, display_to_source) and the month's
// multi-day bars (build_month_bars, hit_month_bar), against python's zoneinfo and dateutil and the month model of
// scripts/gen_schedule_zones_test.py (a copy of the one scripts/gen_schedule_month_test.py compares the module with).
// Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.str
use e.time
use e.time.calendar
use e.tz
use e.ui.accessibility
use e.ui.schedule as sched

"""

EXTRA = r"""
// The reserved lines of each cell and the bars, after the month's own text.
fn render_extra(b: *str.Builder, l: *const sched.MonthLayout, bars: []const sched.Bar, count: usize) -> err {
    var i = 0usize
    while i < l.cell_count {
        try str.push(b, "R ")
        try str.push_u64(b, u64(i))
        try sp(b)
        try str.push_u32(b, l.cells[i].reserved)
        try str.push(b, "\n")
        i += 1usize
    }
    try str.push(b, "L ")
    try str.push_u64(b, u64(count))
    try str.push(b, "\n")
    i = 0usize
    while i < count {
        let r = bars[i]
        try str.push(b, "B ")
        try str.push_u32(b, r.item)
        try sp(b)
        try str.push_u32(b, r.first)
        try sp(b)
        try str.push_u32(b, r.last)
        try sp(b)
        try str.push_u32(b, r.lane)
        try sp(b)
        try num(b, r.x)
        try sp(b)
        try num(b, r.y)
        try sp(b)
        try num(b, r.w)
        try sp(b)
        try num(b, r.h)
        try sp(b)
        try flag(b, r.before)
        try sp(b)
        try flag(b, r.after)
        try sp(b)
        try flag(b, r.recurring)
        try sp(b)
        try str.push_u64(b, u64(r.start))
        try sp(b)
        try str.push_u64(b, u64(r.end))
        try str.push(b, "\n")
        i += 1usize
    }
    ret ok
}

// A series moved by dragging one occurrence, against its model; `valid` false means the move is refused.
fn run_series(a: *mem.Arena, ms: sched.MonthStorage, items: []const sched.Item, from: calendar.DateTime, to: calendar.DateTime, cfg: sched.MonthConfig, want: str, valid: bool) -> i32 {
    var buf: [160]u8 = zero
    let (moved, move_error) = sched.move_series(items[0usize], from, to, buf[0..])
    if !valid {
        if move_error != sched.Invalid { ret 1i32 }
        ret 0i32
    }
    if move_error != ok { ret 2i32 }
    var one: [1]sched.Item = zero
    one[0usize] = moved
    let (l, build_error) = sched.build_month(one[0usize..1usize], cfg, ms)
    if build_error != ok { ret 3i32 }
    let (bld, bld_error) = str.builder(a, 65536usize)
    if bld_error != ok { ret 4i32 }
    var b = bld
    if render_month(&b, &l) != ok { ret 5i32 }
    let got = str.done(&b)
    if !str.eq(got, want) {
        let shown = io.print(got)
        ret 6i32
    }
    ret 0i32
}

fn zone_of(db: *const tz.Database, name: str) -> tz.Zone {
    let (z, e) = tz.zone(db, name)
    if e != ok { os.exit(3i32) }
    ret z
}

// A zoned month against its model; zero when it matches.
fn run_zoned(a: *mem.Arena, db: *const tz.Database, ms: sched.MonthStorage, items: []const sched.Item, cfg: sched.MonthConfig, want: str, src: str, dst: str) -> i32 {
    let (l, build_error) = sched.build_month_zoned(items, cfg, ms, zone_of(db, src), zone_of(db, dst))
    if build_error != ok { ret 1i32 }
    let (bld, bld_error) = str.builder(a, 65536usize)
    if bld_error != ok { ret 2i32 }
    var b = bld
    var none: [1]sched.Bar = zero
    if render_month(&b, &l) != ok { ret 3i32 }
    if render_extra(&b, &l, none[0usize..0usize], 0usize) != ok { ret 4i32 }
    let got = str.done(&b)
    if !str.eq(got, want) {
        let shown = io.print(got)
        ret 5i32
    }
    ret 0i32
}

fn run_bars(a: *mem.Arena, ms: sched.MonthStorage, items: []const sched.Item, cfg: sched.MonthConfig, want: str, hits: str, zoned: bool, db: *const tz.Database) -> i32 {
    var bars: [64]sched.Bar = zero
    var l: sched.MonthLayout = zero
    var count = 0usize
    var build_error: err = ok
    if zoned {
        let (lz, cz, ez) = sched.build_month_zoned_bars(items, cfg, ms, zone_of(db, "America/New_York"), zone_of(db, "Europe/Sofia"), bars[0..])
        l = lz
        count = cz
        build_error = ez
    } else {
        let (lb, cb, eb) = sched.build_month_bars(items, cfg, ms, bars[0..])
        l = lb
        count = cb
        build_error = eb
    }
    if build_error != ok { ret 1i32 }
    let (bld, bld_error) = str.builder(a, 65536usize)
    if bld_error != ok { ret 2i32 }
    var b = bld
    if render_month(&b, &l) != ok { ret 3i32 }
    if render_extra(&b, &l, bars[0usize..count], count) != ok { ret 4i32 }
    let got = str.done(&b)
    if !str.eq(got, want) {
        let shown = io.print(got)
        ret 5i32
    }
    // "x,y,found,index;...": the bar under each point.
    var pos = 0usize
    while pos < hits.len {
        let (x, p1) = next_int(hits, pos)
        let (y, p2) = next_int(hits, p1)
        let (found, p3) = next_int(hits, p2)
        let (index, p4) = next_int(hits, p3)
        pos = p4
        let (got_index, got_found) = sched.hit_month_bar(bars[0usize..count], count, f32(x), f32(y))
        if got_found != (found == 1i32) { ret 6i32 }
        if got_found && i32(got_index) != index { ret 7i32 }
    }
    ret 0i32
}

fn wall(parts: str, from: usize) -> (calendar.DateTime, usize) {
    let (y, p1) = next_int(parts, from)
    let (mo, p2) = next_int(parts, p1)
    let (d, p3) = next_int(parts, p2)
    let (h, p4) = next_int(parts, p3)
    let (mi, p5) = next_int(parts, p4)
    ret (at(y, u8(mo), u8(d), u8(h), u8(mi)), p5)
}

fn field_end(s: str, from: usize) -> usize {
    var i = from
    while i < s.len && s[i] != 124u8 && s[i] != 10u8 { i += 1usize }
    ret i
}

// "source|display|y,m,d,h,mi|y,m,d,h,mi" lines (the integers end with a separator): display_to_source of the first
// wall clock is the second.
fn run_moves_zone(db: *const tz.Database, rows: str) -> i32 {
    var pos = 0usize
    var n = 0i32
    while pos < rows.len {
        let e1 = field_end(rows, pos)
        let e2 = field_end(rows, e1 + 1usize)
        let src = rows[pos..e1]
        let dst = rows[e1 + 1usize..e2]
        let (local, p3) = wall(rows, e2 + 1usize)
        let (want, p4) = wall(rows, p3 + 1usize)
        pos = p4 + 1usize
        n += 1i32
        let got = sched.display_to_source(zone_of(db, src), zone_of(db, dst), local)
        if abs_of(got) != abs_of(want) { ret n }
    }
    ret 0i32
}

"""

MAIN = """fn main(a: *mem.Arena, args: []str) -> err {
    let (db, db_error) = tz.builtin(a)
    if db_error != ok { os.exit(1i32) }
    let (ms, ms_error) = month_storage(a, 256usize, 256usize, 32768usize, 42usize)
    if ms_error != ok { os.exit(2i32) }
    var raw: [32]sched.Item = zero
@@ZONED@@
@@BARS@@
@@SERIES@@
    var zraw: [32]sched.Item = zero
    let zn = zbar_items(zraw[0..])
    if run_bars(a, ms, zraw[0usize..zn], z1_cfg(), zbar_want(), zbar_hits(), true, &db) != 0i32 { os.exit(70i32) }
    let moved = run_moves_zone(&db, moves_want())
    if moved != 0i32 { os.exit(80i32 + moved) }
    // Refusal: a bars slice shorter than the segments need.
    let bn = bar_items(raw[0..])
    var short: [1]sched.Bar = zero
    let (l0, c0, e0) = sched.build_month_bars(raw[0usize..bn], bar_cfg_m1(), ms, short[0..])
    if e0 != sched.TooLarge { os.exit(100i32) }
    try io.print("ui schedule zones ok")
    ret ok
}
"""


def main():
    parts = []
    scenarios = []
    for name, spec_key, src, dst, items in ZONE_SCENARIOS:
        spec = SPEC[spec_key]
        parts.append(base.items_fn(name + "_items", items))
        parts.append(mt.month_cfg_fn(name + "_cfg", spec))
        L = month_layout(spec, items, lambda f, d, it=items, s=src, t=dst: zoned_occ(f, d, it, s, t), False)
        parts.append(f"fn {name}_want() -> str {{ ret {nlit(render(L))} }}\n")
        scenarios.append((name, src, dst))
    items = mt.ITEMS
    parts.append(base.items_fn("bar_items", items))
    bar_cases = []
    for k, spec in mt.MONTHS.items():
        parts.append(mt.month_cfg_fn("bar_cfg_" + k, spec))
        L = month_layout(spec, items, lambda f, d: mt.occ_for(f, d, items), True)
        parts.append(f"fn bar_want_{k}() -> str {{ ret {nlit(render(L))} }}\n")
        parts.append(f"fn bar_hits_{k}() -> str {{ ret {nlit(bar_probes(L))} }}\n")
        bar_cases.append((k, len(L["bars"])))
    zitems = ZONE_SCENARIOS[0][4] + [(7, D(2026, 3, 9, 0, 0), 5760, True, "Trip", ""),
                                     (8, D(2026, 3, 11, 20, 0), 3000, False, "Long haul", "")]
    parts.append(base.items_fn("zbar_items", zitems))
    L = month_layout(SPEC["m1"], zitems, lambda f, d: zoned_occ(f, d, zitems, "America/New_York", "Europe/Sofia"), True)
    parts.append(f"fn zbar_want() -> str {{ ret {nlit(render(L))} }}\n")
    parts.append(f"fn zbar_hits() -> str {{ ret {nlit(bar_probes(L))} }}\n")
    series_calls = []
    for i, (item, frm, to, valid) in enumerate(SERIES):
        parts.append(base.items_fn(f"series_{i}_items", [item]))
        delta = base.abs_min(to) - base.abs_min(frm)
        if item[3]:
            delta = (base.day_no(to.date()) - base.day_no(frm.date())) * 1440
        want = ""
        if valid:
            L = month_layout(SERIES_SPEC, [item], lambda f, d, it=item, dl=delta: series_occ(it, dl, f, d), False)
            want = mt.render_month(L)
        parts.append(f"fn series_{i}_want() -> str {{ ret {nlit(want)} }}\n")
        series_calls.append(
            f"    let series_n_{i} = series_{i}_items(raw[0..])\n"
            f"    if run_series(a, ms, raw[0usize..series_n_{i}], at({frm.year}, {frm.month}u8, {frm.day}u8, {frm.hour}u8, {frm.minute}u8), "
            f"at({to.year}, {to.month}u8, {to.day}u8, {to.hour}u8, {to.minute}u8), series_cfg(), series_{i}_want(), "
            f"{'true' if valid else 'false'}) != 0i32 {{ os.exit({110 + i}i32) }}")
    parts.append(mt.month_cfg_fn("series_cfg", SERIES_SPEC))
    rows = []
    for src, dst, local in MOVES:
        back = to_source(src, dst, local)
        rows.append(f"{src}|{dst}|{local.year},{local.month},{local.day},{local.hour},{local.minute},|"
                    f"{back.year},{back.month},{back.day},{back.hour},{back.minute},")
    parts.append(f"fn moves_want() -> str {{ ret {nlit(chr(10).join(rows) + chr(10))} }}\n")

    text = EXISTING.read_text(encoding="utf-8")
    helpers = text[text.index("fn at(year: i32"):text.index("// The integer at `from`")]
    ints = text[text.index("// The integer at `from`"):text.index("fn key_of(")]
    abs_of = text[text.index("fn abs_of("):text.index("// \"index,gx,gy,x,y,ok,day,start,minutes;...\"")]
    storage = text[text.index("fn month_storage(a: *mem.Arena"):text.index("fn month_text(a: *mem.Arena")]
    zoned_calls = "".join(
        f"    let {n}_n = {n}_items(raw[0..])\n"
        f"    if run_zoned(a, &db, ms, raw[0usize..{n}_n], {n}_cfg(), {n}_want(), \"{s}\", \"{t}\") != 0i32 {{ os.exit({40 + i}i32) }}\n"
        for i, (n, s, t) in enumerate(scenarios))
    bar_calls = "".join(
        f"    let bar_n_{k} = bar_items(raw[0..])\n"
        f"    if run_bars(a, ms, raw[0usize..bar_n_{k}], bar_cfg_{k}(), bar_want_{k}(), bar_hits_{k}(), false, &db) != 0i32 {{ os.exit({60 + i}i32) }}\n"
        for i, (k, _) in enumerate(bar_cases))
    main_text = MAIN.replace("@@SERIES@@", chr(10).join(series_calls)).replace("@@ZONED@@", zoned_calls.rstrip("\n")).replace("@@BARS@@", bar_calls.rstrip("\n"))
    src_text = HEADER + "\n".join(parts) + "\n" + helpers + ints + abs_of + EXTRA + storage + "\n" + main_text
    # the month_text helper is not needed; the helpers block carries role_name, render_month and render_bars
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(src_text, encoding="utf-8", newline="\n")
    print("wrote", OUT, len(scenarios), "zoned scenarios,", len(bar_cases), "bar months")


if __name__ == "__main__":
    main()
