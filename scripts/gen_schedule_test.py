"""Reference layouts for tests/selfhost/fixtures/link/ui_schedule (L148, D2882).

An independent model of lib/e/ui/schedule.e's documented behaviour: python's datetime for
the calendar and python-dateutil's rrule for recurrence (not e.time.recur), the overlap
columns and clipping written again from the module header, and the same hit and drag
rules. Writes item tables, expected renderings and probe tables between BEGIN SCENARIOS
and END SCENARIOS of the fixture's main.e.

    python scripts/gen_schedule_test.py
"""
import datetime as dt
import math
import pathlib

from dateutil.rrule import rrulestr

MAIN = pathlib.Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/ui_schedule/src/main.e"
EPOCH = dt.date(1970, 1, 1)
WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]


def D(y, m, d, h=0, mi=0):
    return dt.datetime(y, m, d, h, mi)


# (id, start, minutes, all_day, title, rule)
ITEMS = [
    (1, D(2026, 10, 12, 9, 0), 30, False, "Standup", "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=10"),
    (2, D(2026, 10, 13, 10, 0), 90, False, "Design review", ""),
    (3, D(2026, 10, 13, 10, 30), 60, False, "Lunch", ""),
    (4, D(2026, 10, 13, 11, 0), 30, False, "Call", ""),
    (5, D(2026, 10, 14, 13, 0), 180, False, "Workshop", ""),
    (6, D(2026, 10, 14, 6, 0), 60, False, "Early", ""),
    (7, D(2026, 10, 15, 19, 0), 360, False, "Overnight", ""),
    (8, D(2026, 10, 14, 0, 0), 2880, True, "Conference", ""),
    (9, D(2026, 10, 16, 0, 0), 1440, True, "Holiday", ""),
    (10, D(2026, 10, 7, 15, 0), 60, False, "Weekly sync", "FREQ=WEEKLY;INTERVAL=1;COUNT=4"),
    (11, D(2026, 7, 15, 10, 0), 60, False, "Monthly", "FREQ=MONTHLY;BYMONTHDAY=15"),
    (12, D(2026, 10, 16, 9, 0), 60, False, "Chain A", ""),
    (13, D(2026, 10, 16, 9, 30), 60, False, "Chain B", ""),
    (14, D(2026, 10, 16, 10, 15), 45, False, "Chain C", ""),
    (15, D(2026, 10, 16, 9, 0), 120, False, "Chain D", ""),
    (16, D(2026, 10, 17, 12, 0), 0, False, "Zero length", ""),
    (17, D(2026, 10, 12, 0, 0), 1440, True, "Standing", "FREQ=WEEKLY;COUNT=3"),
]

BASE = dict(day_start=8, day_end=20, slot=30, agenda_days=10, width=900.0, gutter=60.0, header=30.0, all_day_h=20.0, hour_h=60.0, row_h=24.0, min_h=12.0)
CONFIGS = {
    "w1": dict(BASE, mode="Week", anchor=dt.date(2026, 10, 14), week_start=0),
    "w2": dict(BASE, mode="Week", anchor=dt.date(2026, 10, 14), week_start=6),
    "d1": dict(BASE, mode="Day", anchor=dt.date(2026, 10, 16), week_start=0),
    "a1": dict(BASE, mode="Agenda", anchor=dt.date(2026, 10, 12), week_start=0),
}
MODE_CODE = {"Day": 0, "Week": 1, "Agenda": 2}


def day_no(d):
    return (d - EPOCH).days


def abs_min(t):
    return day_no(t.date()) * 1440 + t.hour * 60 + t.minute


def date_label(n):
    d = EPOCH + dt.timedelta(days=n)
    return f"{WEEKDAYS[d.weekday()]} {d.day} {MONTHS[d.month - 1]} {d.year}"


def clock(a):
    m = a % 1440
    return f"{m // 60:02d}:{m % 60:02d}"


