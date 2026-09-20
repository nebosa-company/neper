// CLDR-shaped formatting: numbers, currency, dates, comparison and case over the built-in
// locales, tag canonicalisation and fallback, and a loaded database.

use e.algo.decimal
use e.io
use e.mem
use e.os
use e.text.locale
use e.time
use e.time.calendar

fn same(a: str, b: str) -> bool {
    ret mem.eq[u8](a, b)
}

fn plain(fraction: u8) -> locale.NumberOptions {
    ret locale.NumberOptions { minimum_fraction: fraction, maximum_fraction: fraction, grouping: true, sign_always: false }
}

fn stamp() -> calendar.DateTime {
    ret calendar.DateTime { date: time.Date { year: 2026i32, month: 9u8, day: 20u8 }, time: time.Time { hour: 15u8, minute: 46u8, second: 5u8, nanos: 0u32 } }
}

fn money(text: str) -> decimal.Decimal {
    let (value, value_error) = decimal.parse(text)
    if value_error != ok { os.exit(99i32) }
    ret value
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (db, db_error) = locale.builtin(a)
    if db_error != ok || !same(locale.version(&db), "47") { os.exit(1i32) }

    // Tags: canonical form, fallback to the parent, refusals.
    let (canon, canon_error) = locale.canonical_tag(a, "EN_us")
    let (script, script_error) = locale.canonical_tag(a, "zh_hant_tw")
    if canon_error != ok || script_error != ok || !same(canon, "en-US") || !same(script, "zh-Hant-TW") { os.exit(2i32) }
    let (_, empty_error) = locale.canonical_tag(a, "")
    let (_, digit_error) = locale.canonical_tag(a, "1en")
    let (_, junk_error) = locale.canonical_tag(a, "en-U$")
    if empty_error != locale.Invalid || digit_error != locale.Invalid || junk_error != locale.Invalid { os.exit(3i32) }
    let (en, en_error) = locale.locale(&db, "en_US")
    let (gb, gb_error) = locale.locale(&db, "en-GB")
    let (de, de_error) = locale.locale(&db, "de-DE")
    let (fr, fr_error) = locale.locale(&db, "fr")
    let (es, es_error) = locale.locale(&db, "es")
    let (ja, ja_error) = locale.locale(&db, "ja-JP")
    let (tr, tr_error) = locale.locale(&db, "tr")
    if en_error != ok || gb_error != ok || de_error != ok || fr_error != ok || es_error != ok || ja_error != ok || tr_error != ok { os.exit(4i32) }
    let (_, missing) = locale.locale(&db, "xx")
    let (_, bad_tag) = locale.locale(&db, "-")
    if missing != locale.NotFound || bad_tag != locale.Invalid { os.exit(5i32) }

    // Integers: grouping, signs, minimum fraction, Spanish minimum grouping.
    let (big, big_error) = locale.format_i64(a, en, 1234567i64, plain(0u8))
    let (neg, neg_error) = locale.format_i64(a, de, -1234567i64, plain(0u8))
    let (signed, signed_error) = locale.format_i64(a, en, 42i64, locale.NumberOptions { minimum_fraction: 2u8, maximum_fraction: 2u8, grouping: true, sign_always: true })
    let (bare, bare_error) = locale.format_i64(a, en, 1234567i64, locale.NumberOptions { minimum_fraction: 0u8, maximum_fraction: 0u8, grouping: false, sign_always: false })
    if big_error != ok || neg_error != ok || signed_error != ok || bare_error != ok { os.exit(6i32) }
    if !same(big, "1,234,567") || !same(neg, "-1.234.567") || !same(signed, "+42.00") || !same(bare, "1234567") { os.exit(7i32) }
    let (four, four_error) = locale.format_i64(a, es, 1234i64, plain(0u8))
    let (five, five_error) = locale.format_i64(a, es, 12345i64, plain(0u8))
    let (thin, thin_error) = locale.format_i64(a, fr, 1234567i64, plain(0u8))
    if four_error != ok || five_error != ok || thin_error != ok || !same(four, "1234") || !same(five, "12.345") || !same(thin, "1\xe2\x80\xaf234\xe2\x80\xaf567") { os.exit(8i32) }

    // Floats: rounding, trimming to the minimum, the locale's separators, the ceiling.
    let (half, half_error) = locale.format_f64(a, en, 1234.5, plain(2u8))
    let (trimmed, trimmed_error) = locale.format_f64(a, de, 1234.5, locale.NumberOptions { minimum_fraction: 0u8, maximum_fraction: 3u8, grouping: true, sign_always: false })
    let (rounded, rounded_error) = locale.format_f64(a, en, 2.675, plain(2u8))
    let (tiny, tiny_error) = locale.format_f64(a, en, -0.001, plain(2u8))
    if half_error != ok || trimmed_error != ok || rounded_error != ok || tiny_error != ok { os.exit(9i32) }
    if !same(half, "1,234.50") || !same(trimmed, "1.234,5") || !same(rounded, "2.68") || !same(tiny, "0.00") { os.exit(10i32) }
    let (_, huge_error) = locale.format_f64(a, en, 1.0e19, plain(2u8))
    let (_, nan_error) = locale.format_f64(a, en, 0.0 / 0.0, plain(2u8))
    if huge_error != locale.Invalid || nan_error != locale.Invalid { os.exit(11i32) }

    // Parsing: separators of the locale, a bare minus, refusals.
    let (parsed_de, parsed_de_error) = locale.parse_f64(de, "1.234,5")
    let (parsed_en, parsed_en_error) = locale.parse_f64(en, "-1,234.25")
    let (parsed_plain, parsed_plain_error) = locale.parse_f64(fr, "42")
    if parsed_de_error != ok || parsed_en_error != ok || parsed_plain_error != ok || parsed_de != 1234.5 || parsed_en != -1234.25 || parsed_plain != 42.0 { os.exit(12i32) }
    let (_, wrong_sep) = locale.parse_f64(en, "1.234,5")
    let (_, trailing) = locale.parse_f64(en, "12x")
    let (_, nothing) = locale.parse_f64(en, "")
    if wrong_sep != locale.Invalid || trailing != locale.Invalid || nothing != locale.Invalid { os.exit(13i32) }

    // Currency: symbol placement, accounting negatives, minor units, unknown codes.
    let (usd, usd_error) = locale.format_currency(a, en, money("1234.56"), locale.CurrencyOptions { code: "USD", accounting: false })
    let (usd_neg, usd_neg_error) = locale.format_currency(a, en, money("-1234.56"), locale.CurrencyOptions { code: "USD", accounting: true })
    let (usd_minus, usd_minus_error) = locale.format_currency(a, en, money("-1234.56"), locale.CurrencyOptions { code: "USD", accounting: false })
    if usd_error != ok || usd_neg_error != ok || usd_minus_error != ok { os.exit(14i32) }
    if !same(usd, "$1,234.56") || !same(usd_neg, "($1,234.56)") || !same(usd_minus, "-$1,234.56") { os.exit(15i32) }
    let (eur, eur_error) = locale.format_currency(a, de, money("1234.5"), locale.CurrencyOptions { code: "EUR", accounting: false })
    let (yen, yen_error) = locale.format_currency(a, ja, money("1234.5"), locale.CurrencyOptions { code: "JPY", accounting: false })
    let (dinar, dinar_error) = locale.format_currency(a, en, money("1.2345"), locale.CurrencyOptions { code: "KWD", accounting: false })
    let (unknown, unknown_error) = locale.format_currency(a, en, money("7"), locale.CurrencyOptions { code: "XYZ", accounting: false })
    let (unknown_de, unknown_de_error) = locale.format_currency(a, de, money("7"), locale.CurrencyOptions { code: "XYZ", accounting: false })
    if eur_error != ok || yen_error != ok || dinar_error != ok || unknown_error != ok || unknown_de_error != ok { os.exit(16i32) }
    if !same(eur, "1.234,50\xc2\xa0€") || !same(yen, "￥1,235") || !same(dinar, "KWD\xc2\xa01.235") || !same(unknown, "XYZ\xc2\xa07.00") || !same(unknown_de, "7,00\xc2\xa0XYZ") { os.exit(17i32) }
    let (_, code_error) = locale.format_currency(a, en, money("1"), locale.CurrencyOptions { code: "us", accounting: false })
    if code_error != locale.Invalid { os.exit(18i32) }

    // Dates: the four styles in four locales.
    let moment = stamp()
    let (en_short, e1) = locale.format_date(a, en, moment, .Short)
    let (en_medium, e2) = locale.format_date(a, en, moment, .Medium)
    let (en_long, e3) = locale.format_date(a, en, moment, .Long)
    let (en_full, e4) = locale.format_date(a, en, moment, .Full)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(19i32) }
    if !same(en_short, "9/20/26, 3:46 PM") || !same(en_medium, "Sep 20, 2026, 3:46:05 PM") || !same(en_long, "September 20, 2026 at 3:46:05 PM") || !same(en_full, "Sunday, September 20, 2026 at 3:46:05 PM") { os.exit(20i32) }
    let (de_short, e5) = locale.format_date(a, de, moment, .Short)
    let (de_full, e6) = locale.format_date(a, de, moment, .Full)
    let (fr_long, e7) = locale.format_date(a, fr, moment, .Long)
    let (ja_full, e8) = locale.format_date(a, ja, moment, .Full)
    let (gb_medium, e9) = locale.format_date(a, gb, moment, .Medium)
    if e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { os.exit(21i32) }
    if !same(de_short, "20.09.26, 15:46") || !same(de_full, "Sonntag, 20. September 2026 um 15:46:05") || !same(fr_long, "20 septembre 2026 à 15:46:05") || !same(ja_full, "2026年9月20日日曜日 15:46:05") || !same(gb_medium, "20 Sep 2026, 15:46:05") { os.exit(22i32) }
    var broken = moment
    broken.date.month = 13u8
    let (_, month_error) = locale.format_date(a, en, broken, .Short)
    if month_error != locale.Invalid { os.exit(23i32) }

    // Comparison and case.
    if locale.compare(en, "apple", "Banana") >= 0i32 || locale.compare(en, "file10", "file9") <= 0i32 || locale.compare(en, "same", "same") != 0i32 || locale.compare(en, "a", "A") == 0i32 { os.exit(24i32) }
    let (low_tr, low_tr_error) = locale.lower(a, tr, "DİYARBAKIR")
    let (up_tr, up_tr_error) = locale.upper(a, tr, "istanbul")
    let (low_en, low_en_error) = locale.lower(a, en, "İSTANBUL")
    let (up_de, up_de_error) = locale.upper(a, de, "straße")
    if low_tr_error != ok || up_tr_error != ok || low_en_error != ok || up_de_error != ok { os.exit(25i32) }
    if !same(low_tr, "diyarbakır") || !same(up_tr, "İSTANBUL") || !same(low_en, "istanbul") || !same(up_de, "STRASSE") { os.exit(26i32) }

    // A loaded database overrides what it names and takes the rest from CLDR root.
    let (custom, custom_error) = locale.load(a, "version 9\nlocale xx\ndecimal ;\ngroup '\nmonths one two three four five six seven eight nine ten eleven twelve\n")
    if custom_error != ok || !same(locale.version(&custom), "9") { os.exit(27i32) }
    let (xx, xx_error) = locale.locale(&custom, "xx-YY")
    let (xx_number, xx_number_error) = locale.format_f64(a, xx, 1234.5, plain(1u8))
    let (xx_date, xx_date_error) = locale.format_date(a, xx, moment, .Long)
    if xx_error != ok || xx_number_error != ok || xx_date_error != ok || !same(xx_number, "1'234;5") || !same(xx_date, "2026 nine 20 15:46:05") { os.exit(28i32) }
    let (_, no_version) = locale.load(a, "locale xx\ndecimal ,\n")
    let (_, no_tag) = locale.load(a, "version 1\ndecimal ,\n")
    if no_version != locale.InvalidData || no_tag != locale.InvalidData { os.exit(29i32) }

    try io.print("text locale ok\n")
    ret ok
}
