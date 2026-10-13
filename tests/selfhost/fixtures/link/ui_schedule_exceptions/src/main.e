// `e.ui.schedule` single-occurrence exceptions of a recurring series (L148, D4606): `EXDATE=` as the last part of an item's
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

fn items_s1(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 10u8, 5u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Standup", rule: "FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=14;EXDATE=20261009T090000,20261012T090000,20261014T090000" }
    out[1usize] = sched.Item { id: 1u32, start: at(2026, 10u8, 14u8, 15u8, 0u8), minutes: 90u32, all_day: false, title: "Standup (moved)", rule: "" }
    out[2usize] = sched.Item { id: 2u32, start: at(2026, 10u8, 13u8, 10u8, 0u8), minutes: 60u32, all_day: false, title: "Other", rule: "" }
    out[3usize] = sched.Item { id: 3u32, start: at(2026, 10u8, 16u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Collides with Friday", rule: "" }
    ret 4usize
}

fn cfg_w() -> sched.Config {
    ret sched.Config { mode: .Week, anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Monday, day_start: 6u32, day_end: 22u32, slot: 30u32, agenda_days: 10u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn want_s1w() -> str { ret "M 20738 7 0 30 990\nP 2 T 1 29864760 29864820 180 270 120 60 0 1 0 0 0\nP 1 T 2 29866500 29866590 300 570 120 90 0 1 0 0 0\nP 0 T 4 29869020 29869080 540 210 60 60 0 2 0 0 1\nP 3 T 4 29869020 29869080 600 210 60 60 1 2 0 0 0\nN Grid 0 0 900 990 Week schedule 0 0 4 7 0\nN ColumnHeader 60 0 120 30 Monday 12 October 2026 0 1 0 7 0\nN ColumnHeader 180 0 120 30 Tuesday 13 October 2026 0 2 0 7 0\nN Cell 180 270 120 60 Other, 10:00 to 11:00 1 2 1 7 0\nN ColumnHeader 300 0 120 30 Wednesday 14 October 2026 0 3 0 7 0\nN Cell 300 570 120 90 Standup (moved), 15:00 to 16:30 1 3 1 7 0\nN ColumnHeader 420 0 120 30 Thursday 15 October 2026 0 4 0 7 0\nN ColumnHeader 540 0 120 30 Friday 16 October 2026 0 5 0 7 0\nN Cell 540 210 60 60 Standup, 09:00 to 10:00, repeats 1 5 2 7 0\nN Cell 600 210 60 60 Collides with Friday, 09:00 to 10:00 2 5 2 7 0\nN ColumnHeader 660 0 120 30 Saturday 17 October 2026 0 6 0 7 0\nN ColumnHeader 780 0 120 30 Sunday 18 October 2026 0 7 0 7 0\n" }

fn cfg_a() -> sched.Config {
    ret sched.Config { mode: .Agenda, anchor: time.Date { year: 2026, month: 10u8, day: 12u8 }, week_start: .Monday, day_start: 6u32, day_end: 22u32, slot: 30u32, agenda_days: 14u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn want_s1a() -> str { ret "M 20738 14 0 30 312\nP 2 T 1 29864760 29864820 0 24 900 24 0 1 0 0 0\nP 1 T 2 29866500 29866590 0 72 900 24 0 1 0 0 0\nP 0 T 4 29869020 29869080 0 120 900 24 0 1 0 0 1\nP 3 T 4 29869020 29869080 0 144 900 24 0 1 0 0 0\nP 0 T 7 29873340 29873400 0 192 900 24 0 1 0 0 1\nP 0 T 9 29876220 29876280 0 240 900 24 0 1 0 0 1\nP 0 T 11 29879100 29879160 0 288 900 24 0 1 0 0 1\nR H 1 0 0 24\nR E 1 0 24 24\nR H 2 0 48 24\nR E 2 1 72 24\nR H 4 0 96 24\nR E 4 2 120 24\nR E 4 3 144 24\nR H 7 0 168 24\nR E 7 4 192 24\nR H 9 0 216 24\nR E 9 5 240 24\nR H 11 0 264 24\nR E 11 6 288 24\nN List 0 0 900 312 Agenda 0 0 7 1 0\nN Heading 0 0 900 24 Tuesday 13 October 2026 0 0 0 1 2\nN ListItem 0 24 900 24 Other, 10:00 to 11:00 0 0 0 1 0\nN Heading 0 48 900 24 Wednesday 14 October 2026 0 0 0 1 2\nN ListItem 0 72 900 24 Standup (moved), 15:00 to 16:30 0 0 0 1 0\nN Heading 0 96 900 24 Friday 16 October 2026 0 0 0 1 2\nN ListItem 0 120 900 24 Standup, 09:00 to 10:00, repeats 0 0 0 1 0\nN ListItem 0 144 900 24 Collides with Friday, 09:00 to 10:00 0 0 0 1 0\nN Heading 0 168 900 24 Monday 19 October 2026 0 0 0 1 2\nN ListItem 0 192 900 24 Standup, 09:00 to 10:00, repeats 0 0 0 1 0\nN Heading 0 216 900 24 Wednesday 21 October 2026 0 0 0 1 2\nN ListItem 0 240 900 24 Standup, 09:00 to 10:00, repeats 0 0 0 1 0\nN Heading 0 264 900 24 Friday 23 October 2026 0 0 0 1 2\nN ListItem 0 288 900 24 Standup, 09:00 to 10:00, repeats 0 0 0 1 0\n" }

fn items_s2(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 10u32, start: at(2026, 10u8, 10u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "Trash", rule: "FREQ=DAILY;COUNT=12;EXDATE=20261013,20261015" }
    out[1usize] = sched.Item { id: 10u32, start: at(2026, 10u8, 19u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "Trash (moved)", rule: "" }
    out[2usize] = sched.Item { id: 11u32, start: at(2026, 10u8, 14u8, 8u8, 0u8), minutes: 30u32, all_day: false, title: "Timed", rule: "" }
    ret 3usize
}


fn want_s2w() -> str { ret "M 20738 7 20 50 1010\nP 0 A 0 29862720 29864160 60 30 120 20 0 1 0 0 1\nP 0 A 2 29865600 29867040 300 30 120 20 0 1 0 0 1\nP 2 T 2 29866080 29866110 300 170 120 30 0 1 0 0 0\nP 0 A 4 29868480 29869920 540 30 120 20 0 1 0 0 1\nP 0 A 5 29869920 29871360 660 30 120 20 0 1 0 0 1\nP 0 A 6 29871360 29872800 780 30 120 20 0 1 0 0 1\nN Grid 0 0 900 1010 Week schedule 0 0 6 7 0\nN ColumnHeader 60 0 120 30 Monday 12 October 2026 0 1 0 7 0\nN Cell 60 30 120 20 Trash, all day, repeats 1 1 1 7 0\nN ColumnHeader 180 0 120 30 Tuesday 13 October 2026 0 2 0 7 0\nN ColumnHeader 300 0 120 30 Wednesday 14 October 2026 0 3 0 7 0\nN Cell 300 30 120 20 Trash, all day, repeats 1 3 2 7 0\nN Cell 300 170 120 30 Timed, 08:00 to 08:30 2 3 2 7 0\nN ColumnHeader 420 0 120 30 Thursday 15 October 2026 0 4 0 7 0\nN ColumnHeader 540 0 120 30 Friday 16 October 2026 0 5 0 7 0\nN Cell 540 30 120 20 Trash, all day, repeats 1 5 1 7 0\nN ColumnHeader 660 0 120 30 Saturday 17 October 2026 0 6 0 7 0\nN Cell 660 30 120 20 Trash, all day, repeats 1 6 1 7 0\nN ColumnHeader 780 0 120 30 Sunday 18 October 2026 0 7 0 7 0\nN Cell 780 30 120 20 Trash, all day, repeats 1 7 1 7 0\n" }


fn want_s2a() -> str { ret "M 20738 14 0 30 432\nP 0 A 0 29862720 29864160 0 24 900 24 0 1 0 0 1\nP 0 A 2 29865600 29867040 0 72 900 24 0 1 0 0 1\nP 2 T 2 29866080 29866110 0 96 900 24 0 1 0 0 0\nP 0 A 4 29868480 29869920 0 144 900 24 0 1 0 0 1\nP 0 A 5 29869920 29871360 0 192 900 24 0 1 0 0 1\nP 0 A 6 29871360 29872800 0 240 900 24 0 1 0 0 1\nP 0 A 7 29872800 29874240 0 288 900 24 0 1 0 0 1\nP 1 A 7 29872800 29874240 0 312 900 24 0 1 0 0 0\nP 0 A 8 29874240 29875680 0 360 900 24 0 1 0 0 1\nP 0 A 9 29875680 29877120 0 408 900 24 0 1 0 0 1\nR H 0 0 0 24\nR E 0 0 24 24\nR H 2 0 48 24\nR E 2 1 72 24\nR E 2 2 96 24\nR H 4 0 120 24\nR E 4 3 144 24\nR H 5 0 168 24\nR E 5 4 192 24\nR H 6 0 216 24\nR E 6 5 240 24\nR H 7 0 264 24\nR E 7 6 288 24\nR E 7 7 312 24\nR H 8 0 336 24\nR E 8 8 360 24\nR H 9 0 384 24\nR E 9 9 408 24\nN List 0 0 900 432 Agenda 0 0 10 1 0\nN Heading 0 0 900 24 Monday 12 October 2026 0 0 0 1 2\nN ListItem 0 24 900 24 Trash, all day, repeats 0 0 0 1 0\nN Heading 0 48 900 24 Wednesday 14 October 2026 0 0 0 1 2\nN ListItem 0 72 900 24 Trash, all day, repeats 0 0 0 1 0\nN ListItem 0 96 900 24 Timed, 08:00 to 08:30 0 0 0 1 0\nN Heading 0 120 900 24 Friday 16 October 2026 0 0 0 1 2\nN ListItem 0 144 900 24 Trash, all day, repeats 0 0 0 1 0\nN Heading 0 168 900 24 Saturday 17 October 2026 0 0 0 1 2\nN ListItem 0 192 900 24 Trash, all day, repeats 0 0 0 1 0\nN Heading 0 216 900 24 Sunday 18 October 2026 0 0 0 1 2\nN ListItem 0 240 900 24 Trash, all day, repeats 0 0 0 1 0\nN Heading 0 264 900 24 Monday 19 October 2026 0 0 0 1 2\nN ListItem 0 288 900 24 Trash, all day, repeats 0 0 0 1 0\nN ListItem 0 312 900 24 Trash (moved), all day 0 0 0 1 0\nN Heading 0 336 900 24 Tuesday 20 October 2026 0 0 0 1 2\nN ListItem 0 360 900 24 Trash, all day, repeats 0 0 0 1 0\nN Heading 0 384 900 24 Wednesday 21 October 2026 0 0 0 1 2\nN ListItem 0 408 900 24 Trash, all day, repeats 0 0 0 1 0\n" }

fn items_s3(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 20u32, start: at(2026, 10u8, 13u8, 18u8, 30u8), minutes: 45u32, all_day: false, title: "Monthly", rule: "FREQ=MONTHLY;BYMONTHDAY=13;COUNT=6;EXDATE=20261013T183000" }
    out[1usize] = sched.Item { id: 21u32, start: at(2026, 10u8, 15u8, 12u8, 0u8), minutes: 60u32, all_day: false, title: "Lunch", rule: "" }
    ret 2usize
}


fn want_s3w() -> str { ret "M 20738 7 0 30 990\nP 1 T 3 29867760 29867820 420 390 120 60 0 1 0 0 0\nN Grid 0 0 900 990 Week schedule 0 0 1 7 0\nN ColumnHeader 60 0 120 30 Monday 12 October 2026 0 1 0 7 0\nN ColumnHeader 180 0 120 30 Tuesday 13 October 2026 0 2 0 7 0\nN ColumnHeader 300 0 120 30 Wednesday 14 October 2026 0 3 0 7 0\nN ColumnHeader 420 0 120 30 Thursday 15 October 2026 0 4 0 7 0\nN Cell 420 390 120 60 Lunch, 12:00 to 13:00 1 4 1 7 0\nN ColumnHeader 540 0 120 30 Friday 16 October 2026 0 5 0 7 0\nN ColumnHeader 660 0 120 30 Saturday 17 October 2026 0 6 0 7 0\nN ColumnHeader 780 0 120 30 Sunday 18 October 2026 0 7 0 7 0\n" }


fn want_s3a() -> str { ret "M 20738 14 0 30 48\nP 1 T 3 29867760 29867820 0 24 900 24 0 1 0 0 0\nR H 3 0 0 24\nR E 3 0 24 24\nN List 0 0 900 48 Agenda 0 0 1 1 0\nN Heading 0 0 900 24 Thursday 15 October 2026 0 0 0 1 2\nN ListItem 0 24 900 24 Lunch, 12:00 to 13:00 0 0 0 1 0\n" }

fn items_s4(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 30u32, start: at(2026, 10u8, 12u8, 7u8, 0u8), minutes: 30u32, all_day: false, title: "Run", rule: "FREQ=DAILY;UNTIL=20261018T235959;EXDATE=20261012T070000,20261013T070000,20261014T070000,20261015T070000,20261016T070000,20261017,20261018T070000,20261101T070000" }
    out[1usize] = sched.Item { id: 31u32, start: at(2026, 10u8, 12u8, 7u8, 0u8), minutes: 30u32, all_day: false, title: "Run, unchanged", rule: "FREQ=DAILY;COUNT=3" }
    ret 2usize
}


fn want_s4w() -> str { ret "M 20738 7 0 30 990\nP 1 T 0 29863140 29863170 60 90 120 30 0 1 0 0 1\nP 1 T 1 29864580 29864610 180 90 120 30 0 1 0 0 1\nP 1 T 2 29866020 29866050 300 90 120 30 0 1 0 0 1\nN Grid 0 0 900 990 Week schedule 0 0 3 7 0\nN ColumnHeader 60 0 120 30 Monday 12 October 2026 0 1 0 7 0\nN Cell 60 90 120 30 Run, unchanged, 07:00 to 07:30, repeats 1 1 1 7 0\nN ColumnHeader 180 0 120 30 Tuesday 13 October 2026 0 2 0 7 0\nN Cell 180 90 120 30 Run, unchanged, 07:00 to 07:30, repeats 1 2 1 7 0\nN ColumnHeader 300 0 120 30 Wednesday 14 October 2026 0 3 0 7 0\nN Cell 300 90 120 30 Run, unchanged, 07:00 to 07:30, repeats 1 3 1 7 0\nN ColumnHeader 420 0 120 30 Thursday 15 October 2026 0 4 0 7 0\nN ColumnHeader 540 0 120 30 Friday 16 October 2026 0 5 0 7 0\nN ColumnHeader 660 0 120 30 Saturday 17 October 2026 0 6 0 7 0\nN ColumnHeader 780 0 120 30 Sunday 18 October 2026 0 7 0 7 0\n" }


fn want_s4a() -> str { ret "M 20738 14 0 30 144\nP 1 T 0 29863140 29863170 0 24 900 24 0 1 0 0 1\nP 1 T 1 29864580 29864610 0 72 900 24 0 1 0 0 1\nP 1 T 2 29866020 29866050 0 120 900 24 0 1 0 0 1\nR H 0 0 0 24\nR E 0 0 24 24\nR H 1 0 48 24\nR E 1 1 72 24\nR H 2 0 96 24\nR E 2 2 120 24\nN List 0 0 900 144 Agenda 0 0 3 1 0\nN Heading 0 0 900 24 Monday 12 October 2026 0 0 0 1 2\nN ListItem 0 24 900 24 Run, unchanged, 07:00 to 07:30, repeats 0 0 0 1 0\nN Heading 0 48 900 24 Tuesday 13 October 2026 0 0 0 1 2\nN ListItem 0 72 900 24 Run, unchanged, 07:00 to 07:30, repeats 0 0 0 1 0\nN Heading 0 96 900 24 Wednesday 14 October 2026 0 0 0 1 2\nN ListItem 0 120 900 24 Run, unchanged, 07:00 to 07:30, repeats 0 0 0 1 0\n" }

fn at(year: i32, month: u8, day: u8, hour: u8, minute: u8) -> calendar.DateTime {
    var t: time.Time = zero
    t.hour = hour
    t.minute = minute
    ret calendar.DateTime { date: time.Date { year: year, month: month, day: day }, time: t }
}

fn role_name(r: accessibility.Role) -> str {
    if r == .Grid { ret "Grid" }
    if r == .ColumnHeader { ret "ColumnHeader" }
    if r == .Cell { ret "Cell" }
    if r == .List { ret "List" }
    if r == .Heading { ret "Heading" }
    if r == .ListItem { ret "ListItem" }
    ret "Other"
}

fn num(b: *str.Builder, v: f32) -> err {
    ret str.push_u32(b, u32(v))
}

fn flag(b: *str.Builder, v: bool) -> err {
    if v { ret str.push(b, "1") }
    ret str.push(b, "0")
}

// The layout in the model's row format.
fn render(b: *str.Builder, l: *const sched.Layout) -> err {
    try str.push(b, "M ")
    try str.push_u64(b, u64(l.first_day))
    try str.push(b, " ")
    try str.push_u64(b, u64(l.days))
    try str.push(b, " ")
    try num(b, l.band_h)
    try str.push(b, " ")
    try num(b, l.grid_top)
    try str.push(b, " ")
    try num(b, l.height)
    try str.push(b, "\n")
    var i = 0usize
    while i < l.placed_count {
        let p = l.placed[i]
        try str.push(b, "P ")
        try str.push_u32(b, p.item)
        if p.kind == .AllDay {
            try str.push(b, " A ")
        } else {
            try str.push(b, " T ")
        }
        try str.push_u32(b, p.day)
        try str.push(b, " ")
        try str.push_u64(b, u64(p.start))
        try str.push(b, " ")
        try str.push_u64(b, u64(p.end))
        try str.push(b, " ")
        try num(b, p.x)
        try str.push(b, " ")
        try num(b, p.y)
        try str.push(b, " ")
        try num(b, p.w)
        try str.push(b, " ")
        try num(b, p.h)
        try str.push(b, " ")
        try str.push_u32(b, p.lane)
        try str.push(b, " ")
        try str.push_u32(b, p.lanes)
        try str.push(b, " ")
        try flag(b, p.before)
        try str.push(b, " ")
        try flag(b, p.after)
        try str.push(b, " ")
        try flag(b, p.recurring)
        try str.push(b, "\n")
        i += 1usize
    }
    i = 0usize
    while i < l.row_count {
        let r = l.rows[i]
        try str.push(b, "R ")
        if r.kind == .DayHeader {
            try str.push(b, "H ")
        } else {
            try str.push(b, "E ")
        }
        try str.push_u32(b, r.day)
        try str.push(b, " ")
        try str.push_u32(b, r.placed)
        try str.push(b, " ")
        try num(b, r.y)
        try str.push(b, " ")
        try num(b, r.h)
        try str.push(b, "\n")
        i += 1usize
    }
    i = 0usize
    while i < l.node_count {
        let n = l.nodes[i]
        try str.push(b, "N ")
        try str.push(b, role_name(n.role))
        try str.push(b, " ")
        try num(b, n.x)
        try str.push(b, " ")
        try num(b, n.y)
        try str.push(b, " ")
        try num(b, n.w)
        try str.push(b, " ")
        try num(b, n.h)
        try str.push(b, " ")
        try str.push(b, sched.label_of(l, i))
        try str.push(b, " ")
        try str.push_u32(b, n.row)
        try str.push(b, " ")
        try str.push_u32(b, n.column)
        try str.push(b, " ")
        try str.push_u32(b, n.row_count)
        try str.push(b, " ")
        try str.push_u32(b, n.column_count)
        try str.push(b, " ")
        try str.push_u32(b, u32(n.level))
        try str.push(b, "\n")
        i += 1usize
    }
    ret ok
}

// The integer at `at` in a comma list; the next position (after the separator).

fn storage(a: *mem.Arena, occ: usize, stamps: usize, placed: usize, labels: usize) -> (sched.Storage, err) {
    let (o, e1) = mem.alloc[sched.Occ](a, occ)
    if e1 != ok { ret (zero, e1) }
    let (s, e2) = mem.alloc[calendar.DateTime](a, stamps)
    if e2 != ok { ret (zero, e2) }
    let (p, e3) = mem.alloc[sched.Placed](a, placed)
    if e3 != ok { ret (zero, e3) }
    let (c, e4) = mem.alloc[sched.Column](a, 8usize)
    if e4 != ok { ret (zero, e4) }
    let (r, e5) = mem.alloc[sched.Row](a, placed * 2usize + 8usize)
    if e5 != ok { ret (zero, e5) }
    let (n, e6) = mem.alloc[sched.Access](a, placed + 16usize)
    if e6 != ok { ret (zero, e6) }
    let (lb, e7) = mem.alloc[u8](a, labels)
    if e7 != ok { ret (zero, e7) }
    let (ord, e8) = mem.alloc[u32](a, occ)
    if e8 != ok { ret (zero, e8) }
    let (le, e9) = mem.alloc[i64](a, occ)
    if e9 != ok { ret (zero, e9) }
    ret (sched.Storage { occ: o, stamps: s, placed: p, columns: c, rows: r, nodes: n, labels: lb, order: ord, lane_end: le }, ok)
}


fn run_view(a: *mem.Arena, st: sched.Storage, raw: []const sched.Item, cfg: sched.Config, want: str) -> u32 {
    let (l, build_error) = sched.build(raw, cfg, st)
    if build_error != ok { ret 1u32 }
    let (bld, bld_error) = str.builder(a, 16384usize)
    if bld_error != ok { ret 2u32 }
    var bb = bld
    if render(&bb, &l) != ok { ret 3u32 }
    let got = str.done(&bb)
    if !str.eq(got, want) {
        let shown = io.print(got)
        ret 4u32
    }
    ret 0u32
}

fn run_ops(st: sched.Storage) -> u32 {
    var w: sched.Item = zero
    w.id = 5u32
    w.start = at(2026, 3u8, 2u8, 9u8, 30u8)
    w.minutes = 60u32
    w.all_day = false
    w.title = "S"
    w.rule = "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10"
    var buf: [128]u8 = zero
    let (c1, e1) = sched.cancel_occurrence(w, at(2026, 3u8, 2u8, 9u8, 30u8), buf[0usize..128usize])
    if !(e1 == ok && str.eq(c1.rule, "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10;EXDATE=20260302T093000")) { ret 1u32 }
    var buf2: [128]u8 = zero
    let (c2, e2) = sched.cancel_occurrence(c1, at(2026, 3u8, 11u8, 9u8, 30u8), buf2[0usize..128usize])
    if !(e2 == ok && str.eq(c2.rule, "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10;EXDATE=20260302T093000,20260311T093000")) { ret 2u32 }
    var buf3: [128]u8 = zero
    let (c3, e3) = sched.cancel_occurrence(c2, at(2026, 3u8, 11u8, 9u8, 30u8), buf3[0usize..128usize])
    if !(e3 == ok && str.eq(c3.rule, "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10;EXDATE=20260302T093000,20260311T093000")) { ret 3u32 }
    let (x1, ex1) = sched.cancel_occurrence(w, at(2026, 3u8, 2u8, 10u8, 0u8), buf[0usize..128usize])
    if !(ex1 == sched.Invalid) { ret 4u32 }
    let (x2, ex2) = sched.cancel_occurrence(w, at(2026, 3u8, 3u8, 9u8, 30u8), buf[0usize..128usize])
    if !(ex2 == sched.Invalid) { ret 5u32 }
    let (x3, ex3) = sched.cancel_occurrence(w, at(2026, 2u8, 23u8, 9u8, 30u8), buf[0usize..128usize])
    if !(ex3 == sched.Invalid) { ret 6u32 }
    let (x4, ex4) = sched.cancel_occurrence(w, at(2026, 4u8, 20u8, 9u8, 30u8), buf[0usize..128usize])
    if !(ex4 == sched.Invalid) { ret 7u32 }
    var plain: sched.Item = zero
    plain.id = 5u32
    plain.start = at(2026, 3u8, 2u8, 9u8, 30u8)
    plain.minutes = 30u32
    plain.all_day = false
    plain.title = "S"
    plain.rule = ""
    let (x5, ex5) = sched.cancel_occurrence(plain, at(2026, 3u8, 2u8, 9u8, 30u8), buf[0usize..128usize])
    if !(ex5 == sched.Invalid) { ret 8u32 }
    var tiny: [20]u8 = zero
    let (x6, ex6) = sched.cancel_occurrence(w, at(2026, 3u8, 2u8, 9u8, 30u8), tiny[0usize..20usize])
    if !(ex6 == sched.TooLarge) { ret 9u32 }
    var ad: sched.Item = zero
    ad.id = 5u32
    ad.start = at(2026, 6u8, 1u8, 0u8, 0u8)
    ad.minutes = 1440u32
    ad.all_day = true
    ad.title = "Trash"
    ad.rule = "FREQ=DAILY;COUNT=20"
    var buf4: [128]u8 = zero
    let (a1, ae1) = sched.cancel_occurrence(ad, at(2026, 6u8, 4u8, 0u8, 0u8), buf4[0usize..128usize])
    if !(ae1 == ok && str.eq(a1.rule, "FREQ=DAILY;COUNT=20;EXDATE=20260604")) { ret 10u32 }
    var buf5: [128]u8 = zero
    let (ms, mo, me) = sched.move_occurrence(w, at(2026, 3u8, 4u8, 9u8, 30u8), at(2026, 3u8, 12u8, 16u8, 45u8), 75u32, buf5[0usize..128usize])
    if !(me == ok && str.eq(ms.rule, "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10;EXDATE=20260304T093000") && mo.rule.len == 0usize && mo.minutes == 75u32 && mo.id == 5u32 && mo.start.date.day == 12u8 && mo.start.time.hour == 16u8 && mo.start.time.minute == 45u8) { ret 11u32 }
    var m: sched.Item = zero
    m.id = 5u32
    m.start = at(2026, 3u8, 2u8, 9u8, 30u8)
    m.minutes = 60u32
    m.all_day = false
    m.title = "S"
    m.rule = "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10;EXDATE=20260302T093000,20260311T093000"
    var buf6: [160]u8 = zero
    let (mv, mve) = sched.move_series(m, at(2026, 3u8, 2u8, 9u8, 30u8), at(2026, 3u8, 3u8, 10u8, 0u8), buf6[0usize..160usize])
    if !(mve == ok && str.eq(mv.rule, "FREQ=WEEKLY;BYDAY=TU,TH;COUNT=10;EXDATE=20260303T100000,20260312T100000")) { ret 12u32 }
    var mad: sched.Item = zero
    mad.id = 5u32
    mad.start = at(2026, 6u8, 1u8, 0u8, 0u8)
    mad.minutes = 1440u32
    mad.all_day = true
    mad.title = "S"
    mad.rule = "FREQ=DAILY;COUNT=20;EXDATE=20260604,20260610"
    var buf7: [160]u8 = zero
    let (mv2, mve2) = sched.move_series(mad, at(2026, 6u8, 1u8, 0u8, 0u8), at(2026, 6u8, 3u8, 0u8, 0u8), buf7[0usize..160usize])
    if !(mve2 == ok && str.eq(mv2.rule, "FREQ=DAILY;COUNT=20;EXDATE=20260606,20260612")) { ret 13u32 }
    var mid: sched.Item = zero
    mid.id = 5u32
    mid.start = at(2026, 3u8, 2u8, 9u8, 30u8)
    mid.minutes = 60u32
    mid.all_day = false
    mid.title = "S"
    mid.rule = "FREQ=DAILY;EXDATE=20260302T093000;COUNT=3"
    var items_bad: [1]sched.Item = zero
    items_bad[0usize] = mid
    var bad_cfg = cfg_a()
    let (bl, be) = sched.build(items_bad[0usize..1usize], bad_cfg, st)
    if !(be == sched.Invalid) { ret 14u32 }
    ret 0u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (st, st_error) = storage(a, 256usize, 128usize, 256usize, 16384usize)
    if st_error != ok { os.exit(100) }
    var raw_s1: [32]sched.Item = zero
    let n_s1 = items_s1(raw_s1[0usize..32usize])
    if run_view(a, st, raw_s1[0usize..n_s1], cfg_w(), want_s1w()) != 0u32 { os.exit(3) }
    if run_view(a, st, raw_s1[0usize..n_s1], cfg_a(), want_s1a()) != 0u32 { os.exit(4) }
    var raw_s2: [32]sched.Item = zero
    let n_s2 = items_s2(raw_s2[0usize..32usize])
    if run_view(a, st, raw_s2[0usize..n_s2], cfg_w(), want_s2w()) != 0u32 { os.exit(7) }
    if run_view(a, st, raw_s2[0usize..n_s2], cfg_a(), want_s2a()) != 0u32 { os.exit(8) }
    var raw_s3: [32]sched.Item = zero
    let n_s3 = items_s3(raw_s3[0usize..32usize])
    if run_view(a, st, raw_s3[0usize..n_s3], cfg_w(), want_s3w()) != 0u32 { os.exit(11) }
    if run_view(a, st, raw_s3[0usize..n_s3], cfg_a(), want_s3a()) != 0u32 { os.exit(12) }
    var raw_s4: [32]sched.Item = zero
    let n_s4 = items_s4(raw_s4[0usize..32usize])
    if run_view(a, st, raw_s4[0usize..n_s4], cfg_w(), want_s4w()) != 0u32 { os.exit(15) }
    if run_view(a, st, raw_s4[0usize..n_s4], cfg_a(), want_s4a()) != 0u32 { os.exit(16) }
    let ops_result = run_ops(st)
    if ops_result != 0u32 { os.exit(i32(100u32 + ops_result)) }
    try io.print("ui schedule exceptions ok\n")
    ret ok
}
