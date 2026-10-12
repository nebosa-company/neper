// `e.ui.schedule` (L148, D3602): a display zone and DST (build_month_zoned, display_to_source) and the month's
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

fn z1_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 2u8, 2u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Weekly 9", rule: "FREQ=WEEKLY;COUNT=30" }
    out[1usize] = sched.Item { id: 2u32, start: at(2026, 3u8, 8u8, 2u8, 30u8), minutes: 30u32, all_day: false, title: "Gap", rule: "" }
    out[2usize] = sched.Item { id: 3u32, start: at(2026, 3u8, 10u8, 20u8, 30u8), minutes: 120u32, all_day: false, title: "Late NY", rule: "" }
    out[3usize] = sched.Item { id: 4u32, start: at(2026, 3u8, 12u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "Floating", rule: "" }
    out[4usize] = sched.Item { id: 5u32, start: at(2026, 3u8, 5u8, 23u8, 30u8), minutes: 45u32, all_day: false, title: "Night", rule: "FREQ=DAILY;COUNT=10" }
    out[5usize] = sched.Item { id: 6u32, start: at(2026, 3u8, 28u8, 22u8, 0u8), minutes: 600u32, all_day: false, title: "Overnight", rule: "" }
    ret 6usize
}

fn z1_cfg() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 3u8, day: 14u8 }, week_start: .Monday, width: 700.0, header: 30.0, cell_h: 120.0, line_h: 20.0, lines: 4u32 }
}

fn z1_want() -> str { ret "M 20507 6 750\nC 20507 0 0 30 100 120 0 1 1 0\nC 20508 0 100 30 100 120 1 0 0 0\nC 20509 0 200 30 100 120 1 0 0 0\nC 20510 0 300 30 100 120 1 0 0 0\nC 20511 0 400 30 100 120 1 0 0 0\nC 20512 0 500 30 100 120 1 0 0 0\nC 20513 1 600 30 100 120 1 0 0 0\nC 20514 1 0 150 100 120 1 1 1 0\nC 20515 1 100 150 100 120 2 0 0 0\nC 20516 1 200 150 100 120 2 0 0 0\nC 20517 1 300 150 100 120 2 0 0 0\nC 20518 1 400 150 100 120 2 1 1 0\nC 20519 1 500 150 100 120 3 1 1 0\nC 20520 1 600 150 100 120 4 2 2 0\nC 20521 1 0 270 100 120 6 2 2 0\nC 20522 1 100 270 100 120 8 1 1 0\nC 20523 1 200 270 100 120 9 2 2 0\nC 20524 1 300 270 100 120 11 2 2 0\nC 20525 1 400 270 100 120 13 1 1 0\nC 20526 1 500 270 100 120 14 1 1 0\nC 20527 1 600 270 100 120 15 1 1 0\nC 20528 1 0 390 100 120 16 1 1 0\nC 20529 1 100 390 100 120 17 0 0 0\nC 20530 1 200 390 100 120 17 0 0 0\nC 20531 1 300 390 100 120 17 0 0 0\nC 20532 1 400 390 100 120 17 0 0 0\nC 20533 1 500 390 100 120 17 0 0 0\nC 20534 1 600 390 100 120 17 0 0 0\nC 20535 1 0 510 100 120 17 1 1 0\nC 20536 1 100 510 100 120 18 0 0 0\nC 20537 1 200 510 100 120 18 0 0 0\nC 20538 1 300 510 100 120 18 0 0 0\nC 20539 1 400 510 100 120 18 0 0 0\nC 20540 1 500 510 100 120 18 0 0 0\nC 20541 1 600 510 100 120 18 1 1 0\nC 20542 1 0 630 100 120 19 1 1 0\nC 20543 1 100 630 100 120 20 0 0 0\nC 20544 0 200 630 100 120 20 0 0 0\nC 20545 0 300 630 100 120 20 0 0 0\nC 20546 0 400 630 100 120 20 0 0 0\nC 20547 0 500 630 100 120 20 0 0 0\nC 20548 0 600 630 100 120 20 0 0 0\nP 0 T 0 29531040 29531100 0 50 100 20 0 1 0 0 1\nP 0 T 7 29541120 29541180 0 170 100 20 0 1 0 0 1\nP 4 T 11 29546310 29546355 400 170 100 20 0 1 0 0 1\nP 4 T 12 29547750 29547795 500 170 100 20 0 1 0 0 1\nP 4 T 13 29549190 29549235 600 170 100 20 0 2 0 0 1\nP 1 T 13 29549370 29549400 600 190 100 20 1 2 0 0 0\nP 4 T 14 29550570 29550615 0 290 100 20 0 2 0 0 1\nP 0 T 14 29551140 29551200 0 310 100 20 1 2 0 0 1\nP 4 T 15 29552010 29552055 100 290 100 20 0 1 0 0 1\nP 2 T 16 29553270 29553390 200 290 100 20 0 2 0 0 0\nP 4 T 16 29553450 29553495 200 310 100 20 1 2 0 0 1\nP 3 A 17 29554560 29556000 300 290 100 20 0 2 0 0 0\nP 4 T 17 29554890 29554935 300 310 100 20 1 2 0 0 1\nP 4 T 18 29556330 29556375 400 290 100 20 0 1 0 0 1\nP 4 T 19 29557770 29557815 500 290 100 20 0 1 0 0 1\nP 4 T 20 29559210 29559255 600 290 100 20 0 1 0 0 1\nP 0 T 21 29561220 29561280 0 410 100 20 0 1 0 0 1\nP 0 T 28 29571300 29571360 0 530 100 20 0 1 0 0 1\nP 5 T 34 29579340 29579940 600 530 100 20 0 1 0 0 0\nP 0 T 35 29581440 29581500 0 650 100 20 0 1 0 0 1\nN Grid 0 0 700 750 Month schedule, March 2026 0 0 6 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 23 February 2026, 1 event 1 1 6 7 0\nN ListItem 0 50 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 100 30 100 120 Tuesday 24 February 2026, no events 1 2 6 7 0\nN Cell 200 30 100 120 Wednesday 25 February 2026, no events 1 3 6 7 0\nN Cell 300 30 100 120 Thursday 26 February 2026, no events 1 4 6 7 0\nN Cell 400 30 100 120 Friday 27 February 2026, no events 1 5 6 7 0\nN Cell 500 30 100 120 Saturday 28 February 2026, no events 1 6 6 7 0\nN Cell 600 30 100 120 Sunday 1 March 2026, no events 1 7 6 7 0\nN Cell 0 150 100 120 Monday 2 March 2026, 1 event 2 1 6 7 0\nN ListItem 0 170 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 100 150 100 120 Tuesday 3 March 2026, no events 2 2 6 7 0\nN Cell 200 150 100 120 Wednesday 4 March 2026, no events 2 3 6 7 0\nN Cell 300 150 100 120 Thursday 5 March 2026, no events 2 4 6 7 0\nN Cell 400 150 100 120 Friday 6 March 2026, 1 event 2 5 6 7 0\nN ListItem 400 170 100 20 Night, 06:30 to 07:15, repeats 0 0 0 0 1\nN Cell 500 150 100 120 Saturday 7 March 2026, 1 event 2 6 6 7 0\nN ListItem 500 170 100 20 Night, 06:30 to 07:15, repeats 0 0 0 0 1\nN Cell 600 150 100 120 Sunday 8 March 2026, 2 events 2 7 6 7 0\nN ListItem 600 170 100 20 Night, 06:30 to 07:15, repeats 0 0 0 0 1\nN ListItem 600 190 100 20 Gap, 09:30 to 10:00 0 0 0 0 1\nN Cell 0 270 100 120 Monday 9 March 2026, 2 events 3 1 6 7 0\nN ListItem 0 290 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN ListItem 0 310 100 20 Weekly 9, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 100 270 100 120 Tuesday 10 March 2026, 1 event 3 2 6 7 0\nN ListItem 100 290 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 200 270 100 120 Wednesday 11 March 2026, 2 events 3 3 6 7 0\nN ListItem 200 290 100 20 Late NY, 02:30 to 04:30 0 0 0 0 1\nN ListItem 200 310 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 300 270 100 120 Thursday 12 March 2026, 2 events 3 4 6 7 0\nN ListItem 300 290 100 20 Floating, all day 0 0 0 0 1\nN ListItem 300 310 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 400 270 100 120 Friday 13 March 2026, 1 event 3 5 6 7 0\nN ListItem 400 290 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 500 270 100 120 Saturday 14 March 2026, 1 event 3 6 6 7 0\nN ListItem 500 290 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 600 270 100 120 Sunday 15 March 2026, 1 event 3 7 6 7 0\nN ListItem 600 290 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 0 390 100 120 Monday 16 March 2026, 1 event 4 1 6 7 0\nN ListItem 0 410 100 20 Weekly 9, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 100 390 100 120 Tuesday 17 March 2026, no events 4 2 6 7 0\nN Cell 200 390 100 120 Wednesday 18 March 2026, no events 4 3 6 7 0\nN Cell 300 390 100 120 Thursday 19 March 2026, no events 4 4 6 7 0\nN Cell 400 390 100 120 Friday 20 March 2026, no events 4 5 6 7 0\nN Cell 500 390 100 120 Saturday 21 March 2026, no events 4 6 6 7 0\nN Cell 600 390 100 120 Sunday 22 March 2026, no events 4 7 6 7 0\nN Cell 0 510 100 120 Monday 23 March 2026, 1 event 5 1 6 7 0\nN ListItem 0 530 100 20 Weekly 9, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 100 510 100 120 Tuesday 24 March 2026, no events 5 2 6 7 0\nN Cell 200 510 100 120 Wednesday 25 March 2026, no events 5 3 6 7 0\nN Cell 300 510 100 120 Thursday 26 March 2026, no events 5 4 6 7 0\nN Cell 400 510 100 120 Friday 27 March 2026, no events 5 5 6 7 0\nN Cell 500 510 100 120 Saturday 28 March 2026, no events 5 6 6 7 0\nN Cell 600 510 100 120 Sunday 29 March 2026, 1 event 5 7 6 7 0\nN ListItem 600 530 100 20 Overnight, 05:00 to 15:00 0 0 0 0 1\nN Cell 0 630 100 120 Monday 30 March 2026, 1 event 6 1 6 7 0\nN ListItem 0 650 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 100 630 100 120 Tuesday 31 March 2026, no events 6 2 6 7 0\nN Cell 200 630 100 120 Wednesday 1 April 2026, no events 6 3 6 7 0\nN Cell 300 630 100 120 Thursday 2 April 2026, no events 6 4 6 7 0\nN Cell 400 630 100 120 Friday 3 April 2026, no events 6 5 6 7 0\nN Cell 500 630 100 120 Saturday 4 April 2026, no events 6 6 6 7 0\nN Cell 600 630 100 120 Sunday 5 April 2026, no events 6 7 6 7 0\nR 0 0\nR 1 0\nR 2 0\nR 3 0\nR 4 0\nR 5 0\nR 6 0\nR 7 0\nR 8 0\nR 9 0\nR 10 0\nR 11 0\nR 12 0\nR 13 0\nR 14 0\nR 15 0\nR 16 0\nR 17 0\nR 18 0\nR 19 0\nR 20 0\nR 21 0\nR 22 0\nR 23 0\nR 24 0\nR 25 0\nR 26 0\nR 27 0\nR 28 0\nR 29 0\nR 30 0\nR 31 0\nR 32 0\nR 33 0\nR 34 0\nR 35 0\nR 36 0\nR 37 0\nR 38 0\nR 39 0\nR 40 0\nR 41 0\nL 0\n" }

fn z2_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 11u8, 1u8, 1u8, 30u8), minutes: 30u32, all_day: false, title: "Ambiguous", rule: "" }
    out[1usize] = sched.Item { id: 2u32, start: at(2026, 10u8, 26u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Weekly 9", rule: "FREQ=WEEKLY;COUNT=8" }
    out[2usize] = sched.Item { id: 3u32, start: at(2026, 11u8, 1u8, 0u8, 0u8), minutes: 2880u32, all_day: true, title: "Two days", rule: "" }
    out[3usize] = sched.Item { id: 4u32, start: at(2026, 11u8, 2u8, 18u8, 0u8), minutes: 90u32, all_day: false, title: "Evening", rule: "FREQ=DAILY;COUNT=5" }
    ret 4usize
}

fn z2_cfg() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 11u8, day: 3u8 }, week_start: .Sunday, width: 700.0, header: 30.0, cell_h: 100.0, line_h: 20.0, lines: 3u32 }
}

