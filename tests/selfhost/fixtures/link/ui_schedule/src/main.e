// `e.ui.schedule` (L148): one item table (timed, all-day, overnight, overlapping runs,
// weekly/monthly/daily recurrences) laid out as a Monday-start week, a Sunday-start week,
// a day and a ten-day agenda, compared row by row (placed rectangles and lanes, agenda rows,
// the accessible tree with roles, labels and positions) with the independent model in
// scripts/gen_schedule_test.py (python-dateutil recurrence, its own overlap columns). Then
// the hit regions, drag-to-create ranges against the model's snapping, and the refusals:
// a bad rule, an inverted hour window, a truncated endless rule and a storage too small.
// Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.str
use e.time
use e.time.calendar
use e.ui.accessibility
use e.ui.schedule as sched

// BEGIN SCENARIOS
fn main_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 10u8, 12u8, 9u8, 0u8), minutes: 30u32, all_day: false, title: "Standup", rule: "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=10" }
    out[1usize] = sched.Item { id: 2u32, start: at(2026, 10u8, 13u8, 10u8, 0u8), minutes: 90u32, all_day: false, title: "Design review", rule: "" }
    out[2usize] = sched.Item { id: 3u32, start: at(2026, 10u8, 13u8, 10u8, 30u8), minutes: 60u32, all_day: false, title: "Lunch", rule: "" }
    out[3usize] = sched.Item { id: 4u32, start: at(2026, 10u8, 13u8, 11u8, 0u8), minutes: 30u32, all_day: false, title: "Call", rule: "" }
    out[4usize] = sched.Item { id: 5u32, start: at(2026, 10u8, 14u8, 13u8, 0u8), minutes: 180u32, all_day: false, title: "Workshop", rule: "" }
    out[5usize] = sched.Item { id: 6u32, start: at(2026, 10u8, 14u8, 6u8, 0u8), minutes: 60u32, all_day: false, title: "Early", rule: "" }
    out[6usize] = sched.Item { id: 7u32, start: at(2026, 10u8, 15u8, 19u8, 0u8), minutes: 360u32, all_day: false, title: "Overnight", rule: "" }
    out[7usize] = sched.Item { id: 8u32, start: at(2026, 10u8, 14u8, 0u8, 0u8), minutes: 2880u32, all_day: true, title: "Conference", rule: "" }
    out[8usize] = sched.Item { id: 9u32, start: at(2026, 10u8, 16u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "Holiday", rule: "" }
    out[9usize] = sched.Item { id: 10u32, start: at(2026, 10u8, 7u8, 15u8, 0u8), minutes: 60u32, all_day: false, title: "Weekly sync", rule: "FREQ=WEEKLY;INTERVAL=1;COUNT=4" }
    out[10usize] = sched.Item { id: 11u32, start: at(2026, 7u8, 15u8, 10u8, 0u8), minutes: 60u32, all_day: false, title: "Monthly", rule: "FREQ=MONTHLY;BYMONTHDAY=15" }
    out[11usize] = sched.Item { id: 12u32, start: at(2026, 10u8, 16u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Chain A", rule: "" }
    out[12usize] = sched.Item { id: 13u32, start: at(2026, 10u8, 16u8, 9u8, 30u8), minutes: 60u32, all_day: false, title: "Chain B", rule: "" }
    out[13usize] = sched.Item { id: 14u32, start: at(2026, 10u8, 16u8, 10u8, 15u8), minutes: 45u32, all_day: false, title: "Chain C", rule: "" }
    out[14usize] = sched.Item { id: 15u32, start: at(2026, 10u8, 16u8, 9u8, 0u8), minutes: 120u32, all_day: false, title: "Chain D", rule: "" }
    out[15usize] = sched.Item { id: 16u32, start: at(2026, 10u8, 17u8, 12u8, 0u8), minutes: 0u32, all_day: false, title: "Zero length", rule: "" }
    out[16usize] = sched.Item { id: 17u32, start: at(2026, 10u8, 12u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "Standing", rule: "FREQ=WEEKLY;COUNT=3" }
    ret 17usize
}

fn cfg_w1() -> sched.Config {
    ret sched.Config { mode: .Week, anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Monday, day_start: 8u32, day_end: 20u32, slot: 30u32, agenda_days: 10u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn want_w1() -> str { ret "M 20738 7 20 50 770\nP 16 A 0 29862720 29864160 60 30 120 20 0 1 0 0 1\nP 0 T 0 29863260 29863290 60 110 120 30 0 1 0 0 1\nP 0 T 1 29864700 29864730 180 110 120 30 0 1 0 0 1\nP 1 T 1 29864760 29864850 180 170 40 90 0 3 0 0 0\nP 2 T 1 29864790 29864850 220 200 40 60 1 3 0 0 0\nP 3 T 1 29864820 29864850 260 230 40 30 2 3 0 0 0\nP 7 A 2 29865600 29868480 300 30 120 20 0 1 0 1 0\nP 0 T 2 29866140 29866170 300 110 120 30 0 1 0 0 1\nP 4 T 2 29866380 29866560 300 350 60 180 0 2 0 0 0\nP 9 T 2 29866500 29866560 360 470 60 60 1 2 0 0 1\nP 7 A 3 29865600 29868480 420 30 120 20 0 1 1 0 0\nP 0 T 3 29867580 29867610 420 110 120 30 0 1 0 0 1\nP 10 T 3 29867640 29867700 420 170 120 60 0 1 0 0 1\nP 6 T 3 29868180 29868240 420 710 120 60 0 1 0 1 0\nP 8 A 4 29868480 29869920 540 30 120 20 0 1 0 0 0\nP 14 T 4 29869020 29869140 540 110 40 120 0 3 0 0 0\nP 11 T 4 29869020 29869080 580 110 40 60 1 3 0 0 0\nP 0 T 4 29869020 29869050 620 110 40 30 2 3 0 0 1\nP 12 T 4 29869050 29869110 620 140 40 60 2 3 0 0 0\nP 13 T 4 29869095 29869140 580 185 40 45 1 3 0 0 0\nP 15 T 5 29870640 29870641 660 290 120 12 0 1 0 0 0\nN Grid 0 0 900 770 Week schedule 0 0 21 7 0\nN ColumnHeader 60 0 120 30 Monday 12 October 2026 0 1 0 7 0\nN Cell 60 30 120 20 Standing, all day, repeats 1 1 2 7 0\nN Cell 60 110 120 30 Standup, 09:00 to 09:30, repeats 2 1 2 7 0\nN ColumnHeader 180 0 120 30 Tuesday 13 October 2026 0 2 0 7 0\nN Cell 180 110 120 30 Standup, 09:00 to 09:30, repeats 1 2 4 7 0\nN Cell 180 170 40 90 Design review, 10:00 to 11:30 2 2 4 7 0\nN Cell 220 200 40 60 Lunch, 10:30 to 11:30 3 2 4 7 0\nN Cell 260 230 40 30 Call, 11:00 to 11:30 4 2 4 7 0\nN ColumnHeader 300 0 120 30 Wednesday 14 October 2026 0 3 0 7 0\nN Cell 300 30 120 20 Conference, all day 1 3 4 7 0\nN Cell 300 110 120 30 Standup, 09:00 to 09:30, repeats 2 3 4 7 0\nN Cell 300 350 60 180 Workshop, 13:00 to 16:00 3 3 4 7 0\nN Cell 360 470 60 60 Weekly sync, 15:00 to 16:00, repeats 4 3 4 7 0\nN ColumnHeader 420 0 120 30 Thursday 15 October 2026 0 4 0 7 0\nN Cell 420 30 120 20 Conference, all day 1 4 4 7 0\nN Cell 420 110 120 30 Standup, 09:00 to 09:30, repeats 2 4 4 7 0\nN Cell 420 170 120 60 Monthly, 10:00 to 11:00, repeats 3 4 4 7 0\nN Cell 420 710 120 60 Overnight, 19:00 to 20:00 4 4 4 7 0\nN ColumnHeader 540 0 120 30 Friday 16 October 2026 0 5 0 7 0\nN Cell 540 30 120 20 Holiday, all day 1 5 6 7 0\nN Cell 540 110 40 120 Chain D, 09:00 to 11:00 2 5 6 7 0\nN Cell 580 110 40 60 Chain A, 09:00 to 10:00 3 5 6 7 0\nN Cell 620 110 40 30 Standup, 09:00 to 09:30, repeats 4 5 6 7 0\nN Cell 620 140 40 60 Chain B, 09:30 to 10:30 5 5 6 7 0\nN Cell 580 185 40 45 Chain C, 10:15 to 11:00 6 5 6 7 0\nN ColumnHeader 660 0 120 30 Saturday 17 October 2026 0 6 0 7 0\nN Cell 660 290 120 12 Zero length, 12:00 to 12:01 1 6 1 7 0\nN ColumnHeader 780 0 120 30 Sunday 18 October 2026 0 7 0 7 0\n" }

fn probes_w1() -> str { ret "61,31,2,0,0;61,111,1,1,0;181,111,1,2,1;181,171,1,3,1;221,201,1,4,1;261,231,1,5,1;301,31,2,6,2;301,111,1,7,2;301,351,1,8,2;361,471,1,9,2;421,31,2,10,3;421,111,1,11,3;421,171,1,12,3;421,711,1,13,3;541,31,2,14,4;541,111,1,15,4;581,111,1,16,4;621,111,1,17,4;621,141,1,18,4;581,186,1,19,4;661,291,1,20,5;10,100,5,0,0;70,10,4,0,0;200,10,4,1,1;65,55,3,0,480;185,383,3,1,810;905,50,0,0,0;30,100,5,0,0;65,780,0,0,0;300,769,3,2,1170" }

fn drags_w1() -> str { ret "70,85,70,150,1,0,29863230,90;190,250,190,200,1,1,29864790,60;70,111,70,112,1,0,29863260,30;70,750,70,950,1,0,29863890,30;70,60,70,10,1,0,29863200,30;5,5,100,100,0,0,0,0" }

fn cfg_w2() -> sched.Config {
    ret sched.Config { mode: .Week, anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Sunday, day_start: 8u32, day_end: 20u32, slot: 30u32, agenda_days: 10u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn want_w2() -> str { ret "M 20737 7 20 50 770\nP 16 A 1 29862720 29864160 180 30 120 20 0 1 0 0 1\nP 0 T 1 29863260 29863290 180 110 120 30 0 1 0 0 1\nP 0 T 2 29864700 29864730 300 110 120 30 0 1 0 0 1\nP 1 T 2 29864760 29864850 300 170 40 90 0 3 0 0 0\nP 2 T 2 29864790 29864850 340 200 40 60 1 3 0 0 0\nP 3 T 2 29864820 29864850 380 230 40 30 2 3 0 0 0\nP 7 A 3 29865600 29868480 420 30 120 20 0 1 0 1 0\nP 0 T 3 29866140 29866170 420 110 120 30 0 1 0 0 1\nP 4 T 3 29866380 29866560 420 350 60 180 0 2 0 0 0\nP 9 T 3 29866500 29866560 480 470 60 60 1 2 0 0 1\nP 7 A 4 29865600 29868480 540 30 120 20 0 1 1 0 0\nP 0 T 4 29867580 29867610 540 110 120 30 0 1 0 0 1\nP 10 T 4 29867640 29867700 540 170 120 60 0 1 0 0 1\nP 6 T 4 29868180 29868240 540 710 120 60 0 1 0 1 0\nP 8 A 5 29868480 29869920 660 30 120 20 0 1 0 0 0\nP 14 T 5 29869020 29869140 660 110 40 120 0 3 0 0 0\nP 11 T 5 29869020 29869080 700 110 40 60 1 3 0 0 0\nP 0 T 5 29869020 29869050 740 110 40 30 2 3 0 0 1\nP 12 T 5 29869050 29869110 740 140 40 60 2 3 0 0 0\nP 13 T 5 29869095 29869140 700 185 40 45 1 3 0 0 0\nP 15 T 6 29870640 29870641 780 290 120 12 0 1 0 0 0\nN Grid 0 0 900 770 Week schedule 0 0 21 7 0\nN ColumnHeader 60 0 120 30 Sunday 11 October 2026 0 1 0 7 0\nN ColumnHeader 180 0 120 30 Monday 12 October 2026 0 2 0 7 0\nN Cell 180 30 120 20 Standing, all day, repeats 1 2 2 7 0\nN Cell 180 110 120 30 Standup, 09:00 to 09:30, repeats 2 2 2 7 0\nN ColumnHeader 300 0 120 30 Tuesday 13 October 2026 0 3 0 7 0\nN Cell 300 110 120 30 Standup, 09:00 to 09:30, repeats 1 3 4 7 0\nN Cell 300 170 40 90 Design review, 10:00 to 11:30 2 3 4 7 0\nN Cell 340 200 40 60 Lunch, 10:30 to 11:30 3 3 4 7 0\nN Cell 380 230 40 30 Call, 11:00 to 11:30 4 3 4 7 0\nN ColumnHeader 420 0 120 30 Wednesday 14 October 2026 0 4 0 7 0\nN Cell 420 30 120 20 Conference, all day 1 4 4 7 0\nN Cell 420 110 120 30 Standup, 09:00 to 09:30, repeats 2 4 4 7 0\nN Cell 420 350 60 180 Workshop, 13:00 to 16:00 3 4 4 7 0\nN Cell 480 470 60 60 Weekly sync, 15:00 to 16:00, repeats 4 4 4 7 0\nN ColumnHeader 540 0 120 30 Thursday 15 October 2026 0 5 0 7 0\nN Cell 540 30 120 20 Conference, all day 1 5 4 7 0\nN Cell 540 110 120 30 Standup, 09:00 to 09:30, repeats 2 5 4 7 0\nN Cell 540 170 120 60 Monthly, 10:00 to 11:00, repeats 3 5 4 7 0\nN Cell 540 710 120 60 Overnight, 19:00 to 20:00 4 5 4 7 0\nN ColumnHeader 660 0 120 30 Friday 16 October 2026 0 6 0 7 0\nN Cell 660 30 120 20 Holiday, all day 1 6 6 7 0\nN Cell 660 110 40 120 Chain D, 09:00 to 11:00 2 6 6 7 0\nN Cell 700 110 40 60 Chain A, 09:00 to 10:00 3 6 6 7 0\nN Cell 740 110 40 30 Standup, 09:00 to 09:30, repeats 4 6 6 7 0\nN Cell 740 140 40 60 Chain B, 09:30 to 10:30 5 6 6 7 0\nN Cell 700 185 40 45 Chain C, 10:15 to 11:00 6 6 6 7 0\nN ColumnHeader 780 0 120 30 Saturday 17 October 2026 0 7 0 7 0\nN Cell 780 290 120 12 Zero length, 12:00 to 12:01 1 7 1 7 0\n" }

fn cfg_d1() -> sched.Config {
    ret sched.Config { mode: .Day, anchor: time.Date { year: 2026, month: 10u8, day: 16u8 }, week_start: .Monday, day_start: 8u32, day_end: 20u32, slot: 30u32, agenda_days: 10u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn want_d1() -> str { ret "M 20742 1 20 50 770\nP 8 A 0 29868480 29869920 60 30 840 20 0 1 0 0 0\nP 14 T 0 29869020 29869140 60 110 280 120 0 3 0 0 0\nP 11 T 0 29869020 29869080 340 110 280 60 1 3 0 0 0\nP 0 T 0 29869020 29869050 620 110 280 30 2 3 0 0 1\nP 12 T 0 29869050 29869110 620 140 280 60 2 3 0 0 0\nP 13 T 0 29869095 29869140 340 185 280 45 1 3 0 0 0\nN Grid 0 0 900 770 Day schedule 0 0 6 1 0\nN ColumnHeader 60 0 840 30 Friday 16 October 2026 0 1 0 1 0\nN Cell 60 30 840 20 Holiday, all day 1 1 6 1 0\nN Cell 60 110 280 120 Chain D, 09:00 to 11:00 2 1 6 1 0\nN Cell 340 110 280 60 Chain A, 09:00 to 10:00 3 1 6 1 0\nN Cell 620 110 280 30 Standup, 09:00 to 09:30, repeats 4 1 6 1 0\nN Cell 620 140 280 60 Chain B, 09:30 to 10:30 5 1 6 1 0\nN Cell 340 185 280 45 Chain C, 10:15 to 11:00 6 1 6 1 0\n" }

fn probes_d1() -> str { ret "61,31,2,0,0;61,111,1,1,0;341,111,1,2,0;621,111,1,3,0;621,141,1,4,0;341,186,1,5,0;10,100,5,0,0;70,10,4,0,0;200,10,4,0,0;65,55,3,0,480;185,383,3,0,810;905,50,0,0,0;30,100,5,0,0;65,780,0,0,0;300,769,3,0,1170" }

fn drags_d1() -> str { ret "70,85,70,150,1,0,29868990,90;190,250,190,200,1,0,29869110,60;70,111,70,112,1,0,29869020,30;70,750,70,950,1,0,29869650,30;70,60,70,10,1,0,29868960,30;5,5,100,100,0,0,0,0" }

fn cfg_a1() -> sched.Config {
    ret sched.Config { mode: .Agenda, anchor: time.Date { year: 2026, month: 10u8, day: 12u8 }, week_start: .Monday, day_start: 8u32, day_end: 20u32, slot: 30u32, agenda_days: 10u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn want_a1() -> str { ret "M 20738 10 0 30 888\nP 16 A 0 29862720 29864160 0 24 900 24 0 1 0 0 1\nP 0 T 0 29863260 29863290 0 48 900 24 0 1 0 0 1\nP 0 T 1 29864700 29864730 0 96 900 24 0 1 0 0 1\nP 1 T 1 29864760 29864850 0 120 900 24 0 1 0 0 0\nP 2 T 1 29864790 29864850 0 144 900 24 0 1 0 0 0\nP 3 T 1 29864820 29864850 0 168 900 24 0 1 0 0 0\nP 7 A 2 29865600 29867040 0 216 900 24 0 1 0 1 0\nP 5 T 2 29865960 29866020 0 240 900 24 0 1 0 0 0\nP 0 T 2 29866140 29866170 0 264 900 24 0 1 0 0 1\nP 4 T 2 29866380 29866560 0 288 900 24 0 1 0 0 0\nP 9 T 2 29866500 29866560 0 312 900 24 0 1 0 0 1\nP 7 A 3 29867040 29868480 0 360 900 24 0 1 1 0 0\nP 0 T 3 29867580 29867610 0 384 900 24 0 1 0 0 1\nP 10 T 3 29867640 29867700 0 408 900 24 0 1 0 0 1\nP 6 T 3 29868180 29868480 0 432 900 24 0 1 0 1 0\nP 8 A 4 29868480 29869920 0 480 900 24 0 1 0 0 0\nP 6 T 4 29868480 29868540 0 504 900 24 0 1 1 0 0\nP 14 T 4 29869020 29869140 0 528 900 24 0 1 0 0 0\nP 11 T 4 29869020 29869080 0 552 900 24 0 1 0 0 0\nP 0 T 4 29869020 29869050 0 576 900 24 0 1 0 0 1\nP 12 T 4 29869050 29869110 0 600 900 24 0 1 0 0 0\nP 13 T 4 29869095 29869140 0 624 900 24 0 1 0 0 0\nP 15 T 5 29870640 29870641 0 672 900 24 0 1 0 0 0\nP 16 A 7 29872800 29874240 0 720 900 24 0 1 0 0 1\nP 0 T 7 29873340 29873370 0 744 900 24 0 1 0 0 1\nP 0 T 8 29874780 29874810 0 792 900 24 0 1 0 0 1\nP 0 T 9 29876220 29876250 0 840 900 24 0 1 0 0 1\nP 9 T 9 29876580 29876640 0 864 900 24 0 1 0 0 1\nR H 0 0 0 24\nR E 0 0 24 24\nR E 0 1 48 24\nR H 1 0 72 24\nR E 1 2 96 24\nR E 1 3 120 24\nR E 1 4 144 24\nR E 1 5 168 24\nR H 2 0 192 24\nR E 2 6 216 24\nR E 2 7 240 24\nR E 2 8 264 24\nR E 2 9 288 24\nR E 2 10 312 24\nR H 3 0 336 24\nR E 3 11 360 24\nR E 3 12 384 24\nR E 3 13 408 24\nR E 3 14 432 24\nR H 4 0 456 24\nR E 4 15 480 24\nR E 4 16 504 24\nR E 4 17 528 24\nR E 4 18 552 24\nR E 4 19 576 24\nR E 4 20 600 24\nR E 4 21 624 24\nR H 5 0 648 24\nR E 5 22 672 24\nR H 7 0 696 24\nR E 7 23 720 24\nR E 7 24 744 24\nR H 8 0 768 24\nR E 8 25 792 24\nR H 9 0 816 24\nR E 9 26 840 24\nR E 9 27 864 24\nN List 0 0 900 888 Agenda 0 0 28 1 0\nN Heading 0 0 900 24 Monday 12 October 2026 0 0 0 1 2\nN ListItem 0 24 900 24 Standing, all day, repeats 0 0 0 1 0\nN ListItem 0 48 900 24 Standup, 09:00 to 09:30, repeats 0 0 0 1 0\nN Heading 0 72 900 24 Tuesday 13 October 2026 0 0 0 1 2\nN ListItem 0 96 900 24 Standup, 09:00 to 09:30, repeats 0 0 0 1 0\nN ListItem 0 120 900 24 Design review, 10:00 to 11:30 0 0 0 1 0\nN ListItem 0 144 900 24 Lunch, 10:30 to 11:30 0 0 0 1 0\nN ListItem 0 168 900 24 Call, 11:00 to 11:30 0 0 0 1 0\nN Heading 0 192 900 24 Wednesday 14 October 2026 0 0 0 1 2\nN ListItem 0 216 900 24 Conference, all day 0 0 0 1 0\nN ListItem 0 240 900 24 Early, 06:00 to 07:00 0 0 0 1 0\nN ListItem 0 264 900 24 Standup, 09:00 to 09:30, repeats 0 0 0 1 0\nN ListItem 0 288 900 24 Workshop, 13:00 to 16:00 0 0 0 1 0\nN ListItem 0 312 900 24 Weekly sync, 15:00 to 16:00, repeats 0 0 0 1 0\nN Heading 0 336 900 24 Thursday 15 October 2026 0 0 0 1 2\nN ListItem 0 360 900 24 Conference, all day 0 0 0 1 0\nN ListItem 0 384 900 24 Standup, 09:00 to 09:30, repeats 0 0 0 1 0\nN ListItem 0 408 900 24 Monthly, 10:00 to 11:00, repeats 0 0 0 1 0\nN ListItem 0 432 900 24 Overnight, 19:00 to 00:00 0 0 0 1 0\nN Heading 0 456 900 24 Friday 16 October 2026 0 0 0 1 2\nN ListItem 0 480 900 24 Holiday, all day 0 0 0 1 0\nN ListItem 0 504 900 24 Overnight, 00:00 to 01:00 0 0 0 1 0\nN ListItem 0 528 900 24 Chain D, 09:00 to 11:00 0 0 0 1 0\nN ListItem 0 552 900 24 Chain A, 09:00 to 10:00 0 0 0 1 0\nN ListItem 0 576 900 24 Standup, 09:00 to 09:30, repeats 0 0 0 1 0\nN ListItem 0 600 900 24 Chain B, 09:30 to 10:30 0 0 0 1 0\nN ListItem 0 624 900 24 Chain C, 10:15 to 11:00 0 0 0 1 0\nN Heading 0 648 900 24 Saturday 17 October 2026 0 0 0 1 2\nN ListItem 0 672 900 24 Zero length, 12:00 to 12:01 0 0 0 1 0\nN Heading 0 696 900 24 Monday 19 October 2026 0 0 0 1 2\nN ListItem 0 720 900 24 Standing, all day, repeats 0 0 0 1 0\nN ListItem 0 744 900 24 Standup, 09:00 to 09:30, repeats 0 0 0 1 0\nN Heading 0 768 900 24 Tuesday 20 October 2026 0 0 0 1 2\nN ListItem 0 792 900 24 Standup, 09:00 to 09:30, repeats 0 0 0 1 0\nN Heading 0 816 900 24 Wednesday 21 October 2026 0 0 0 1 2\nN ListItem 0 840 900 24 Standup, 09:00 to 09:30, repeats 0 0 0 1 0\nN ListItem 0 864 900 24 Weekly sync, 15:00 to 16:00, repeats 0 0 0 1 0\n" }

fn probes_a1() -> str { ret "1,25,2,0,0;1,49,1,1,0;1,97,1,2,1;1,121,1,3,1;1,145,1,4,1;1,169,1,5,1;1,217,2,6,2;1,241,1,7,2;1,265,1,8,2;1,289,1,9,2;1,313,1,10,2;1,361,2,11,3;1,385,1,12,3;1,409,1,13,3;1,433,1,14,3;1,481,2,15,4;1,505,1,16,4;1,529,1,17,4;1,553,1,18,4;1,577,1,19,4;1,601,1,20,4;1,625,1,21,4;1,673,1,22,5;1,721,2,23,7;1,745,1,24,7;1,793,1,25,8;1,841,1,26,9;1,865,1,27,9;5,3,4,0,0;5,892,0,0,0" }

fn want_first_row() -> str { ret "M 20738 7 0 30 750\nP 0 T 0 29863260 29863290 60 90 120 30 0 1 0 0 1\nP 0 T 1 29864700 29864730 180 90 120 30 0 1 0 0 1\nP 0 T 2 29866140 29866170 300 90 120 30 0 1 0 0 1\nP 0 T 3 29867580 29867610 420 90 120 30 0 1 0 0 1\nP 0 T 4 29869020 29869050 540 90 120 30 0 1 0 0 1\nN Grid 0 0 900 750 Week schedule 0 0 5 7 0\nN ColumnHeader 60 0 120 30 Monday 12 October 2026 0 1 0 7 0\nN Cell 60 90 120 30 Standup, 09:00 to 09:30, repeats 1 1 1 7 0\nN ColumnHeader 180 0 120 30 Tuesday 13 October 2026 0 2 0 7 0\nN Cell 180 90 120 30 Standup, 09:00 to 09:30, repeats 1 2 1 7 0\nN ColumnHeader 300 0 120 30 Wednesday 14 October 2026 0 3 0 7 0\nN Cell 300 90 120 30 Standup, 09:00 to 09:30, repeats 1 3 1 7 0\nN ColumnHeader 420 0 120 30 Thursday 15 October 2026 0 4 0 7 0\nN Cell 420 90 120 30 Standup, 09:00 to 09:30, repeats 1 4 1 7 0\nN ColumnHeader 540 0 120 30 Friday 16 October 2026 0 5 0 7 0\nN Cell 540 90 120 30 Standup, 09:00 to 09:30, repeats 1 5 1 7 0\nN ColumnHeader 660 0 120 30 Saturday 17 October 2026 0 6 0 7 0\nN ColumnHeader 780 0 120 30 Sunday 18 October 2026 0 7 0 7 0\n" }

fn first_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 10u8, 12u8, 9u8, 0u8), minutes: 30u32, all_day: false, title: "Standup", rule: "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=10" }
    ret 1usize
}
// END SCENARIOS

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
fn next_int(s: str, from: usize) -> (i32, usize) {
    var i = from
    var neg = false
    if i < s.len && s[i] == 45u8 {
        neg = true
        i += 1usize
    }
    var v = 0i32
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        v = v * 10i32 + i32(s[i] - 48u8)
        i += 1usize
    }
    if neg { v = 0i32 - v }
    ret (v, i + 1usize)
}

fn kind_code(k: sched.HitKind) -> i32 {
    if k == .Event { ret 1i32 }
    if k == .AllDay { ret 2i32 }
    if k == .Slot { ret 3i32 }
    if k == .DayHeader { ret 4i32 }
    if k == .Gutter { ret 5i32 }
    ret 0i32
}

// First failing probe number plus one, or zero. A probe is "x,y,kind,a,b": for an event
// the index and day, a slot the day and minute, a header the column or row and day.
fn run_probes(l: *const sched.Layout, list: str) -> u32 {
    var at_pos = 0usize
    var n = 0u32
    while at_pos < list.len {
        let (x, p1) = next_int(list, at_pos)
        let (y, p2) = next_int(list, p1)
        let (kind, p3) = next_int(list, p2)
        let (a, p4) = next_int(list, p3)
        let (bb, p5) = next_int(list, p4)
        at_pos = p5
        n += 1u32
        let h = sched.hit(l, f32(x), f32(y))
        if kind_code(h.kind) != kind { ret n }
        if kind == 1i32 || kind == 2i32 {
            if i32(h.index) != a || i32(h.day) != bb { ret n }
        } else if kind == 3i32 {
            if i32(h.day) != a || i32(h.minute) != bb { ret n }
        } else if kind == 4i32 {
            if i32(h.index) != a || i32(h.day) != bb { ret n }
        }
    }
    ret 0u32
}

// "x0,y0,x1,y1,ok,day,start,minutes;..." drag-to-create ranges.
fn run_drags(l: *const sched.Layout, list: str) -> u32 {
    var at_pos = 0usize
    var n = 0u32
    while at_pos < list.len {
        let (x0, p1) = next_int(list, at_pos)
        let (y0, p2) = next_int(list, p1)
        let (x1, p3) = next_int(list, p2)
        let (y1, p4) = next_int(list, p3)
        let (good, p5) = next_int(list, p4)
        let (day, p6) = next_int(list, p5)
        let (start, p7) = next_int(list, p6)
        let (minutes, p8) = next_int(list, p7)
        at_pos = p8
        n += 1u32
        let (span, found) = sched.drag_range(l, f32(x0), f32(y0), f32(x1), f32(y1))
        if found != (good == 1i32) { ret n }
        if found {
            let abs = calendar.day_count(span.start.date) * 1440i64 + i64(span.start.time.hour) * 60i64 + i64(span.start.time.minute)
            if i32(span.day) != day || abs != i64(start) || i32(span.minutes) != minutes { ret n }
        }
    }
    ret 0u32
}

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

fn main(a: *mem.Arena, args: []str) -> err {
    var raw: [32]sched.Item = zero
    let n = main_items(raw[0..])
    let (st, st_error) = storage(a, 128usize, 64usize, 128usize, 8192usize)
    if st_error != ok { os.exit(1) }

    // Four views against the model: rows, probes and drags.
    var which = 0usize
    while which < 4usize {
        var cfg = cfg_w1()
        var want: str = ""
        var probes: str = ""
        var drags: str = ""
        if which == 0usize {
            want = want_w1()
            probes = probes_w1()
            drags = drags_w1()
        } else if which == 1usize {
            cfg = cfg_w2()
            want = want_w2()
        } else if which == 2usize {
            cfg = cfg_d1()
            want = want_d1()
            probes = probes_d1()
            drags = drags_d1()
        } else {
            cfg = cfg_a1()
            want = want_a1()
            probes = probes_a1()
        }
        let (l, build_error) = sched.build(raw[0usize..n], cfg, st)
        if build_error != ok { os.exit(2 + i32(which)) }
        let (bld, bld_error) = str.builder(a, 16384usize)
        if bld_error != ok { os.exit(6) }
        var bb = bld
        if render(&bb, &l) != ok { os.exit(7) }
        let got = str.done(&bb)
        if !str.eq(got, want) {
            try io.print(got)
            os.exit(10 + i32(which))
        }
        if l.truncated { os.exit(14) }
        if probes.len > 0usize && run_probes(&l, probes) != 0u32 { os.exit(20 + i32(which)) }
        if drags.len > 0usize && run_drags(&l, drags) != 0u32 { os.exit(30 + i32(which)) }
        which += 1usize
    }

    // Refusals and truncation.
    var bad = raw
    bad[0usize].rule = "FREQ=SOMETIMES"
    let (_, bad_rule) = sched.build(bad[0usize..n], cfg_w1(), st)
    if bad_rule != sched.Invalid { os.exit(40) }
    var inverted = cfg_w1()
    inverted.day_start = 20u32
    inverted.day_end = 8u32
    let (_, bad_window) = sched.build(raw[0usize..n], inverted, st)
    if bad_window != sched.Invalid { os.exit(41) }
    var no_slot = cfg_w1()
    no_slot.slot = 0u32
    let (_, bad_slot) = sched.build(raw[0usize..n], no_slot, st)
    if bad_slot != sched.Invalid { os.exit(42) }
    let (tiny, tiny_error) = storage(a, 3usize, 8usize, 3usize, 64usize)
    if tiny_error != ok { os.exit(43) }
    let (_, too_small) = sched.build(raw[0usize..n], cfg_w1(), tiny)
    if too_small != sched.TooLarge { os.exit(44) }
    // One endless-ish rule read into a two-stamp scratch: shown, and marked truncated.
    var first: [2]sched.Item = zero
    let n_first = first_items(first[0..])
    let (two, two_error) = storage(a, 16usize, 2usize, 16usize, 4096usize)
    if two_error != ok { os.exit(45) }
    let (cut, cut_error) = sched.build(first[0usize..n_first], cfg_w1(), two)
    if cut_error != ok || !cut.truncated || cut.placed_count != 2usize { os.exit(46) }
    // Its full expansion on the roomy storage: ten weekday occurrences, the week showing five.
    let (full, full_error) = sched.build(first[0usize..n_first], cfg_w1(), st)
    if full_error != ok || full.truncated || full.placed_count != 5usize { os.exit(47) }
    let (sixth, sixth_error) = str.builder(a, 4096usize)
    if sixth_error != ok { os.exit(48) }
    var sb = sixth
    if render(&sb, &full) != ok || !str.eq(str.done(&sb), want_first_row()) { os.exit(49) }

    try io.print("ui schedule ok\n")
    ret ok
}
