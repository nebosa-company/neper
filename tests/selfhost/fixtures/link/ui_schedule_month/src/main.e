// `e.ui.schedule` (L148, D3303): the month view, the all-day bars, moving and resizing a
// placed occurrence, keyboard focus and a second set of label words, against the
// independent models in scripts/gen_schedule_month_test.py (python datetime and dateutil;
// the time-grid layouts they start from are the model scripts/gen_schedule_test.py already
// compares with the module). Three months (a five-week one with a "+N more" line, a
// four-week February, a six-week August with no lines) are compared row by row (cells,
// placed rectangles, the accessible tree), the same October again in German words, every
// hit region and arrow-key move of the first, bars and move/resize/focus probes for a week,
// a day and an agenda, and the refusals. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.str
use e.time
use e.time.calendar
use e.ui.accessibility
use e.ui.schedule as sched

// BEGIN SCENARIOS
fn all_items(out: []sched.Item) -> usize {
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
    out[17usize] = sched.Item { id: 18u32, start: at(2026, 10u8, 10u8, 0u8, 0u8), minutes: 7200u32, all_day: true, title: "Trip", rule: "" }
    out[18usize] = sched.Item { id: 19u32, start: at(2026, 10u8, 13u8, 0u8, 0u8), minutes: 4320u32, all_day: true, title: "Offsite", rule: "" }
    out[19usize] = sched.Item { id: 20u32, start: at(2026, 10u8, 30u8, 0u8, 0u8), minutes: 4320u32, all_day: true, title: "Month end", rule: "" }
    out[20usize] = sched.Item { id: 21u32, start: at(2026, 10u8, 20u8, 22u8, 0u8), minutes: 180u32, all_day: false, title: "Late call", rule: "" }
    out[21usize] = sched.Item { id: 22u32, start: at(2026, 10u8, 16u8, 9u8, 45u8), minutes: 30u32, all_day: false, title: "Chain E", rule: "" }
    out[22usize] = sched.Item { id: 23u32, start: at(2026, 10u8, 16u8, 14u8, 0u8), minutes: 30u32, all_day: false, title: "Afternoon", rule: "" }
    out[23usize] = sched.Item { id: 24u32, start: at(2026, 8u8, 31u8, 12u8, 0u8), minutes: 60u32, all_day: false, title: "Boundary", rule: "" }
    out[24usize] = sched.Item { id: 25u32, start: at(2027, 2u8, 8u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Feb standup", rule: "FREQ=DAILY;COUNT=3" }
    out[25usize] = sched.Item { id: 26u32, start: at(2027, 2u8, 8u8, 0u8, 0u8), minutes: 2880u32, all_day: true, title: "Feb fair", rule: "" }
    out[26usize] = sched.Item { id: 27u32, start: at(2027, 2u8, 9u8, 15u8, 0u8), minutes: 30u32, all_day: false, title: "Feb call", rule: "" }
    out[27usize] = sched.Item { id: 28u32, start: at(2027, 2u8, 9u8, 11u8, 0u8), minutes: 30u32, all_day: false, title: "Feb sync", rule: "" }
    ret 28usize
}

fn mcfg_m1() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Monday, width: 700.0, header: 30.0, cell_h: 120.0, line_h: 20.0, lines: 4u32 }
}

fn mcfg_m2() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2027, month: 2u8, day: 3u8 }, week_start: .Monday, width: 700.0, header: 30.0, cell_h: 100.0, line_h: 25.0, lines: 2u32 }
}

fn mcfg_m3() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 8u8, day: 20u8 }, week_start: .Sunday, width: 840.0, header: 24.0, cell_h: 90.0, line_h: 18.0, lines: 0u32 }
}

fn de_names() -> sched.Names {
    var n = sched.english()
    n.weekdays[0usize] = "Montag"
    n.weekdays[1usize] = "Dienstag"
    n.weekdays[2usize] = "Mittwoch"
    n.weekdays[3usize] = "Donnerstag"
    n.weekdays[4usize] = "Freitag"
    n.weekdays[5usize] = "Samstag"
    n.weekdays[6usize] = "Sonntag"
    n.months[0usize] = "Januar"
    n.months[1usize] = "Februar"
    n.months[2usize] = "Maerz"
    n.months[3usize] = "April"
    n.months[4usize] = "Mai"
    n.months[5usize] = "Juni"
    n.months[6usize] = "Juli"
    n.months[7usize] = "August"
    n.months[8usize] = "September"
    n.months[9usize] = "Oktober"
    n.months[10usize] = "November"
    n.months[11usize] = "Dezember"
    n.all_day = ", ganztaegig"
    n.to = " bis "
    n.repeats = ", wiederholt"
    n.day_schedule = "Tagesplan"
    n.week_schedule = "Wochenplan"
    n.agenda = "Terminliste"
    n.month_schedule = "Monatsplan"
    n.no_events = "keine Termine"
    n.one_event = "1 Termin"
    n.events = " Termine"
    n.more = " weitere"
    ret n
}

fn want_m1() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 1 1 0\nC 20734 1 300 150 100 120 1 0 0 0\nC 20735 1 400 150 100 120 1 0 0 0\nC 20736 1 500 150 100 120 1 1 1 0\nC 20737 1 600 150 100 120 2 1 1 0\nC 20738 1 0 270 100 120 3 3 3 0\nC 20739 1 100 270 100 120 6 6 3 3\nC 20740 1 200 270 100 120 12 7 3 4\nC 20741 1 300 270 100 120 19 5 3 2\nC 20742 1 400 270 100 120 24 9 3 6\nC 20743 1 500 270 100 120 33 1 1 0\nC 20744 1 600 270 100 120 34 0 0 0\nC 20745 1 0 390 100 120 34 2 2 0\nC 20746 1 100 390 100 120 36 2 2 0\nC 20747 1 200 390 100 120 38 3 3 0\nC 20748 1 300 390 100 120 41 1 1 0\nC 20749 1 400 390 100 120 42 1 1 0\nC 20750 1 500 390 100 120 43 0 0 0\nC 20751 1 600 390 100 120 43 0 0 0\nC 20752 1 0 510 100 120 43 1 1 0\nC 20753 1 100 510 100 120 44 0 0 0\nC 20754 1 200 510 100 120 44 1 1 0\nC 20755 1 300 510 100 120 45 0 0 0\nC 20756 1 400 510 100 120 45 1 1 0\nC 20757 1 500 510 100 120 46 1 1 0\nC 20758 0 600 510 100 120 47 1 1 0\nP 9 T 9 29856420 29856480 200 170 100 20 0 1 0 0 1\nP 17 A 12 29859840 29861280 500 170 100 20 0 1 0 1 0\nP 17 A 13 29861280 29862720 600 170 100 20 0 1 1 1 0\nP 17 A 14 29862720 29864160 0 290 100 20 0 3 1 1 0\nP 16 A 14 29862720 29864160 0 310 100 20 1 3 0 0 1\nP 0 T 14 29863260 29863290 0 330 100 20 2 3 0 0 1\nP 17 A 15 29864160 29865600 100 290 100 20 0 6 1 1 0\nP 18 A 15 29864160 29865600 100 310 100 20 1 6 0 1 0\nP 0 T 15 29864700 29864730 100 330 100 20 2 6 0 0 1\nP 1 T 15 29864760 29864850 100 270 0 0 3 6 0 0 0\nP 2 T 15 29864790 29864850 100 270 0 0 4 6 0 0 0\nP 3 T 15 29864820 29864850 100 270 0 0 5 6 0 0 0\nP 17 A 16 29865600 29867040 200 290 100 20 0 7 1 0 0\nP 18 A 16 29865600 29867040 200 310 100 20 1 7 1 1 0\nP 7 A 16 29865600 29867040 200 330 100 20 2 7 0 1 0\nP 5 T 16 29865960 29866020 200 270 0 0 3 7 0 0 0\nP 0 T 16 29866140 29866170 200 270 0 0 4 7 0 0 1\nP 4 T 16 29866380 29866560 200 270 0 0 5 7 0 0 0\nP 9 T 16 29866500 29866560 200 270 0 0 6 7 0 0 1\nP 18 A 17 29867040 29868480 300 290 100 20 0 5 1 0 0\nP 7 A 17 29867040 29868480 300 310 100 20 1 5 1 0 0\nP 0 T 17 29867580 29867610 300 330 100 20 2 5 0 0 1\nP 10 T 17 29867640 29867700 300 270 0 0 3 5 0 0 1\nP 6 T 17 29868180 29868480 300 270 0 0 4 5 0 1 0\nP 8 A 18 29868480 29869920 400 290 100 20 0 9 0 0 0\nP 6 T 18 29868480 29868540 400 310 100 20 1 9 1 0 0\nP 14 T 18 29869020 29869140 400 330 100 20 2 9 0 0 0\nP 11 T 18 29869020 29869080 400 270 0 0 3 9 0 0 0\nP 0 T 18 29869020 29869050 400 270 0 0 4 9 0 0 1\nP 12 T 18 29869050 29869110 400 270 0 0 5 9 0 0 0\nP 21 T 18 29869065 29869095 400 270 0 0 6 9 0 0 0\nP 13 T 18 29869095 29869140 400 270 0 0 7 9 0 0 0\nP 22 T 18 29869320 29869350 400 270 0 0 8 9 0 0 0\nP 15 T 19 29870640 29870641 500 290 100 20 0 1 0 0 0\nP 16 A 21 29872800 29874240 0 410 100 20 0 2 0 0 1\nP 0 T 21 29873340 29873370 0 430 100 20 1 2 0 0 1\nP 0 T 22 29874780 29874810 100 410 100 20 0 2 0 0 1\nP 20 T 22 29875560 29875680 100 430 100 20 1 2 0 1 0\nP 20 T 23 29875680 29875740 200 410 100 20 0 3 1 0 0\nP 0 T 23 29876220 29876250 200 430 100 20 1 3 0 0 1\nP 9 T 23 29876580 29876640 200 450 100 20 2 3 0 0 1\nP 0 T 24 29877660 29877690 300 410 100 20 0 1 0 0 1\nP 0 T 25 29879100 29879130 400 410 100 20 0 1 0 0 1\nP 16 A 28 29882880 29884320 0 530 100 20 0 1 0 0 1\nP 9 T 30 29886660 29886720 200 530 100 20 0 1 0 0 1\nP 19 A 32 29888640 29890080 400 530 100 20 0 1 0 1 0\nP 19 A 33 29890080 29891520 500 530 100 20 0 1 1 1 0\nP 19 A 34 29891520 29892960 600 530 100 20 0 1 1 0 0\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, 1 event 2 3 5 7 0\nN ListItem 200 170 100 20 Weekly sync, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 300 150 100 120 Thursday 8 October 2026, no events 2 4 5 7 0\nN Cell 400 150 100 120 Friday 9 October 2026, no events 2 5 5 7 0\nN Cell 500 150 100 120 Saturday 10 October 2026, 1 event 2 6 5 7 0\nN ListItem 500 170 100 20 Trip, all day 0 0 0 0 1\nN Cell 600 150 100 120 Sunday 11 October 2026, 1 event 2 7 5 7 0\nN ListItem 600 170 100 20 Trip, all day 0 0 0 0 1\nN Cell 0 270 100 120 Monday 12 October 2026, 3 events 3 1 5 7 0\nN ListItem 0 290 100 20 Trip, all day 0 0 0 0 1\nN ListItem 0 310 100 20 Standing, all day, repeats 0 0 0 0 1\nN ListItem 0 330 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 100 270 100 120 Tuesday 13 October 2026, 6 events 3 2 5 7 0\nN ListItem 100 290 100 20 Trip, all day 0 0 0 0 1\nN ListItem 100 310 100 20 Offsite, all day 0 0 0 0 1\nN ListItem 100 330 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 100 270 0 0 Design review, 10:00 to 11:30 0 0 0 0 1\nN ListItem 100 270 0 0 Lunch, 10:30 to 11:30 0 0 0 0 1\nN ListItem 100 270 0 0 Call, 11:00 to 11:30 0 0 0 0 1\nN Cell 200 270 100 120 Wednesday 14 October 2026, 7 events 3 3 5 7 0\nN ListItem 200 290 100 20 Trip, all day 0 0 0 0 1\nN ListItem 200 310 100 20 Offsite, all day 0 0 0 0 1\nN ListItem 200 330 100 20 Conference, all day 0 0 0 0 1\nN ListItem 200 270 0 0 Early, 06:00 to 07:00 0 0 0 0 1\nN ListItem 200 270 0 0 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 200 270 0 0 Workshop, 13:00 to 16:00 0 0 0 0 1\nN ListItem 200 270 0 0 Weekly sync, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 300 270 100 120 Thursday 15 October 2026, 5 events 3 4 5 7 0\nN ListItem 300 290 100 20 Offsite, all day 0 0 0 0 1\nN ListItem 300 310 100 20 Conference, all day 0 0 0 0 1\nN ListItem 300 330 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 300 270 0 0 Monthly, 10:00 to 11:00, repeats 0 0 0 0 1\nN ListItem 300 270 0 0 Overnight, 19:00 to 00:00 0 0 0 0 1\nN Cell 400 270 100 120 Friday 16 October 2026, 9 events 3 5 5 7 0\nN ListItem 400 290 100 20 Holiday, all day 0 0 0 0 1\nN ListItem 400 310 100 20 Overnight, 00:00 to 01:00 0 0 0 0 1\nN ListItem 400 330 100 20 Chain D, 09:00 to 11:00 0 0 0 0 1\nN ListItem 400 270 0 0 Chain A, 09:00 to 10:00 0 0 0 0 1\nN ListItem 400 270 0 0 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 400 270 0 0 Chain B, 09:30 to 10:30 0 0 0 0 1\nN ListItem 400 270 0 0 Chain E, 09:45 to 10:15 0 0 0 0 1\nN ListItem 400 270 0 0 Chain C, 10:15 to 11:00 0 0 0 0 1\nN ListItem 400 270 0 0 Afternoon, 14:00 to 14:30 0 0 0 0 1\nN Cell 500 270 100 120 Saturday 17 October 2026, 1 event 3 6 5 7 0\nN ListItem 500 290 100 20 Zero length, 12:00 to 12:01 0 0 0 0 1\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, 2 events 4 1 5 7 0\nN ListItem 0 410 100 20 Standing, all day, repeats 0 0 0 0 1\nN ListItem 0 430 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 100 390 100 120 Tuesday 20 October 2026, 2 events 4 2 5 7 0\nN ListItem 100 410 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 100 430 100 20 Late call, 22:00 to 00:00 0 0 0 0 1\nN Cell 200 390 100 120 Wednesday 21 October 2026, 3 events 4 3 5 7 0\nN ListItem 200 410 100 20 Late call, 00:00 to 01:00 0 0 0 0 1\nN ListItem 200 430 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 200 450 100 20 Weekly sync, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 300 390 100 120 Thursday 22 October 2026, 1 event 4 4 5 7 0\nN ListItem 300 410 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 400 390 100 120 Friday 23 October 2026, 1 event 4 5 5 7 0\nN ListItem 400 410 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, 1 event 5 1 5 7 0\nN ListItem 0 530 100 20 Standing, all day, repeats 0 0 0 0 1\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, 1 event 5 3 5 7 0\nN ListItem 200 530 100 20 Weekly sync, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, 1 event 5 5 5 7 0\nN ListItem 400 530 100 20 Month end, all day 0 0 0 0 1\nN Cell 500 510 100 120 Saturday 31 October 2026, 1 event 5 6 5 7 0\nN ListItem 500 530 100 20 Month end, all day 0 0 0 0 1\nN Cell 600 510 100 120 Sunday 1 November 2026, 1 event 5 7 5 7 0\nN ListItem 600 530 100 20 Month end, all day 0 0 0 0 1\n" }