fn z2_want() -> str { ret "M 20758 5 530\nC 20758 1 0 30 100 100 0 2 2 0\nC 20759 1 100 30 100 100 2 2 2 0\nC 20760 1 200 30 100 100 4 1 1 0\nC 20761 1 300 30 100 100 5 1 1 0\nC 20762 1 400 30 100 100 6 1 1 0\nC 20763 1 500 30 100 100 7 1 1 0\nC 20764 1 600 30 100 100 8 1 1 0\nC 20765 1 0 130 100 100 9 0 0 0\nC 20766 1 100 130 100 100 9 1 1 0\nC 20767 1 200 130 100 100 10 0 0 0\nC 20768 1 300 130 100 100 10 0 0 0\nC 20769 1 400 130 100 100 10 0 0 0\nC 20770 1 500 130 100 100 10 0 0 0\nC 20771 1 600 130 100 100 10 0 0 0\nC 20772 1 0 230 100 100 10 0 0 0\nC 20773 1 100 230 100 100 10 1 1 0\nC 20774 1 200 230 100 100 11 0 0 0\nC 20775 1 300 230 100 100 11 0 0 0\nC 20776 1 400 230 100 100 11 0 0 0\nC 20777 1 500 230 100 100 11 0 0 0\nC 20778 1 600 230 100 100 11 0 0 0\nC 20779 1 0 330 100 100 11 0 0 0\nC 20780 1 100 330 100 100 11 1 1 0\nC 20781 1 200 330 100 100 12 0 0 0\nC 20782 1 300 330 100 100 12 0 0 0\nC 20783 1 400 330 100 100 12 0 0 0\nC 20784 1 500 330 100 100 12 0 0 0\nC 20785 1 600 330 100 100 12 0 0 0\nC 20786 1 0 430 100 100 12 0 0 0\nC 20787 1 100 430 100 100 12 1 1 0\nC 20788 0 200 430 100 100 13 0 0 0\nC 20789 0 300 430 100 100 13 0 0 0\nC 20790 0 400 430 100 100 13 0 0 0\nC 20791 0 500 430 100 100 13 0 0 0\nC 20792 0 600 430 100 100 13 0 0 0\nP 2 A 0 29891520 29892960 0 50 100 20 0 2 0 1 0\nP 0 T 0 29891970 29892000 0 70 100 20 1 2 0 0 0\nP 2 A 1 29892960 29894400 100 50 100 20 0 2 1 0 0\nP 1 T 1 29893920 29893980 100 70 100 20 1 2 0 0 1\nP 3 T 2 29894460 29894550 200 50 100 20 0 1 0 0 1\nP 3 T 3 29895900 29895990 300 50 100 20 0 1 0 0 1\nP 3 T 4 29897340 29897430 400 50 100 20 0 1 0 0 1\nP 3 T 5 29898780 29898870 500 50 100 20 0 1 0 0 1\nP 3 T 6 29900220 29900310 600 50 100 20 0 1 0 0 1\nP 1 T 8 29904000 29904060 100 150 100 20 0 1 0 0 1\nP 1 T 15 29914080 29914140 100 250 100 20 0 1 0 0 1\nP 1 T 22 29924160 29924220 100 350 100 20 0 1 0 0 1\nP 1 T 29 29934240 29934300 100 450 100 20 0 1 0 0 1\nN Grid 0 0 700 530 Month schedule, November 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Sunday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Monday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Tuesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Wednesday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Thursday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Friday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Saturday 0 7 0 7 0\nN Cell 0 30 100 100 Sunday 1 November 2026, 2 events 1 1 5 7 0\nN ListItem 0 50 100 20 Two days, all day 0 0 0 0 1\nN ListItem 0 70 100 20 Ambiguous, 07:30 to 08:00 0 0 0 0 1\nN Cell 100 30 100 100 Monday 2 November 2026, 2 events 1 2 5 7 0\nN ListItem 100 50 100 20 Two days, all day 0 0 0 0 1\nN ListItem 100 70 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 200 30 100 100 Tuesday 3 November 2026, 1 event 1 3 5 7 0\nN ListItem 200 50 100 20 Evening, 01:00 to 02:30, repeats 0 0 0 0 1\nN Cell 300 30 100 100 Wednesday 4 November 2026, 1 event 1 4 5 7 0\nN ListItem 300 50 100 20 Evening, 01:00 to 02:30, repeats 0 0 0 0 1\nN Cell 400 30 100 100 Thursday 5 November 2026, 1 event 1 5 5 7 0\nN ListItem 400 50 100 20 Evening, 01:00 to 02:30, repeats 0 0 0 0 1\nN Cell 500 30 100 100 Friday 6 November 2026, 1 event 1 6 5 7 0\nN ListItem 500 50 100 20 Evening, 01:00 to 02:30, repeats 0 0 0 0 1\nN Cell 600 30 100 100 Saturday 7 November 2026, 1 event 1 7 5 7 0\nN ListItem 600 50 100 20 Evening, 01:00 to 02:30, repeats 0 0 0 0 1\nN Cell 0 130 100 100 Sunday 8 November 2026, no events 2 1 5 7 0\nN Cell 100 130 100 100 Monday 9 November 2026, 1 event 2 2 5 7 0\nN ListItem 100 150 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 200 130 100 100 Tuesday 10 November 2026, no events 2 3 5 7 0\nN Cell 300 130 100 100 Wednesday 11 November 2026, no events 2 4 5 7 0\nN Cell 400 130 100 100 Thursday 12 November 2026, no events 2 5 5 7 0\nN Cell 500 130 100 100 Friday 13 November 2026, no events 2 6 5 7 0\nN Cell 600 130 100 100 Saturday 14 November 2026, no events 2 7 5 7 0\nN Cell 0 230 100 100 Sunday 15 November 2026, no events 3 1 5 7 0\nN Cell 100 230 100 100 Monday 16 November 2026, 1 event 3 2 5 7 0\nN ListItem 100 250 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 200 230 100 100 Tuesday 17 November 2026, no events 3 3 5 7 0\nN Cell 300 230 100 100 Wednesday 18 November 2026, no events 3 4 5 7 0\nN Cell 400 230 100 100 Thursday 19 November 2026, no events 3 5 5 7 0\nN Cell 500 230 100 100 Friday 20 November 2026, no events 3 6 5 7 0\nN Cell 600 230 100 100 Saturday 21 November 2026, no events 3 7 5 7 0\nN Cell 0 330 100 100 Sunday 22 November 2026, no events 4 1 5 7 0\nN Cell 100 330 100 100 Monday 23 November 2026, 1 event 4 2 5 7 0\nN ListItem 100 350 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 200 330 100 100 Tuesday 24 November 2026, no events 4 3 5 7 0\nN Cell 300 330 100 100 Wednesday 25 November 2026, no events 4 4 5 7 0\nN Cell 400 330 100 100 Thursday 26 November 2026, no events 4 5 5 7 0\nN Cell 500 330 100 100 Friday 27 November 2026, no events 4 6 5 7 0\nN Cell 600 330 100 100 Saturday 28 November 2026, no events 4 7 5 7 0\nN Cell 0 430 100 100 Sunday 29 November 2026, no events 5 1 5 7 0\nN Cell 100 430 100 100 Monday 30 November 2026, 1 event 5 2 5 7 0\nN ListItem 100 450 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 200 430 100 100 Tuesday 1 December 2026, no events 5 3 5 7 0\nN Cell 300 430 100 100 Wednesday 2 December 2026, no events 5 4 5 7 0\nN Cell 400 430 100 100 Thursday 3 December 2026, no events 5 5 5 7 0\nN Cell 500 430 100 100 Friday 4 December 2026, no events 5 6 5 7 0\nN Cell 600 430 100 100 Saturday 5 December 2026, no events 5 7 5 7 0\nR 0 0\nR 1 0\nR 2 0\nR 3 0\nR 4 0\nR 5 0\nR 6 0\nR 7 0\nR 8 0\nR 9 0\nR 10 0\nR 11 0\nR 12 0\nR 13 0\nR 14 0\nR 15 0\nR 16 0\nR 17 0\nR 18 0\nR 19 0\nR 20 0\nR 21 0\nR 22 0\nR 23 0\nR 24 0\nR 25 0\nR 26 0\nR 27 0\nR 28 0\nR 29 0\nR 30 0\nR 31 0\nR 32 0\nR 33 0\nR 34 0\nL 0\n" }

fn z3_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 3u8, 30u8, 7u8, 0u8), minutes: 60u32, all_day: false, title: "LH weekly", rule: "FREQ=WEEKLY;COUNT=12" }
    out[1usize] = sched.Item { id: 2u32, start: at(2026, 4u8, 5u8, 1u8, 45u8), minutes: 30u32, all_day: false, title: "LH gap", rule: "" }
    out[2usize] = sched.Item { id: 3u32, start: at(2026, 4u8, 4u8, 23u8, 0u8), minutes: 120u32, all_day: false, title: "LH late", rule: "" }
    ret 3usize
}

fn z3_cfg() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 4u8, day: 9u8 }, week_start: .Monday, width: 700.0, header: 30.0, cell_h: 140.0, line_h: 20.0, lines: 5u32 }
}

fn z3_want() -> str { ret "M 20542 5 730\nC 20542 0 0 30 100 140 0 0 0 0\nC 20543 0 100 30 100 140 0 0 0 0\nC 20544 1 200 30 100 140 0 0 0 0\nC 20545 1 300 30 100 140 0 0 0 0\nC 20546 1 400 30 100 140 0 0 0 0\nC 20547 1 500 30 100 140 0 2 2 0\nC 20548 1 600 30 100 140 2 1 1 0\nC 20549 1 0 170 100 140 3 0 0 0\nC 20550 1 100 170 100 140 3 0 0 0\nC 20551 1 200 170 100 140 3 0 0 0\nC 20552 1 300 170 100 140 3 0 0 0\nC 20553 1 400 170 100 140 3 0 0 0\nC 20554 1 500 170 100 140 3 0 0 0\nC 20555 1 600 170 100 140 3 1 1 0\nC 20556 1 0 310 100 140 4 0 0 0\nC 20557 1 100 310 100 140 4 0 0 0\nC 20558 1 200 310 100 140 4 0 0 0\nC 20559 1 300 310 100 140 4 0 0 0\nC 20560 1 400 310 100 140 4 0 0 0\nC 20561 1 500 310 100 140 4 0 0 0\nC 20562 1 600 310 100 140 4 1 1 0\nC 20563 1 0 450 100 140 5 0 0 0\nC 20564 1 100 450 100 140 5 0 0 0\nC 20565 1 200 450 100 140 5 0 0 0\nC 20566 1 300 450 100 140 5 0 0 0\nC 20567 1 400 450 100 140 5 0 0 0\nC 20568 1 500 450 100 140 5 0 0 0\nC 20569 1 600 450 100 140 5 1 1 0\nC 20570 1 0 590 100 140 6 0 0 0\nC 20571 1 100 590 100 140 6 0 0 0\nC 20572 1 200 590 100 140 6 0 0 0\nC 20573 1 300 590 100 140 6 0 0 0\nC 20574 0 400 590 100 140 6 0 0 0\nC 20575 0 500 590 100 140 6 0 0 0\nC 20576 0 600 590 100 140 6 1 1 0\nP 2 T 5 29588400 29588520 500 50 100 20 0 2 0 0 0\nP 1 T 5 29588565 29588595 500 70 100 20 1 2 0 0 0\nP 0 T 6 29590350 29590410 600 50 100 20 0 1 0 0 1\nP 0 T 13 29600430 29600490 600 190 100 20 0 1 0 0 1\nP 0 T 20 29610510 29610570 600 330 100 20 0 1 0 0 1\nP 0 T 27 29620590 29620650 600 470 100 20 0 1 0 0 1\nP 0 T 34 29630670 29630730 600 610 100 20 0 1 0 0 1\nN Grid 0 0 700 730 Month schedule, April 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 140 Monday 30 March 2026, no events 1 1 5 7 0\nN Cell 100 30 100 140 Tuesday 31 March 2026, no events 1 2 5 7 0\nN Cell 200 30 100 140 Wednesday 1 April 2026, no events 1 3 5 7 0\nN Cell 300 30 100 140 Thursday 2 April 2026, no events 1 4 5 7 0\nN Cell 400 30 100 140 Friday 3 April 2026, no events 1 5 5 7 0\nN Cell 500 30 100 140 Saturday 4 April 2026, 2 events 1 6 5 7 0\nN ListItem 500 50 100 20 LH late, 12:00 to 14:00 0 0 0 0 1\nN ListItem 500 70 100 20 LH gap, 14:45 to 15:15 0 0 0 0 1\nN Cell 600 30 100 140 Sunday 5 April 2026, 1 event 1 7 5 7 0\nN ListItem 600 50 100 20 LH weekly, 20:30 to 21:30, repeats 0 0 0 0 1\nN Cell 0 170 100 140 Monday 6 April 2026, no events 2 1 5 7 0\nN Cell 100 170 100 140 Tuesday 7 April 2026, no events 2 2 5 7 0\nN Cell 200 170 100 140 Wednesday 8 April 2026, no events 2 3 5 7 0\nN Cell 300 170 100 140 Thursday 9 April 2026, no events 2 4 5 7 0\nN Cell 400 170 100 140 Friday 10 April 2026, no events 2 5 5 7 0\nN Cell 500 170 100 140 Saturday 11 April 2026, no events 2 6 5 7 0\nN Cell 600 170 100 140 Sunday 12 April 2026, 1 event 2 7 5 7 0\nN ListItem 600 190 100 20 LH weekly, 20:30 to 21:30, repeats 0 0 0 0 1\nN Cell 0 310 100 140 Monday 13 April 2026, no events 3 1 5 7 0\nN Cell 100 310 100 140 Tuesday 14 April 2026, no events 3 2 5 7 0\nN Cell 200 310 100 140 Wednesday 15 April 2026, no events 3 3 5 7 0\nN Cell 300 310 100 140 Thursday 16 April 2026, no events 3 4 5 7 0\nN Cell 400 310 100 140 Friday 17 April 2026, no events 3 5 5 7 0\nN Cell 500 310 100 140 Saturday 18 April 2026, no events 3 6 5 7 0\nN Cell 600 310 100 140 Sunday 19 April 2026, 1 event 3 7 5 7 0\nN ListItem 600 330 100 20 LH weekly, 20:30 to 21:30, repeats 0 0 0 0 1\nN Cell 0 450 100 140 Monday 20 April 2026, no events 4 1 5 7 0\nN Cell 100 450 100 140 Tuesday 21 April 2026, no events 4 2 5 7 0\nN Cell 200 450 100 140 Wednesday 22 April 2026, no events 4 3 5 7 0\nN Cell 300 450 100 140 Thursday 23 April 2026, no events 4 4 5 7 0\nN Cell 400 450 100 140 Friday 24 April 2026, no events 4 5 5 7 0\nN Cell 500 450 100 140 Saturday 25 April 2026, no events 4 6 5 7 0\nN Cell 600 450 100 140 Sunday 26 April 2026, 1 event 4 7 5 7 0\nN ListItem 600 470 100 20 LH weekly, 20:30 to 21:30, repeats 0 0 0 0 1\nN Cell 0 590 100 140 Monday 27 April 2026, no events 5 1 5 7 0\nN Cell 100 590 100 140 Tuesday 28 April 2026, no events 5 2 5 7 0\nN Cell 200 590 100 140 Wednesday 29 April 2026, no events 5 3 5 7 0\nN Cell 300 590 100 140 Thursday 30 April 2026, no events 5 4 5 7 0\nN Cell 400 590 100 140 Friday 1 May 2026, no events 5 5 5 7 0\nN Cell 500 590 100 140 Saturday 2 May 2026, no events 5 6 5 7 0\nN Cell 600 590 100 140 Sunday 3 May 2026, 1 event 5 7 5 7 0\nN ListItem 600 610 100 20 LH weekly, 20:30 to 21:30, repeats 0 0 0 0 1\nR 0 0\nR 1 0\nR 2 0\nR 3 0\nR 4 0\nR 5 0\nR 6 0\nR 7 0\nR 8 0\nR 9 0\nR 10 0\nR 11 0\nR 12 0\nR 13 0\nR 14 0\nR 15 0\nR 16 0\nR 17 0\nR 18 0\nR 19 0\nR 20 0\nR 21 0\nR 22 0\nR 23 0\nR 24 0\nR 25 0\nR 26 0\nR 27 0\nR 28 0\nR 29 0\nR 30 0\nR 31 0\nR 32 0\nR 33 0\nR 34 0\nL 0\n" }

fn z4_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 4u8, 1u8, 6u8, 30u8), minutes: 45u32, all_day: false, title: "Kolkata morning", rule: "FREQ=DAILY;COUNT=20" }
    out[1usize] = sched.Item { id: 2u32, start: at(2026, 4u8, 6u8, 23u8, 45u8), minutes: 30u32, all_day: false, title: "Near midnight", rule: "" }
    out[2usize] = sched.Item { id: 3u32, start: at(2026, 4u8, 6u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "Day", rule: "" }
    ret 3usize
}

fn z4_cfg() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 4u8, day: 9u8 }, week_start: .Monday, width: 700.0, header: 30.0, cell_h: 140.0, line_h: 20.0, lines: 5u32 }
}

