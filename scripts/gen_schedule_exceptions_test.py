#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/ui_schedule_exceptions/src/main.e (L148, D4606): single-occurrence exceptions of a
recurring series in e.ui.schedule -- `EXDATE=` in an item's rule text, `cancel_occurrence`, `move_occurrence` and
`move_series` shifting the exceptions with the series.

Independent model: python's datetime for the calendar and python-dateutil's rrule for recurrence (the occurrences of the
series are expanded by dateutil and the cancelled ones removed; a moved occurrence is a plain item), laid out by the
model of scripts/gen_schedule_test.py (the same rows, rectangles and accessible tree that fixture compares). The rule text
the operations write is the format `schedule.cancel_occurrence` documents (the original occurrence's date, `T` and
`HHMMSS` for a timed series, `YYYYMMDD` for an all-day one).

    PYTHONPATH=<dateutil install dir> python scripts/gen_schedule_exceptions_test.py
"""
import datetime as dt
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_schedule_test as base  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "tests/selfhost/fixtures/link/ui_schedule_exceptions/src/main.e"
EXISTING = ROOT / "tests/selfhost/fixtures/link/ui_schedule/src/main.e"
D = base.D
nlit = base.nlit

_original = base.occurrences


def ex_values(rule):
    """The EXDATE values of a rule text and the rule without them."""
    if "EXDATE=" not in rule:
        return rule, []
    head, tail = rule.rsplit("EXDATE=", 1)
    return head.rstrip(";"), tail.split(",")


def occurrences(item, first, days):
    iid, start, minutes, all_day, title, rule = item
    rule_only, values = ex_values(rule)
    out = _original((iid, start, minutes, all_day, title, rule_only), first, days)
    if not values:
        return out
    kept = []
    for o in out:
        day, minute = divmod(o["start"], 1440)
        d = base.EPOCH + dt.timedelta(days=day)
        gone = False
        for v in values:
            vd = dt.date(int(v[0:4]), int(v[4:6]), int(v[6:8]))
            if vd != d:
                continue
            if all_day or len(v) == 8:
                gone = True
            elif int(v[9:11]) * 60 + int(v[11:13]) == minute:
                gone = True
        if not gone:
            kept.append(o)
    return kept


base.occurrences = occurrences

CFG = dict(base.BASE, day_start=6, day_end=22)
WEEK = dict(CFG, mode="Week", anchor=dt.date(2026, 10, 14), week_start=0)
AGENDA = dict(CFG, mode="Agenda", anchor=dt.date(2026, 10, 12), week_start=0, agenda_days=14)

SERIES = (1, D(2026, 10, 5, 9, 0), 60, False, "Standup", "FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=14")
EX1 = "20261012T090000"            # Monday in view
EX2 = "20261014T090000"            # Wednesday in view
EX3 = "20261009T090000"            # a Friday before the view
SCENARIOS = {
    # weekly timed series, two occurrences cancelled in the week, one before it, one moved (a standalone item)
    "s1": [SERIES[:5] + (SERIES[5] + ";EXDATE=" + ",".join([EX3, EX1, EX2]),),
           (1, D(2026, 10, 14, 15, 0), 90, False, "Standup (moved)", ""),
           (2, D(2026, 10, 13, 10, 0), 60, False, "Other", ""),
           (3, D(2026, 10, 16, 9, 0), 60, False, "Collides with Friday", "")],
    # all-day daily series with two days cancelled and one moved to a later day
    "s2": [(10, D(2026, 10, 10, 0, 0), 1440, True, "Trash", "FREQ=DAILY;COUNT=12;EXDATE=20261013,20261015"),
           (10, D(2026, 10, 19, 0, 0), 1440, True, "Trash (moved)", ""),
           (11, D(2026, 10, 14, 8, 0), 30, False, "Timed", "")],
    # the first occurrence of the series is the cancelled one, a monthly rule
    "s3": [(20, D(2026, 10, 13, 18, 30), 45, False, "Monthly", "FREQ=MONTHLY;BYMONTHDAY=13;COUNT=6;EXDATE=20261013T183000"),
           (21, D(2026, 10, 15, 12, 0), 60, False, "Lunch", "")],
    # everything in view cancelled; an EXDATE beyond UNTIL is harmless; a date-only value on a timed series
    "s4": [(30, D(2026, 10, 12, 7, 0), 30, False, "Run", "FREQ=DAILY;UNTIL=20261018T235959;EXDATE=20261012T070000,20261013T070000,20261014T070000,20261015T070000,20261016T070000,20261017,20261018T070000,20261101T070000"),
           (31, D(2026, 10, 12, 7, 0), 30, False, "Run, unchanged", "FREQ=DAILY;COUNT=3")],
}
VIEWS = {"w": WEEK, "a": AGENDA}


def items_literal(name, items):
    return base.items_fn(name, items)


def at(dtv):
    return f"at({dtv.year}, {dtv.month}u8, {dtv.day}u8, {dtv.hour}u8, {dtv.minute}u8)"


def fmt_ex(dtv, all_day):
    s = f"{dtv.year:04d}{dtv.month:02d}{dtv.day:02d}"
    return s if all_day else s + f"T{dtv.hour:02d}{dtv.minute:02d}00"


def shift_value(v, delta):
    """UNTIL/EXDATE moved by `delta` minutes (whole days for a date value)."""
    d = dt.date(int(v[0:4]), int(v[4:6]), int(v[6:8]))
    if len(v) == 8:
        return (d + dt.timedelta(days=delta // 1440)).strftime("%Y%m%d")
    t = dt.datetime(d.year, d.month, d.day, int(v[9:11]), int(v[11:13])) + dt.timedelta(minutes=delta)
    return t.strftime("%Y%m%dT%H%M") + v[13:]


def ops():
    """Checks of cancel_occurrence, move_occurrence and move_series, as Neper source lines."""
    code = []
    n = [0]

    def check(cond):
        n[0] += 1
        code.append(f"    if !({cond}) {{ ret {n[0]}u32 }}")

    def series(var, start, minutes, all_day, rule, title="S"):
        code.append(f"    var {var}: sched.Item = zero\n    {var}.id = 5u32\n    {var}.start = {at(start)}\n    {var}.minutes = {minutes}u32\n"
                    f"    {var}.all_day = {'true' if all_day else 'false'}\n    {var}.title = {nlit(title)}\n    {var}.rule = {nlit(rule)}")

    start = D(2026, 3, 2, 9, 30)
    series("w", start, 60, False, "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10")
    code.append("    var buf: [128]u8 = zero")
    # cancel the first, a middle one, then the same again (unchanged) and a third (appended after a comma)
    first = D(2026, 3, 2, 9, 30)
    code.append(f"    let (c1, e1) = sched.cancel_occurrence(w, {at(first)}, buf[0usize..128usize])")
    r1 = "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10;EXDATE=" + fmt_ex(first, False)
    check(f"e1 == ok && str.eq(c1.rule, {nlit(r1)})")
    mid = D(2026, 3, 11, 9, 30)
    code.append(f"    var buf2: [128]u8 = zero\n    let (c2, e2) = sched.cancel_occurrence(c1, {at(mid)}, buf2[0usize..128usize])")
    r2 = r1 + "," + fmt_ex(mid, False)
    check(f"e2 == ok && str.eq(c2.rule, {nlit(r2)})")
    code.append(f"    var buf3: [128]u8 = zero\n    let (c3, e3) = sched.cancel_occurrence(c2, {at(mid)}, buf3[0usize..128usize])")
    check(f"e3 == ok && str.eq(c3.rule, {nlit(r2)})")
    # refusals: a time that is not an occurrence, a day that is not, before the start, a non-recurring item, too small
    code.append(f"    let (x1, ex1) = sched.cancel_occurrence(w, {at(D(2026, 3, 2, 10, 0))}, buf[0usize..128usize])")
    check("ex1 == sched.Invalid")
    code.append(f"    let (x2, ex2) = sched.cancel_occurrence(w, {at(D(2026, 3, 3, 9, 30))}, buf[0usize..128usize])")
    check("ex2 == sched.Invalid")
    code.append(f"    let (x3, ex3) = sched.cancel_occurrence(w, {at(D(2026, 2, 23, 9, 30))}, buf[0usize..128usize])")
    check("ex3 == sched.Invalid")
    code.append(f"    let (x4, ex4) = sched.cancel_occurrence(w, {at(D(2026, 4, 20, 9, 30))}, buf[0usize..128usize])")
    check("ex4 == sched.Invalid")   # the series ended (COUNT=10: the last is 2026-04-01)
    series("plain", start, 30, False, "")
    code.append(f"    let (x5, ex5) = sched.cancel_occurrence(plain, {at(start)}, buf[0usize..128usize])")
    check("ex5 == sched.Invalid")
    code.append(f"    var tiny: [20]u8 = zero\n    let (x6, ex6) = sched.cancel_occurrence(w, {at(first)}, tiny[0usize..20usize])")
    check("ex6 == sched.TooLarge")
    # an all-day series writes dates only, and its second occurrence is found by date
    series("ad", D(2026, 6, 1, 0, 0), 1440, True, "FREQ=DAILY;COUNT=20", "Trash")
    ad_day = D(2026, 6, 4, 0, 0)
    code.append(f"    var buf4: [128]u8 = zero\n    let (a1, ae1) = sched.cancel_occurrence(ad, {at(ad_day)}, buf4[0usize..128usize])")
    check(f"ae1 == ok && str.eq(a1.rule, {nlit('FREQ=DAILY;COUNT=20;EXDATE=20260604')})")
    # move_occurrence: the series without it and the occurrence as an item of its own
    new_start = D(2026, 3, 12, 16, 45)
    code.append(f"    var buf5: [128]u8 = zero\n    let (ms, mo, me) = sched.move_occurrence(w, {at(D(2026, 3, 4, 9, 30))}, {at(new_start)}, 75u32, buf5[0usize..128usize])")
    check(f"me == ok && str.eq(ms.rule, {nlit('FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10;EXDATE=20260304T093000')}) && mo.rule.len == 0usize && mo.minutes == 75u32 && mo.id == 5u32 && mo.start.date.day == 12u8 && mo.start.time.hour == 16u8 && mo.start.time.minute == 45u8")
    # move_series: the EXDATE values move with the series (a drag of +1 day +30 minutes; all-day by whole days)
    ex_series = "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10;EXDATE=20260302T093000,20260311T093000"
    series("m", start, 60, False, ex_series)
    to = D(2026, 3, 3, 10, 0)
    code.append(f"    var buf6: [160]u8 = zero\n    let (mv, mve) = sched.move_series(m, {at(start)}, {at(to)}, buf6[0usize..160usize])")
    delta = 24 * 60 + 30
    want = "FREQ=WEEKLY;BYDAY=TU,TH;COUNT=10;EXDATE=" + ",".join(shift_value(v, delta) for v in ("20260302T093000", "20260311T093000"))
    check(f"mve == ok && str.eq(mv.rule, {nlit(want)})")
    series("mad", D(2026, 6, 1, 0, 0), 1440, True, "FREQ=DAILY;COUNT=20;EXDATE=20260604,20260610")
    code.append(f"    var buf7: [160]u8 = zero\n    let (mv2, mve2) = sched.move_series(mad, {at(D(2026, 6, 1, 0, 0))}, {at(D(2026, 6, 3, 0, 0))}, buf7[0usize..160usize])")
    check(f"mve2 == ok && str.eq(mv2.rule, {nlit('FREQ=DAILY;COUNT=20;EXDATE=' + ','.join(shift_value(v, 2 * 1440) for v in ('20260604', '20260610')))})")
    # EXDATE not last is refused when a layout is built
    series("mid", start, 60, False, "FREQ=DAILY;EXDATE=20260302T093000;COUNT=3")
    code.append("    var items_bad: [1]sched.Item = zero\n    items_bad[0usize] = mid")
    code.append("    var bad_cfg = cfg_a()\n    let (bl, be) = sched.build(items_bad[0usize..1usize], bad_cfg, st)")
    check("be == sched.Invalid")
    return "\n".join(code), n[0]


def main():
    parts = []
    for name, items in SCENARIOS.items():
        parts.append(items_literal("items_" + name, items))
        for vname, cfg in VIEWS.items():
            key = f"{name}{vname}"
            parts.append(base.config_fn("cfg_" + vname, cfg) if name == "s1" else "")
            L = base.layout(cfg, items)
            parts.append(f"fn want_{key}() -> str {{ ret {nlit(base.render(cfg, L))} }}\n")
    op_code, op_count = ops()
    helpers = EXISTING.read_text(encoding="utf-8")
    helpers = helpers[helpers.index("fn at("):helpers.index("fn role_name(")] + helpers[helpers.index("fn role_name("):helpers.index("fn next_int(")]
    store = EXISTING.read_text(encoding="utf-8")
    store = store[store.index("fn storage("):store.index("fn main(")]
    checks = []
    for name in SCENARIOS:
        for vname in VIEWS:
            if vname == "w":
                checks.append(f"    var raw_{name}: [32]sched.Item = zero")
                checks.append(f"    let n_{name} = items_{name}(raw_{name}[0usize..32usize])")
            checks.append(f"    if run_view(a, st, raw_{name}[0usize..n_{name}], cfg_{vname}(), want_{name}{vname}()) != 0u32 {{ os.exit({len(checks) + 1}) }}")
    src = f"""// `e.ui.schedule` single-occurrence exceptions of a recurring series (L148, D4606): `EXDATE=` as the last part of an item's