fn hits_m1() -> str { ret "-1,5,0,0,0;700,5,0,0,0;5,5,1,0,0;699,5,1,6,0;250,29,1,2,0;3,32,2,0,0;3,149,2,0,0;103,32,2,1,0;103,149,2,1,0;203,32,2,2,0;203,149,2,2,0;303,32,2,3,0;303,149,2,3,0;403,32,2,4,0;403,149,2,4,0;503,32,2,5,0;503,149,2,5,0;603,32,2,6,0;603,149,2,6,0;3,152,2,7,0;3,269,2,7,0;103,152,2,8,0;103,269,2,8,0;203,152,2,9,0;203,171,3,9,0;203,269,2,9,0;303,152,2,10,0;303,269,2,10,0;403,152,2,11,0;403,269,2,11,0;503,152,2,12,0;503,171,3,12,1;503,269,2,12,0;603,152,2,13,0;603,171,3,13,2;603,269,2,13,0;3,272,2,14,0;3,291,3,14,3;3,311,3,14,4;3,331,3,14,5;3,389,2,14,0;103,272,2,15,0;103,291,3,15,6;103,311,3,15,7;103,331,3,15,8;103,351,4,15,15;103,371,2,15,0;103,391,2,22,0;103,389,2,15,0;203,272,2,16,0;203,291,3,16,12;203,311,3,16,13;203,331,3,16,14;203,351,4,16,16;203,371,2,16,0;203,391,2,23,0;203,411,3,23,38;203,389,2,16,0;303,272,2,17,0;303,291,3,17,19;303,311,3,17,20;303,331,3,17,21;303,351,4,17,17;303,371,2,17,0;303,389,2,17,0;403,272,2,18,0;403,291,3,18,24;403,311,3,18,25;403,331,3,18,26;403,351,4,18,18;403,371,2,18,0;403,391,2,25,0;403,411,3,25,42;403,431,2,25,0;403,451,2,25,0;403,389,2,18,0;503,272,2,19,0;503,291,3,19,33;503,389,2,19,0;603,272,2,20,0;603,389,2,20,0;3,392,2,21,0;3,411,3,21,34;3,431,3,21,35;3,509,2,21,0;103,392,2,22,0;103,411,3,22,36;103,431,3,22,37;103,509,2,22,0;203,392,2,23,0;203,411,3,23,38;203,431,3,23,39;203,451,3,23,40;203,509,2,23,0;303,392,2,24,0;303,411,3,24,41;303,509,2,24,0;403,392,2,25,0;403,411,3,25,42;403,509,2,25,0;503,392,2,26,0;503,509,2,26,0;603,392,2,27,0;603,509,2,27,0;3,512,2,28,0;3,531,3,28,43;3,629,2,28,0;103,512,2,29,0;103,629,2,29,0;203,512,2,30,0;203,531,3,30,44;203,629,2,30,0;303,512,2,31,0;303,629,2,31,0;403,512,2,32,0;403,531,3,32,45;403,629,2,32,0;503,512,2,33,0;503,531,3,33,46;503,629,2,33,0;603,512,2,34,0;603,531,3,34,47;603,629,2,34,0;10,631,0,0,0" }

fn want_m2() -> str { ret "M 20850 4 430\nC 20850 1 0 30 100 100 0 0 0 0\nC 20851 1 100 30 100 100 0 0 0 0\nC 20852 1 200 30 100 100 0 0 0 0\nC 20853 1 300 30 100 100 0 0 0 0\nC 20854 1 400 30 100 100 0 0 0 0\nC 20855 1 500 30 100 100 0 0 0 0\nC 20856 1 600 30 100 100 0 0 0 0\nC 20857 1 0 130 100 100 0 2 2 0\nC 20858 1 100 130 100 100 2 4 1 3\nC 20859 1 200 130 100 100 6 1 1 0\nC 20860 1 300 130 100 100 7 0 0 0\nC 20861 1 400 130 100 100 7 0 0 0\nC 20862 1 500 130 100 100 7 0 0 0\nC 20863 1 600 130 100 100 7 0 0 0\nC 20864 1 0 230 100 100 7 1 1 0\nC 20865 1 100 230 100 100 8 0 0 0\nC 20866 1 200 230 100 100 8 0 0 0\nC 20867 1 300 230 100 100 8 0 0 0\nC 20868 1 400 230 100 100 8 0 0 0\nC 20869 1 500 230 100 100 8 0 0 0\nC 20870 1 600 230 100 100 8 0 0 0\nC 20871 1 0 330 100 100 8 0 0 0\nC 20872 1 100 330 100 100 8 0 0 0\nC 20873 1 200 330 100 100 8 0 0 0\nC 20874 1 300 330 100 100 8 0 0 0\nC 20875 1 400 330 100 100 8 0 0 0\nC 20876 1 500 330 100 100 8 0 0 0\nC 20877 1 600 330 100 100 8 0 0 0\nP 25 A 7 30034080 30035520 0 155 100 25 0 2 0 1 0\nP 24 T 7 30034620 30034680 0 180 100 25 1 2 0 0 1\nP 25 A 8 30035520 30036960 100 155 100 25 0 4 1 0 0\nP 24 T 8 30036060 30036120 100 130 0 0 1 4 0 0 1\nP 27 T 8 30036180 30036210 100 130 0 0 2 4 0 0 0\nP 26 T 8 30036420 30036450 100 130 0 0 3 4 0 0 0\nP 24 T 9 30037500 30037560 200 155 100 25 0 1 0 0 1\nP 10 T 14 30044760 30044820 0 255 100 25 0 1 0 0 1\nN Grid 0 0 700 430 Month schedule, February 2027 0 0 4 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 100 Monday 1 February 2027, no events 1 1 4 7 0\nN Cell 100 30 100 100 Tuesday 2 February 2027, no events 1 2 4 7 0\nN Cell 200 30 100 100 Wednesday 3 February 2027, no events 1 3 4 7 0\nN Cell 300 30 100 100 Thursday 4 February 2027, no events 1 4 4 7 0\nN Cell 400 30 100 100 Friday 5 February 2027, no events 1 5 4 7 0\nN Cell 500 30 100 100 Saturday 6 February 2027, no events 1 6 4 7 0\nN Cell 600 30 100 100 Sunday 7 February 2027, no events 1 7 4 7 0\nN Cell 0 130 100 100 Monday 8 February 2027, 2 events 2 1 4 7 0\nN ListItem 0 155 100 25 Feb fair, all day 0 0 0 0 1\nN ListItem 0 180 100 25 Feb standup, 09:00 to 10:00, repeats 0 0 0 0 1\nN Cell 100 130 100 100 Tuesday 9 February 2027, 4 events 2 2 4 7 0\nN ListItem 100 155 100 25 Feb fair, all day 0 0 0 0 1\nN ListItem 100 130 0 0 Feb standup, 09:00 to 10:00, repeats 0 0 0 0 1\nN ListItem 100 130 0 0 Feb sync, 11:00 to 11:30 0 0 0 0 1\nN ListItem 100 130 0 0 Feb call, 15:00 to 15:30 0 0 0 0 1\nN Cell 200 130 100 100 Wednesday 10 February 2027, 1 event 2 3 4 7 0\nN ListItem 200 155 100 25 Feb standup, 09:00 to 10:00, repeats 0 0 0 0 1\nN Cell 300 130 100 100 Thursday 11 February 2027, no events 2 4 4 7 0\nN Cell 400 130 100 100 Friday 12 February 2027, no events 2 5 4 7 0\nN Cell 500 130 100 100 Saturday 13 February 2027, no events 2 6 4 7 0\nN Cell 600 130 100 100 Sunday 14 February 2027, no events 2 7 4 7 0\nN Cell 0 230 100 100 Monday 15 February 2027, 1 event 3 1 4 7 0\nN ListItem 0 255 100 25 Monthly, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 100 230 100 100 Tuesday 16 February 2027, no events 3 2 4 7 0\nN Cell 200 230 100 100 Wednesday 17 February 2027, no events 3 3 4 7 0\nN Cell 300 230 100 100 Thursday 18 February 2027, no events 3 4 4 7 0\nN Cell 400 230 100 100 Friday 19 February 2027, no events 3 5 4 7 0\nN Cell 500 230 100 100 Saturday 20 February 2027, no events 3 6 4 7 0\nN Cell 600 230 100 100 Sunday 21 February 2027, no events 3 7 4 7 0\nN Cell 0 330 100 100 Monday 22 February 2027, no events 4 1 4 7 0\nN Cell 100 330 100 100 Tuesday 23 February 2027, no events 4 2 4 7 0\nN Cell 200 330 100 100 Wednesday 24 February 2027, no events 4 3 4 7 0\nN Cell 300 330 100 100 Thursday 25 February 2027, no events 4 4 4 7 0\nN Cell 400 330 100 100 Friday 26 February 2027, no events 4 5 4 7 0\nN Cell 500 330 100 100 Saturday 27 February 2027, no events 4 6 4 7 0\nN Cell 600 330 100 100 Sunday 28 February 2027, no events 4 7 4 7 0\n" }