fn z4_want() -> str { ret "M 20542 5 730\nC 20542 0 0 30 100 140 0 0 0 0\nC 20543 0 100 30 100 140 0 1 1 0\nC 20544 1 200 30 100 140 1 1 1 0\nC 20545 1 300 30 100 140 2 1 1 0\nC 20546 1 400 30 100 140 3 1 1 0\nC 20547 1 500 30 100 140 4 1 1 0\nC 20548 1 600 30 100 140 5 1 1 0\nC 20549 1 0 170 100 140 6 3 3 0\nC 20550 1 100 170 100 140 9 1 1 0\nC 20551 1 200 170 100 140 10 1 1 0\nC 20552 1 300 170 100 140 11 1 1 0\nC 20553 1 400 170 100 140 12 1 1 0\nC 20554 1 500 170 100 140 13 1 1 0\nC 20555 1 600 170 100 140 14 1 1 0\nC 20556 1 0 310 100 140 15 1 1 0\nC 20557 1 100 310 100 140 16 1 1 0\nC 20558 1 200 310 100 140 17 1 1 0\nC 20559 1 300 310 100 140 18 1 1 0\nC 20560 1 400 310 100 140 19 1 1 0\nC 20561 1 500 310 100 140 20 1 1 0\nC 20562 1 600 310 100 140 21 1 1 0\nC 20563 1 0 450 100 140 22 0 0 0\nC 20564 1 100 450 100 140 22 0 0 0\nC 20565 1 200 450 100 140 22 0 0 0\nC 20566 1 300 450 100 140 22 0 0 0\nC 20567 1 400 450 100 140 22 0 0 0\nC 20568 1 500 450 100 140 22 0 0 0\nC 20569 1 600 450 100 140 22 0 0 0\nC 20570 1 0 590 100 140 22 0 0 0\nC 20571 1 100 590 100 140 22 0 0 0\nC 20572 1 200 590 100 140 22 0 0 0\nC 20573 1 300 590 100 140 22 0 0 0\nC 20574 0 400 590 100 140 22 0 0 0\nC 20575 0 500 590 100 140 22 0 0 0\nC 20576 0 600 590 100 140 22 0 0 0\nP 0 T 1 29583000 29583045 100 50 100 20 0 1 0 0 1\nP 0 T 2 29584440 29584485 200 50 100 20 0 1 0 0 1\nP 0 T 3 29585880 29585925 300 50 100 20 0 1 0 0 1\nP 0 T 4 29587320 29587365 400 50 100 20 0 1 0 0 1\nP 0 T 5 29588760 29588805 500 50 100 20 0 1 0 0 1\nP 0 T 6 29590200 29590245 600 50 100 20 0 1 0 0 1\nP 2 A 7 29590560 29592000 0 190 100 20 0 3 0 0 0\nP 1 T 7 29591235 29591265 0 210 100 20 1 3 0 0 0\nP 0 T 7 29591640 29591685 0 230 100 20 2 3 0 0 1\nP 0 T 8 29593080 29593125 100 190 100 20 0 1 0 0 1\nP 0 T 9 29594520 29594565 200 190 100 20 0 1 0 0 1\nP 0 T 10 29595960 29596005 300 190 100 20 0 1 0 0 1\nP 0 T 11 29597400 29597445 400 190 100 20 0 1 0 0 1\nP 0 T 12 29598840 29598885 500 190 100 20 0 1 0 0 1\nP 0 T 13 29600280 29600325 600 190 100 20 0 1 0 0 1\nP 0 T 14 29601720 29601765 0 330 100 20 0 1 0 0 1\nP 0 T 15 29603160 29603205 100 330 100 20 0 1 0 0 1\nP 0 T 16 29604600 29604645 200 330 100 20 0 1 0 0 1\nP 0 T 17 29606040 29606085 300 330 100 20 0 1 0 0 1\nP 0 T 18 29607480 29607525 400 330 100 20 0 1 0 0 1\nP 0 T 19 29608920 29608965 500 330 100 20 0 1 0 0 1\nP 0 T 20 29610360 29610405 600 330 100 20 0 1 0 0 1\nN Grid 0 0 700 730 Month schedule, April 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 140 Monday 30 March 2026, no events 1 1 5 7 0\nN Cell 100 30 100 140 Tuesday 31 March 2026, 1 event 1 2 5 7 0\nN ListItem 100 50 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 200 30 100 140 Wednesday 1 April 2026, 1 event 1 3 5 7 0\nN ListItem 200 50 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 300 30 100 140 Thursday 2 April 2026, 1 event 1 4 5 7 0\nN ListItem 300 50 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 400 30 100 140 Friday 3 April 2026, 1 event 1 5 5 7 0\nN ListItem 400 50 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 500 30 100 140 Saturday 4 April 2026, 1 event 1 6 5 7 0\nN ListItem 500 50 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 600 30 100 140 Sunday 5 April 2026, 1 event 1 7 5 7 0\nN ListItem 600 50 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 0 170 100 140 Monday 6 April 2026, 3 events 2 1 5 7 0\nN ListItem 0 190 100 20 Day, all day 0 0 0 0 1\nN ListItem 0 210 100 20 Near midnight, 11:15 to 11:45 0 0 0 0 1\nN ListItem 0 230 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 100 170 100 140 Tuesday 7 April 2026, 1 event 2 2 5 7 0\nN ListItem 100 190 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 200 170 100 140 Wednesday 8 April 2026, 1 event 2 3 5 7 0\nN ListItem 200 190 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 300 170 100 140 Thursday 9 April 2026, 1 event 2 4 5 7 0\nN ListItem 300 190 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 400 170 100 140 Friday 10 April 2026, 1 event 2 5 5 7 0\nN ListItem 400 190 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 500 170 100 140 Saturday 11 April 2026, 1 event 2 6 5 7 0\nN ListItem 500 190 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 600 170 100 140 Sunday 12 April 2026, 1 event 2 7 5 7 0\nN ListItem 600 190 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 0 310 100 140 Monday 13 April 2026, 1 event 3 1 5 7 0\nN ListItem 0 330 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 100 310 100 140 Tuesday 14 April 2026, 1 event 3 2 5 7 0\nN ListItem 100 330 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 200 310 100 140 Wednesday 15 April 2026, 1 event 3 3 5 7 0\nN ListItem 200 330 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 300 310 100 140 Thursday 16 April 2026, 1 event 3 4 5 7 0\nN ListItem 300 330 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 400 310 100 140 Friday 17 April 2026, 1 event 3 5 5 7 0\nN ListItem 400 330 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 500 310 100 140 Saturday 18 April 2026, 1 event 3 6 5 7 0\nN ListItem 500 330 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 600 310 100 140 Sunday 19 April 2026, 1 event 3 7 5 7 0\nN ListItem 600 330 100 20 Kolkata morning, 18:00 to 18:45, repeats 0 0 0 0 1\nN Cell 0 450 100 140 Monday 20 April 2026, no events 4 1 5 7 0\nN Cell 100 450 100 140 Tuesday 21 April 2026, no events 4 2 5 7 0\nN Cell 200 450 100 140 Wednesday 22 April 2026, no events 4 3 5 7 0\nN Cell 300 450 100 140 Thursday 23 April 2026, no events 4 4 5 7 0\nN Cell 400 450 100 140 Friday 24 April 2026, no events 4 5 5 7 0\nN Cell 500 450 100 140 Saturday 25 April 2026, no events 4 6 5 7 0\nN Cell 600 450 100 140 Sunday 26 April 2026, no events 4 7 5 7 0\nN Cell 0 590 100 140 Monday 27 April 2026, no events 5 1 5 7 0\nN Cell 100 590 100 140 Tuesday 28 April 2026, no events 5 2 5 7 0\nN Cell 200 590 100 140 Wednesday 29 April 2026, no events 5 3 5 7 0\nN Cell 300 590 100 140 Thursday 30 April 2026, no events 5 4 5 7 0\nN Cell 400 590 100 140 Friday 1 May 2026, no events 5 5 5 7 0\nN Cell 500 590 100 140 Saturday 2 May 2026, no events 5 6 5 7 0\nN Cell 600 590 100 140 Sunday 3 May 2026, no events 5 7 5 7 0\nR 0 0\nR 1 0\nR 2 0\nR 3 0\nR 4 0\nR 5 0\nR 6 0\nR 7 0\nR 8 0\nR 9 0\nR 10 0\nR 11 0\nR 12 0\nR 13 0\nR 14 0\nR 15 0\nR 16 0\nR 17 0\nR 18 0\nR 19 0\nR 20 0\nR 21 0\nR 22 0\nR 23 0\nR 24 0\nR 25 0\nR 26 0\nR 27 0\nR 28 0\nR 29 0\nR 30 0\nR 31 0\nR 32 0\nR 33 0\nR 34 0\nL 0\n" }

fn bar_items(out: []sched.Item) -> usize {
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

fn bar_cfg_m1() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Monday, width: 700.0, header: 30.0, cell_h: 120.0, line_h: 20.0, lines: 4u32 }
}

fn bar_want_m1() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 1 1 0\nC 20734 1 300 150 100 120 1 0 0 0\nC 20735 1 400 150 100 120 1 0 0 0\nC 20736 1 500 150 100 120 1 0 0 0\nC 20737 1 600 150 100 120 1 0 0 0\nC 20738 1 0 270 100 120 1 2 0 2\nC 20739 1 100 270 100 120 3 4 0 4\nC 20740 1 200 270 100 120 7 4 0 4\nC 20741 1 300 270 100 120 11 2 0 2\nC 20742 1 400 270 100 120 13 8 0 8\nC 20743 1 500 270 100 120 21 1 1 0\nC 20744 1 600 270 100 120 22 0 0 0\nC 20745 1 0 390 100 120 22 2 2 0\nC 20746 1 100 390 100 120 24 1 1 0\nC 20747 1 200 390 100 120 25 2 2 0\nC 20748 1 300 390 100 120 27 1 1 0\nC 20749 1 400 390 100 120 28 1 1 0\nC 20750 1 500 390 100 120 29 0 0 0\nC 20751 1 600 390 100 120 29 0 0 0\nC 20752 1 0 510 100 120 29 1 1 0\nC 20753 1 100 510 100 120 30 0 0 0\nC 20754 1 200 510 100 120 30 1 1 0\nC 20755 1 300 510 100 120 31 0 0 0\nC 20756 1 400 510 100 120 31 0 0 0\nC 20757 1 500 510 100 120 31 0 0 0\nC 20758 0 600 510 100 120 31 0 0 0\nP 9 T 9 29856420 29856480 200 190 100 20 0 1 0 0 1\nP 16 A 14 29862720 29864160 0 270 0 0 0 2 0 0 1\nP 0 T 14 29863260 29863290 0 270 0 0 1 2 0 0 1\nP 0 T 15 29864700 29864730 100 270 0 0 0 4 0 0 1\nP 1 T 15 29864760 29864850 100 270 0 0 1 4 0 0 0\nP 2 T 15 29864790 29864850 100 270 0 0 2 4 0 0 0\nP 3 T 15 29864820 29864850 100 270 0 0 3 4 0 0 0\nP 5 T 16 29865960 29866020 200 270 0 0 0 4 0 0 0\nP 0 T 16 29866140 29866170 200 270 0 0 1 4 0 0 1\nP 4 T 16 29866380 29866560 200 270 0 0 2 4 0 0 0\nP 9 T 16 29866500 29866560 200 270 0 0 3 4 0 0 1\nP 0 T 17 29867580 29867610 300 270 0 0 0 2 0 0 1\nP 10 T 17 29867640 29867700 300 270 0 0 1 2 0 0 1\nP 8 A 18 29868480 29869920 400 270 0 0 0 8 0 0 0\nP 14 T 18 29869020 29869140 400 270 0 0 1 8 0 0 0\nP 11 T 18 29869020 29869080 400 270 0 0 2 8 0 0 0\nP 0 T 18 29869020 29869050 400 270 0 0 3 8 0 0 1\nP 12 T 18 29869050 29869110 400 270 0 0 4 8 0 0 0\nP 21 T 18 29869065 29869095 400 270 0 0 5 8 0 0 0\nP 13 T 18 29869095 29869140 400 270 0 0 6 8 0 0 0\nP 22 T 18 29869320 29869350 400 270 0 0 7 8 0 0 0\nP 15 T 19 29870640 29870641 500 350 100 20 0 1 0 0 0\nP 16 A 21 29872800 29874240 0 430 100 20 0 2 0 0 1\nP 0 T 21 29873340 29873370 0 450 100 20 1 2 0 0 1\nP 0 T 22 29874780 29874810 100 430 100 20 0 1 0 0 1\nP 0 T 23 29876220 29876250 200 430 100 20 0 2 0 0 1\nP 9 T 23 29876580 29876640 200 450 100 20 1 2 0 0 1\nP 0 T 24 29877660 29877690 300 430 100 20 0 1 0 0 1\nP 0 T 25 29879100 29879130 400 430 100 20 0 1 0 0 1\nP 16 A 28 29882880 29884320 0 550 100 20 0 1 0 0 1\nP 9 T 30 29886660 29886720 200 550 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, 1 event 2 3 5 7 0\nN ListItem 200 190 100 20 Weekly sync, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 300 150 100 120 Thursday 8 October 2026, no events 2 4 5 7 0\nN Cell 400 150 100 120 Friday 9 October 2026, no events 2 5 5 7 0\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, 2 events 3 1 5 7 0\nN ListItem 0 270 0 0 Standing, all day, repeats 0 0 0 0 1\nN ListItem 0 270 0 0 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 100 270 100 120 Tuesday 13 October 2026, 4 events 3 2 5 7 0\nN ListItem 100 270 0 0 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 100 270 0 0 Design review, 10:00 to 11:30 0 0 0 0 1\nN ListItem 100 270 0 0 Lunch, 10:30 to 11:30 0 0 0 0 1\nN ListItem 100 270 0 0 Call, 11:00 to 11:30 0 0 0 0 1\nN Cell 200 270 100 120 Wednesday 14 October 2026, 4 events 3 3 5 7 0\nN ListItem 200 270 0 0 Early, 06:00 to 07:00 0 0 0 0 1\nN ListItem 200 270 0 0 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 200 270 0 0 Workshop, 13:00 to 16:00 0 0 0 0 1\nN ListItem 200 270 0 0 Weekly sync, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 300 270 100 120 Thursday 15 October 2026, 2 events 3 4 5 7 0\nN ListItem 300 270 0 0 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 300 270 0 0 Monthly, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 400 270 100 120 Friday 16 October 2026, 8 events 3 5 5 7 0\nN ListItem 400 270 0 0 Holiday, all day 0 0 0 0 1\nN ListItem 400 270 0 0 Chain D, 09:00 to 11:00 0 0 0 0 1\nN ListItem 400 270 0 0 Chain A, 09:00 to 10:00 0 0 0 0 1\nN ListItem 400 270 0 0 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 400 270 0 0 Chain B, 09:30 to 10:30 0 0 0 0 1\nN ListItem 400 270 0 0 Chain E, 09:45 to 10:15 0 0 0 0 1\nN ListItem 400 270 0 0 Chain C, 10:15 to 11:00 0 0 0 0 1\nN ListItem 400 270 0 0 Afternoon, 14:00 to 14:30 0 0 0 0 1\nN Cell 500 270 100 120 Saturday 17 October 2026, 1 event 3 6 5 7 0\nN ListItem 500 350 100 20 Zero length, 12:00 to 12:01 0 0 0 0 1\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, 2 events 4 1 5 7 0\nN ListItem 0 430 100 20 Standing, all day, repeats 0 0 0 0 1\nN ListItem 0 450 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 100 390 100 120 Tuesday 20 October 2026, 1 event 4 2 5 7 0\nN ListItem 100 430 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 200 390 100 120 Wednesday 21 October 2026, 2 events 4 3 5 7 0\nN ListItem 200 430 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 200 450 100 20 Weekly sync, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 300 390 100 120 Thursday 22 October 2026, 1 event 4 4 5 7 0\nN ListItem 300 430 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 400 390 100 120 Friday 23 October 2026, 1 event 4 5 5 7 0\nN ListItem 400 430 100 20 Standup, 09:00 to 09:30, repeats 0 0 0 0 1\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, 1 event 5 1 5 7 0\nN ListItem 0 550 100 20 Standing, all day, repeats 0 0 0 0 1\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, 1 event 5 3 5 7 0\nN ListItem 200 550 100 20 Weekly sync, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\nN ListItem 500 170 200 20 Trip, all day 0 0 0 0 1\nN ListItem 0 290 300 20 Trip, all day 0 0 0 0 1\nN ListItem 100 310 300 20 Offsite, all day 0 0 0 0 1\nN ListItem 200 330 200 20 Conference, all day 0 0 0 0 1\nN ListItem 300 290 200 20 Overnight, 19:00 to 01:00 0 0 0 0 1\nN ListItem 100 410 200 20 Late call, 22:00 to 01:00 0 0 0 0 1\nN ListItem 400 530 300 20 Month end, all day 0 0 0 0 1\nR 0 0\nR 1 0\nR 2 0\nR 3 0\nR 4 0\nR 5 0\nR 6 0\nR 7 1\nR 8 1\nR 9 1\nR 10 1\nR 11 1\nR 12 1\nR 13 1\nR 14 3\nR 15 3\nR 16 3\nR 17 3\nR 18 3\nR 19 3\nR 20 3\nR 21 1\nR 22 1\nR 23 1\nR 24 1\nR 25 1\nR 26 1\nR 27 1\nR 28 1\nR 29 1\nR 30 1\nR 31 1\nR 32 1\nR 33 1\nR 34 1\nL 7\nB 17 12 13 0 500 170 200 20 0 1 0 29859840 29867040\nB 17 14 16 0 0 290 300 20 1 0 0 29859840 29867040\nB 18 15 17 1 100 310 300 20 0 0 0 29864160 29868480\nB 7 16 17 2 200 330 200 20 0 0 0 29865600 29868480\nB 6 17 18 0 300 290 200 20 0 0 0 29868180 29868540\nB 20 22 23 0 100 410 200 20 0 0 0 29875560 29875740\nB 19 32 34 0 400 530 300 20 0 0 0 29888640 29892960\n" }