def occurrences(item, first, days):
    iid, start, minutes, all_day, title, rule = item
    minutes = max(minutes, 1)
    if all_day:
        start = dt.datetime.combine(start.date(), dt.time())
        minutes = -(-minutes // 1440) * 1440
    lo, hi = first * 1440, (first + days) * 1440
    out = []
    if not rule:
        starts = [start]
    else:
        back = -(-minutes // 1440)
        floor = max(dt.datetime.combine(EPOCH + dt.timedelta(days=first - back), dt.time()), start)
        rr = rrulestr(rule, dtstart=start)
        starts = []
        for s in rr:
            if s < floor:
                continue
            if abs_min(s) >= hi:
                break
            starts.append(s)
    for s in starts:
        a = abs_min(s) if not all_day else day_no(s.date()) * 1440
        if a < hi and a + minutes > lo:
            out.append({"item": iid, "title": title, "start": a, "minutes": minutes, "all_day": all_day, "recurring": bool(rule)})
    return out


def order_key(o):
    return (not o["all_day"], o["start"], -o["minutes"], o["item"])


def layout(cfg, items=ITEMS):
    mode = cfg["mode"]
    anchor = day_no(cfg["anchor"])
    if mode == "Day":
        first, days = anchor, 1
    elif mode == "Week":
        first, days = anchor - ((((anchor + 3) % 7) - cfg["week_start"]) % 7), 7
    else:
        first, days = anchor, cfg["agenda_days"]
    # item indexes are positions in the list, as in the module
    occ = []
    for idx, it in enumerate(items):
        for o in occurrences(it, first, days):
            o["item"] = idx
            occ.append(o)
    L = dict(placed=[], rows=[], nodes=[], first=first, days=days, band=0.0, height=0.0)
    ds, de, hh = cfg["day_start"], cfg["day_end"], cfg["hour_h"]

    def label_event(p):
        o = items[p["item"]]
        s = o[4]
        if p["kind"] == "AllDay":
            s += ", all day"
        else:
            s += ", " + clock(p["start"]) + " to " + clock(p["end"])
        if p["recurring"]:
            s += ", repeats"
        return s

    if mode == "Agenda":
        y = 0.0
        L["nodes"].append(["List", "Agenda", 0.0, 0.0, cfg["width"], 0.0, 0, 0, 0, 1, 0])
        total = 0
        for d in range(days):
            day0 = (first + d) * 1440
            todays = sorted([o for o in occ if o["start"] < day0 + 1440 and o["start"] + o["minutes"] > day0], key=order_key)
            if not todays:
                continue
            L["rows"].append(("H", d, 0, y, cfg["row_h"]))
            L["nodes"].append(["Heading", date_label(first + d), 0.0, y, cfg["width"], cfg["row_h"], 0, 0, 0, 1, 2])
            y += cfg["row_h"]
            for o in todays:
                p = dict(item=o["item"], kind="AllDay" if o["all_day"] else "Timed", day=d, start=max(o["start"], day0),
                         end=min(o["start"] + o["minutes"], day0 + 1440), x=0.0, y=y, w=cfg["width"], h=cfg["row_h"], lane=0, lanes=1,
                         before=o["start"] < day0, after=o["start"] + o["minutes"] > day0 + 1440, recurring=o["recurring"])
                L["placed"].append(p)
                L["rows"].append(("E", d, len(L["placed"]) - 1, y, cfg["row_h"]))
                L["nodes"].append(["ListItem", label_event(p), 0.0, y, cfg["width"], cfg["row_h"], 0, 0, 0, 1, 0])
                total += 1
                y += cfg["row_h"]
        L["nodes"][0][6] = 0
        L["nodes"][0][5] = y
        L["nodes"][0][8] = total
        L["height"] = y
        return L
    col_w = (cfg["width"] - cfg["gutter"]) / days
    cols = [dict(count=first + d, x=cfg["gutter"] + d * col_w, w=col_w) for d in range(days)]
    L["cols"] = cols
    band_rows = 0
    for c in cols:
        n = sum(1 for o in occ if o["all_day"] and o["start"] < c["count"] * 1440 + 1440 and o["start"] + o["minutes"] > c["count"] * 1440)
        band_rows = max(band_rows, n)
    band = band_rows * cfg["all_day_h"]
    top = cfg["header"] + band
    for d, c in enumerate(cols):
        day0 = c["count"] * 1440
        w0, w1 = day0 + ds * 60, day0 + de * 60
        todays = sorted([o for o in occ if o["start"] < day0 + 1440 and o["start"] + o["minutes"] > day0], key=order_key)
        row = 0
        for o in todays:
            if o["all_day"]:
                L["placed"].append(dict(item=o["item"], kind="AllDay", day=d, start=o["start"], end=o["start"] + o["minutes"], x=c["x"], y=cfg["header"] + row * cfg["all_day_h"],
                                        w=c["w"], h=cfg["all_day_h"], lane=0, lanes=1, before=o["start"] < day0, after=o["start"] + o["minutes"] > day0 + 1440, recurring=o["recurring"]))
                row += 1
        # timed: clip, cluster by transitive overlap, first free lane
        segs = []
        for o in todays:
            if o["all_day"]:
                continue
            s, e = max(o["start"], w0), min(o["start"] + o["minutes"], w1)
            if s < e:
                segs.append((s, e, o))
        clusters, cur, cur_end = [], [], None
        for seg in segs:
            if cur and seg[0] < cur_end:
                cur.append(seg)
                cur_end = max(cur_end, seg[1])
            else:
                if cur:
                    clusters.append(cur)
                cur, cur_end = [seg], seg[1]
        if cur:
            clusters.append(cur)
        for cl in clusters:
            lane_end, assigned = [], []
            for (s, e, o) in cl:
                lane = next((i for i, le in enumerate(lane_end) if le <= s), None)
                if lane is None:
                    lane_end.append(e)
                    lane = len(lane_end) - 1
                else:
                    lane_end[lane] = e
                assigned.append(lane)
            n = len(lane_end)
            for (s, e, o), lane in zip(cl, assigned):
                h = max((e - s) * hh / 60.0, cfg["min_h"])
                L["placed"].append(dict(item=o["item"], kind="Timed", day=d, start=s, end=e, x=c["x"] + lane * (c["w"] / n), y=top + (s - w0) * hh / 60.0,
                                        w=c["w"] / n, h=h, lane=lane, lanes=n, before=o["start"] < day0, after=o["start"] + o["minutes"] > day0 + 1440, recurring=o["recurring"]))
    grid_h = top + (de - ds) * hh
    L["band"], L["top"], L["height"] = band, top, grid_h
    L["nodes"].append(["Grid", "Day schedule" if mode == "Day" else "Week schedule", 0.0, 0.0, cfg["width"], grid_h, 0, 0, len(L["placed"]), days, 0])
    for d, c in enumerate(cols):
        L["nodes"].append(["ColumnHeader", date_label(c["count"]), c["x"], 0.0, c["w"], cfg["header"], 0, d + 1, 0, days, 0])
        mine = [p for p in L["placed"] if p["day"] == d]
        for k, p in enumerate(mine):
            L["nodes"].append(["Cell", label_event(p), p["x"], p["y"], p["w"], p["h"], k + 1, d + 1, len(mine), days, 0])
    return L


def num(v):
    assert float(v).is_integer(), v
    return str(int(v))


def render(cfg, L):
    out = [f"M {L['first']} {L['days']} {num(L['band'])} {num(cfg['header'] + L['band'])} {num(L['height'])}\n"]
    for p in L["placed"]:
        out.append("P %d %s %d %d %d %s %s %s %s %d %d %d %d %d\n" % (p["item"], p["kind"][0], p["day"], p["start"], p["end"], num(p["x"]), num(p["y"]), num(p["w"]), num(p["h"]),
                                                                    p["lane"], p["lanes"], p["before"], p["after"], p["recurring"]))
    for (k, d, pl, y, h) in L["rows"]:
        out.append(f"R {k} {d} {pl} {num(y)} {num(h)}\n")
    for n in L["nodes"]:
        out.append("N %s %s %s %s %s %s %d %d %d %d %d\n" % (n[0], num(n[2]), num(n[3]), num(n[4]), num(n[5]), n[1], n[6], n[7], n[8], n[9], n[10]))
    return "".join(out)


KIND = {"none": 0, "event": 1, "allday": 2, "slot": 3, "header": 4, "gutter": 5}


def probes(cfg, L):
    """(x, y) -> (kind, a, b): the module's hit rules."""
    pts = []
    for p in L["placed"]:
        pts.append((p["x"] + 1.0, p["y"] + 1.0))
    if cfg["mode"] != "Agenda":
        pts += [(10.0, 100.0), (70.0, 10.0), (200.0, 10.0), (cfg["gutter"] + 5.0, L["top"] + 5.0), (cfg["gutter"] + 125.0, L["top"] + 333.0),
                (cfg["width"] + 5.0, 50.0), (30.0, L["top"] + 50.0), (cfg["gutter"] + 5.0, L["height"] + 10.0), (300.0, L["top"] + 719.0)]
    else:
        pts += [(5.0, 3.0), (5.0, L["height"] + 4.0)]
    out = []
    for (x, y) in pts:
        out.append((x, y) + hit(cfg, L, x, y))
    return out


def hit(cfg, L, x, y):
    if y < 0 or x < 0 or x >= cfg["width"]:
        return (0, 0, 0)
    for i in range(len(L["placed"]) - 1, -1, -1):
        p = L["placed"][i]
        if p["x"] <= x < p["x"] + p["w"] and p["y"] <= y < p["y"] + p["h"]:
            return (2 if p["kind"] == "AllDay" else 1, i, p["day"])
    if cfg["mode"] == "Agenda":
        for r, (k, d, pl, ry, rh) in enumerate(L["rows"]):
            if k == "H" and ry <= y < ry + rh:
                return (4, r, d)
        return (0, 0, 0)
    if y < cfg["header"]:
        for d, c in enumerate(L["cols"]):
            if c["x"] <= x < c["x"] + c["w"]:
                return (4, d, d)
        return (5, 0, 0)
    if x < cfg["gutter"]:
        return (5, 0, 0)
    s = slot(cfg, L, x, y)
    if s:
        return (3, s[0], s[1])
    return (0, 0, 0)


def slot(cfg, L, x, y):
    if cfg["mode"] == "Agenda" or y < L["top"] or x < cfg["gutter"]:
        return None
    bottom = L["top"] + (cfg["day_end"] - cfg["day_start"]) * cfg["hour_h"]
    if y >= bottom or x >= cfg["width"]:
        return None
    for d, c in enumerate(L["cols"]):
        if c["x"] <= x < c["x"] + c["w"]:
            raw = int((y - L["top"]) * 60.0 / cfg["hour_h"])
            return (d, raw // cfg["slot"] * cfg["slot"] + cfg["day_start"] * 60)
    return None


def drags(cfg, L):
    out = []
    cases = [
        (cfg["gutter"] + 10.0, L["top"] + 35.0, cfg["gutter"] + 10.0, L["top"] + 100.0),
        (cfg["gutter"] + 130.0, L["top"] + 200.0, cfg["gutter"] + 130.0, L["top"] + 150.0),
        (cfg["gutter"] + 10.0, L["top"] + 61.0, cfg["gutter"] + 10.0, L["top"] + 62.0),
        (cfg["gutter"] + 10.0, L["top"] + 700.0, cfg["gutter"] + 10.0, L["top"] + 900.0),
        (cfg["gutter"] + 10.0, L["top"] + 10.0, cfg["gutter"] + 10.0, L["top"] - 40.0),
        (5.0, 5.0, 100.0, 100.0),
    ]
    for (x0, y0, x1, y1) in cases:
        s = slot(cfg, L, x0, y0)
        if not s:
            out.append((x0, y0, x1, y1, 0, 0, 0, 0))
            continue
        yy = min(max(y1, L["top"]), L["top"] + (cfg["day_end"] - cfg["day_start"]) * cfg["hour_h"] - 0.001)
        lo = int((y0 - L["top"]) * 60.0 / cfg["hour_h"])
        hi = int((yy - L["top"]) * 60.0 / cfg["hour_h"])
        a, b = min(lo, hi), max(lo, hi)
        sl = cfg["slot"]
        begin = a // sl * sl
        finish = -(-b // sl) * sl
        if finish <= begin:
            finish = begin + sl
        window = (cfg["day_end"] - cfg["day_start"]) * 60
        finish = min(finish, window)
        start_abs = L["cols"][s[0]]["count"] * 1440 + begin + cfg["day_start"] * 60
        out.append((x0, y0, x1, y1, 1, s[0], start_abs, finish - begin))
    return out


def nlit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def items_fn(name, items):
    s = f"fn {name}(out: []sched.Item) -> usize {{\n"
    for i, (iid, start, minutes, all_day, title, rule) in enumerate(items):
        s += (f"    out[{i}usize] = sched.Item {{ id: {iid}u32, start: at({start.year}, {start.month}u8, {start.day}u8, {start.hour}u8, {start.minute}u8), "
              f"minutes: {minutes}u32, all_day: {'true' if all_day else 'false'}, title: {nlit(title)}, rule: {nlit(rule)} }}\n")
    s += f"    ret {len(items)}usize\n}}\n"
    return s


def config_fn(name, cfg):
    mode = cfg["mode"]
    wd = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][cfg["week_start"]]
    a = cfg["anchor"]
    return (f"fn {name}() -> sched.Config {{\n    ret sched.Config {{ mode: .{mode}, anchor: time.Date {{ year: {a.year}, month: {a.month}u8, day: {a.day}u8 }}, week_start: .{wd}, "
            f"day_start: {cfg['day_start']}u32, day_end: {cfg['day_end']}u32, slot: {cfg['slot']}u32, agenda_days: {cfg['agenda_days']}u32, width: {cfg['width']}, "
            f"gutter: {cfg['gutter']}, header: {cfg['header']}, all_day_h: {cfg['all_day_h']}, hour_h: {cfg['hour_h']}, row_h: {cfg['row_h']}, min_h: {cfg['min_h']} }}\n}}\n")


def main():
    parts = [items_fn("main_items", ITEMS)]
    for k, cfg in CONFIGS.items():
        parts.append(config_fn("cfg_" + k, cfg))
        L = layout(cfg)
        parts.append(f"fn want_{k}() -> str {{ ret {nlit(render(cfg, L))} }}\n")
        if k in ("w1", "d1", "a1"):
            pr = ";".join(f"{num(x)},{num(y)},{kind},{a},{b}" for (x, y, kind, a, b) in probes(cfg, L))
            parts.append(f"fn probes_{k}() -> str {{ ret {nlit(pr)} }}\n")
        if k in ("w1", "d1"):
            dr = ";".join(",".join(num(v) if isinstance(v, float) else str(v) for v in row) for row in drags(cfg, L))
            parts.append(f"fn drags_{k}() -> str {{ ret {nlit(dr)} }}\n")
    # a rule with an endless count read into a tiny scratch: truncated
    L = layout(CONFIGS["w1"], [ITEMS[0]])
    parts.append(f"fn want_first_row() -> str {{ ret {nlit(render(CONFIGS['w1'], L))} }}\n")
    parts.append(items_fn("first_items", [ITEMS[0]]))
    text = MAIN.read_text(encoding="utf-8")
    lo = text.index("// BEGIN SCENARIOS\n") + len("// BEGIN SCENARIOS\n")
    hi = text.index("// END SCENARIOS")
    MAIN.write_text(text[:lo] + "\n".join(parts) + text[hi:], encoding="utf-8")
    for k, cfg in CONFIGS.items():
        L = layout(cfg)
        print(k, len(L["placed"]), "placed", len(L["nodes"]), "nodes", len(L["rows"]), "rows")


if __name__ == "__main__":
    main()