fn hits_m2() -> str { ret "-1,5,0,0,0;700,5,0,0,0;5,5,1,0,0;699,5,1,6,0;250,29,1,2,0;3,32,2,0,0;3,129,2,0,0;103,32,2,1,0;103,129,2,1,0;203,32,2,2,0;203,129,2,2,0;303,32,2,3,0;303,129,2,3,0;403,32,2,4,0;403,129,2,4,0;503,32,2,5,0;503,129,2,5,0;603,32,2,6,0;603,129,2,6,0;3,132,2,7,0;3,156,3,7,0;3,181,3,7,1;3,229,2,7,0;103,132,2,8,0;103,156,3,8,2;103,181,4,8,8;103,206,2,8,0;103,231,2,15,0;103,229,2,8,0;203,132,2,9,0;203,156,3,9,6;203,229,2,9,0;303,132,2,10,0;303,229,2,10,0;403,132,2,11,0;403,229,2,11,0;503,132,2,12,0;503,229,2,12,0;603,132,2,13,0;603,229,2,13,0;3,232,2,14,0;3,256,3,14,7;3,329,2,14,0;103,232,2,15,0;103,329,2,15,0;203,232,2,16,0;203,329,2,16,0;303,232,2,17,0;303,329,2,17,0;403,232,2,18,0;403,329,2,18,0;503,232,2,19,0;503,329,2,19,0;603,232,2,20,0;603,329,2,20,0;3,332,2,21,0;3,429,2,21,0;103,332,2,22,0;103,429,2,22,0;203,332,2,23,0;203,429,2,23,0;303,332,2,24,0;303,429,2,24,0;403,332,2,25,0;403,429,2,25,0;503,332,2,26,0;503,429,2,26,0;603,332,2,27,0;603,429,2,27,0;10,431,0,0,0" }

fn want_m3() -> str { ret "M 20660 6 564\nC 20660 0 0 24 120 90 0 0 0 0\nC 20661 0 120 24 120 90 0 0 0 0\nC 20662 0 240 24 120 90 0 0 0 0\nC 20663 0 360 24 120 90 0 0 0 0\nC 20664 0 480 24 120 90 0 0 0 0\nC 20665 0 600 24 120 90 0 0 0 0\nC 20666 1 720 24 120 90 0 0 0 0\nC 20667 1 0 114 120 90 0 0 0 0\nC 20668 1 120 114 120 90 0 0 0 0\nC 20669 1 240 114 120 90 0 0 0 0\nC 20670 1 360 114 120 90 0 0 0 0\nC 20671 1 480 114 120 90 0 0 0 0\nC 20672 1 600 114 120 90 0 0 0 0\nC 20673 1 720 114 120 90 0 0 0 0\nC 20674 1 0 204 120 90 0 0 0 0\nC 20675 1 120 204 120 90 0 0 0 0\nC 20676 1 240 204 120 90 0 0 0 0\nC 20677 1 360 204 120 90 0 0 0 0\nC 20678 1 480 204 120 90 0 0 0 0\nC 20679 1 600 204 120 90 0 0 0 0\nC 20680 1 720 204 120 90 0 1 0 1\nC 20681 1 0 294 120 90 1 0 0 0\nC 20682 1 120 294 120 90 1 0 0 0\nC 20683 1 240 294 120 90 1 0 0 0\nC 20684 1 360 294 120 90 1 0 0 0\nC 20685 1 480 294 120 90 1 0 0 0\nC 20686 1 600 294 120 90 1 0 0 0\nC 20687 1 720 294 120 90 1 0 0 0\nC 20688 1 0 384 120 90 1 0 0 0\nC 20689 1 120 384 120 90 1 0 0 0\nC 20690 1 240 384 120 90 1 0 0 0\nC 20691 1 360 384 120 90 1 0 0 0\nC 20692 1 480 384 120 90 1 0 0 0\nC 20693 1 600 384 120 90 1 0 0 0\nC 20694 1 720 384 120 90 1 0 0 0\nC 20695 1 0 474 120 90 1 0 0 0\nC 20696 1 120 474 120 90 1 1 0 1\nC 20697 0 240 474 120 90 2 0 0 0\nC 20698 0 360 474 120 90 2 0 0 0\nC 20699 0 480 474 120 90 2 0 0 0\nC 20700 0 600 474 120 90 2 0 0 0\nC 20701 0 720 474 120 90 2 0 0 0\nP 10 T 20 29779800 29779860 720 204 0 0 0 1 0 0 1\nP 23 T 36 29802960 29803020 120 474 0 0 0 1 0 0 0\nN Grid 0 0 840 564 Month schedule, August 2026 0 0 6 7 0\nN ColumnHeader 0 0 120 24 Sunday 0 1 0 7 0\nN ColumnHeader 120 0 120 24 Monday 0 2 0 7 0\nN ColumnHeader 240 0 120 24 Tuesday 0 3 0 7 0\nN ColumnHeader 360 0 120 24 Wednesday 0 4 0 7 0\nN ColumnHeader 480 0 120 24 Thursday 0 5 0 7 0\nN ColumnHeader 600 0 120 24 Friday 0 6 0 7 0\nN ColumnHeader 720 0 120 24 Saturday 0 7 0 7 0\nN Cell 0 24 120 90 Sunday 26 July 2026, no events 1 1 6 7 0\nN Cell 120 24 120 90 Monday 27 July 2026, no events 1 2 6 7 0\nN Cell 240 24 120 90 Tuesday 28 July 2026, no events 1 3 6 7 0\nN Cell 360 24 120 90 Wednesday 29 July 2026, no events 1 4 6 7 0\nN Cell 480 24 120 90 Thursday 30 July 2026, no events 1 5 6 7 0\nN Cell 600 24 120 90 Friday 31 July 2026, no events 1 6 6 7 0\nN Cell 720 24 120 90 Saturday 1 August 2026, no events 1 7 6 7 0\nN Cell 0 114 120 90 Sunday 2 August 2026, no events 2 1 6 7 0\nN Cell 120 114 120 90 Monday 3 August 2026, no events 2 2 6 7 0\nN Cell 240 114 120 90 Tuesday 4 August 2026, no events 2 3 6 7 0\nN Cell 360 114 120 90 Wednesday 5 August 2026, no events 2 4 6 7 0\nN Cell 480 114 120 90 Thursday 6 August 2026, no events 2 5 6 7 0\nN Cell 600 114 120 90 Friday 7 August 2026, no events 2 6 6 7 0\nN Cell 720 114 120 90 Saturday 8 August 2026, no events 2 7 6 7 0\nN Cell 0 204 120 90 Sunday 9 August 2026, no events 3 1 6 7 0\nN Cell 120 204 120 90 Monday 10 August 2026, no events 3 2 6 7 0\nN Cell 240 204 120 90 Tuesday 11 August 2026, no events 3 3 6 7 0\nN Cell 360 204 120 90 Wednesday 12 August 2026, no events 3 4 6 7 0\nN Cell 480 204 120 90 Thursday 13 August 2026, no events 3 5 6 7 0\nN Cell 600 204 120 90 Friday 14 August 2026, no events 3 6 6 7 0\nN Cell 720 204 120 90 Saturday 15 August 2026, 1 event 3 7 6 7 0\nN ListItem 720 204 0 0 Monthly, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 0 294 120 90 Sunday 16 August 2026, no events 4 1 6 7 0\nN Cell 120 294 120 90 Monday 17 August 2026, no events 4 2 6 7 0\nN Cell 240 294 120 90 Tuesday 18 August 2026, no events 4 3 6 7 0\nN Cell 360 294 120 90 Wednesday 19 August 2026, no events 4 4 6 7 0\nN Cell 480 294 120 90 Thursday 20 August 2026, no events 4 5 6 7 0\nN Cell 600 294 120 90 Friday 21 August 2026, no events 4 6 6 7 0\nN Cell 720 294 120 90 Saturday 22 August 2026, no events 4 7 6 7 0\nN Cell 0 384 120 90 Sunday 23 August 2026, no events 5 1 6 7 0\nN Cell 120 384 120 90 Monday 24 August 2026, no events 5 2 6 7 0\nN Cell 240 384 120 90 Tuesday 25 August 2026, no events 5 3 6 7 0\nN Cell 360 384 120 90 Wednesday 26 August 2026, no events 5 4 6 7 0\nN Cell 480 384 120 90 Thursday 27 August 2026, no events 5 5 6 7 0\nN Cell 600 384 120 90 Friday 28 August 2026, no events 5 6 6 7 0\nN Cell 720 384 120 90 Saturday 29 August 2026, no events 5 7 6 7 0\nN Cell 0 474 120 90 Sunday 30 August 2026, no events 6 1 6 7 0\nN Cell 120 474 120 90 Monday 31 August 2026, 1 event 6 2 6 7 0\nN ListItem 120 474 0 0 Boundary, 12:00 to 13:00 0 0 0 0 1\nN Cell 240 474 120 90 Tuesday 1 September 2026, no events 6 3 6 7 0\nN Cell 360 474 120 90 Wednesday 2 September 2026, no events 6 4 6 7 0\nN Cell 480 474 120 90 Thursday 3 September 2026, no events 6 5 6 7 0\nN Cell 600 474 120 90 Friday 4 September 2026, no events 6 6 6 7 0\nN Cell 720 474 120 90 Saturday 5 September 2026, no events 6 7 6 7 0\n" }