fn bar_hits_m1() -> str { ret "600,180,1,0;500,170,1,0;700,170,0,0;501,189,1,0;150,300,1,1;0,290,1,1;300,290,1,4;1,309,1,1;250,320,1,2;100,310,1,2;400,310,0,0;101,329,1,2;300,340,1,3;200,330,1,3;400,330,0,0;201,349,1,3;400,300,1,4;300,290,1,4;500,290,0,0;301,309,1,4;200,420,1,5;100,410,1,5;300,410,0,0;101,429,1,5;550,540,1,6;400,530,1,6;700,530,0,0;401,549,1,6;1,1,0,0;5,40,0,0;" }

fn bar_cfg_m2() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2027, month: 2u8, day: 3u8 }, week_start: .Monday, width: 700.0, header: 30.0, cell_h: 100.0, line_h: 25.0, lines: 2u32 }
}

fn bar_want_m2() -> str { ret "M 20850 4 430\nC 20850 1 0 30 100 100 0 0 0 0\nC 20851 1 100 30 100 100 0 0 0 0\nC 20852 1 200 30 100 100 0 0 0 0\nC 20853 1 300 30 100 100 0 0 0 0\nC 20854 1 400 30 100 100 0 0 0 0\nC 20855 1 500 30 100 100 0 0 0 0\nC 20856 1 600 30 100 100 0 0 0 0\nC 20857 1 0 130 100 100 0 1 1 0\nC 20858 1 100 130 100 100 1 3 0 3\nC 20859 1 200 130 100 100 4 1 1 0\nC 20860 1 300 130 100 100 5 0 0 0\nC 20861 1 400 130 100 100 5 0 0 0\nC 20862 1 500 130 100 100 5 0 0 0\nC 20863 1 600 130 100 100 5 0 0 0\nC 20864 1 0 230 100 100 5 1 1 0\nC 20865 1 100 230 100 100 6 0 0 0\nC 20866 1 200 230 100 100 6 0 0 0\nC 20867 1 300 230 100 100 6 0 0 0\nC 20868 1 400 230 100 100 6 0 0 0\nC 20869 1 500 230 100 100 6 0 0 0\nC 20870 1 600 230 100 100 6 0 0 0\nC 20871 1 0 330 100 100 6 0 0 0\nC 20872 1 100 330 100 100 6 0 0 0\nC 20873 1 200 330 100 100 6 0 0 0\nC 20874 1 300 330 100 100 6 0 0 0\nC 20875 1 400 330 100 100 6 0 0 0\nC 20876 1 500 330 100 100 6 0 0 0\nC 20877 1 600 330 100 100 6 0 0 0\nP 24 T 7 30034620 30034680 0 180 100 25 0 1 0 0 1\nP 24 T 8 30036060 30036120 100 130 0 0 0 3 0 0 1\nP 27 T 8 30036180 30036210 100 130 0 0 1 3 0 0 0\nP 26 T 8 30036420 30036450 100 130 0 0 2 3 0 0 0\nP 24 T 9 30037500 30037560 200 180 100 25 0 1 0 0 1\nP 10 T 14 30044760 30044820 0 255 100 25 0 1 0 0 1\nN Grid 0 0 700 430 Month schedule, February 2027 0 0 4 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 100 Monday 1 February 2027, no events 1 1 4 7 0\nN Cell 100 30 100 100 Tuesday 2 February 2027, no events 1 2 4 7 0\nN Cell 200 30 100 100 Wednesday 3 February 2027, no events 1 3 4 7 0\nN Cell 300 30 100 100 Thursday 4 February 2027, no events 1 4 4 7 0\nN Cell 400 30 100 100 Friday 5 February 2027, no events 1 5 4 7 0\nN Cell 500 30 100 100 Saturday 6 February 2027, no events 1 6 4 7 0\nN Cell 600 30 100 100 Sunday 7 February 2027, no events 1 7 4 7 0\nN Cell 0 130 100 100 Monday 8 February 2027, 1 event 2 1 4 7 0\nN ListItem 0 180 100 25 Feb standup, 09:00 to 10:00, repeats 0 0 0 0 1\nN Cell 100 130 100 100 Tuesday 9 February 2027, 3 events 2 2 4 7 0\nN ListItem 100 130 0 0 Feb standup, 09:00 to 10:00, repeats 0 0 0 0 1\nN ListItem 100 130 0 0 Feb sync, 11:00 to 11:30 0 0 0 0 1\nN ListItem 100 130 0 0 Feb call, 15:00 to 15:30 0 0 0 0 1\nN Cell 200 130 100 100 Wednesday 10 February 2027, 1 event 2 3 4 7 0\nN ListItem 200 180 100 25 Feb standup, 09:00 to 10:00, repeats 0 0 0 0 1\nN Cell 300 130 100 100 Thursday 11 February 2027, no events 2 4 4 7 0\nN Cell 400 130 100 100 Friday 12 February 2027, no events 2 5 4 7 0\nN Cell 500 130 100 100 Saturday 13 February 2027, no events 2 6 4 7 0\nN Cell 600 130 100 100 Sunday 14 February 2027, no events 2 7 4 7 0\nN Cell 0 230 100 100 Monday 15 February 2027, 1 event 3 1 4 7 0\nN ListItem 0 255 100 25 Monthly, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 100 230 100 100 Tuesday 16 February 2027, no events 3 2 4 7 0\nN Cell 200 230 100 100 Wednesday 17 February 2027, no events 3 3 4 7 0\nN Cell 300 230 100 100 Thursday 18 February 2027, no events 3 4 4 7 0\nN Cell 400 230 100 100 Friday 19 February 2027, no events 3 5 4 7 0\nN Cell 500 230 100 100 Saturday 20 February 2027, no events 3 6 4 7 0\nN Cell 600 230 100 100 Sunday 21 February 2027, no events 3 7 4 7 0\nN Cell 0 330 100 100 Monday 22 February 2027, no events 4 1 4 7 0\nN Cell 100 330 100 100 Tuesday 23 February 2027, no events 4 2 4 7 0\nN Cell 200 330 100 100 Wednesday 24 February 2027, no events 4 3 4 7 0\nN Cell 300 330 100 100 Thursday 25 February 2027, no events 4 4 4 7 0\nN Cell 400 330 100 100 Friday 26 February 2027, no events 4 5 4 7 0\nN Cell 500 330 100 100 Saturday 27 February 2027, no events 4 6 4 7 0\nN Cell 600 330 100 100 Sunday 28 February 2027, no events 4 7 4 7 0\nN ListItem 0 155 200 25 Feb fair, all day 0 0 0 0 1\nR 0 0\nR 1 0\nR 2 0\nR 3 0\nR 4 0\nR 5 0\nR 6 0\nR 7 1\nR 8 1\nR 9 1\nR 10 1\nR 11 1\nR 12 1\nR 13 1\nR 14 0\nR 15 0\nR 16 0\nR 17 0\nR 18 0\nR 19 0\nR 20 0\nR 21 0\nR 22 0\nR 23 0\nR 24 0\nR 25 0\nR 26 0\nR 27 0\nL 1\nB 25 7 8 0 0 155 200 25 0 0 0 30034080 30036960\n" }

fn bar_hits_m2() -> str { ret "100,167,1,0;0,155,1,0;200,155,0,0;1,179,1,0;1,1,0,0;5,40,0,0;" }

fn bar_cfg_m3() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 8u8, day: 20u8 }, week_start: .Sunday, width: 840.0, header: 24.0, cell_h: 90.0, line_h: 18.0, lines: 0u32 }
}

fn bar_want_m3() -> str { ret "M 20660 6 564\nC 20660 0 0 24 120 90 0 0 0 0\nC 20661 0 120 24 120 90 0 0 0 0\nC 20662 0 240 24 120 90 0 0 0 0\nC 20663 0 360 24 120 90 0 0 0 0\nC 20664 0 480 24 120 90 0 0 0 0\nC 20665 0 600 24 120 90 0 0 0 0\nC 20666 1 720 24 120 90 0 0 0 0\nC 20667 1 0 114 120 90 0 0 0 0\nC 20668 1 120 114 120 90 0 0 0 0\nC 20669 1 240 114 120 90 0 0 0 0\nC 20670 1 360 114 120 90 0 0 0 0\nC 20671 1 480 114 120 90 0 0 0 0\nC 20672 1 600 114 120 90 0 0 0 0\nC 20673 1 720 114 120 90 0 0 0 0\nC 20674 1 0 204 120 90 0 0 0 0\nC 20675 1 120 204 120 90 0 0 0 0\nC 20676 1 240 204 120 90 0 0 0 0\nC 20677 1 360 204 120 90 0 0 0 0\nC 20678 1 480 204 120 90 0 0 0 0\nC 20679 1 600 204 120 90 0 0 0 0\nC 20680 1 720 204 120 90 0 1 0 1\nC 20681 1 0 294 120 90 1 0 0 0\nC 20682 1 120 294 120 90 1 0 0 0\nC 20683 1 240 294 120 90 1 0 0 0\nC 20684 1 360 294 120 90 1 0 0 0\nC 20685 1 480 294 120 90 1 0 0 0\nC 20686 1 600 294 120 90 1 0 0 0\nC 20687 1 720 294 120 90 1 0 0 0\nC 20688 1 0 384 120 90 1 0 0 0\nC 20689 1 120 384 120 90 1 0 0 0\nC 20690 1 240 384 120 90 1 0 0 0\nC 20691 1 360 384 120 90 1 0 0 0\nC 20692 1 480 384 120 90 1 0 0 0\nC 20693 1 600 384 120 90 1 0 0 0\nC 20694 1 720 384 120 90 1 0 0 0\nC 20695 1 0 474 120 90 1 0 0 0\nC 20696 1 120 474 120 90 1 1 0 1\nC 20697 0 240 474 120 90 2 0 0 0\nC 20698 0 360 474 120 90 2 0 0 0\nC 20699 0 480 474 120 90 2 0 0 0\nC 20700 0 600 474 120 90 2 0 0 0\nC 20701 0 720 474 120 90 2 0 0 0\nP 10 T 20 29779800 29779860 720 204 0 0 0 1 0 0 1\nP 23 T 36 29802960 29803020 120 474 0 0 0 1 0 0 0\nN Grid 0 0 840 564 Month schedule, August 2026 0 0 6 7 0\nN ColumnHeader 0 0 120 24 Sunday 0 1 0 7 0\nN ColumnHeader 120 0 120 24 Monday 0 2 0 7 0\nN ColumnHeader 240 0 120 24 Tuesday 0 3 0 7 0\nN ColumnHeader 360 0 120 24 Wednesday 0 4 0 7 0\nN ColumnHeader 480 0 120 24 Thursday 0 5 0 7 0\nN ColumnHeader 600 0 120 24 Friday 0 6 0 7 0\nN ColumnHeader 720 0 120 24 Saturday 0 7 0 7 0\nN Cell 0 24 120 90 Sunday 26 July 2026, no events 1 1 6 7 0\nN Cell 120 24 120 90 Monday 27 July 2026, no events 1 2 6 7 0\nN Cell 240 24 120 90 Tuesday 28 July 2026, no events 1 3 6 7 0\nN Cell 360 24 120 90 Wednesday 29 July 2026, no events 1 4 6 7 0\nN Cell 480 24 120 90 Thursday 30 July 2026, no events 1 5 6 7 0\nN Cell 600 24 120 90 Friday 31 July 2026, no events 1 6 6 7 0\nN Cell 720 24 120 90 Saturday 1 August 2026, no events 1 7 6 7 0\nN Cell 0 114 120 90 Sunday 2 August 2026, no events 2 1 6 7 0\nN Cell 120 114 120 90 Monday 3 August 2026, no events 2 2 6 7 0\nN Cell 240 114 120 90 Tuesday 4 August 2026, no events 2 3 6 7 0\nN Cell 360 114 120 90 Wednesday 5 August 2026, no events 2 4 6 7 0\nN Cell 480 114 120 90 Thursday 6 August 2026, no events 2 5 6 7 0\nN Cell 600 114 120 90 Friday 7 August 2026, no events 2 6 6 7 0\nN Cell 720 114 120 90 Saturday 8 August 2026, no events 2 7 6 7 0\nN Cell 0 204 120 90 Sunday 9 August 2026, no events 3 1 6 7 0\nN Cell 120 204 120 90 Monday 10 August 2026, no events 3 2 6 7 0\nN Cell 240 204 120 90 Tuesday 11 August 2026, no events 3 3 6 7 0\nN Cell 360 204 120 90 Wednesday 12 August 2026, no events 3 4 6 7 0\nN Cell 480 204 120 90 Thursday 13 August 2026, no events 3 5 6 7 0\nN Cell 600 204 120 90 Friday 14 August 2026, no events 3 6 6 7 0\nN Cell 720 204 120 90 Saturday 15 August 2026, 1 event 3 7 6 7 0\nN ListItem 720 204 0 0 Monthly, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 0 294 120 90 Sunday 16 August 2026, no events 4 1 6 7 0\nN Cell 120 294 120 90 Monday 17 August 2026, no events 4 2 6 7 0\nN Cell 240 294 120 90 Tuesday 18 August 2026, no events 4 3 6 7 0\nN Cell 360 294 120 90 Wednesday 19 August 2026, no events 4 4 6 7 0\nN Cell 480 294 120 90 Thursday 20 August 2026, no events 4 5 6 7 0\nN Cell 600 294 120 90 Friday 21 August 2026, no events 4 6 6 7 0\nN Cell 720 294 120 90 Saturday 22 August 2026, no events 4 7 6 7 0\nN Cell 0 384 120 90 Sunday 23 August 2026, no events 5 1 6 7 0\nN Cell 120 384 120 90 Monday 24 August 2026, no events 5 2 6 7 0\nN Cell 240 384 120 90 Tuesday 25 August 2026, no events 5 3 6 7 0\nN Cell 360 384 120 90 Wednesday 26 August 2026, no events 5 4 6 7 0\nN Cell 480 384 120 90 Thursday 27 August 2026, no events 5 5 6 7 0\nN Cell 600 384 120 90 Friday 28 August 2026, no events 5 6 6 7 0\nN Cell 720 384 120 90 Saturday 29 August 2026, no events 5 7 6 7 0\nN Cell 0 474 120 90 Sunday 30 August 2026, no events 6 1 6 7 0\nN Cell 120 474 120 90 Monday 31 August 2026, 1 event 6 2 6 7 0\nN ListItem 120 474 0 0 Boundary, 12:00 to 13:00 0 0 0 0 1\nN Cell 240 474 120 90 Tuesday 1 September 2026, no events 6 3 6 7 0\nN Cell 360 474 120 90 Wednesday 2 September 2026, no events 6 4 6 7 0\nN Cell 480 474 120 90 Thursday 3 September 2026, no events 6 5 6 7 0\nN Cell 600 474 120 90 Friday 4 September 2026, no events 6 6 6 7 0\nN Cell 720 474 120 90 Saturday 5 September 2026, no events 6 7 6 7 0\nR 0 0\nR 1 0\nR 2 0\nR 3 0\nR 4 0\nR 5 0\nR 6 0\nR 7 0\nR 8 0\nR 9 0\nR 10 0\nR 11 0\nR 12 0\nR 13 0\nR 14 0\nR 15 0\nR 16 0\nR 17 0\nR 18 0\nR 19 0\nR 20 0\nR 21 0\nR 22 0\nR 23 0\nR 24 0\nR 25 0\nR 26 0\nR 27 0\nR 28 0\nR 29 0\nR 30 0\nR 31 0\nR 32 0\nR 33 0\nR 34 0\nR 35 0\nR 36 0\nR 37 0\nR 38 0\nR 39 0\nR 40 0\nR 41 0\nL 0\n" }

