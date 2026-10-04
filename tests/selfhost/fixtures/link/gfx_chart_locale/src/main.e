use e.gfx.chart
use e.gfx.chart.locale as chart_locale
use e.io
use e.mem
use e.str
use e.text.locale
use e.time

fn all(got: []str, want: []const str) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < want.len {
        if !str.eq(got[i], want[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn ticks(values: []const f32, out: []chart.Tick) -> []chart.Tick {
    var i = 0usize
    while i < values.len {
        out[i] = chart.Tick { value: values[i], fraction: f32(i) / 4.0 }
        i += 1usize
    }
    ret out[..values.len]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (db, db_error) = locale.builtin(a)
    if db_error != ok { ret db_error }
    let (en, en_error) = locale.locale(&db, "en-US")
    let (de, de_error) = locale.locale(&db, "de")
    let (fr, fr_error) = locale.locale(&db, "fr")
    let (es, es_error) = locale.locale(&db, "es")
    let (ja, ja_error) = locale.locale(&db, "ja")
    if en_error != ok || de_error != ok || fr_error != ok || es_error != ok || ja_error != ok { ret chart.Invalid }
    var tick_storage: [5]chart.Tick = zero
    var out: [5]str = zero
    let big = [5]f32{ 0.0, 2500.0, 5000.0, 7500.0, 10000.0 }
    let big_ticks = ticks(big[..], tick_storage[..])
    let (en_big, en_big_error) = chart_locale.format_ticks_in(a, en, big_ticks, out[..])
    let en_want = [5]str{ "0", "2,500", "5,000", "7,500", "10,000" }
    if en_big_error != ok || !all(en_big, en_want[..]) { ret chart.Invalid }
    let (de_big, de_big_error) = chart_locale.format_ticks_in(a, de, big_ticks, out[..])
    let de_want = [5]str{ "0", "2.500", "5.000", "7.500", "10.000" }
    if de_big_error != ok || !all(de_big, de_want[..]) { ret chart.Invalid }
    // French groups with a narrow no-break space; Spanish leaves four digits alone.
    let (fr_big, fr_big_error) = chart_locale.format_ticks_in(a, fr, big_ticks, out[..])
    let fr_want = [5]str{ "0", "2\xe2\x80\xaf500", "5\xe2\x80\xaf000", "7\xe2\x80\xaf500", "10\xe2\x80\xaf000" }
    if fr_big_error != ok || !all(fr_big, fr_want[..]) { ret chart.Invalid }
    let (es_big, es_big_error) = chart_locale.format_ticks_in(a, es, big_ticks, out[..])
    let es_want = [5]str{ "0", "2500", "5000", "7500", "10.000" }
    if es_big_error != ok || !all(es_big, es_want[..]) { ret chart.Invalid }
    // One shared precision per axis, negative zero written as zero.
    let quarters = [5]f32{ -0.0, 0.25, 0.5, 0.75, 1.0 }
    let (de_small, de_small_error) = chart_locale.format_ticks_in(a, de, ticks(quarters[..], tick_storage[..]), out[..])
    let small_want = [5]str{ "0,00", "0,25", "0,50", "0,75", "1,00" }
    if de_small_error != ok || !all(de_small, small_want[..]) { ret chart.Invalid }
    let signed = [3]f32{ -1.5, 0.0, 1.5 }
    let (en_signed, en_signed_error) = chart_locale.format_ticks_in(a, en, ticks(signed[..], tick_storage[..]), out[..])
    let signed_want = [3]str{ "-1.5", "0.0", "1.5" }
    if en_signed_error != ok || !all(en_signed, signed_want[..]) { ret chart.Invalid }
    let (digits, digits_error) = chart_locale.tick_decimals(ticks(big[..], tick_storage[..]))
    let tenths = [2]f32{ 0.1, 0.3 }
    let (tenth_digits, tenth_error) = chart_locale.tick_decimals(ticks(tenths[..], tick_storage[..]))
    if digits_error != ok || digits != 0u8 || tenth_error != ok || tenth_digits != 1u8 { ret chart.Invalid }
    // Month ticks in each locale's own abbreviations.
    var date_storage: [4]chart.DateTick = zero
    let (quarter_ticks, quarter_error) = chart.date_ticks(time.Date { year: 2024i32, month: 1u8, day: 1u8 }, time.Date { year: 2024i32, month: 12u8, day: 31u8 }, 3usize, date_storage[..])
    if quarter_error != ok || quarter_ticks.len != 4usize { ret chart.Invalid }
    var dates: [4]str = zero
    let (en_dates, en_dates_error) = chart_locale.format_date_ticks_in(a, en, quarter_ticks, "MMM y", dates[..])
    let en_dates_want = [4]str{ "Jan 2024", "Apr 2024", "Jul 2024", "Oct 2024" }
    if en_dates_error != ok || !all(en_dates, en_dates_want[..]) { ret chart.Invalid }
    let (fr_dates, fr_dates_error) = chart_locale.format_date_ticks_in(a, fr, quarter_ticks, "MMM y", dates[..])
    let fr_dates_want = [4]str{ "janv. 2024", "avr. 2024", "juil. 2024", "oct. 2024" }
    if fr_dates_error != ok || !all(fr_dates, fr_dates_want[..]) { ret chart.Invalid }
    let (ja_dates, ja_dates_error) = chart_locale.format_date_ticks_in(a, ja, quarter_ticks, "y'年'M'月'", dates[..])
    let ja_dates_want = [4]str{ "2024年1月", "2024年4月", "2024年7月", "2024年10月" }
    if ja_dates_error != ok || !all(ja_dates, ja_dates_want[..]) { ret chart.Invalid }
    let (_, short_error) = chart_locale.format_ticks_in(a, en, big_ticks, out[..4usize])
    let infinite = [1]chart.Tick{ chart.Tick { value: 1.0 / 0.0f32, fraction: 0.0 } }
    let (_, infinite_error) = chart_locale.format_ticks_in(a, en, infinite[..], out[..])
    let (_, pattern_error) = chart_locale.format_date_ticks_in(a, en, quarter_ticks, "", dates[..])
    let (_, dates_short_error) = chart_locale.format_date_ticks_in(a, en, quarter_ticks, "MMM", dates[..3usize])
    if short_error != chart_locale.TooLarge || infinite_error != chart_locale.Invalid || pattern_error != chart_locale.Invalid || dates_short_error != chart_locale.TooLarge { ret chart.Invalid }
    try io.print("gfx chart locale ok\n")
    ret ok
}