fn want_m1_de() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 1 1 0\nC 20734 1 300 150 100 120 1 0 0 0\nC 20735 1 400 150 100 120 1 0 0 0\nC 20736 1 500 150 100 120 1 1 1 0\nC 20737 1 600 150 100 120 2 1 1 0\nC 20738 1 0 270 100 120 3 3 3 0\nC 20739 1 100 270 100 120 6 6 3 3\nC 20740 1 200 270 100 120 12 7 3 4\nC 20741 1 300 270 100 120 19 5 3 2\nC 20742 1 400 270 100 120 24 9 3 6\nC 20743 1 500 270 100 120 33 1 1 0\nC 20744 1 600 270 100 120 34 0 0 0\nC 20745 1 0 390 100 120 34 2 2 0\nC 20746 1 100 390 100 120 36 2 2 0\nC 20747 1 200 390 100 120 38 3 3 0\nC 20748 1 300 390 100 120 41 1 1 0\nC 20749 1 400 390 100 120 42 1 1 0\nC 20750 1 500 390 100 120 43 0 0 0\nC 20751 1 600 390 100 120 43 0 0 0\nC 20752 1 0 510 100 120 43 1 1 0\nC 20753 1 100 510 100 120 44 0 0 0\nC 20754 1 200 510 100 120 44 1 1 0\nC 20755 1 300 510 100 120 45 0 0 0\nC 20756 1 400 510 100 120 45 1 1 0\nC 20757 1 500 510 100 120 46 1 1 0\nC 20758 0 600 510 100 120 47 1 1 0\nP 9 T 9 29856420 29856480 200 170 100 20 0 1 0 0 1\nP 17 A 12 29859840 29861280 500 170 100 20 0 1 0 1 0\nP 17 A 13 29861280 29862720 600 170 100 20 0 1 1 1 0\nP 17 A 14 29862720 29864160 0 290 100 20 0 3 1 1 0\nP 16 A 14 29862720 29864160 0 310 100 20 1 3 0 0 1\nP 0 T 14 29863260 29863290 0 330 100 20 2 3 0 0 1\nP 17 A 15 29864160 29865600 100 290 100 20 0 6 1 1 0\nP 18 A 15 29864160 29865600 100 310 100 20 1 6 0 1 0\nP 0 T 15 29864700 29864730 100 330 100 20 2 6 0 0 1\nP 1 T 15 29864760 29864850 100 270 0 0 3 6 0 0 0\nP 2 T 15 29864790 29864850 100 270 0 0 4 6 0 0 0\nP 3 T 15 29864820 29864850 100 270 0 0 5 6 0 0 0\nP 17 A 16 29865600 29867040 200 290 100 20 0 7 1 0 0\nP 18 A 16 29865600 29867040 200 310 100 20 1 7 1 1 0\nP 7 A 16 29865600 29867040 200 330 100 20 2 7 0 1 0\nP 5 T 16 29865960 29866020 200 270 0 0 3 7 0 0 0\nP 0 T 16 29866140 29866170 200 270 0 0 4 7 0 0 1\nP 4 T 16 29866380 29866560 200 270 0 0 5 7 0 0 0\nP 9 T 16 29866500 29866560 200 270 0 0 6 7 0 0 1\nP 18 A 17 29867040 29868480 300 290 100 20 0 5 1 0 0\nP 7 A 17 29867040 29868480 300 310 100 20 1 5 1 0 0\nP 0 T 17 29867580 29867610 300 330 100 20 2 5 0 0 1\nP 10 T 17 29867640 29867700 300 270 0 0 3 5 0 0 1\nP 6 T 17 29868180 29868480 300 270 0 0 4 5 0 1 0\nP 8 A 18 29868480 29869920 400 290 100 20 0 9 0 0 0\nP 6 T 18 29868480 29868540 400 310 100 20 1 9 1 0 0\nP 14 T 18 29869020 29869140 400 330 100 20 2 9 0 0 0\nP 11 T 18 29869020 29869080 400 270 0 0 3 9 0 0 0\nP 0 T 18 29869020 29869050 400 270 0 0 4 9 0 0 1\nP 12 T 18 29869050 29869110 400 270 0 0 5 9 0 0 0\nP 21 T 18 29869065 29869095 400 270 0 0 6 9 0 0 0\nP 13 T 18 29869095 29869140 400 270 0 0 7 9 0 0 0\nP 22 T 18 29869320 29869350 400 270 0 0 8 9 0 0 0\nP 15 T 19 29870640 29870641 500 290 100 20 0 1 0 0 0\nP 16 A 21 29872800 29874240 0 410 100 20 0 2 0 0 1\nP 0 T 21 29873340 29873370 0 430 100 20 1 2 0 0 1\nP 0 T 22 29874780 29874810 100 410 100 20 0 2 0 0 1\nP 20 T 22 29875560 29875680 100 430 100 20 1 2 0 1 0\nP 20 T 23 29875680 29875740 200 410 100 20 0 3 1 0 0\nP 0 T 23 29876220 29876250 200 430 100 20 1 3 0 0 1\nP 9 T 23 29876580 29876640 200 450 100 20 2 3 0 0 1\nP 0 T 24 29877660 29877690 300 410 100 20 0 1 0 0 1\nP 0 T 25 29879100 29879130 400 410 100 20 0 1 0 0 1\nP 16 A 28 29882880 29884320 0 530 100 20 0 1 0 0 1\nP 9 T 30 29886660 29886720 200 530 100 20 0 1 0 0 1\nP 19 A 32 29888640 29890080 400 530 100 20 0 1 0 1 0\nP 19 A 33 29890080 29891520 500 530 100 20 0 1 1 1 0\nP 19 A 34 29891520 29892960 600 530 100 20 0 1 1 0 0\nN Grid 0 0 700 630 Monatsplan, Oktober 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Montag 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Dienstag 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Mittwoch 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Donnerstag 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Freitag 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Samstag 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sonntag 0 7 0 7 0\nN Cell 0 30 100 120 Montag 28 September 2026, keine Termine 1 1 5 7 0\nN Cell 100 30 100 120 Dienstag 29 September 2026, keine Termine 1 2 5 7 0\nN Cell 200 30 100 120 Mittwoch 30 September 2026, keine Termine 1 3 5 7 0\nN Cell 300 30 100 120 Donnerstag 1 Oktober 2026, keine Termine 1 4 5 7 0\nN Cell 400 30 100 120 Freitag 2 Oktober 2026, keine Termine 1 5 5 7 0\nN Cell 500 30 100 120 Samstag 3 Oktober 2026, keine Termine 1 6 5 7 0\nN Cell 600 30 100 120 Sonntag 4 Oktober 2026, keine Termine 1 7 5 7 0\nN Cell 0 150 100 120 Montag 5 Oktober 2026, keine Termine 2 1 5 7 0\nN Cell 100 150 100 120 Dienstag 6 Oktober 2026, keine Termine 2 2 5 7 0\nN Cell 200 150 100 120 Mittwoch 7 Oktober 2026, 1 Termin 2 3 5 7 0\nN ListItem 200 170 100 20 Weekly sync, 15:00 bis 16:00, wiederholt 0 0 0 0 1\nN Cell 300 150 100 120 Donnerstag 8 Oktober 2026, keine Termine 2 4 5 7 0\nN Cell 400 150 100 120 Freitag 9 Oktober 2026, keine Termine 2 5 5 7 0\nN Cell 500 150 100 120 Samstag 10 Oktober 2026, 1 Termin 2 6 5 7 0\nN ListItem 500 170 100 20 Trip, ganztaegig 0 0 0 0 1\nN Cell 600 150 100 120 Sonntag 11 Oktober 2026, 1 Termin 2 7 5 7 0\nN ListItem 600 170 100 20 Trip, ganztaegig 0 0 0 0 1\nN Cell 0 270 100 120 Montag 12 Oktober 2026, 3 Termine 3 1 5 7 0\nN ListItem 0 290 100 20 Trip, ganztaegig 0 0 0 0 1\nN ListItem 0 310 100 20 Standing, ganztaegig, wiederholt 0 0 0 0 1\nN ListItem 0 330 100 20 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN Cell 100 270 100 120 Dienstag 13 Oktober 2026, 6 Termine 3 2 5 7 0\nN ListItem 100 290 100 20 Trip, ganztaegig 0 0 0 0 1\nN ListItem 100 310 100 20 Offsite, ganztaegig 0 0 0 0 1\nN ListItem 100 330 100 20 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN ListItem 100 270 0 0 Design review, 10:00 bis 11:30 0 0 0 0 1\nN ListItem 100 270 0 0 Lunch, 10:30 bis 11:30 0 0 0 0 1\nN ListItem 100 270 0 0 Call, 11:00 bis 11:30 0 0 0 0 1\nN Cell 200 270 100 120 Mittwoch 14 Oktober 2026, 7 Termine 3 3 5 7 0\nN ListItem 200 290 100 20 Trip, ganztaegig 0 0 0 0 1\nN ListItem 200 310 100 20 Offsite, ganztaegig 0 0 0 0 1\nN ListItem 200 330 100 20 Conference, ganztaegig 0 0 0 0 1\nN ListItem 200 270 0 0 Early, 06:00 bis 07:00 0 0 0 0 1\nN ListItem 200 270 0 0 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN ListItem 200 270 0 0 Workshop, 13:00 bis 16:00 0 0 0 0 1\nN ListItem 200 270 0 0 Weekly sync, 15:00 bis 16:00, wiederholt 0 0 0 0 1\nN Cell 300 270 100 120 Donnerstag 15 Oktober 2026, 5 Termine 3 4 5 7 0\nN ListItem 300 290 100 20 Offsite, ganztaegig 0 0 0 0 1\nN ListItem 300 310 100 20 Conference, ganztaegig 0 0 0 0 1\nN ListItem 300 330 100 20 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN ListItem 300 270 0 0 Monthly, 10:00 bis 11:00, wiederholt 0 0 0 0 1\nN ListItem 300 270 0 0 Overnight, 19:00 bis 00:00 0 0 0 0 1\nN Cell 400 270 100 120 Freitag 16 Oktober 2026, 9 Termine 3 5 5 7 0\nN ListItem 400 290 100 20 Holiday, ganztaegig 0 0 0 0 1\nN ListItem 400 310 100 20 Overnight, 00:00 bis 01:00 0 0 0 0 1\nN ListItem 400 330 100 20 Chain D, 09:00 bis 11:00 0 0 0 0 1\nN ListItem 400 270 0 0 Chain A, 09:00 bis 10:00 0 0 0 0 1\nN ListItem 400 270 0 0 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN ListItem 400 270 0 0 Chain B, 09:30 bis 10:30 0 0 0 0 1\nN ListItem 400 270 0 0 Chain E, 09:45 bis 10:15 0 0 0 0 1\nN ListItem 400 270 0 0 Chain C, 10:15 bis 11:00 0 0 0 0 1\nN ListItem 400 270 0 0 Afternoon, 14:00 bis 14:30 0 0 0 0 1\nN Cell 500 270 100 120 Samstag 17 Oktober 2026, 1 Termin 3 6 5 7 0\nN ListItem 500 290 100 20 Zero length, 12:00 bis 12:01 0 0 0 0 1\nN Cell 600 270 100 120 Sonntag 18 Oktober 2026, keine Termine 3 7 5 7 0\nN Cell 0 390 100 120 Montag 19 Oktober 2026, 2 Termine 4 1 5 7 0\nN ListItem 0 410 100 20 Standing, ganztaegig, wiederholt 0 0 0 0 1\nN ListItem 0 430 100 20 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN Cell 100 390 100 120 Dienstag 20 Oktober 2026, 2 Termine 4 2 5 7 0\nN ListItem 100 410 100 20 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN ListItem 100 430 100 20 Late call, 22:00 bis 00:00 0 0 0 0 1\nN Cell 200 390 100 120 Mittwoch 21 Oktober 2026, 3 Termine 4 3 5 7 0\nN ListItem 200 410 100 20 Late call, 00:00 bis 01:00 0 0 0 0 1\nN ListItem 200 430 100 20 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN ListItem 200 450 100 20 Weekly sync, 15:00 bis 16:00, wiederholt 0 0 0 0 1\nN Cell 300 390 100 120 Donnerstag 22 Oktober 2026, 1 Termin 4 4 5 7 0\nN ListItem 300 410 100 20 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN Cell 400 390 100 120 Freitag 23 Oktober 2026, 1 Termin 4 5 5 7 0\nN ListItem 400 410 100 20 Standup, 09:00 bis 09:30, wiederholt 0 0 0 0 1\nN Cell 500 390 100 120 Samstag 24 Oktober 2026, keine Termine 4 6 5 7 0\nN Cell 600 390 100 120 Sonntag 25 Oktober 2026, keine Termine 4 7 5 7 0\nN Cell 0 510 100 120 Montag 26 Oktober 2026, 1 Termin 5 1 5 7 0\nN ListItem 0 530 100 20 Standing, ganztaegig, wiederholt 0 0 0 0 1\nN Cell 100 510 100 120 Dienstag 27 Oktober 2026, keine Termine 5 2 5 7 0\nN Cell 200 510 100 120 Mittwoch 28 Oktober 2026, 1 Termin 5 3 5 7 0\nN ListItem 200 530 100 20 Weekly sync, 15:00 bis 16:00, wiederholt 0 0 0 0 1\nN Cell 300 510 100 120 Donnerstag 29 Oktober 2026, keine Termine 5 4 5 7 0\nN Cell 400 510 100 120 Freitag 30 Oktober 2026, 1 Termin 5 5 5 7 0\nN ListItem 400 530 100 20 Month end, ganztaegig 0 0 0 0 1\nN Cell 500 510 100 120 Samstag 31 Oktober 2026, 1 Termin 5 6 5 7 0\nN ListItem 500 530 100 20 Month end, ganztaegig 0 0 0 0 1\nN Cell 600 510 100 120 Sonntag 1 November 2026, 1 Termin 5 7 5 7 0\nN ListItem 600 530 100 20 Month end, ganztaegig 0 0 0 0 1\n" }