fn bar_hits_m3() -> str { ret "1,1,0,0;5,40,0,0;" }

fn zbar_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 2u8, 2u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Weekly 9", rule: "FREQ=WEEKLY;COUNT=30" }
    out[1usize] = sched.Item { id: 2u32, start: at(2026, 3u8, 8u8, 2u8, 30u8), minutes: 30u32, all_day: false, title: "Gap", rule: "" }
    out[2usize] = sched.Item { id: 3u32, start: at(2026, 3u8, 10u8, 20u8, 30u8), minutes: 120u32, all_day: false, title: "Late NY", rule: "" }
    out[3usize] = sched.Item { id: 4u32, start: at(2026, 3u8, 12u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "Floating", rule: "" }
    out[4usize] = sched.Item { id: 5u32, start: at(2026, 3u8, 5u8, 23u8, 30u8), minutes: 45u32, all_day: false, title: "Night", rule: "FREQ=DAILY;COUNT=10" }
    out[5usize] = sched.Item { id: 6u32, start: at(2026, 3u8, 28u8, 22u8, 0u8), minutes: 600u32, all_day: false, title: "Overnight", rule: "" }
    out[6usize] = sched.Item { id: 7u32, start: at(2026, 3u8, 9u8, 0u8, 0u8), minutes: 5760u32, all_day: true, title: "Trip", rule: "" }
    out[7usize] = sched.Item { id: 8u32, start: at(2026, 3u8, 11u8, 20u8, 0u8), minutes: 3000u32, all_day: false, title: "Long haul", rule: "" }
    ret 8usize
}

fn zbar_want() -> str { ret "M 20507 6 750\nC 20507 0 0 30 100 120 0 1 1 0\nC 20508 0 100 30 100 120 1 0 0 0\nC 20509 0 200 30 100 120 1 0 0 0\nC 20510 0 300 30 100 120 1 0 0 0\nC 20511 0 400 30 100 120 1 0 0 0\nC 20512 0 500 30 100 120 1 0 0 0\nC 20513 1 600 30 100 120 1 0 0 0\nC 20514 1 0 150 100 120 1 1 1 0\nC 20515 1 100 150 100 120 2 0 0 0\nC 20516 1 200 150 100 120 2 0 0 0\nC 20517 1 300 150 100 120 2 0 0 0\nC 20518 1 400 150 100 120 2 1 1 0\nC 20519 1 500 150 100 120 3 1 1 0\nC 20520 1 600 150 100 120 4 2 2 0\nC 20521 1 0 270 100 120 6 2 2 0\nC 20522 1 100 270 100 120 8 1 1 0\nC 20523 1 200 270 100 120 9 2 2 0\nC 20524 1 300 270 100 120 11 2 2 0\nC 20525 1 400 270 100 120 13 1 1 0\nC 20526 1 500 270 100 120 14 1 1 0\nC 20527 1 600 270 100 120 15 1 1 0\nC 20528 1 0 390 100 120 16 1 1 0\nC 20529 1 100 390 100 120 17 0 0 0\nC 20530 1 200 390 100 120 17 0 0 0\nC 20531 1 300 390 100 120 17 0 0 0\nC 20532 1 400 390 100 120 17 0 0 0\nC 20533 1 500 390 100 120 17 0 0 0\nC 20534 1 600 390 100 120 17 0 0 0\nC 20535 1 0 510 100 120 17 1 1 0\nC 20536 1 100 510 100 120 18 0 0 0\nC 20537 1 200 510 100 120 18 0 0 0\nC 20538 1 300 510 100 120 18 0 0 0\nC 20539 1 400 510 100 120 18 0 0 0\nC 20540 1 500 510 100 120 18 0 0 0\nC 20541 1 600 510 100 120 18 1 1 0\nC 20542 1 0 630 100 120 19 1 1 0\nC 20543 1 100 630 100 120 20 0 0 0\nC 20544 0 200 630 100 120 20 0 0 0\nC 20545 0 300 630 100 120 20 0 0 0\nC 20546 0 400 630 100 120 20 0 0 0\nC 20547 0 500 630 100 120 20 0 0 0\nC 20548 0 600 630 100 120 20 0 0 0\nP 0 T 0 29531040 29531100 0 50 100 20 0 1 0 0 1\nP 0 T 7 29541120 29541180 0 170 100 20 0 1 0 0 1\nP 4 T 11 29546310 29546355 400 170 100 20 0 1 0 0 1\nP 4 T 12 29547750 29547795 500 170 100 20 0 1 0 0 1\nP 4 T 13 29549190 29549235 600 170 100 20 0 2 0 0 1\nP 1 T 13 29549370 29549400 600 190 100 20 1 2 0 0 0\nP 4 T 14 29550570 29550615 0 330 100 20 0 2 0 0 1\nP 0 T 14 29551140 29551200 0 350 100 20 1 2 0 0 1\nP 4 T 15 29552010 29552055 100 330 100 20 0 1 0 0 1\nP 2 T 16 29553270 29553390 200 330 100 20 0 2 0 0 0\nP 4 T 16 29553450 29553495 200 350 100 20 1 2 0 0 1\nP 3 A 17 29554560 29556000 300 330 100 20 0 2 0 0 0\nP 4 T 17 29554890 29554935 300 350 100 20 1 2 0 0 1\nP 4 T 18 29556330 29556375 400 330 100 20 0 1 0 0 1\nP 4 T 19 29557770 29557815 500 330 100 20 0 1 0 0 1\nP 4 T 20 29559210 29559255 600 330 100 20 0 1 0 0 1\nP 0 T 21 29561220 29561280 0 410 100 20 0 1 0 0 1\nP 0 T 28 29571300 29571360 0 530 100 20 0 1 0 0 1\nP 5 T 34 29579340 29579940 600 530 100 20 0 1 0 0 0\nP 0 T 35 29581440 29581500 0 650 100 20 0 1 0 0 1\nN Grid 0 0 700 750 Month schedule, March 2026 0 0 6 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 23 February 2026, 1 event 1 1 6 7 0\nN ListItem 0 50 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 100 30 100 120 Tuesday 24 February 2026, no events 1 2 6 7 0\nN Cell 200 30 100 120 Wednesday 25 February 2026, no events 1 3 6 7 0\nN Cell 300 30 100 120 Thursday 26 February 2026, no events 1 4 6 7 0\nN Cell 400 30 100 120 Friday 27 February 2026, no events 1 5 6 7 0\nN Cell 500 30 100 120 Saturday 28 February 2026, no events 1 6 6 7 0\nN Cell 600 30 100 120 Sunday 1 March 2026, no events 1 7 6 7 0\nN Cell 0 150 100 120 Monday 2 March 2026, 1 event 2 1 6 7 0\nN ListItem 0 170 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 100 150 100 120 Tuesday 3 March 2026, no events 2 2 6 7 0\nN Cell 200 150 100 120 Wednesday 4 March 2026, no events 2 3 6 7 0\nN Cell 300 150 100 120 Thursday 5 March 2026, no events 2 4 6 7 0\nN Cell 400 150 100 120 Friday 6 March 2026, 1 event 2 5 6 7 0\nN ListItem 400 170 100 20 Night, 06:30 to 07:15, repeats 0 0 0 0 1\nN Cell 500 150 100 120 Saturday 7 March 2026, 1 event 2 6 6 7 0\nN ListItem 500 170 100 20 Night, 06:30 to 07:15, repeats 0 0 0 0 1\nN Cell 600 150 100 120 Sunday 8 March 2026, 2 events 2 7 6 7 0\nN ListItem 600 170 100 20 Night, 06:30 to 07:15, repeats 0 0 0 0 1\nN ListItem 600 190 100 20 Gap, 09:30 to 10:00 0 0 0 0 1\nN Cell 0 270 100 120 Monday 9 March 2026, 2 events 3 1 6 7 0\nN ListItem 0 330 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN ListItem 0 350 100 20 Weekly 9, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 100 270 100 120 Tuesday 10 March 2026, 1 event 3 2 6 7 0\nN ListItem 100 330 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 200 270 100 120 Wednesday 11 March 2026, 2 events 3 3 6 7 0\nN ListItem 200 330 100 20 Late NY, 02:30 to 04:30 0 0 0 0 1\nN ListItem 200 350 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 300 270 100 120 Thursday 12 March 2026, 2 events 3 4 6 7 0\nN ListItem 300 330 100 20 Floating, all day 0 0 0 0 1\nN ListItem 300 350 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 400 270 100 120 Friday 13 March 2026, 1 event 3 5 6 7 0\nN ListItem 400 330 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 500 270 100 120 Saturday 14 March 2026, 1 event 3 6 6 7 0\nN ListItem 500 330 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 600 270 100 120 Sunday 15 March 2026, 1 event 3 7 6 7 0\nN ListItem 600 330 100 20 Night, 05:30 to 06:15, repeats 0 0 0 0 1\nN Cell 0 390 100 120 Monday 16 March 2026, 1 event 4 1 6 7 0\nN ListItem 0 410 100 20 Weekly 9, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 100 390 100 120 Tuesday 17 March 2026, no events 4 2 6 7 0\nN Cell 200 390 100 120 Wednesday 18 March 2026, no events 4 3 6 7 0\nN Cell 300 390 100 120 Thursday 19 March 2026, no events 4 4 6 7 0\nN Cell 400 390 100 120 Friday 20 March 2026, no events 4 5 6 7 0\nN Cell 500 390 100 120 Saturday 21 March 2026, no events 4 6 6 7 0\nN Cell 600 390 100 120 Sunday 22 March 2026, no events 4 7 6 7 0\nN Cell 0 510 100 120 Monday 23 March 2026, 1 event 5 1 6 7 0\nN ListItem 0 530 100 20 Weekly 9, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 100 510 100 120 Tuesday 24 March 2026, no events 5 2 6 7 0\nN Cell 200 510 100 120 Wednesday 25 March 2026, no events 5 3 6 7 0\nN Cell 300 510 100 120 Thursday 26 March 2026, no events 5 4 6 7 0\nN Cell 400 510 100 120 Friday 27 March 2026, no events 5 5 6 7 0\nN Cell 500 510 100 120 Saturday 28 March 2026, no events 5 6 6 7 0\nN Cell 600 510 100 120 Sunday 29 March 2026, 1 event 5 7 6 7 0\nN ListItem 600 530 100 20 Overnight, 05:00 to 15:00 0 0 0 0 1\nN Cell 0 630 100 120 Monday 30 March 2026, 1 event 6 1 6 7 0\nN ListItem 0 650 100 20 Weekly 9, 16:00 to 17:00, repeats 0 0 0 0 1\nN Cell 100 630 100 120 Tuesday 31 March 2026, no events 6 2 6 7 0\nN Cell 200 630 100 120 Wednesday 1 April 2026, no events 6 3 6 7 0\nN Cell 300 630 100 120 Thursday 2 April 2026, no events 6 4 6 7 0\nN Cell 400 630 100 120 Friday 3 April 2026, no events 6 5 6 7 0\nN Cell 500 630 100 120 Saturday 4 April 2026, no events 6 6 6 7 0\nN Cell 600 630 100 120 Sunday 5 April 2026, no events 6 7 6 7 0\nN ListItem 0 290 400 20 Trip, all day 0 0 0 0 1\nN ListItem 300 310 300 20 Long haul, 02:00 to 04:00 0 0 0 0 1\nR 0 0\nR 1 0\nR 2 0\nR 3 0\nR 4 0\nR 5 0\nR 6 0\nR 7 0\nR 8 0\nR 9 0\nR 10 0\nR 11 0\nR 12 0\nR 13 0\nR 14 2\nR 15 2\nR 16 2\nR 17 2\nR 18 2\nR 19 2\nR 20 2\nR 21 0\nR 22 0\nR 23 0\nR 24 0\nR 25 0\nR 26 0\nR 27 0\nR 28 0\nR 29 0\nR 30 0\nR 31 0\nR 32 0\nR 33 0\nR 34 0\nR 35 0\nR 36 0\nR 37 0\nR 38 0\nR 39 0\nR 40 0\nR 41 0\nL 2\nB 6 14 17 0 0 290 400 20 0 0 0 29550240 29556000\nB 7 17 19 1 300 310 300 20 0 0 0 29554680 29557680\n" }

fn zbar_hits() -> str { ret "200,300,1,0;0,290,1,0;400,290,0,0;1,309,1,0;450,320,1,1;300,310,1,1;600,310,0,0;301,329,1,1;1,1,0,0;5,40,0,0;" }

fn series_0_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 1u32, start: at(2026, 10u8, 5u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Mon Wed", rule: "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=12" }
    ret 1usize
}

