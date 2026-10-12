"""Reference data for tests/selfhost/fixtures/link/ui_schedule_month (L148, D3303).

Independent models, written from the module header and python's datetime/calendar and
dateutil (not e.time.recur), of the month view (cells, "+N more", accessible tree, hit
regions, focus moves), the all-day bars, move and resize of placed occurrences, keyboard
focus among them, and a second set of words for the labels. The week, day and agenda
layouts they start from come from scripts/gen_schedule_test.py's model (the one the
ui_schedule fixture already compares with the module).

    python scripts/gen_schedule_month_test.py
"""
import calendar
import datetime as dt
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_schedule_test as base  # noqa: E402

MAIN = pathlib.Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/ui_schedule_month/src/main.e"
D = base.D
ITEMS = list(base.ITEMS) + [
    (18, D(2026, 10, 10, 0, 0), 7200, True, "Trip", ""),            # five days, starts before the week of the 14th
    (19, D(2026, 10, 13, 0, 0), 4320, True, "Offsite", ""),          # three days, overlaps Trip and Conference
    (20, D(2026, 10, 30, 0, 0), 4320, True, "Month end", ""),        # runs into November
    (21, D(2026, 10, 20, 22, 0), 180, False, "Late call", ""),       # past midnight
    (22, D(2026, 10, 16, 9, 45), 30, False, "Chain E", ""),
    (23, D(2026, 10, 16, 14, 0), 30, False, "Afternoon", ""),
    (24, D(2026, 8, 31, 12, 0), 60, False, "Boundary", ""),
    (25, D(2027, 2, 8, 9, 0), 60, False, "Feb standup", "FREQ=DAILY;COUNT=3"),
    (26, D(2027, 2, 8, 0, 0), 2880, True, "Feb fair", ""),
    (27, D(2027, 2, 9, 15, 0), 30, False, "Feb call", ""),
    (28, D(2027, 2, 9, 11, 0), 30, False, "Feb sync", ""),
]
WEEKDAYS_EN = base.WEEKDAYS
MONTHS_EN = base.MONTHS
EN = dict(weekdays=WEEKDAYS_EN, months=MONTHS_EN, all_day=", all day", to=" to ", repeats=", repeats", day="Day schedule",
          week="Week schedule", agenda="Agenda", month="Month schedule", none="no events", one="1 event", many=" events", more=" more")