fn moves_m1() -> str { ret "0,0,0;0,1,1;0,2,0;0,3,7;0,4,0;0,5,6;1,0,0;1,1,2;1,2,1;1,3,8;1,4,0;1,5,6;2,0,1;2,1,3;2,2,2;2,3,9;2,4,0;2,5,6;3,0,2;3,1,4;3,2,3;3,3,10;3,4,0;3,5,6;4,0,3;4,1,5;4,2,4;4,3,11;4,4,0;4,5,6;5,0,4;5,1,6;5,2,5;5,3,12;5,4,0;5,5,6;6,0,5;6,1,7;6,2,6;6,3,13;6,4,0;6,5,6;7,0,6;7,1,8;7,2,0;7,3,14;7,4,7;7,5,13;8,0,7;8,1,9;8,2,1;8,3,15;8,4,7;8,5,13;9,0,8;9,1,10;9,2,2;9,3,16;9,4,7;9,5,13;10,0,9;10,1,11;10,2,3;10,3,17;10,4,7;10,5,13;11,0,10;11,1,12;11,2,4;11,3,18;11,4,7;11,5,13;12,0,11;12,1,13;12,2,5;12,3,19;12,4,7;12,5,13;13,0,12;13,1,14;13,2,6;13,3,20;13,4,7;13,5,13;14,0,13;14,1,15;14,2,7;14,3,21;14,4,14;14,5,20;15,0,14;15,1,16;15,2,8;15,3,22;15,4,14;15,5,20;16,0,15;16,1,17;16,2,9;16,3,23;16,4,14;16,5,20;17,0,16;17,1,18;17,2,10;17,3,24;17,4,14;17,5,20;18,0,17;18,1,19;18,2,11;18,3,25;18,4,14;18,5,20;19,0,18;19,1,20;19,2,12;19,3,26;19,4,14;19,5,20;20,0,19;20,1,21;20,2,13;20,3,27;20,4,14;20,5,20;21,0,20;21,1,22;21,2,14;21,3,28;21,4,21;21,5,27;22,0,21;22,1,23;22,2,15;22,3,29;22,4,21;22,5,27;23,0,22;23,1,24;23,2,16;23,3,30;23,4,21;23,5,27;24,0,23;24,1,25;24,2,17;24,3,31;24,4,21;24,5,27;25,0,24;25,1,26;25,2,18;25,3,32;25,4,21;25,5,27;26,0,25;26,1,27;26,2,19;26,3,33;26,4,21;26,5,27;27,0,26;27,1,28;27,2,20;27,3,34;27,4,21;27,5,27;28,0,27;28,1,29;28,2,21;28,3,28;28,4,28;28,5,34;29,0,28;29,1,30;29,2,22;29,3,29;29,4,28;29,5,34;30,0,29;30,1,31;30,2,23;30,3,30;30,4,28;30,5,34;31,0,30;31,1,32;31,2,24;31,3,31;31,4,28;31,5,34;32,0,31;32,1,33;32,2,25;32,3,32;32,4,28;32,5,34;33,0,32;33,1,34;33,2,26;33,3,33;33,4,28;33,5,34;34,0,33;34,1,34;34,2,27;34,3,34;34,4,28;34,5,34" }