fn series_0_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 1 1 0\nC 20733 1 200 150 100 120 1 0 0 0\nC 20734 1 300 150 100 120 1 1 1 0\nC 20735 1 400 150 100 120 2 0 0 0\nC 20736 1 500 150 100 120 2 0 0 0\nC 20737 1 600 150 100 120 2 0 0 0\nC 20738 1 0 270 100 120 2 0 0 0\nC 20739 1 100 270 100 120 2 1 1 0\nC 20740 1 200 270 100 120 3 0 0 0\nC 20741 1 300 270 100 120 3 1 1 0\nC 20742 1 400 270 100 120 4 0 0 0\nC 20743 1 500 270 100 120 4 0 0 0\nC 20744 1 600 270 100 120 4 0 0 0\nC 20745 1 0 390 100 120 4 0 0 0\nC 20746 1 100 390 100 120 4 1 1 0\nC 20747 1 200 390 100 120 5 0 0 0\nC 20748 1 300 390 100 120 5 1 1 0\nC 20749 1 400 390 100 120 6 0 0 0\nC 20750 1 500 390 100 120 6 0 0 0\nC 20751 1 600 390 100 120 6 0 0 0\nC 20752 1 0 510 100 120 6 0 0 0\nC 20753 1 100 510 100 120 6 1 1 0\nC 20754 1 200 510 100 120 7 0 0 0\nC 20755 1 300 510 100 120 7 1 1 0\nC 20756 1 400 510 100 120 8 0 0 0\nC 20757 1 500 510 100 120 8 0 0 0\nC 20758 0 600 510 100 120 8 0 0 0\nP 0 T 8 29854770 29854830 100 170 100 20 0 1 0 0 1\nP 0 T 10 29857650 29857710 300 170 100 20 0 1 0 0 1\nP 0 T 15 29864850 29864910 100 290 100 20 0 1 0 0 1\nP 0 T 17 29867730 29867790 300 290 100 20 0 1 0 0 1\nP 0 T 22 29874930 29874990 100 410 100 20 0 1 0 0 1\nP 0 T 24 29877810 29877870 300 410 100 20 0 1 0 0 1\nP 0 T 29 29885010 29885070 100 530 100 20 0 1 0 0 1\nP 0 T 31 29887890 29887950 300 530 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, 1 event 2 2 5 7 0\nN ListItem 100 170 100 20 Mon Wed, 11:30 to 12:30, repeats 0 0 0 0 1\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, 1 event 2 4 5 7 0\nN ListItem 300 170 100 20 Mon Wed, 11:30 to 12:30, repeats 0 0 0 0 1\nN Cell 400 150 100 120 Friday 9 October 2026, no events 2 5 5 7 0\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, 1 event 3 2 5 7 0\nN ListItem 100 290 100 20 Mon Wed, 11:30 to 12:30, repeats 0 0 0 0 1\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, 1 event 3 4 5 7 0\nN ListItem 300 290 100 20 Mon Wed, 11:30 to 12:30, repeats 0 0 0 0 1\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, 1 event 4 2 5 7 0\nN ListItem 100 410 100 20 Mon Wed, 11:30 to 12:30, repeats 0 0 0 0 1\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, 1 event 4 4 5 7 0\nN ListItem 300 410 100 20 Mon Wed, 11:30 to 12:30, repeats 0 0 0 0 1\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, 1 event 5 2 5 7 0\nN ListItem 100 530 100 20 Mon Wed, 11:30 to 12:30, repeats 0 0 0 0 1\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, 1 event 5 4 5 7 0\nN ListItem 300 530 100 20 Mon Wed, 11:30 to 12:30, repeats 0 0 0 0 1\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_1_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 2u32, start: at(2026, 10u8, 2u8, 18u8, 0u8), minutes: 90u32, all_day: false, title: "Fri Sun", rule: "FREQ=WEEKLY;BYDAY=FR,SU;COUNT=10" }
    ret 1usize
}

fn series_1_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 1 1 0\nC 20731 1 0 150 100 120 1 0 0 0\nC 20732 1 100 150 100 120 1 1 1 0\nC 20733 1 200 150 100 120 2 0 0 0\nC 20734 1 300 150 100 120 2 0 0 0\nC 20735 1 400 150 100 120 2 0 0 0\nC 20736 1 500 150 100 120 2 0 0 0\nC 20737 1 600 150 100 120 2 1 1 0\nC 20738 1 0 270 100 120 3 0 0 0\nC 20739 1 100 270 100 120 3 1 1 0\nC 20740 1 200 270 100 120 4 0 0 0\nC 20741 1 300 270 100 120 4 0 0 0\nC 20742 1 400 270 100 120 4 0 0 0\nC 20743 1 500 270 100 120 4 0 0 0\nC 20744 1 600 270 100 120 4 1 1 0\nC 20745 1 0 390 100 120 5 0 0 0\nC 20746 1 100 390 100 120 5 1 1 0\nC 20747 1 200 390 100 120 6 0 0 0\nC 20748 1 300 390 100 120 6 0 0 0\nC 20749 1 400 390 100 120 6 0 0 0\nC 20750 1 500 390 100 120 6 0 0 0\nC 20751 1 600 390 100 120 6 1 1 0\nC 20752 1 0 510 100 120 7 0 0 0\nC 20753 1 100 510 100 120 7 1 1 0\nC 20754 1 200 510 100 120 8 0 0 0\nC 20755 1 300 510 100 120 8 0 0 0\nC 20756 1 400 510 100 120 8 0 0 0\nC 20757 1 500 510 100 120 8 0 0 0\nC 20758 0 600 510 100 120 8 1 1 0\nP 0 T 6 29851740 29851830 600 50 100 20 0 1 0 0 1\nP 0 T 8 29854620 29854710 100 170 100 20 0 1 0 0 1\nP 0 T 13 29861820 29861910 600 170 100 20 0 1 0 0 1\nP 0 T 15 29864700 29864790 100 290 100 20 0 1 0 0 1\nP 0 T 20 29871900 29871990 600 290 100 20 0 1 0 0 1\nP 0 T 22 29874780 29874870 100 410 100 20 0 1 0 0 1\nP 0 T 27 29881980 29882070 600 410 100 20 0 1 0 0 1\nP 0 T 29 29884860 29884950 100 530 100 20 0 1 0 0 1\nP 0 T 34 29892060 29892150 600 530 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, 1 event 1 7 5 7 0\nN ListItem 600 50 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, 1 event 2 2 5 7 0\nN ListItem 100 170 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, no events 2 4 5 7 0\nN Cell 400 150 100 120 Friday 9 October 2026, no events 2 5 5 7 0\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, 1 event 2 7 5 7 0\nN ListItem 600 170 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, 1 event 3 2 5 7 0\nN ListItem 100 290 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, no events 3 4 5 7 0\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, 1 event 3 7 5 7 0\nN ListItem 600 290 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, 1 event 4 2 5 7 0\nN ListItem 100 410 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, no events 4 4 5 7 0\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, 1 event 4 7 5 7 0\nN ListItem 600 410 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, 1 event 5 2 5 7 0\nN ListItem 100 530 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, 1 event 5 7 5 7 0\nN ListItem 600 530 100 20 Fri Sun, 09:00 to 10:30, repeats 0 0 0 0 1\n" }

fn series_2_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 3u32, start: at(2026, 10u8, 3u8, 7u8, 0u8), minutes: 30u32, all_day: false, title: "Daily", rule: "FREQ=DAILY;COUNT=15" }
    ret 1usize
}

fn series_2_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 1 1 0\nC 20730 1 600 30 100 120 1 1 1 0\nC 20731 1 0 150 100 120 2 1 1 0\nC 20732 1 100 150 100 120 3 1 1 0\nC 20733 1 200 150 100 120 4 1 1 0\nC 20734 1 300 150 100 120 5 1 1 0\nC 20735 1 400 150 100 120 6 1 1 0\nC 20736 1 500 150 100 120 7 1 1 0\nC 20737 1 600 150 100 120 8 1 1 0\nC 20738 1 0 270 100 120 9 1 1 0\nC 20739 1 100 270 100 120 10 1 1 0\nC 20740 1 200 270 100 120 11 1 1 0\nC 20741 1 300 270 100 120 12 1 1 0\nC 20742 1 400 270 100 120 13 1 1 0\nC 20743 1 500 270 100 120 14 1 1 0\nC 20744 1 600 270 100 120 15 0 0 0\nC 20745 1 0 390 100 120 15 0 0 0\nC 20746 1 100 390 100 120 15 0 0 0\nC 20747 1 200 390 100 120 15 0 0 0\nC 20748 1 300 390 100 120 15 0 0 0\nC 20749 1 400 390 100 120 15 0 0 0\nC 20750 1 500 390 100 120 15 0 0 0\nC 20751 1 600 390 100 120 15 0 0 0\nC 20752 1 0 510 100 120 15 0 0 0\nC 20753 1 100 510 100 120 15 0 0 0\nC 20754 1 200 510 100 120 15 0 0 0\nC 20755 1 300 510 100 120 15 0 0 0\nC 20756 1 400 510 100 120 15 0 0 0\nC 20757 1 500 510 100 120 15 0 0 0\nC 20758 0 600 510 100 120 15 0 0 0\nP 0 T 5 29850270 29850300 500 50 100 20 0 1 0 0 1\nP 0 T 6 29851710 29851740 600 50 100 20 0 1 0 0 1\nP 0 T 7 29853150 29853180 0 170 100 20 0 1 0 0 1\nP 0 T 8 29854590 29854620 100 170 100 20 0 1 0 0 1\nP 0 T 9 29856030 29856060 200 170 100 20 0 1 0 0 1\nP 0 T 10 29857470 29857500 300 170 100 20 0 1 0 0 1\nP 0 T 11 29858910 29858940 400 170 100 20 0 1 0 0 1\nP 0 T 12 29860350 29860380 500 170 100 20 0 1 0 0 1\nP 0 T 13 29861790 29861820 600 170 100 20 0 1 0 0 1\nP 0 T 14 29863230 29863260 0 290 100 20 0 1 0 0 1\nP 0 T 15 29864670 29864700 100 290 100 20 0 1 0 0 1\nP 0 T 16 29866110 29866140 200 290 100 20 0 1 0 0 1\nP 0 T 17 29867550 29867580 300 290 100 20 0 1 0 0 1\nP 0 T 18 29868990 29869020 400 290 100 20 0 1 0 0 1\nP 0 T 19 29870430 29870460 500 290 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, 1 event 1 6 5 7 0\nN ListItem 500 50 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 600 30 100 120 Sunday 4 October 2026, 1 event 1 7 5 7 0\nN ListItem 600 50 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 0 150 100 120 Monday 5 October 2026, 1 event 2 1 5 7 0\nN ListItem 0 170 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 100 150 100 120 Tuesday 6 October 2026, 1 event 2 2 5 7 0\nN ListItem 100 170 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 200 150 100 120 Wednesday 7 October 2026, 1 event 2 3 5 7 0\nN ListItem 200 170 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 300 150 100 120 Thursday 8 October 2026, 1 event 2 4 5 7 0\nN ListItem 300 170 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 400 150 100 120 Friday 9 October 2026, 1 event 2 5 5 7 0\nN ListItem 400 170 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 500 150 100 120 Saturday 10 October 2026, 1 event 2 6 5 7 0\nN ListItem 500 170 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 600 150 100 120 Sunday 11 October 2026, 1 event 2 7 5 7 0\nN ListItem 600 170 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 0 270 100 120 Monday 12 October 2026, 1 event 3 1 5 7 0\nN ListItem 0 290 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 100 270 100 120 Tuesday 13 October 2026, 1 event 3 2 5 7 0\nN ListItem 100 290 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 200 270 100 120 Wednesday 14 October 2026, 1 event 3 3 5 7 0\nN ListItem 200 290 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 300 270 100 120 Thursday 15 October 2026, 1 event 3 4 5 7 0\nN ListItem 300 290 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 400 270 100 120 Friday 16 October 2026, 1 event 3 5 5 7 0\nN ListItem 400 290 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 500 270 100 120 Saturday 17 October 2026, 1 event 3 6 5 7 0\nN ListItem 500 290 100 20 Daily, 08:30 to 09:00, repeats 0 0 0 0 1\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, no events 4 4 5 7 0\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_3_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 4u32, start: at(2026, 10u8, 1u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Until time", rule: "FREQ=WEEKLY;UNTIL=20261120T090000Z;BYDAY=TH" }
    ret 1usize
}

fn series_3_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 1 1 0\nC 20729 1 500 30 100 120 1 0 0 0\nC 20730 1 600 30 100 120 1 0 0 0\nC 20731 1 0 150 100 120 1 0 0 0\nC 20732 1 100 150 100 120 1 0 0 0\nC 20733 1 200 150 100 120 1 0 0 0\nC 20734 1 300 150 100 120 1 0 0 0\nC 20735 1 400 150 100 120 1 1 1 0\nC 20736 1 500 150 100 120 2 0 0 0\nC 20737 1 600 150 100 120 2 0 0 0\nC 20738 1 0 270 100 120 2 0 0 0\nC 20739 1 100 270 100 120 2 0 0 0\nC 20740 1 200 270 100 120 2 0 0 0\nC 20741 1 300 270 100 120 2 0 0 0\nC 20742 1 400 270 100 120 2 1 1 0\nC 20743 1 500 270 100 120 3 0 0 0\nC 20744 1 600 270 100 120 3 0 0 0\nC 20745 1 0 390 100 120 3 0 0 0\nC 20746 1 100 390 100 120 3 0 0 0\nC 20747 1 200 390 100 120 3 0 0 0\nC 20748 1 300 390 100 120 3 0 0 0\nC 20749 1 400 390 100 120 3 1 1 0\nC 20750 1 500 390 100 120 4 0 0 0\nC 20751 1 600 390 100 120 4 0 0 0\nC 20752 1 0 510 100 120 4 0 0 0\nC 20753 1 100 510 100 120 4 0 0 0\nC 20754 1 200 510 100 120 4 0 0 0\nC 20755 1 300 510 100 120 4 0 0 0\nC 20756 1 400 510 100 120 4 1 1 0\nC 20757 1 500 510 100 120 5 0 0 0\nC 20758 0 600 510 100 120 5 0 0 0\nP 0 T 4 29848920 29848980 400 50 100 20 0 1 0 0 1\nP 0 T 11 29859000 29859060 400 170 100 20 0 1 0 0 1\nP 0 T 18 29869080 29869140 400 290 100 20 0 1 0 0 1\nP 0 T 25 29879160 29879220 400 410 100 20 0 1 0 0 1\nP 0 T 32 29889240 29889300 400 530 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, 1 event 1 5 5 7 0\nN ListItem 400 50 100 20 Until time, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, no events 2 4 5 7 0\nN Cell 400 150 100 120 Friday 9 October 2026, 1 event 2 5 5 7 0\nN ListItem 400 170 100 20 Until time, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, no events 3 2 5 7 0\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, no events 3 4 5 7 0\nN Cell 400 270 100 120 Friday 16 October 2026, 1 event 3 5 5 7 0\nN ListItem 400 290 100 20 Until time, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, no events 4 4 5 7 0\nN Cell 400 390 100 120 Friday 23 October 2026, 1 event 4 5 5 7 0\nN ListItem 400 410 100 20 Until time, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, 1 event 5 5 5 7 0\nN ListItem 400 530 100 20 Until time, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_4_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 5u32, start: at(2026, 10u8, 5u8, 8u8, 0u8), minutes: 60u32, all_day: false, title: "Until date", rule: "FREQ=WEEKLY;UNTIL=20261031;BYDAY=MO" }
    ret 1usize
}

