// The calendar (overlay.calendar) in all ten looks: docs/ui/looks/<look>/calendar.png, October 2026 (a month starting on a
// Thursday), the week starting where the look's language puts it. Derived: day discs, selection, today ring and range band on
// the shared tokens; Linux, Cupertino and Material change only their metrics and colours. No platform reference is compared.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.time
use e.ui.control
use e.ui.looks
use e.ui.looks_y87
use e.ui.looks_b_run
use e.ui.overlay
use e.ui.widget

fn noop_date(ctx: *void, value: time.Date) -> err { ret ok }

fn day(d: u8) -> time.Date { ret time.Date { year: 2026i32, month: 10u8, day: d } }

// Chosen days, range band and links hold 4.5:1 (any other look is passed through unchanged).
fn build(ctx: *void, a: *mem.Arena, original: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let tones = [5]looks_y87.RoleTone{ looks_y87.RoleTone { role: .Primary, light: 0x0A60FFu32, dark: 0x409CFFu32 }, looks_y87.RoleTone { role: .OnPrimary, light: 0xFFFFFFu32, dark: 0x0B0B0Cu32 }, looks_y87.RoleTone { role: .FocusRing, light: 0x0A60FFu32, dark: 0x409CFFu32 }, looks_y87.RoleTone { role: .PrimaryContainer, light: 0xDCE8FFu32, dark: 0x1E3A66u32 }, looks_y87.RoleTone { role: .OnPrimaryContainer, light: 0x0040DDu32, dark: 0x9CC8FFu32 } }
    let (tokens, tokens_error) = looks_y87.retoned(a, original.tokens, tones[0usize..5usize])
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *original
    themed.tokens = tokens
    let (count, count_error) = build_base(ctx, a, &themed, cells)
    ret (count, count_error)
}

fn build_base(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // The keyboard focus cell is the last: Tab and Shift+Tab walk every cell of the window, and the focus wraps round to the last
    // calendar's chosen day, so the ring lands in the cell that shows it.
    let names = [6]str{ "Nothing chosen", "Chosen day, today", "Range 12 to 18", "Hover on a day", "Week numbers, events", "Keyboard focus" }
    let drives = [6]looks.Drive{ .None, .None, .None, .Hover, .None, .Focus }
    let show = widget.Change[time.Date] { ctx: zero, invoke: noop_date }
    let pick = widget.Change[time.Date] { ctx: zero, invoke: noop_date }
    var i = 0usize
    while i < 6usize {
        var has_selected = true
        var ranged = false
        var has_today = false
        var marks: overlay.CalendarMarks = zero
        if i == 0usize { has_selected = false }
        if i == 1usize { has_today = true }
        if i == 2usize { ranged = true }
        let events = [2]time.Date{ day(8u8), day(20u8) }
        if i == 4usize {
            marks.week_numbers = true
            marks.events = events[0usize..2usize]
            has_today = true
        }
        let (node, node_error) = overlay.calendar_with(a, u64((i + 1usize) * 1000usize), t, "October 2026", day(1u8), day(15u8), has_selected, ranged, day(12u8), day(18u8), day(21u8), has_today, show, pick, marks)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drives[i] }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "calendar", cells: 6usize, columns: 3usize, cell_w: 300.0, cell_h: 330.0, ctx: zero, build: build }
    ret looks_b_run.run_ten(a, &sheet)
}