fn cfg_w1() -> sched.Config {
    ret sched.Config { mode: .Week, anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Monday, day_start: 8u32, day_end: 20u32, slot: 30u32, agenda_days: 10u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn want_bars_w1() -> str { ret "L 3 5\nB 17 0 2 0 60 30 360 20 1 0 0\nB 16 0 0 1 60 50 120 20 0 0 1\nB 18 1 3 1 180 50 360 20 0 0 0\nB 7 2 3 2 300 70 240 20 0 0 0\nB 8 4 4 0 540 30 120 20 0 0 0\n" }

fn moves_w1() -> str { ret "0,62,33,182,103,1,0,29861280,7200;0,62,33,-63,0,0,0,0,0;0,62,33,62,890,1,0,29859840,7200;0,62,33,5,30,0,0,0,0;0,62,33,312,5,1,0,29862720,7200;1,62,53,182,123,1,1,29864160,1440;1,62,53,-63,20,0,0,0,0;1,62,53,62,890,1,0,29862720,1440;1,62,53,5,50,0,0,0,0;1,62,53,312,5,1,2,29865600,1440;2,62,153,182,223,1,1,29864760,30;2,62,153,-63,120,0,0,0,0;2,62,153,62,890,1,0,29863890,30;2,62,153,5,150,0,0,0,0;2,62,153,312,5,1,2,29866080,30;3,182,33,302,103,1,0,29861280,7200;3,182,33,57,0,0,0,0,0;3,182,33,182,890,1,0,29859840,7200;3,182,33,5,30,0,0,0,0;3,182,33,432,5,1,0,29862720,7200;4,182,53,302,123,1,2,29865600,4320;4,182,53,57,20,0,0,0,0;4,182,53,182,890,1,1,29864160,4320;4,182,53,5,50,0,0,0,0;4,182,53,432,5,1,3,29867040,4320;5,182,153,302,223,1,2,29866200,30;5,182,153,57,120,0,0,0,0;5,182,153,182,890,1,1,29865330,30;5,182,153,5,150,0,0,0,0;5,182,153,432,5,1,3,29867520,30;6,182,213,302,283,1,2,29866260,90;6,182,213,57,180,0,0,0,0;6,182,213,182,890,1,1,29865330,90;6,182,213,5,210,0,0,0,0;6,182,213,432,5,1,3,29867520,90;7,222,243,342,313,1,2,29866290,60;7,222,243,97,210,1,0,29863290,60;7,222,243,222,890,1,1,29865330,60;7,222,243,5,240,0,0,0,0;7,222,243,472,5,1,3,29867520,60;8,262,273,382,343,1,2,29866320,30;8,262,273,137,240,1,0,29863320,30;8,262,273,262,890,1,1,29865330,30;8,262,273,5,270,0,0,0,0;8,262,273,512,5,1,3,29867520,30;9,302,33,422,103,1,0,29861280,7200;9,302,33,177,0,1,0,29856960,7200;9,302,33,302,890,1,0,29859840,7200;9,302,33,5,30,0,0,0,0;9,302,33,552,5,1,0,29862720,7200;10,302,53,422,123,1,2,29865600,4320;10,302,53,177,20,1,0,29861280,4320;10,302,53,302,890,1,1,29864160,4320;10,302,53,5,50,0,0,0,0;10,302,53,552,5,1,3,29867040,4320;11,302,73,422,143,1,3,29867040,2880;11,302,73,177,40,1,0,29862720,2880;11,302,73,302,890,1,2,29865600,2880;11,302,73,5,70,0,0,0,0;11,302,73,552,5,1,4,29868480,2880;12,302,153,422,223,1,3,29867640,30;12,302,153,177,120,1,0,29863200,30;12,302,153,302,890,1,2,29866770,30;12,302,153,5,150,0,0,0,0;12,302,153,552,5,1,4,29868960,30;13,302,393,422,463,1,3,29867880,180;13,302,393,177,360,1,0,29863440,180;13,302,393,302,890,1,2,29866770,180;13,302,393,5,390,0,0,0,0;13,302,393,552,5,1,4,29868960,180;14,362,513,482,583,1,3,29868000,60;14,362,513,237,480,1,1,29865000,60;14,362,513,362,890,1,2,29866770,60;14,362,513,5,510,0,0,0,0;14,362,513,612,5,1,4,29868960,60;15,422,33,542,103,1,2,29865600,4320;15,422,33,297,0,1,0,29861280,4320;15,422,33,422,890,1,1,29864160,4320;15,422,33,5,30,0,0,0,0;15,422,33,672,5,1,3,29867040,4320;16,422,53,542,123,1,3,29867040,2880;16,422,53,297,20,1,0,29862720,2880;16,422,53,422,890,1,2,29865600,2880;16,422,53,5,50,0,0,0,0;16,422,53,672,5,1,4,29868480,2880;17,422,153,542,223,1,4,29869080,30;17,422,153,297,120,1,1,29864640,30;17,422,153,422,890,1,3,29868210,30;17,422,153,5,150,0,0,0,0;17,422,153,672,5,1,5,29870400,30;18,422,213,542,283,1,4,29869140,60;18,422,213,297,180,1,1,29864700,60;18,422,213,422,890,1,3,29868210,60;18,422,213,5,210,0,0,0,0;18,422,213,672,5,1,5,29870400,60;19,422,753,542,823,1,4,29869650,360;19,422,753,297,720,1,1,29865240,360;19,422,753,422,890,1,3,29868210,360;19,422,753,5,750,0,0,0,0;19,422,753,672,5,1,5,29870400,360;20,542,33,662,103,1,5,29869920,1440;20,542,33,417,0,1,2,29865600,1440;20,542,33,542,890,1,4,29868480,1440;20,542,33,5,30,0,0,0,0;20,542,33,792,5,1,6,29871360,1440;21,542,153,662,223,1,5,29870520,120;21,542,153,417,120,1,2,29866080,120;21,542,153,542,890,1,4,29869650,120;21,542,153,5,150,0,0,0,0;21,542,153,792,5,1,6,29871840,120;22,572,153,692,223,1,5,29870520,60;22,572,153,447,120,1,3,29867520,60;22,572,153,572,890,1,4,29869650,60;22,572,153,5,150,0,0,0,0;22,572,153,822,5,1,6,29871840,60;23,602,153,722,223,1,5,29870520,30;23,602,153,477,120,1,3,29867520,30;23,602,153,602,890,1,4,29869650,30;23,602,153,5,150,0,0,0,0;23,602,153,852,5,1,6,29871840,30;24,602,183,722,253,1,5,29870550,60;24,602,183,477,150,1,3,29867550,60;24,602,183,602,890,1,4,29869650,60;24,602,183,5,180,0,0,0,0;24,602,183,852,5,1,6,29871840,60;25,632,198,752,268,1,5,29870550,30;25,632,198,507,165,1,3,29867580,30;25,632,198,632,890,1,4,29869650,30;25,632,198,5,195,0,0,0,0;25,632,198,882,5,1,6,29871840,30;26,572,228,692,298,1,5,29870580,45;26,572,228,447,195,1,3,29867610,45;26,572,228,572,890,1,4,29869650,45;26,572,228,5,225,0,0,0,0;26,572,228,822,5,1,6,29871840,45;27,542,453,662,523,1,5,29870820,30;27,542,453,417,420,1,2,29866380,30;27,542,453,542,890,1,4,29869650,30;27,542,453,5,450,0,0,0,0;27,542,453,792,5,1,6,29871840,30;28,662,333,782,403,1,6,29872140,1;28,662,333,537,300,1,3,29867700,1;28,662,333,662,890,1,5,29871090,1;28,662,333,5,330,0,0,0,0;28,662,333,912,5,0,0,0,0" }

fn resizes_w1() -> str { ret "0,67,0,0;0,31,0,0;0,60,0,0;0,860,0,0;0,150,0,0;1,87,0,0;1,51,0,0;1,60,0,0;1,860,0,0;1,170,0,0;2,197,1,60;2,151,1,30;2,60,1,30;2,860,1,660;2,280,1,150;3,67,0,0;3,31,0,0;3,60,0,0;3,860,0,0;3,150,0,0;4,87,0,0;4,51,0,0;4,60,0,0;4,860,0,0;4,170,0,0;5,197,1,60;5,151,1,30;5,60,1,30;5,860,1,660;5,280,1,150;6,317,1,120;6,211,1,30;6,60,1,30;6,860,1,600;6,400,1,210;7,317,1,90;7,241,1,30;7,60,1,30;7,860,1,570;7,400,1,180;8,317,1,60;8,271,1,30;8,60,1,30;8,860,1,540;8,400,1,150;9,67,0,0;9,31,0,0;9,60,0,0;9,860,0,0;9,150,0,0;10,87,0,0;10,51,0,0;10,60,0,0;10,860,0,0;10,170,0,0;11,107,0,0;11,71,0,0;11,60,0,0;11,860,0,0;11,190,0,0;12,197,1,60;12,151,1,30;12,60,1,30;12,860,1,660;12,280,1,150;13,587,1,210;13,391,1,30;13,60,1,30;13,860,1,420;13,670,1,300;14,587,1,90;14,511,1,30;14,60,1,30;14,860,1,300;14,670,1,180;15,67,0,0;15,31,0,0;15,60,0,0;15,860,0,0;15,150,0,0;16,87,0,0;16,51,0,0;16,60,0,0;16,860,0,0;16,170,0,0;17,197,1,60;17,151,1,30;17,60,1,30;17,860,1,660;17,280,1,150;18,287,1,90;18,211,1,30;18,60,1,30;18,860,1,600;18,370,1,180;19,827,0,0;19,751,0,0;19,60,0,0;19,860,0,0;19,910,0,0;20,67,0,0;20,31,0,0;20,60,0,0;20,860,0,0;20,150,0,0;21,287,1,150;21,151,1,30;21,60,1,30;21,860,1,660;21,370,1,240;22,227,1,90;22,151,1,30;22,60,1,30;22,860,1,660;22,310,1,180;23,197,1,60;23,151,1,30;23,60,1,30;23,860,1,660;23,280,1,150;24,257,1,90;24,181,1,30;24,60,1,30;24,860,1,630;24,340,1,180;25,242,1,75;25,196,1,15;25,60,1,30;25,860,1,615;25,325,1,135;26,287,1,75;26,226,1,15;26,60,1,30;26,860,1,585;26,370,1,165;27,497,1,60;27,451,1,30;27,60,1,30;27,860,1,360;27,580,1,150;28,359,1,30;28,331,1,30;28,60,1,30;28,860,1,480;28,442,1,120" }

fn focus_w1() -> str { ret "0,0,0;0,1,3;0,2,0;0,3,1;0,4,0;0,5,2;1,0,1;1,1,3;1,2,0;1,3,2;1,4,0;1,5,2;2,0,2;2,1,3;2,2,1;2,3,2;2,4,0;2,5,2;3,0,2;3,1,9;3,2,3;3,3,4;3,4,3;3,5,8;4,0,2;4,1,9;4,2,3;4,3,5;4,4,3;4,5,8;5,0,2;5,1,9;5,2,4;5,3,6;5,4,3;5,5,8;6,0,2;6,1,9;6,2,5;6,3,7;6,4,3;6,5,8;7,0,2;7,1,9;7,2,6;7,3,8;7,4,3;7,5,8;8,0,2;8,1,9;8,2,7;8,3,8;8,4,3;8,5,8;9,0,8;9,1,15;9,2,9;9,3,10;9,4,9;9,5,14;10,0,8;10,1,15;10,2,9;10,3,11;10,4,9;10,5,14;11,0,8;11,1,15;11,2,10;11,3,12;11,4,9;11,5,14;12,0,8;12,1,15;12,2,11;12,3,13;12,4,9;12,5,14;13,0,8;13,1,15;13,2,12;13,3,14;13,4,9;13,5,14;14,0,8;14,1,15;14,2,13;14,3,14;14,4,9;14,5,14;15,0,14;15,1,20;15,2,15;15,3,16;15,4,15;15,5,19;16,0,14;16,1,20;16,2,15;16,3,17;16,4,15;16,5,19;17,0,14;17,1,20;17,2,16;17,3,18;17,4,15;17,5,19;18,0,14;18,1,20;18,2,17;18,3,19;18,4,15;18,5,19;19,0,14;19,1,20;19,2,18;19,3,19;19,4,15;19,5,19;20,0,19;20,1,28;20,2,20;20,3,21;20,4,20;20,5,27;21,0,19;21,1,28;21,2,20;21,3,22;21,4,20;21,5,27;22,0,19;22,1,28;22,2,21;22,3,23;22,4,20;22,5,27;23,0,19;23,1,28;23,2,22;23,3,24;23,4,20;23,5,27;24,0,19;24,1,28;24,2,23;24,3,25;24,4,20;24,5,27;25,0,19;25,1,28;25,2,24;25,3,26;25,4,20;25,5,27;26,0,19;26,1,28;26,2,25;26,3,27;26,4,20;26,5,27;27,0,19;27,1,28;27,2,26;27,3,27;27,4,20;27,5,27;28,0,27;28,1,28;28,2,28;28,3,28;28,4,28;28,5,28" }

fn cfg_d1() -> sched.Config {
    ret sched.Config { mode: .Day, anchor: time.Date { year: 2026, month: 10u8, day: 16u8 }, week_start: .Monday, day_start: 8u32, day_end: 20u32, slot: 30u32, agenda_days: 10u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn want_bars_d1() -> str { ret "L 1 1\nB 8 0 0 0 60 30 840 20 0 0 0\n" }

fn moves_d1() -> str { ret "0,62,33,182,103,1,0,29868480,1440;0,62,33,-63,0,0,0,0,0;0,62,33,62,850,1,0,29868480,1440;0,62,33,5,30,0,0,0,0;0,62,33,312,5,1,0,29868480,1440;1,62,113,182,183,1,0,29869080,120;1,62,113,-63,80,0,0,0,0;1,62,113,62,850,1,0,29869650,120;1,62,113,5,110,0,0,0,0;1,62,113,312,5,1,0,29868960,120;2,272,113,392,183,1,0,29869080,60;2,272,113,147,80,1,0,29868960,60;2,272,113,272,850,1,0,29869650,60;2,272,113,5,110,0,0,0,0;2,272,113,522,5,1,0,29868960,60;3,482,113,602,183,1,0,29869080,30;3,482,113,357,80,1,0,29868960,30;3,482,113,482,850,1,0,29869650,30;3,482,113,5,110,0,0,0,0;3,482,113,732,5,1,0,29868960,30;4,482,143,602,213,1,0,29869110,60;4,482,143,357,110,1,0,29868990,60;4,482,143,482,850,1,0,29869650,60;4,482,143,5,140,0,0,0,0;4,482,143,732,5,1,0,29868960,60;5,692,158,812,228,1,0,29869110,30;5,692,158,567,125,1,0,29869020,30;5,692,158,692,850,1,0,29869650,30;5,692,158,5,155,0,0,0,0;5,692,158,942,5,0,0,0,0;6,272,188,392,258,1,0,29869140,45;6,272,188,147,155,1,0,29869050,45;6,272,188,272,850,1,0,29869650,45;6,272,188,5,185,0,0,0,0;6,272,188,522,5,1,0,29868960,45;7,62,413,182,483,1,0,29869380,30;7,62,413,-63,380,0,0,0,0;7,62,413,62,850,1,0,29869650,30;7,62,413,5,410,0,0,0,0;7,62,413,312,5,1,0,29868960,30" }

fn resizes_d1() -> str { ret "0,67,0,0;0,31,0,0;0,20,0,0;0,820,0,0;0,150,0,0;1,247,1,150;1,111,1,30;1,20,1,30;1,820,1,660;1,330,1,240;2,187,1,90;2,111,1,30;2,20,1,30;2,820,1,660;2,270,1,180;3,157,1,60;3,111,1,30;3,20,1,30;3,820,1,660;3,240,1,150;4,217,1,90;4,141,1,30;4,20,1,30;4,820,1,630;4,300,1,180;5,202,1,75;5,156,1,15;5,20,1,30;5,820,1,615;5,285,1,135;6,247,1,75;6,186,1,15;6,20,1,30;6,820,1,585;6,330,1,165;7,457,1,60;7,411,1,30;7,20,1,30;7,820,1,360;7,540,1,150" }

fn focus_d1() -> str { ret "0,0,0;0,1,0;0,2,0;0,3,1;0,4,0;0,5,7;1,0,1;1,1,1;1,2,0;1,3,2;1,4,0;1,5,7;2,0,2;2,1,2;2,2,1;2,3,3;2,4,0;2,5,7;3,0,3;3,1,3;3,2,2;3,3,4;3,4,0;3,5,7;4,0,4;4,1,4;4,2,3;4,3,5;4,4,0;4,5,7;5,0,5;5,1,5;5,2,4;5,3,6;5,4,0;5,5,7;6,0,6;6,1,6;6,2,5;6,3,7;6,4,0;6,5,7;7,0,7;7,1,7;7,2,6;7,3,7;7,4,0;7,5,7" }

fn cfg_a1() -> sched.Config {
    ret sched.Config { mode: .Agenda, anchor: time.Date { year: 2026, month: 10u8, day: 12u8 }, week_start: .Monday, day_start: 8u32, day_end: 20u32, slot: 30u32, agenda_days: 10u32, width: 900.0, gutter: 60.0, header: 30.0, all_day_h: 20.0, hour_h: 60.0, row_h: 24.0, min_h: 12.0 }
}

fn focus_a1() -> str { ret "0,0,0;0,1,0;0,2,0;0,3,1;0,4,0;0,5,37;1,0,1;1,1,1;1,2,0;1,3,2;1,4,0;1,5,37;2,0,2;2,1,2;2,2,1;2,3,3;2,4,0;2,5,37;3,0,3;3,1,3;3,2,2;3,3,4;3,4,0;3,5,37;4,0,4;4,1,4;4,2,3;4,3,5;4,4,0;4,5,37;5,0,5;5,1,5;5,2,4;5,3,6;5,4,0;5,5,37;6,0,6;6,1,6;6,2,5;6,3,7;6,4,0;6,5,37;7,0,7;7,1,7;7,2,6;7,3,8;7,4,0;7,5,37;8,0,8;8,1,8;8,2,7;8,3,9;8,4,0;8,5,37;9,0,9;9,1,9;9,2,8;9,3,10;9,4,0;9,5,37;10,0,10;10,1,10;10,2,9;10,3,11;10,4,0;10,5,37;11,0,11;11,1,11;11,2,10;11,3,12;11,4,0;11,5,37;12,0,12;12,1,12;12,2,11;12,3,13;12,4,0;12,5,37;13,0,13;13,1,13;13,2,12;13,3,14;13,4,0;13,5,37;14,0,14;14,1,14;14,2,13;14,3,15;14,4,0;14,5,37;15,0,15;15,1,15;15,2,14;15,3,16;15,4,0;15,5,37;16,0,16;16,1,16;16,2,15;16,3,17;16,4,0;16,5,37;17,0,17;17,1,17;17,2,16;17,3,18;17,4,0;17,5,37;18,0,18;18,1,18;18,2,17;18,3,19;18,4,0;18,5,37;19,0,19;19,1,19;19,2,18;19,3,20;19,4,0;19,5,37;20,0,20;20,1,20;20,2,19;20,3,21;20,4,0;20,5,37;21,0,21;21,1,21;21,2,20;21,3,22;21,4,0;21,5,37;22,0,22;22,1,22;22,2,21;22,3,23;22,4,0;22,5,37;23,0,23;23,1,23;23,2,22;23,3,24;23,4,0;23,5,37;24,0,24;24,1,24;24,2,23;24,3,25;24,4,0;24,5,37;25,0,25;25,1,25;25,2,24;25,3,26;25,4,0;25,5,37;26,0,26;26,1,26;26,2,25;26,3,27;26,4,0;26,5,37;27,0,27;27,1,27;27,2,26;27,3,28;27,4,0;27,5,37;28,0,28;28,1,28;28,2,27;28,3,29;28,4,0;28,5,37;29,0,29;29,1,29;29,2,28;29,3,30;29,4,0;29,5,37;30,0,30;30,1,30;30,2,29;30,3,31;30,4,0;30,5,37;31,0,31;31,1,31;31,2,30;31,3,32;31,4,0;31,5,37;32,0,32;32,1,32;32,2,31;32,3,33;32,4,0;32,5,37;33,0,33;33,1,33;33,2,32;33,3,34;33,4,0;33,5,37;34,0,34;34,1,34;34,2,33;34,3,35;34,4,0;34,5,37;35,0,35;35,1,35;35,2,34;35,3,36;35,4,0;35,5,37;36,0,36;36,1,36;36,2,35;36,3,37;36,4,0;36,5,37;37,0,37;37,1,37;37,2,36;37,3,37;37,4,0;37,5,37" }

fn de_week_labels() -> str { ret "Wochenplan\nMontag 12 Oktober 2026\nTrip, ganztaegig\nStanding, ganztaegig, wiederholt\nStandup, 09:00 bis 09:30, wiederholt\nDienstag 13 Oktober 2026\nTrip, ganztaegig\nOffsite, ganztaegig\nStandup, 09:00 bis 09:30, wiederholt\nDesign review, 10:00 bis 11:30\nLunch, 10:30 bis 11:30\nCall, 11:00 bis 11:30\nMittwoch 14 Oktober 2026\nTrip, ganztaegig\nOffsite, ganztaegig\nConference, ganztaegig\nStandup, 09:00 bis 09:30, wiederholt\nWorkshop, 13:00 bis 16:00\nWeekly sync, 15:00 bis 16:00, wiederholt\nDonnerstag 15 Oktober 2026\nOffsite, ganztaegig\nConference, ganztaegig\nStandup, 09:00 bis 09:30, wiederholt\nMonthly, 10:00 bis 11:00, wiederholt\nOvernight, 19:00 bis 20:00\nFreitag 16 Oktober 2026\nHoliday, ganztaegig\nChain D, 09:00 bis 11:00\nChain A, 09:00 bis 10:00\nStandup, 09:00 bis 09:30, wiederholt\nChain B, 09:30 bis 10:30\nChain E, 09:45 bis 10:15\nChain C, 10:15 bis 11:00\nAfternoon, 14:00 bis 14:30\nSamstag 17 Oktober 2026\nZero length, 12:00 bis 12:01\nSonntag 18 Oktober 2026" }
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
    if r == .ListItem { ret "ListItem" }
    ret "Other"
}

fn num(b: *str.Builder, v: f32) -> err { ret str.push_u32(b, u32(v)) }

fn flag(b: *str.Builder, v: bool) -> err {
    if v { ret str.push(b, "1") }
    ret str.push(b, "0")
}

fn sp(b: *str.Builder) -> err { ret str.push(b, " ") }

fn render_month(b: *str.Builder, l: *const sched.MonthLayout) -> err {
    try str.push(b, "M ")
    try str.push_u64(b, u64(l.first_day))
    try sp(b)
    try str.push_u32(b, l.weeks)
    try sp(b)
    try num(b, l.height)
    try str.push(b, "\n")
    var i = 0usize
    while i < l.cell_count {
        let c = l.cells[i]
        try str.push(b, "C ")
        try str.push_u64(b, u64(c.count))
        try sp(b)
        try flag(b, c.in_month)
        try sp(b)
        try num(b, c.x)
        try sp(b)
        try num(b, c.y)
        try sp(b)
        try num(b, c.w)
        try sp(b)
        try num(b, c.h)
        try sp(b)
        try str.push_u32(b, c.first)
        try sp(b)
        try str.push_u32(b, c.total)
        try sp(b)
        try str.push_u32(b, c.shown)
        try sp(b)
        try str.push_u32(b, c.more)
        try str.push(b, "\n")
        i += 1usize
    }
    i = 0usize
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
        try sp(b)
        try str.push_u64(b, u64(p.start))
        try sp(b)
        try str.push_u64(b, u64(p.end))
        try sp(b)
        try num(b, p.x)
        try sp(b)
        try num(b, p.y)
        try sp(b)
        try num(b, p.w)
        try sp(b)
        try num(b, p.h)
        try sp(b)
        try str.push_u32(b, p.lane)
        try sp(b)
        try str.push_u32(b, p.lanes)
        try sp(b)
        try flag(b, p.before)
        try sp(b)
        try flag(b, p.after)
        try sp(b)
        try flag(b, p.recurring)
        try str.push(b, "\n")
        i += 1usize
    }
    i = 0usize
    while i < l.node_count {
        let n = l.nodes[i]
        try str.push(b, "N ")
        try str.push(b, role_name(n.role))
        try sp(b)
        try num(b, n.x)
        try sp(b)
        try num(b, n.y)
        try sp(b)
        try num(b, n.w)
        try sp(b)
        try num(b, n.h)
        try sp(b)
        try str.push(b, sched.month_label_of(l, i))
        try sp(b)
        try str.push_u32(b, n.row)
        try sp(b)
        try str.push_u32(b, n.column)
        try sp(b)
        try str.push_u32(b, n.row_count)
        try sp(b)
        try str.push_u32(b, n.column_count)
        try sp(b)
        try str.push_u32(b, u32(n.level))
        try str.push(b, "\n")
        i += 1usize
    }
    ret ok
}

fn render_bars(b: *str.Builder, bars: []const sched.Bar, count: usize, lanes: u32) -> err {
    try str.push(b, "L ")
    try str.push_u32(b, lanes)
    try sp(b)
    try str.push_u64(b, u64(count))
    try str.push(b, "\n")
    var i = 0usize
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
        try str.push(b, "\n")
        i += 1usize
    }
    ret ok
}

// The integer at `from` in a list; the next position (after the separator).
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

fn key_of(code: i32) -> sched.Key {
    if code == 0i32 { ret .Left }
    if code == 1i32 { ret .Right }
    if code == 2i32 { ret .Up }
    if code == 3i32 { ret .Down }
    if code == 4i32 { ret .Home }
    ret .End
}

fn month_kind_code(k: sched.MonthHitKind) -> i32 {
    if k == .Header { ret 1i32 }
    if k == .Cell { ret 2i32 }
    if k == .Event { ret 3i32 }
    if k == .More { ret 4i32 }
    ret 0i32
}

// "x,y,kind,cell,index;...": the first failing probe number, or zero.
fn run_month_hits(l: *const sched.MonthLayout, list: str) -> u32 {
    var pos = 0usize
    var n = 0u32
    while pos < list.len {
        let (x, p1) = next_int(list, pos)
        let (y, p2) = next_int(list, p1)
        let (kind, p3) = next_int(list, p2)
        let (cell, p4) = next_int(list, p3)
        let (index, p5) = next_int(list, p4)
        pos = p5
        n += 1u32
        let h = sched.hit_month(l, f32(x), f32(y))
        if month_kind_code(h.kind) != kind { ret n }
        if kind != 0i32 && i32(h.cell) != cell { ret n }
        if (kind == 3i32 || kind == 4i32) && i32(h.index) != index { ret n }
    }
    ret 0u32
}

fn run_month_moves(l: *const sched.MonthLayout, list: str) -> u32 {
    var pos = 0usize
    var n = 0u32
    while pos < list.len {
        let (cell, p1) = next_int(list, pos)
        let (key, p2) = next_int(list, p1)
        let (want, p3) = next_int(list, p2)
        pos = p3
        n += 1u32
        if i32(sched.month_move(l, u32(cell), key_of(key))) != want { ret n }
    }
    ret 0u32
}

fn abs_of(d: calendar.DateTime) -> i64 {
    ret calendar.day_count(d.date) * 1440i64 + i64(d.time.hour) * 60i64 + i64(d.time.minute)
}

// "index,gx,gy,x,y,ok,day,start,minutes;..."
fn run_moves(l: *const sched.Layout, items: []const sched.Item, list: str) -> u32 {
    var pos = 0usize
    var n = 0u32
    while pos < list.len {
        let (index, p1) = next_int(list, pos)
        let (gx, p2) = next_int(list, p1)
        let (gy, p3) = next_int(list, p2)
        let (x, p4) = next_int(list, p3)
        let (y, p5) = next_int(list, p4)
        let (good, p6) = next_int(list, p5)
        let (day, p7) = next_int(list, p6)
        let (start, p8) = next_int(list, p7)
        let (minutes, p9) = next_int(list, p8)
        pos = p9
        n += 1u32
        let (span, found) = sched.move_target(l, items, usize(index), f32(gx), f32(gy), f32(x), f32(y))
        if found != (good == 1i32) { ret n }
        if found {
            if i32(span.day) != day || abs_of(span.start) != i64(start) || i32(span.minutes) != minutes { ret n }
        }
    }
    ret 0u32
}

// "index,y,ok,minutes;..."
fn run_resizes(l: *const sched.Layout, list: str) -> u32 {
    var pos = 0usize
    var n = 0u32
    while pos < list.len {
        let (index, p1) = next_int(list, pos)
        let (y, p2) = next_int(list, p1)
        let (good, p3) = next_int(list, p2)
        let (minutes, p4) = next_int(list, p3)
        pos = p4
        n += 1u32
        let (got, found) = sched.resize_target(l, usize(index), f32(y))
        if found != (good == 1i32) { ret n }
        if found && i32(got) != minutes { ret n }
    }
    ret 0u32
}

// "index,key,result;..."
fn run_focus(l: *const sched.Layout, list: str) -> u32 {
    var pos = 0usize
    var n = 0u32
    while pos < list.len {
        let (index, p1) = next_int(list, pos)
        let (key, p2) = next_int(list, p1)
        let (want, p3) = next_int(list, p2)
        pos = p3
        n += 1u32
        if i32(sched.focus_next(l, usize(index), key_of(key))) != want { ret n }
    }
    ret 0u32
}

fn storage(a: *mem.Arena, occ: usize, placed: usize, labels: usize) -> (sched.Storage, err) {
    let (o, e1) = mem.alloc[sched.Occ](a, occ)
    if e1 != ok { ret (zero, e1) }
    let (s, e2) = mem.alloc[calendar.DateTime](a, 128usize)
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

fn month_storage(a: *mem.Arena, occ: usize, placed: usize, labels: usize, cells: usize) -> (sched.MonthStorage, err) {
    let (o, e1) = mem.alloc[sched.Occ](a, occ)
    if e1 != ok { ret (zero, e1) }
    let (s, e2) = mem.alloc[calendar.DateTime](a, 128usize)
    if e2 != ok { ret (zero, e2) }
    let (p, e3) = mem.alloc[sched.Placed](a, placed)
    if e3 != ok { ret (zero, e3) }
    let (c, e4) = mem.alloc[sched.MonthCell](a, cells)
    if e4 != ok { ret (zero, e4) }
    let (n, e5) = mem.alloc[sched.Access](a, placed + 64usize)
    if e5 != ok { ret (zero, e5) }
    let (lb, e6) = mem.alloc[u8](a, labels)
    if e6 != ok { ret (zero, e6) }
    let (ord, e7) = mem.alloc[u32](a, occ)
    if e7 != ok { ret (zero, e7) }
    ret (sched.MonthStorage { occ: o, stamps: s, placed: p, cells: c, order: ord, nodes: n, labels: lb }, ok)
}

fn month_text(a: *mem.Arena, l: *const sched.MonthLayout) -> (str, err) {
    let (bld, bld_error) = str.builder(a, 32768usize)
    if bld_error != ok { ret ("", bld_error) }
    var b = bld
    try render_month(&b, l)
    ret (str.done(&b), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var raw: [32]sched.Item = zero
    let n = all_items(raw[0..])
    let items = raw[0usize..n]
    let (ms, ms_error) = month_storage(a, 256usize, 256usize, 16384usize, 42usize)
    if ms_error != ok { os.exit(1) }

    // The three months against the model, then October in German words.
    var which = 0usize
    while which < 4usize {
        var cfg = mcfg_m1()
        var want: str = want_m1()
        if which == 1usize {
            cfg = mcfg_m2()
            want = want_m2()
        } else if which == 2usize {
            cfg = mcfg_m3()
            want = want_m3()
        }
        var l: sched.MonthLayout = zero
        var build_error: err = ok
        if which == 3usize {
            let (l3, e3) = sched.build_month_named(items, mcfg_m1(), ms, de_names())
            l = l3
            build_error = e3
            want = want_m1_de()
        } else {
            let (l0, e0) = sched.build_month(items, cfg, ms)
            l = l0
            build_error = e0
        }
        if build_error != ok { os.exit(2 + i32(which)) }
        let (got, text_error) = month_text(a, &l)
        if text_error != ok { os.exit(6) }
        if !str.eq(got, want) {
            try io.print(got)
            os.exit(10 + i32(which))
        }
        if l.truncated { os.exit(14) }
        if which == 0usize {
            if run_month_hits(&l, hits_m1()) != 0u32 { os.exit(20) }
            if run_month_moves(&l, moves_m1()) != 0u32 { os.exit(21) }
        } else if which == 1usize {
            if run_month_hits(&l, hits_m2()) != 0u32 { os.exit(22) }
        }
        which += 1usize
    }

    // The week, the day and the agenda: bars, moves, resizes and focus.
    let (st, st_error) = storage(a, 256usize, 256usize, 16384usize)
    if st_error != ok { os.exit(30) }
    var bars: [32]sched.Bar = zero
    var view = 0usize
    while view < 3usize {
        var cfg = cfg_w1()
        if view == 1usize { cfg = cfg_d1() }
        if view == 2usize { cfg = cfg_a1() }
        let (l, build_error) = sched.build(items, cfg, st)
        if build_error != ok { os.exit(31 + i32(view)) }
        if view < 2usize {
            let (count, lanes, bar_error) = sched.all_day_bars(&l, bars[0..])
            if bar_error != ok { os.exit(34 + i32(view)) }
            let (bld, bld_error) = str.builder(a, 8192usize)
            if bld_error != ok { os.exit(36) }
            var b = bld
            if render_bars(&b, bars[0usize..count], count, lanes) != ok { os.exit(37) }
            var want_bars: str = want_bars_w1()
            if view == 1usize { want_bars = want_bars_d1() }
            if !str.eq(str.done(&b), want_bars) { os.exit(38 + i32(view)) }
            var moves: str = moves_w1()
            var resizes: str = resizes_w1()
            if view == 1usize {
                moves = moves_d1()
                resizes = resizes_d1()
            }
            if run_moves(&l, items, moves) != 0u32 { os.exit(40 + i32(view)) }
            if run_resizes(&l, resizes) != 0u32 { os.exit(42 + i32(view)) }
        }
        var focus: str = focus_w1()
        if view == 1usize { focus = focus_d1() }
        if view == 2usize { focus = focus_a1() }
        if run_focus(&l, focus) != 0u32 { os.exit(44 + i32(view)) }
        view += 1usize
    }

    // The agenda has no bars; a bars buffer that is too small is refused.
    let (agenda, agenda_error) = sched.build(items, cfg_a1(), st)
    if agenda_error != ok { os.exit(50) }
    let (_, _, no_bars) = sched.all_day_bars(&agenda, bars[0..])
    if no_bars != sched.Invalid { os.exit(51) }
    let (week, week_error) = sched.build(items, cfg_w1(), st)
    if week_error != ok { os.exit(52) }
    var two: [2]sched.Bar = zero
    let (_, _, small) = sched.all_day_bars(&week, two[0..])
    if small != sched.TooLarge { os.exit(53) }

    // The German week's labels: the grid, each header and each cell.
    let (german, german_error) = sched.build_named(items, cfg_w1(), st, de_names())
    if german_error != ok { os.exit(54) }
    let (bld, bld_error) = str.builder(a, 8192usize)
    if bld_error != ok { os.exit(55) }
    var lb = bld
    var node = 0usize
    while node < german.node_count {
        if node > 0usize {
            if str.push(&lb, "\n") != ok { os.exit(56) }
        }
        if str.push(&lb, sched.label_of(&german, node)) != ok { os.exit(56) }
        node += 1usize
    }
    if !str.eq(str.done(&lb), de_week_labels()) { os.exit(57) }

    // Refusals: a month outside 1..12, no cells for the weeks, a bad rule.
    var bad_cfg = mcfg_m1()
    bad_cfg.anchor.month = 13u8
    let (_, bad_month) = sched.build_month(items, bad_cfg, ms)
    if bad_month != sched.Invalid { os.exit(60) }
    var no_size = mcfg_m1()
    no_size.cell_h = 0.0
    let (_, bad_size) = sched.build_month(items, no_size, ms)
    if bad_size != sched.Invalid { os.exit(61) }
    let (tiny, tiny_error) = month_storage(a, 256usize, 256usize, 16384usize, 20usize)
    if tiny_error != ok { os.exit(62) }
    let (_, no_cells) = sched.build_month(items, mcfg_m1(), tiny)
    if no_cells != sched.TooLarge { os.exit(63) }
    var bad_items = raw
    bad_items[0usize].rule = "FREQ=SOMETIMES"
    let (_, bad_rule) = sched.build_month(bad_items[0usize..n], mcfg_m1(), ms)
    if bad_rule != sched.Invalid { os.exit(64) }

    try io.print("ui schedule month ok\n")
    ret ok
}