fn series_4_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 0 0 0\nC 20734 1 300 150 100 120 0 1 1 0\nC 20735 1 400 150 100 120 1 0 0 0\nC 20736 1 500 150 100 120 1 0 0 0\nC 20737 1 600 150 100 120 1 0 0 0\nC 20738 1 0 270 100 120 1 0 0 0\nC 20739 1 100 270 100 120 1 0 0 0\nC 20740 1 200 270 100 120 1 0 0 0\nC 20741 1 300 270 100 120 1 1 1 0\nC 20742 1 400 270 100 120 2 0 0 0\nC 20743 1 500 270 100 120 2 0 0 0\nC 20744 1 600 270 100 120 2 0 0 0\nC 20745 1 0 390 100 120 2 0 0 0\nC 20746 1 100 390 100 120 2 0 0 0\nC 20747 1 200 390 100 120 2 0 0 0\nC 20748 1 300 390 100 120 2 1 1 0\nC 20749 1 400 390 100 120 3 0 0 0\nC 20750 1 500 390 100 120 3 0 0 0\nC 20751 1 600 390 100 120 3 0 0 0\nC 20752 1 0 510 100 120 3 0 0 0\nC 20753 1 100 510 100 120 3 0 0 0\nC 20754 1 200 510 100 120 3 0 0 0\nC 20755 1 300 510 100 120 3 1 1 0\nC 20756 1 400 510 100 120 4 0 0 0\nC 20757 1 500 510 100 120 4 0 0 0\nC 20758 0 600 510 100 120 4 0 0 0\nP 0 T 10 29857440 29857500 300 170 100 20 0 1 0 0 1\nP 0 T 17 29867520 29867580 300 290 100 20 0 1 0 0 1\nP 0 T 24 29877600 29877660 300 410 100 20 0 1 0 0 1\nP 0 T 31 29887680 29887740 300 530 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, 1 event 2 4 5 7 0\nN ListItem 300 170 100 20 Until date, 08:00 to 09:00, repeats 0 0 0 0 1\nN Cell 400 150 100 120 Friday 9 October 2026, no events 2 5 5 7 0\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, no events 3 2 5 7 0\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, 1 event 3 4 5 7 0\nN ListItem 300 290 100 20 Until date, 08:00 to 09:00, repeats 0 0 0 0 1\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, 1 event 4 4 5 7 0\nN ListItem 300 410 100 20 Until date, 08:00 to 09:00, repeats 0 0 0 0 1\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, 1 event 5 4 5 7 0\nN ListItem 300 530 100 20 Until date, 08:00 to 09:00, repeats 0 0 0 0 1\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_5_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 6u32, start: at(2026, 10u8, 6u8, 0u8, 0u8), minutes: 1440u32, all_day: true, title: "All day", rule: "FREQ=WEEKLY;COUNT=4" }
    ret 1usize
}

fn series_5_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 0 0 0\nC 20734 1 300 150 100 120 0 1 1 0\nC 20735 1 400 150 100 120 1 0 0 0\nC 20736 1 500 150 100 120 1 0 0 0\nC 20737 1 600 150 100 120 1 0 0 0\nC 20738 1 0 270 100 120 1 0 0 0\nC 20739 1 100 270 100 120 1 0 0 0\nC 20740 1 200 270 100 120 1 0 0 0\nC 20741 1 300 270 100 120 1 1 1 0\nC 20742 1 400 270 100 120 2 0 0 0\nC 20743 1 500 270 100 120 2 0 0 0\nC 20744 1 600 270 100 120 2 0 0 0\nC 20745 1 0 390 100 120 2 0 0 0\nC 20746 1 100 390 100 120 2 0 0 0\nC 20747 1 200 390 100 120 2 0 0 0\nC 20748 1 300 390 100 120 2 1 1 0\nC 20749 1 400 390 100 120 3 0 0 0\nC 20750 1 500 390 100 120 3 0 0 0\nC 20751 1 600 390 100 120 3 0 0 0\nC 20752 1 0 510 100 120 3 0 0 0\nC 20753 1 100 510 100 120 3 0 0 0\nC 20754 1 200 510 100 120 3 0 0 0\nC 20755 1 300 510 100 120 3 1 1 0\nC 20756 1 400 510 100 120 4 0 0 0\nC 20757 1 500 510 100 120 4 0 0 0\nC 20758 0 600 510 100 120 4 0 0 0\nP 0 A 10 29856960 29858400 300 170 100 20 0 1 0 0 1\nP 0 A 17 29867040 29868480 300 290 100 20 0 1 0 0 1\nP 0 A 24 29877120 29878560 300 410 100 20 0 1 0 0 1\nP 0 A 31 29887200 29888640 300 530 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, 1 event 2 4 5 7 0\nN ListItem 300 170 100 20 All day, all day, repeats 0 0 0 0 1\nN Cell 400 150 100 120 Friday 9 October 2026, no events 2 5 5 7 0\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, no events 3 2 5 7 0\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, 1 event 3 4 5 7 0\nN ListItem 300 290 100 20 All day, all day, repeats 0 0 0 0 1\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, 1 event 4 4 5 7 0\nN ListItem 300 410 100 20 All day, all day, repeats 0 0 0 0 1\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, 1 event 5 4 5 7 0\nN ListItem 300 530 100 20 All day, all day, repeats 0 0 0 0 1\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_6_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 7u32, start: at(2026, 10u8, 5u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "First Monday", rule: "FREQ=MONTHLY;BYDAY=1MO" }
    ret 1usize
}

fn series_6_want() -> str { ret "" }

fn series_7_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 8u32, start: at(2026, 10u8, 15u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Fifteenth", rule: "FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3" }
    ret 1usize
}

fn series_7_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 0 0 0\nC 20734 1 300 150 100 120 0 0 0 0\nC 20735 1 400 150 100 120 0 0 0 0\nC 20736 1 500 150 100 120 0 0 0 0\nC 20737 1 600 150 100 120 0 0 0 0\nC 20738 1 0 270 100 120 0 0 0 0\nC 20739 1 100 270 100 120 0 0 0 0\nC 20740 1 200 270 100 120 0 0 0 0\nC 20741 1 300 270 100 120 0 1 1 0\nC 20742 1 400 270 100 120 1 0 0 0\nC 20743 1 500 270 100 120 1 0 0 0\nC 20744 1 600 270 100 120 1 0 0 0\nC 20745 1 0 390 100 120 1 0 0 0\nC 20746 1 100 390 100 120 1 0 0 0\nC 20747 1 200 390 100 120 1 0 0 0\nC 20748 1 300 390 100 120 1 0 0 0\nC 20749 1 400 390 100 120 1 0 0 0\nC 20750 1 500 390 100 120 1 0 0 0\nC 20751 1 600 390 100 120 1 0 0 0\nC 20752 1 0 510 100 120 1 0 0 0\nC 20753 1 100 510 100 120 1 0 0 0\nC 20754 1 200 510 100 120 1 0 0 0\nC 20755 1 300 510 100 120 1 0 0 0\nC 20756 1 400 510 100 120 1 0 0 0\nC 20757 1 500 510 100 120 1 0 0 0\nC 20758 0 600 510 100 120 1 0 0 0\nP 0 T 17 29867880 29867940 300 290 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, no events 2 4 5 7 0\nN Cell 400 150 100 120 Friday 9 October 2026, no events 2 5 5 7 0\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, no events 3 2 5 7 0\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, 1 event 3 4 5 7 0\nN ListItem 300 290 100 20 Fifteenth, 14:00 to 15:00, repeats 0 0 0 0 1\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, no events 4 4 5 7 0\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_8_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 9u32, start: at(2026, 10u8, 15u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Fifteenth", rule: "FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3" }
    ret 1usize
}

fn series_8_want() -> str { ret "" }

fn series_9_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 10u32, start: at(2026, 10u8, 5u8, 9u8, 0u8), minutes: 30u32, all_day: false, title: "Hours", rule: "FREQ=DAILY;BYHOUR=9,17;COUNT=6" }
    ret 1usize
}

fn series_9_want() -> str { ret "" }

fn series_10_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 11u32, start: at(2026, 10u8, 5u8, 9u8, 0u8), minutes: 30u32, all_day: false, title: "Hours", rule: "FREQ=DAILY;BYHOUR=9,17;COUNT=6" }
    ret 1usize
}

fn series_10_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 2 2 0\nC 20734 1 300 150 100 120 2 2 2 0\nC 20735 1 400 150 100 120 4 2 2 0\nC 20736 1 500 150 100 120 6 0 0 0\nC 20737 1 600 150 100 120 6 0 0 0\nC 20738 1 0 270 100 120 6 0 0 0\nC 20739 1 100 270 100 120 6 0 0 0\nC 20740 1 200 270 100 120 6 0 0 0\nC 20741 1 300 270 100 120 6 0 0 0\nC 20742 1 400 270 100 120 6 0 0 0\nC 20743 1 500 270 100 120 6 0 0 0\nC 20744 1 600 270 100 120 6 0 0 0\nC 20745 1 0 390 100 120 6 0 0 0\nC 20746 1 100 390 100 120 6 0 0 0\nC 20747 1 200 390 100 120 6 0 0 0\nC 20748 1 300 390 100 120 6 0 0 0\nC 20749 1 400 390 100 120 6 0 0 0\nC 20750 1 500 390 100 120 6 0 0 0\nC 20751 1 600 390 100 120 6 0 0 0\nC 20752 1 0 510 100 120 6 0 0 0\nC 20753 1 100 510 100 120 6 0 0 0\nC 20754 1 200 510 100 120 6 0 0 0\nC 20755 1 300 510 100 120 6 0 0 0\nC 20756 1 400 510 100 120 6 0 0 0\nC 20757 1 500 510 100 120 6 0 0 0\nC 20758 0 600 510 100 120 6 0 0 0\nP 0 T 9 29856060 29856090 200 170 100 20 0 2 0 0 1\nP 0 T 9 29856540 29856570 200 190 100 20 1 2 0 0 1\nP 0 T 10 29857500 29857530 300 170 100 20 0 2 0 0 1\nP 0 T 10 29857980 29858010 300 190 100 20 1 2 0 0 1\nP 0 T 11 29858940 29858970 400 170 100 20 0 2 0 0 1\nP 0 T 11 29859420 29859450 400 190 100 20 1 2 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, 2 events 2 3 5 7 0\nN ListItem 200 170 100 20 Hours, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 200 190 100 20 Hours, 17:00 to 17:30, repeats 0 0 0 0 1\nN Cell 300 150 100 120 Thursday 8 October 2026, 2 events 2 4 5 7 0\nN ListItem 300 170 100 20 Hours, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 300 190 100 20 Hours, 17:00 to 17:30, repeats 0 0 0 0 1\nN Cell 400 150 100 120 Friday 9 October 2026, 2 events 2 5 5 7 0\nN ListItem 400 170 100 20 Hours, 09:00 to 09:30, repeats 0 0 0 0 1\nN ListItem 400 190 100 20 Hours, 17:00 to 17:30, repeats 0 0 0 0 1\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, no events 3 2 5 7 0\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, no events 3 4 5 7 0\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, no events 4 4 5 7 0\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_11_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 12u32, start: at(2026, 10u8, 5u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Biweekly", rule: "FREQ=WEEKLY;INTERVAL=2;COUNT=6" }
    ret 1usize
}

fn series_11_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 0 0 0\nC 20734 1 300 150 100 120 0 0 0 0\nC 20735 1 400 150 100 120 0 1 1 0\nC 20736 1 500 150 100 120 1 0 0 0\nC 20737 1 600 150 100 120 1 0 0 0\nC 20738 1 0 270 100 120 1 0 0 0\nC 20739 1 100 270 100 120 1 0 0 0\nC 20740 1 200 270 100 120 1 0 0 0\nC 20741 1 300 270 100 120 1 0 0 0\nC 20742 1 400 270 100 120 1 0 0 0\nC 20743 1 500 270 100 120 1 0 0 0\nC 20744 1 600 270 100 120 1 0 0 0\nC 20745 1 0 390 100 120 1 0 0 0\nC 20746 1 100 390 100 120 1 0 0 0\nC 20747 1 200 390 100 120 1 0 0 0\nC 20748 1 300 390 100 120 1 0 0 0\nC 20749 1 400 390 100 120 1 1 1 0\nC 20750 1 500 390 100 120 2 0 0 0\nC 20751 1 600 390 100 120 2 0 0 0\nC 20752 1 0 510 100 120 2 0 0 0\nC 20753 1 100 510 100 120 2 0 0 0\nC 20754 1 200 510 100 120 2 0 0 0\nC 20755 1 300 510 100 120 2 0 0 0\nC 20756 1 400 510 100 120 2 0 0 0\nC 20757 1 500 510 100 120 2 0 0 0\nC 20758 0 600 510 100 120 2 0 0 0\nP 0 T 11 29859300 29859360 400 170 100 20 0 1 0 0 1\nP 0 T 25 29879460 29879520 400 410 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, no events 2 4 5 7 0\nN Cell 400 150 100 120 Friday 9 October 2026, 1 event 2 5 5 7 0\nN ListItem 400 170 100 20 Biweekly, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, no events 3 2 5 7 0\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, no events 3 4 5 7 0\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, no events 4 4 5 7 0\nN Cell 400 390 100 120 Friday 23 October 2026, 1 event 4 5 5 7 0\nN ListItem 400 410 100 20 Biweekly, 15:00 to 16:00, repeats 0 0 0 0 1\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_12_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 13u32, start: at(2026, 10u8, 5u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Biweekly days", rule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=6" }
    ret 1usize
}

fn series_12_want() -> str { ret "" }

fn series_13_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 14u32, start: at(2026, 10u8, 5u8, 9u8, 0u8), minutes: 60u32, all_day: false, title: "Biweekly days", rule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=6" }
    ret 1usize
}

