// Round 84, lane z: the keyboard walk a sheet cell can ask for. `looks.drive_cell` carries only the hook (Drive.Tabs).
// A modal's focus order starts at its first control, so n Tab presses put the ring on the nth stop; `tab_stops` is set by
// the sheet's build before the frame is driven.
use e.ui.testing

var tab_stops: usize = 0usize

fn stops(n: usize) { tab_stops = n }

fn walk(h: *testing.Harness) -> err {
    var n = 0usize
    while n < tab_stops {
        try testing.tab(h, false)
        n += 1usize
    }
    ret testing.hover(h, -500.0, -500.0)
}
