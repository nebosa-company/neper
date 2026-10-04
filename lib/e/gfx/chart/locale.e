// Locale-aware tick text for chart axes: numbers in the locale's decimal and
// grouping separators at one shared precision, dates as an LDML pattern in the
// locale's month and day names. The geometry stays in e.gfx.chart; this module
// only turns its ticks into strings, from the caller's arena.
use e.gfx.chart
use e.math
use e.mem
use e.text.locale
use e.time
use e.time.calendar

error Invalid
error TooLarge

// The fewest decimals, up to six, that write every tick exactly, so one axis
// shares a precision: a 0.25 step needs two, a 2,500 step none.
fn tick_decimals(values: []const chart.Tick) -> (u8, err) {
    var i = 0usize
    while i < values.len {
        if !chart.finite(values[i].value) { ret (0u8, Invalid) }
        i += 1usize
    }
    var digits = 0u8
    var scale = 1.0f64
    while digits < 6u8 {
        var exact = true
        i = 0usize
        while exact && i < values.len {
            let scaled = f64(values[i].value) * scale
            if math.abs[f64](scaled - math.round[f64](scaled)) > 0.001f64 { exact = false }
            i += 1usize
        }
        if exact { ret (digits, ok) }
        digits += 1u8
        scale *= 10.0f64
    }
    ret (6u8, ok)
}

fn format_ticks_in(a: *mem.Arena, place: locale.Locale, values: []const chart.Tick, out: []str) -> ([]str, err) {
    if out.len < values.len { ret (zero, TooLarge) }
    let (digits, digits_error) = tick_decimals(values)
    if digits_error != ok { ret (zero, digits_error) }
    let options = locale.NumberOptions { minimum_fraction: digits, maximum_fraction: digits, grouping: true, sign_always: false }
    var i = 0usize
    while i < values.len {
        var value = f64(values[i].value)
        if value == 0.0f64 { value = 0.0f64 }
        let (text, text_error) = locale.format_f64(a, place, value, options)
        if text_error != ok { ret (zero, text_error) }
        out[i] = text
        i += 1usize
    }
    ret (out[..values.len], ok)
}

// Date ticks through an LDML pattern such as `MMM y` or `MMMM`; the time of
// day is midnight.
fn format_date_ticks_in(a: *mem.Arena, place: locale.Locale, ticks: []const chart.DateTick, pattern: str, out: []str) -> ([]str, err) {
    if out.len < ticks.len { ret (zero, TooLarge) }
    if pattern.len == 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i < ticks.len {
        let (text, text_error) = locale.format_pattern(a, place, pattern, calendar.DateTime { date: ticks[i].date, time: zero })
        if text_error != ok { ret (zero, text_error) }
        out[i] = text
        i += 1usize
    }
    ret (out[..ticks.len], ok)
}