DE = dict(weekdays=["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"],
          months=["Januar", "Februar", "Maerz", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"],
          all_day=", ganztaegig", to=" bis ", repeats=", wiederholt", day="Tagesplan", week="Wochenplan", agenda="Terminliste",
          month="Monatsplan", none="keine Termine", one="1 Termin", many=" Termine", more=" weitere")

MONTHS = {
    # name: (anchor, week_start, width, header, cell_h, line_h, lines)
    "m1": (dt.date(2026, 10, 14), 0, 700.0, 30.0, 120.0, 20.0, 4),
    "m2": (dt.date(2027, 2, 3), 0, 700.0, 30.0, 100.0, 25.0, 2),
    "m3": (dt.date(2026, 8, 20), 6, 840.0, 24.0, 90.0, 18.0, 0),
}
CELL_KIND = {"none": 0, "header": 1, "cell": 2, "event": 3, "more": 4}


def num(v):
    return base.num(v)


def occ_for(first, days, items):
    occ = []
    for idx, it in enumerate(items):
        for o in base.occurrences(it, first, days):
            o["item"] = idx
            occ.append(o)
    return occ


def label_event(items, p, names):
    s = items[p["item"]][4]
    if p["kind"] == "AllDay":
        s += names["all_day"]
    else:
        s += ", " + base.clock(p["start"]) + names["to"] + base.clock(p["end"])
    if p["recurring"]:
        s += names["repeats"]
    return s


def date_label(n, names):
    d = base.EPOCH + dt.timedelta(days=n)
    return f"{names['weekdays'][d.weekday()]} {d.day} {names['months'][d.month - 1]} {d.year}"


def month_layout(spec, items, names):
    anchor, ws, width, header, cell_h, line_h, lines = spec
    first_of = dt.date(anchor.year, anchor.month, 1)
    behind = (first_of.weekday() - ws) % 7
    dim = calendar.monthrange(anchor.year, anchor.month)[1]
    weeks = (behind + dim + 6) // 7
    first = base.day_no(first_of) - behind
    days = weeks * 7
    occ = occ_for(first, days, items)
    col_w = width / 7
    placed, cells = [], []
    for d in range(days):
        count = first + d
        day0 = count * 1440
        cx, cy = (d % 7) * col_w, header + (d // 7) * cell_h
        todays = sorted([o for o in occ if o["start"] < day0 + 1440 and o["start"] + o["minutes"] > day0], key=base.order_key)
        n = len(todays)
        shown, more = n, 0
        if n > lines:
            shown = 0 if lines == 0 else lines - 1
            more = n - shown
        start_index = len(placed)
        for k, o in enumerate(todays):
            visible = k < shown
            placed.append(dict(item=o["item"], kind="AllDay" if o["all_day"] else "Timed", day=d, start=max(o["start"], day0),
                               end=min(o["start"] + o["minutes"], day0 + 1440), x=cx, y=(cy + (k + 1) * line_h) if visible else cy,
                               w=col_w if visible else 0.0, h=line_h if visible else 0.0, lane=k, lanes=n,
                               before=o["start"] < day0, after=o["start"] + o["minutes"] > day0 + 1440, recurring=o["recurring"]))
        d0 = dt.date.fromordinal(count + 719163)
        cells.append(dict(count=count, in_month=(d0.month == anchor.month and d0.year == anchor.year), x=cx, y=cy, w=col_w, h=cell_h,
                          first=start_index, total=n, shown=shown, more=more))
    height = header + weeks * cell_h
    nodes = [("Grid", f"{names['month']}, {names['months'][anchor.month - 1]} {anchor.year}", 0.0, 0.0, width, height, 0, 0, weeks, 7, 0)]
    for col in range(7):
        nodes.append(("ColumnHeader", names["weekdays"][(ws + col) % 7], col * col_w, 0.0, col_w, header, 0, col + 1, 0, 7, 0))
    for d, c in enumerate(cells):
        total = c["total"]
        words = names["none"] if total == 0 else (names["one"] if total == 1 else f"{total}{names['many']}")
        nodes.append(("Cell", date_label(c["count"], names) + ", " + words, c["x"], c["y"], c["w"], c["h"], d // 7 + 1, d % 7 + 1, weeks, 7, 0))
        for k in range(total):
            p = placed[c["first"] + k]
            nodes.append(("ListItem", label_event(items, p, names), p["x"], p["y"], p["w"], p["h"], 0, 0, 0, 0, 1))
    return dict(first=first, weeks=weeks, days=days, height=height, cells=cells, placed=placed, nodes=nodes, spec=spec)


def render_month(L):
    out = [f"M {L['first']} {L['weeks']} {num(L['height'])}\n"]
    for c in L["cells"]:
        out.append("C %d %d %s %s %s %s %d %d %d %d\n" % (c["count"], c["in_month"], num(c["x"]), num(c["y"]), num(c["w"]), num(c["h"]),
                                                       c["first"], c["total"], c["shown"], c["more"]))
    for p in L["placed"]:
        out.append("P %d %s %d %d %d %s %s %s %s %d %d %d %d %d\n" % (p["item"], p["kind"][0], p["day"], p["start"], p["end"], num(p["x"]), num(p["y"]),
                                                                    num(p["w"]), num(p["h"]), p["lane"], p["lanes"], p["before"], p["after"], p["recurring"]))
    for n in L["nodes"]:
        out.append("N %s %s %s %s %s %s %d %d %d %d %d\n" % (n[0], num(n[2]), num(n[3]), num(n[4]), num(n[5]), n[1], n[6], n[7], n[8], n[9], n[10]))
    return "".join(out)


def month_hits(L):
    anchor, ws, width, header, cell_h, line_h, lines = L["spec"]
    col_w = width / 7
    pts = [(-1.0, 5.0), (width, 5.0), (5.0, 5.0), (width - 1.0, 5.0), (250.0, header - 1.0)]
    for c in L["cells"]:
        pts.append((c["x"] + 3.0, c["y"] + 2.0))                      # the number line
        for k in range(c["total"]):
            pts.append((c["x"] + 3.0, c["y"] + (k + 1) * line_h + 1.0))   # each line, shown or not
        pts.append((c["x"] + 3.0, c["y"] + c["h"] - 1.0))
    pts.append((10.0, L["height"] + 1.0))
    out = []
    for (x, y) in pts:
        out.append((int(x), int(y)) + month_hit(L, x, y))
    return out


def month_hit(L, x, y):
    anchor, ws, width, header, cell_h, line_h, lines = L["spec"]
    col_w = width / 7
    if x < 0 or y < 0 or x >= width or y >= header + L["weeks"] * cell_h:
        return (0, 0, 0)
    col = min(int(x / col_w), 6)
    if y < header:
        return (1, col, 0)
    index = int((y - header) / cell_h) * 7 + col
    c = L["cells"][index]
    for k in range(c["shown"]):
        p = L["placed"][c["first"] + k]
        if p["y"] <= y < p["y"] + p["h"]:
            return (3, index, c["first"] + k)
    if c["more"] > 0:
        top = c["y"] + (c["shown"] + 1) * line_h
        if top <= y < top + line_h:
            return (4, index, index)
    return (2, index, 0)


def month_moves(L):
    out = []
    n = len(L["cells"])
    for cell in range(n):
        for key in range(6):
            r = cell
            if key == 0 and cell > 0:
                r = cell - 1
            elif key == 1 and cell + 1 < n:
                r = cell + 1
            elif key == 2 and cell >= 7:
                r = cell - 7
            elif key == 3 and cell + 7 < n:
                r = cell + 7
            elif key == 4:
                r = cell - cell % 7
            elif key == 5:
                r = cell - cell % 7 + 6
            out.append((cell, key, r))
    return out


# ---- bars, moves, resizes, focus over a time-grid layout of the model ----

def bars(cfg, L, items):
    first, days = L["first"], L["days"]
    occ = occ_for(first, days, items)
    out = []
    for o in occ:
        if not o["all_day"]:
            continue
        a = max(o["start"] // 1440 - first, 0)
        b = min((o["start"] + o["minutes"] - 1) // 1440 - first, days - 1)
        if b < 0 or a > days - 1:
            continue
        out.append(dict(item=o["item"], first=a, last=b, before=o["start"] < first * 1440 + a * 1440, after=o["start"] + o["minutes"] > (first + days) * 1440,
                        recurring=o["recurring"], lane=0))
    out.sort(key=lambda b: (b["first"], -(b["last"] - b["first"]), b["item"]))
    lanes = 0
    for i, b in enumerate(out):
        lane = 0
        while any(o["lane"] == lane and o["last"] >= b["first"] and o["first"] <= b["last"] for o in out[:i]):
            lane += 1
        b["lane"] = lane
        lanes = max(lanes, lane + 1)
        cols = L["cols"]
        b["x"] = cols[b["first"]]["x"]
        b["y"] = cfg["header"] + lane * cfg["all_day_h"]
        b["w"] = cols[b["last"]]["x"] + cols[b["last"]]["w"] - cols[b["first"]]["x"]
        b["h"] = cfg["all_day_h"]
    return out, lanes


def render_bars(bs, lanes):
    out = [f"L {lanes} {len(bs)}\n"]
    for b in bs:
        out.append("B %d %d %d %d %s %s %s %s %d %d %d\n" % (b["item"], b["first"], b["last"], b["lane"], num(b["x"]), num(b["y"]), num(b["w"]), num(b["h"]),
                                                          b["before"], b["after"], b["recurring"]))
    return "".join(out)


def column_of(L, x):
    for d, c in enumerate(L["cols"]):
        if c["x"] <= x < c["x"] + c["w"]:
            return d
    return None


def slot_of(cfg, L, x, y):
    if y < L["top"] or x < cfg["gutter"]:
        return None
    bottom = L["top"] + (cfg["day_end"] - cfg["day_start"]) * cfg["hour_h"]
    if y >= bottom or x >= cfg["width"]:
        return None
    d = column_of(L, x)
    if d is None:
        return None
    raw = int((y - L["top"]) * 60.0 / cfg["hour_h"])
    return d, raw // cfg["slot"] * cfg["slot"] + cfg["day_start"] * 60


def move_cases(cfg, L, items):
    """(index, gx, gy, x, y, ok, day, start, minutes)."""
    out = []
    top = L["top"]
    bottom = top + (cfg["day_end"] - cfg["day_start"]) * cfg["hour_h"]
    for i, p in enumerate(L["placed"]):
        item = items[p["item"]]
        mins = max(item[2], 1)
        probes = [(p["x"] + 2.0, p["y"] + 3.0, p["x"] + 2.0 + 120.0, p["y"] + 3.0 + 70.0),
                  (p["x"] + 2.0, p["y"] + 3.0, p["x"] + 2.0 - 125.0, p["y"] + 3.0 - 33.0),
                  (p["x"] + 2.0, p["y"] + 3.0, p["x"] + 2.0, bottom + 80.0),
                  (p["x"] + 2.0, p["y"] + 3.0, 5.0, p["y"]),
                  (p["x"] + 2.0, p["y"] + 3.0, p["x"] + 2.0 + 250.0, 5.0)]
        for (gx, gy, x, y) in probes:
            gx, gy, x, y = int(gx), int(gy), int(x), int(y)
            if p["kind"] == "AllDay":
                a, b = column_of(L, gx), column_of(L, x)
                if a is None or b is None:
                    out.append((i, gx, gy, x, y, 0, 0, 0, 0))
                    continue
                start = p["start"] + (b - a) * 1440
                col = min(max(start // 1440 - L["first"], 0), L["days"] - 1)
                out.append((i, gx, gy, x, y, 1, col, start, -(-mins // 1440) * 1440))
            else:
                if p["before"]:
                    out.append((i, gx, gy, x, y, 0, 0, 0, 0))
                    continue
                ty = y - (gy - p["y"])
                ty = max(ty, top)
                if ty >= bottom:
                    ty = bottom - 0.001
                s = slot_of(cfg, L, float(x), ty)
                if s is None:
                    out.append((i, gx, gy, x, y, 0, 0, 0, 0))
                    continue
                out.append((i, gx, gy, x, y, 1, s[0], L["cols"][s[0]]["count"] * 1440 + s[1], mins))
    return out


def resize_cases(cfg, L):
    out = []
    top = L["top"]
    bottom = top + (cfg["day_end"] - cfg["day_start"]) * cfg["hour_h"]
    for i, p in enumerate(L["placed"]):
        for y in (p["y"] + p["h"] + 17.0, p["y"] + 1.0, top - 30.0, bottom + 50.0, p["y"] + p["h"] + 100.0):
            y = int(y)
            if p["kind"] != "Timed" or p["before"] or p["after"]:
                out.append((i, y, 0, 0))
                continue
            yy = min(max(float(y), top), bottom - 0.001)
            day0 = L["cols"][p["day"]]["count"] * 1440
            start_minute = p["start"] - day0
            raw = int((yy - top) * 60.0 / cfg["hour_h"]) + cfg["day_start"] * 60
            finish = -(-raw // cfg["slot"]) * cfg["slot"]
            if finish <= start_minute:
                finish = start_minute + cfg["slot"]
            finish = min(finish, cfg["day_end"] * 60)
            if finish <= start_minute:
                out.append((i, y, 0, 0))
            else:
                out.append((i, y, 1, finish - start_minute))
    return out


def focus_cases(cfg, L):
    """(index, key, result), key 0 Left 1 Right 2 Up 3 Down 4 Home 5 End."""
    placed = L["placed"]
    out = []
    agenda = cfg["mode"] == "Agenda"
    for i, p in enumerate(placed):
        for key in range(6):
            r = i
            if agenda:
                if key == 2 and i > 0:
                    r = i - 1
                elif key == 3 and i + 1 < len(placed):
                    r = i + 1
                elif key == 4:
                    r = 0
                elif key == 5:
                    r = len(placed) - 1
            else:
                same = [j for j, q in enumerate(placed) if q["day"] == p["day"]]
                if key == 2:
                    r = max([j for j in same if j < i], default=i)
                elif key == 3:
                    r = min([j for j in same if j > i], default=i)
                elif key == 4:
                    r = same[0]
                elif key == 5:
                    r = same[-1]
                else:
                    step = -1 if key == 0 else 1
                    mark = p["start"] if p["kind"] == "Timed" else (L["first"] + p["day"]) * 1440
                    t = p["day"] + step
                    while 0 <= t < len(L["cols"]):
                        cand = [(abs((q["start"] if q["kind"] == "Timed" else (L["first"] + t) * 1440) - mark), j)
                                for j, q in enumerate(placed) if q["day"] == t]
                        if cand:
                            r = min(cand)[1]
                            break
                        t += step
            out.append((i, key, r))
    return out


def nlit(s):
    return base.nlit(s)


def intlist(rows):
    return ";".join(",".join(str(v) for v in row) for row in rows)


def words_fn(prefix, names):
    s = f"fn {prefix}_names() -> sched.Names {{\n    var n = sched.english()\n"
    for i, w in enumerate(names["weekdays"]):
        s += f"    n.weekdays[{i}usize] = {nlit(w)}\n"
    for i, w in enumerate(names["months"]):
        s += f"    n.months[{i}usize] = {nlit(w)}\n"
    s += (f"    n.all_day = {nlit(names['all_day'])}\n    n.to = {nlit(names['to'])}\n    n.repeats = {nlit(names['repeats'])}\n"
          f"    n.day_schedule = {nlit(names['day'])}\n    n.week_schedule = {nlit(names['week'])}\n    n.agenda = {nlit(names['agenda'])}\n"
          f"    n.month_schedule = {nlit(names['month'])}\n    n.no_events = {nlit(names['none'])}\n    n.one_event = {nlit(names['one'])}\n"
          f"    n.events = {nlit(names['many'])}\n    n.more = {nlit(names['more'])}\n    ret n\n}}\n")
    return s


def month_cfg_fn(name, spec):
    anchor, ws, width, header, cell_h, line_h, lines = spec
    wd = WEEKDAYS_EN[ws]
    return (f"fn {name}() -> sched.MonthConfig {{\n    ret sched.MonthConfig {{ anchor: time.Date {{ year: {anchor.year}, month: {anchor.month}u8, day: {anchor.day}u8 }}, "
            f"week_start: .{wd}, width: {width}, header: {header}, cell_h: {cell_h}, line_h: {line_h}, lines: {lines}u32 }}\n}}\n")


def main():
    parts = [base.items_fn("all_items", ITEMS)]
    for k, spec in MONTHS.items():
        parts.append(month_cfg_fn("mcfg_" + k, spec))
    parts.append(words_fn("de", DE))
    for k, spec in MONTHS.items():
        L = month_layout(spec, ITEMS, EN)
        parts.append(f"fn want_{k}() -> str {{ ret {nlit(render_month(L))} }}\n")
        if k in ("m1", "m2"):
            parts.append(f"fn hits_{k}() -> str {{ ret {nlit(intlist(month_hits(L)))} }}\n")
    L = month_layout(MONTHS["m1"], ITEMS, DE)
    parts.append(f"fn want_m1_de() -> str {{ ret {nlit(render_month(L))} }}\n")
    parts.append(f"fn moves_m1() -> str {{ ret {nlit(intlist(month_moves(month_layout(MONTHS['m1'], ITEMS, EN))))} }}\n")
    # the grid layouts of the other fixture's configs over the longer item table
    for k in ("w1", "d1", "a1"):
        cfg = base.CONFIGS[k]
        parts.append(base.config_fn("cfg_" + k, cfg))
        G = base.layout(cfg, ITEMS)
        if cfg["mode"] != "Agenda":
            bs, lanes = bars(cfg, G, ITEMS)
            parts.append(f"fn want_bars_{k}() -> str {{ ret {nlit(render_bars(bs, lanes))} }}\n")
            parts.append(f"fn moves_{k}() -> str {{ ret {nlit(intlist(move_cases(cfg, G, ITEMS)))} }}\n")
            parts.append(f"fn resizes_{k}() -> str {{ ret {nlit(intlist(resize_cases(cfg, G)))} }}\n")
        parts.append(f"fn focus_{k}() -> str {{ ret {nlit(intlist(focus_cases(cfg, G)))} }}\n")
    # the German week: the labels of the time grid in another language
    G = base.layout(base.CONFIGS["w1"], ITEMS)
    parts.append(f"fn de_week_labels() -> str {{ ret {nlit(chr(10).join(de_week_labels(G)))} }}\n")
    text = MAIN.read_text(encoding="utf-8")
    lo = text.index("// BEGIN SCENARIOS\n") + len("// BEGIN SCENARIOS\n")
    hi = text.index("// END SCENARIOS")
    MAIN.write_text(text[:lo] + "\n".join(parts) + text[hi:], encoding="utf-8")
    for k, spec in MONTHS.items():
        L = month_layout(spec, ITEMS, EN)
        print(k, L["weeks"], "weeks", len(L["placed"]), "placed", len(L["nodes"]), "nodes")


def de_week_labels(G):
    """The labels the module writes for a week layout with the German names: the grid, the column headers and the cells."""
    first = G["first"]
    out = [DE["week"]]
    L_items = ITEMS
    for d, c in enumerate(G["cols"]):
        out.append(date_label(c["count"], DE))
        for p in [q for q in G["placed"] if q["day"] == d]:
            out.append(label_event(L_items, p, DE))
    return out


if __name__ == "__main__":
    main()
