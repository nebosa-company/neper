use e.gfx.chart
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d > -0.01 && d < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var out: [8]chart.Tick = zero
    let (whole, whole_error) = chart.nice_ticks(linear, 0.0, 10.0, 6usize, out[..])
    if whole_error != ok || whole.len != 6usize || !near(whole[1usize].value, 2.0) || !near(whole[5usize].fraction, 1.0) { ret chart.Invalid }
    var words: [8]str = zero
    var storage: [128]u8 = zero
    let (whole_text, text_error) = chart.format_ticks(whole, words[..], storage[..])
    if text_error != ok || whole_text.len != 6usize || !str.eq(whole_text[1usize], "2") || !str.eq(whole_text[5usize], "10") { ret chart.Invalid }
    let (decimal, decimal_error) = chart.nice_ticks(linear, 0.11, 0.89, 5usize, out[..])
    if decimal_error != ok || decimal.len != 4usize || !near(decimal[0usize].value, 0.2) || !near(decimal[3usize].value, 0.8) { ret chart.Invalid }
    let (decimal_text, decimal_text_error) = chart.format_ticks(decimal, words[..], storage[..])
    if decimal_text_error != ok || !str.eq(decimal_text[0usize], "0.2") || !str.eq(decimal_text[3usize], "0.8") { ret chart.Invalid }
    let reversed = chart.Scale { kind: .Linear, reverse: true, linthresh: 1.0 }
    let (reverse_ticks, reverse_error) = chart.nice_ticks(reversed, 0.0, 10.0, 6usize, out[..])
    if reverse_error != ok || !near(reverse_ticks[0usize].fraction, 1.0) || !near(reverse_ticks[5usize].fraction, 0.0) { ret chart.Invalid }
    let logarithmic = chart.Scale { kind: .Log10, reverse: false, linthresh: 1.0 }
    let (decades, decades_error) = chart.nice_ticks(logarithmic, 1.0, 1000.0, 4usize, out[..])
    if decades_error != ok || decades.len != 4usize || !near(decades[0usize].value, 1.0) || !near(decades[1usize].value, 10.0) || !near(decades[2usize].value, 100.0) || !near(decades[3usize].value, 1000.0) { ret chart.Invalid }
    let (narrow, narrow_error) = chart.nice_ticks(logarithmic, 2.0, 8.0, 5usize, out[..])
    if narrow_error != ok || narrow.len != 2usize || !near(narrow[0usize].value, 2.0) || !near(narrow[1usize].value, 5.0) { ret chart.Invalid }
    let symmetric = chart.Scale { kind: .Symlog, reverse: false, linthresh: 1.0 }
    let (signed_ticks, signed_error) = chart.nice_ticks(symmetric, -99.0, 99.0, 5usize, out[..])
    if signed_error != ok || signed_ticks.len != 5usize || !near(signed_ticks[1usize].value, -9.0) || !near(signed_ticks[2usize].value, 0.0) || !near(signed_ticks[3usize].value, 9.0) { ret chart.Invalid }
    let (signed_text, signed_text_error) = chart.format_ticks(signed_ticks, words[..], storage[..])
    if signed_text_error != ok || !str.eq(signed_text[1usize], "-9") || !str.eq(signed_text[2usize], "0") { ret chart.Invalid }
    let (negative, negative_error) = chart.nice_ticks(linear, -5.0, 5.0, 5usize, out[..])
    if negative_error != ok || negative.len != 3usize || !near(negative[1usize].value, 0.0) { ret chart.Invalid }
    let (small_log, small_log_error) = chart.nice_ticks(logarithmic, 0.000001, 0.001, 4usize, out[..])
    if small_log_error != ok || small_log.len != 4usize || !near(small_log[0usize].fraction, 0.0) || !near(small_log[3usize].fraction, 1.0) { ret chart.Invalid }
    let reversed_log = chart.Scale { kind: .Log10, reverse: true, linthresh: 1.0 }
    let (reverse_log_ticks, reverse_log_error) = chart.nice_ticks(reversed_log, 1.0, 1000.0, 4usize, out[..])
    if reverse_log_error != ok || !near(reverse_log_ticks[0usize].fraction, 1.0) || !near(reverse_log_ticks[3usize].fraction, 0.0) { ret chart.Invalid }
    let (_, invalid_log) = chart.nice_ticks(logarithmic, 0.0, 10.0, 4usize, out[..])
    if invalid_log != chart.Invalid { ret chart.Invalid }
    let (_, invalid_count) = chart.nice_ticks(linear, 0.0, 10.0, 1usize, out[..])
    if invalid_count != chart.Invalid { ret chart.Invalid }
    let (_, short_output) = chart.nice_ticks(linear, 0.0, 10.0, 6usize, out[..3usize])
    if short_output != chart.TooLarge { ret chart.Invalid }
    let (_, short_text) = chart.format_ticks(signed_ticks, words[..2usize], storage[..])
    if short_text != chart.TooLarge { ret chart.Invalid }
    let (_, short_storage) = chart.format_ticks(signed_ticks, words[..], storage[..0usize])
    if short_storage == ok { ret chart.Invalid }
    try io.print("gfx chart nice ticks ok\n")
    ret ok
}