fn series_13_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 0 0 0\nC 20734 1 300 150 100 120 0 0 0 0\nC 20735 1 400 150 100 120 0 0 0 0\nC 20736 1 500 150 100 120 0 0 0 0\nC 20737 1 600 150 100 120 0 0 0 0\nC 20738 1 0 270 100 120 0 1 1 0\nC 20739 1 100 270 100 120 1 0 0 0\nC 20740 1 200 270 100 120 1 1 1 0\nC 20741 1 300 270 100 120 2 0 0 0\nC 20742 1 400 270 100 120 2 0 0 0\nC 20743 1 500 270 100 120 2 0 0 0\nC 20744 1 600 270 100 120 2 0 0 0\nC 20745 1 0 390 100 120 2 0 0 0\nC 20746 1 100 390 100 120 2 0 0 0\nC 20747 1 200 390 100 120 2 0 0 0\nC 20748 1 300 390 100 120 2 0 0 0\nC 20749 1 400 390 100 120 2 0 0 0\nC 20750 1 500 390 100 120 2 0 0 0\nC 20751 1 600 390 100 120 2 0 0 0\nC 20752 1 0 510 100 120 2 1 1 0\nC 20753 1 100 510 100 120 3 0 0 0\nC 20754 1 200 510 100 120 3 1 1 0\nC 20755 1 300 510 100 120 4 0 0 0\nC 20756 1 400 510 100 120 4 0 0 0\nC 20757 1 500 510 100 120 4 0 0 0\nC 20758 0 600 510 100 120 4 0 0 0\nP 0 T 14 29863320 29863380 0 290 100 20 0 1 0 0 1\nP 0 T 16 29866200 29866260 200 290 100 20 0 1 0 0 1\nP 0 T 28 29883480 29883540 0 530 100 20 0 1 0 0 1\nP 0 T 30 29886360 29886420 200 530 100 20 0 1 0 0 1\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, no events 2 4 5 7 0\nN Cell 400 150 100 120 Friday 9 October 2026, no events 2 5 5 7 0\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, 1 event 3 1 5 7 0\nN ListItem 0 290 100 20 Biweekly days, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 100 270 100 120 Tuesday 13 October 2026, no events 3 2 5 7 0\nN Cell 200 270 100 120 Wednesday 14 October 2026, 1 event 3 3 5 7 0\nN ListItem 200 290 100 20 Biweekly days, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 300 270 100 120 Thursday 15 October 2026, no events 3 4 5 7 0\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, no events 4 4 5 7 0\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, 1 event 5 1 5 7 0\nN ListItem 0 530 100 20 Biweekly days, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, 1 event 5 3 5 7 0\nN ListItem 200 530 100 20 Biweekly days, 10:00 to 11:00, repeats 0 0 0 0 1\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_14_items(out: []sched.Item) -> usize {
    out[0usize] = sched.Item { id: 15u32, start: at(2026, 10u8, 8u8, 12u8, 0u8), minutes: 45u32, all_day: false, title: "Single", rule: "" }
    ret 1usize
}

fn series_14_want() -> str { ret "M 20724 5 630\nC 20724 0 0 30 100 120 0 0 0 0\nC 20725 0 100 30 100 120 0 0 0 0\nC 20726 0 200 30 100 120 0 0 0 0\nC 20727 1 300 30 100 120 0 0 0 0\nC 20728 1 400 30 100 120 0 0 0 0\nC 20729 1 500 30 100 120 0 0 0 0\nC 20730 1 600 30 100 120 0 0 0 0\nC 20731 1 0 150 100 120 0 0 0 0\nC 20732 1 100 150 100 120 0 0 0 0\nC 20733 1 200 150 100 120 0 0 0 0\nC 20734 1 300 150 100 120 0 0 0 0\nC 20735 1 400 150 100 120 0 1 1 0\nC 20736 1 500 150 100 120 1 0 0 0\nC 20737 1 600 150 100 120 1 0 0 0\nC 20738 1 0 270 100 120 1 0 0 0\nC 20739 1 100 270 100 120 1 0 0 0\nC 20740 1 200 270 100 120 1 0 0 0\nC 20741 1 300 270 100 120 1 0 0 0\nC 20742 1 400 270 100 120 1 0 0 0\nC 20743 1 500 270 100 120 1 0 0 0\nC 20744 1 600 270 100 120 1 0 0 0\nC 20745 1 0 390 100 120 1 0 0 0\nC 20746 1 100 390 100 120 1 0 0 0\nC 20747 1 200 390 100 120 1 0 0 0\nC 20748 1 300 390 100 120 1 0 0 0\nC 20749 1 400 390 100 120 1 0 0 0\nC 20750 1 500 390 100 120 1 0 0 0\nC 20751 1 600 390 100 120 1 0 0 0\nC 20752 1 0 510 100 120 1 0 0 0\nC 20753 1 100 510 100 120 1 0 0 0\nC 20754 1 200 510 100 120 1 0 0 0\nC 20755 1 300 510 100 120 1 0 0 0\nC 20756 1 400 510 100 120 1 0 0 0\nC 20757 1 500 510 100 120 1 0 0 0\nC 20758 0 600 510 100 120 1 0 0 0\nP 0 T 11 29859195 29859240 400 170 100 20 0 1 0 0 0\nN Grid 0 0 700 630 Month schedule, October 2026 0 0 5 7 0\nN ColumnHeader 0 0 100 30 Monday 0 1 0 7 0\nN ColumnHeader 100 0 100 30 Tuesday 0 2 0 7 0\nN ColumnHeader 200 0 100 30 Wednesday 0 3 0 7 0\nN ColumnHeader 300 0 100 30 Thursday 0 4 0 7 0\nN ColumnHeader 400 0 100 30 Friday 0 5 0 7 0\nN ColumnHeader 500 0 100 30 Saturday 0 6 0 7 0\nN ColumnHeader 600 0 100 30 Sunday 0 7 0 7 0\nN Cell 0 30 100 120 Monday 28 September 2026, no events 1 1 5 7 0\nN Cell 100 30 100 120 Tuesday 29 September 2026, no events 1 2 5 7 0\nN Cell 200 30 100 120 Wednesday 30 September 2026, no events 1 3 5 7 0\nN Cell 300 30 100 120 Thursday 1 October 2026, no events 1 4 5 7 0\nN Cell 400 30 100 120 Friday 2 October 2026, no events 1 5 5 7 0\nN Cell 500 30 100 120 Saturday 3 October 2026, no events 1 6 5 7 0\nN Cell 600 30 100 120 Sunday 4 October 2026, no events 1 7 5 7 0\nN Cell 0 150 100 120 Monday 5 October 2026, no events 2 1 5 7 0\nN Cell 100 150 100 120 Tuesday 6 October 2026, no events 2 2 5 7 0\nN Cell 200 150 100 120 Wednesday 7 October 2026, no events 2 3 5 7 0\nN Cell 300 150 100 120 Thursday 8 October 2026, no events 2 4 5 7 0\nN Cell 400 150 100 120 Friday 9 October 2026, 1 event 2 5 5 7 0\nN ListItem 400 170 100 20 Single, 13:15 to 14:00 0 0 0 0 1\nN Cell 500 150 100 120 Saturday 10 October 2026, no events 2 6 5 7 0\nN Cell 600 150 100 120 Sunday 11 October 2026, no events 2 7 5 7 0\nN Cell 0 270 100 120 Monday 12 October 2026, no events 3 1 5 7 0\nN Cell 100 270 100 120 Tuesday 13 October 2026, no events 3 2 5 7 0\nN Cell 200 270 100 120 Wednesday 14 October 2026, no events 3 3 5 7 0\nN Cell 300 270 100 120 Thursday 15 October 2026, no events 3 4 5 7 0\nN Cell 400 270 100 120 Friday 16 October 2026, no events 3 5 5 7 0\nN Cell 500 270 100 120 Saturday 17 October 2026, no events 3 6 5 7 0\nN Cell 600 270 100 120 Sunday 18 October 2026, no events 3 7 5 7 0\nN Cell 0 390 100 120 Monday 19 October 2026, no events 4 1 5 7 0\nN Cell 100 390 100 120 Tuesday 20 October 2026, no events 4 2 5 7 0\nN Cell 200 390 100 120 Wednesday 21 October 2026, no events 4 3 5 7 0\nN Cell 300 390 100 120 Thursday 22 October 2026, no events 4 4 5 7 0\nN Cell 400 390 100 120 Friday 23 October 2026, no events 4 5 5 7 0\nN Cell 500 390 100 120 Saturday 24 October 2026, no events 4 6 5 7 0\nN Cell 600 390 100 120 Sunday 25 October 2026, no events 4 7 5 7 0\nN Cell 0 510 100 120 Monday 26 October 2026, no events 5 1 5 7 0\nN Cell 100 510 100 120 Tuesday 27 October 2026, no events 5 2 5 7 0\nN Cell 200 510 100 120 Wednesday 28 October 2026, no events 5 3 5 7 0\nN Cell 300 510 100 120 Thursday 29 October 2026, no events 5 4 5 7 0\nN Cell 400 510 100 120 Friday 30 October 2026, no events 5 5 5 7 0\nN Cell 500 510 100 120 Saturday 31 October 2026, no events 5 6 5 7 0\nN Cell 600 510 100 120 Sunday 1 November 2026, no events 5 7 5 7 0\n" }

fn series_cfg() -> sched.MonthConfig {
    ret sched.MonthConfig { anchor: time.Date { year: 2026, month: 10u8, day: 14u8 }, week_start: .Monday, width: 700.0, header: 30.0, cell_h: 120.0, line_h: 20.0, lines: 4u32 }
}

fn moves_want() -> str { ret "America/New_York|Europe/Sofia|2026,3,8,9,30,|2026,3,8,3,30,\nAmerica/New_York|Europe/Sofia|2026,3,29,3,30,|2026,3,28,21,30,\nAmerica/New_York|Europe/Sofia|2026,10,25,3,30,|2026,10,24,20,30,\nAmerica/New_York|Europe/Sofia|2026,11,1,7,30,|2026,11,1,1,30,\nEurope/Sofia|America/New_York|2026,3,8,2,30,|2026,3,8,9,30,\nEurope/Sofia|America/New_York|2026,11,1,1,30,|2026,11,1,7,30,\nUTC|Australia/Lord_Howe|2026,4,5,1,45,|2026,4,4,14,45,\nUTC|Australia/Lord_Howe|2026,4,5,1,15,|2026,4,4,14,15,\nUTC|Asia/Kolkata|2026,6,1,5,30,|2026,6,1,0,0,\nAmerica/Los_Angeles|Asia/Kathmandu|2026,7,1,0,15,|2026,6,30,11,30,\n" }

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

fn abs_of(d: calendar.DateTime) -> i64 {
    ret calendar.day_count(d.date) * 1440i64 + i64(d.time.hour) * 60i64 + i64(d.time.minute)
}


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


fn main(a: *mem.Arena, args: []str) -> err {
    let (db, db_error) = tz.builtin(a)
    if db_error != ok { os.exit(1i32) }
    let (ms, ms_error) = month_storage(a, 256usize, 256usize, 32768usize, 42usize)
    if ms_error != ok { os.exit(2i32) }
    var raw: [32]sched.Item = zero
    let z1_n = z1_items(raw[0..])
    if run_zoned(a, &db, ms, raw[0usize..z1_n], z1_cfg(), z1_want(), "America/New_York", "Europe/Sofia") != 0i32 { os.exit(40i32) }
    let z2_n = z2_items(raw[0..])
    if run_zoned(a, &db, ms, raw[0usize..z2_n], z2_cfg(), z2_want(), "America/New_York", "Europe/Sofia") != 0i32 { os.exit(41i32) }
    let z3_n = z3_items(raw[0..])
    if run_zoned(a, &db, ms, raw[0usize..z3_n], z3_cfg(), z3_want(), "Australia/Lord_Howe", "UTC") != 0i32 { os.exit(42i32) }
    let z4_n = z4_items(raw[0..])
    if run_zoned(a, &db, ms, raw[0usize..z4_n], z4_cfg(), z4_want(), "Asia/Kolkata", "America/Los_Angeles") != 0i32 { os.exit(43i32) }
    let bar_n_m1 = bar_items(raw[0..])
    if run_bars(a, ms, raw[0usize..bar_n_m1], bar_cfg_m1(), bar_want_m1(), bar_hits_m1(), false, &db) != 0i32 { os.exit(60i32) }
    let bar_n_m2 = bar_items(raw[0..])
    if run_bars(a, ms, raw[0usize..bar_n_m2], bar_cfg_m2(), bar_want_m2(), bar_hits_m2(), false, &db) != 0i32 { os.exit(61i32) }
    let bar_n_m3 = bar_items(raw[0..])
    if run_bars(a, ms, raw[0usize..bar_n_m3], bar_cfg_m3(), bar_want_m3(), bar_hits_m3(), false, &db) != 0i32 { os.exit(62i32) }
    let series_n_0 = series_0_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_0], at(2026, 10u8, 5u8, 9u8, 0u8), at(2026, 10u8, 6u8, 11u8, 30u8), series_cfg(), series_0_want(), true) != 0i32 { os.exit(110i32) }
    let series_n_1 = series_1_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_1], at(2026, 10u8, 2u8, 18u8, 0u8), at(2026, 10u8, 4u8, 9u8, 0u8), series_cfg(), series_1_want(), true) != 0i32 { os.exit(111i32) }
    let series_n_2 = series_2_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_2], at(2026, 10u8, 3u8, 7u8, 0u8), at(2026, 10u8, 3u8, 8u8, 30u8), series_cfg(), series_2_want(), true) != 0i32 { os.exit(112i32) }
    let series_n_3 = series_3_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_3], at(2026, 10u8, 1u8, 9u8, 0u8), at(2026, 10u8, 2u8, 10u8, 0u8), series_cfg(), series_3_want(), true) != 0i32 { os.exit(113i32) }
    let series_n_4 = series_4_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_4], at(2026, 10u8, 12u8, 8u8, 0u8), at(2026, 10u8, 15u8, 8u8, 0u8), series_cfg(), series_4_want(), true) != 0i32 { os.exit(114i32) }
    let series_n_5 = series_5_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_5], at(2026, 10u8, 13u8, 0u8, 0u8), at(2026, 10u8, 15u8, 0u8, 0u8), series_cfg(), series_5_want(), true) != 0i32 { os.exit(115i32) }
    let series_n_6 = series_6_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_6], at(2026, 10u8, 5u8, 9u8, 0u8), at(2026, 10u8, 6u8, 9u8, 0u8), series_cfg(), series_6_want(), false) != 0i32 { os.exit(116i32) }
    let series_n_7 = series_7_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_7], at(2026, 10u8, 15u8, 9u8, 0u8), at(2026, 10u8, 15u8, 14u8, 0u8), series_cfg(), series_7_want(), true) != 0i32 { os.exit(117i32) }
    let series_n_8 = series_8_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_8], at(2026, 10u8, 15u8, 9u8, 0u8), at(2026, 10u8, 16u8, 9u8, 0u8), series_cfg(), series_8_want(), false) != 0i32 { os.exit(118i32) }
    let series_n_9 = series_9_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_9], at(2026, 10u8, 5u8, 9u8, 0u8), at(2026, 10u8, 5u8, 9u8, 30u8), series_cfg(), series_9_want(), false) != 0i32 { os.exit(119i32) }
    let series_n_10 = series_10_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_10], at(2026, 10u8, 5u8, 9u8, 0u8), at(2026, 10u8, 7u8, 9u8, 0u8), series_cfg(), series_10_want(), true) != 0i32 { os.exit(120i32) }
    let series_n_11 = series_11_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_11], at(2026, 10u8, 5u8, 9u8, 0u8), at(2026, 10u8, 9u8, 15u8, 0u8), series_cfg(), series_11_want(), true) != 0i32 { os.exit(121i32) }
    let series_n_12 = series_12_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_12], at(2026, 10u8, 5u8, 9u8, 0u8), at(2026, 10u8, 6u8, 9u8, 0u8), series_cfg(), series_12_want(), false) != 0i32 { os.exit(122i32) }
    let series_n_13 = series_13_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_13], at(2026, 10u8, 5u8, 9u8, 0u8), at(2026, 10u8, 12u8, 10u8, 0u8), series_cfg(), series_13_want(), true) != 0i32 { os.exit(123i32) }
    let series_n_14 = series_14_items(raw[0..])
    if run_series(a, ms, raw[0usize..series_n_14], at(2026, 10u8, 8u8, 12u8, 0u8), at(2026, 10u8, 9u8, 13u8, 15u8), series_cfg(), series_14_want(), true) != 0i32 { os.exit(124i32) }
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