// rule text cancels occurrences, `cancel_occurrence` and `move_occurrence` write it, `move_series` shifts it with the
// series. Four item tables (weekly timed, all-day daily, monthly, everything cancelled) laid out as a week and as a
// fourteen-day agenda are compared row by row with the model of scripts/gen_schedule_exceptions_test.py (python-dateutil
// recurrence with the cancelled occurrences removed, the moved ones as plain items). Generated; do not edit.

use e.io
use e.mem
use e.os
use e.str
use e.time
use e.time.calendar
use e.ui.accessibility
use e.ui.schedule as sched

{chr(10).join(parts)}
{helpers}
{store}
fn run_view(a: *mem.Arena, st: sched.Storage, raw: []const sched.Item, cfg: sched.Config, want: str) -> u32 {{
    let (l, build_error) = sched.build(raw, cfg, st)
    if build_error != ok {{ ret 1u32 }}
    let (bld, bld_error) = str.builder(a, 16384usize)
    if bld_error != ok {{ ret 2u32 }}
    var bb = bld
    if render(&bb, &l) != ok {{ ret 3u32 }}
    let got = str.done(&bb)
    if !str.eq(got, want) {{
        let shown = io.print(got)
        ret 4u32
    }}
    ret 0u32
}}

fn run_ops(st: sched.Storage) -> u32 {{
{op_code}
    ret 0u32
}}

fn main(a: *mem.Arena, args: []str) -> err {{
    let (st, st_error) = storage(a, 256usize, 128usize, 256usize, 16384usize)
    if st_error != ok {{ os.exit(100) }}
{chr(10).join(checks)}
    let ops_result = run_ops(st)
    if ops_result != 0u32 {{ os.exit(i32(100u32 + ops_result)) }}
    try io.print("ui schedule exceptions ok\\n")
    ret ok
}}
"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(src.encode("utf-8"))
    print("wrote", OUT, len(SCENARIOS) * len(VIEWS), "views", op_count, "op checks")


main()
