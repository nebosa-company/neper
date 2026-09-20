// Locale-aware numbers, currency, dates, comparison and case, over a small database in
// CLDR's terms. `builtin` carries a subset of CLDR 47 for en, en-GB, de, fr, es, it, pt,
// ja and tr; `load` takes the same text format, one `locale <tag>` block per locale, so a
// program can ship its own data. `version` names the CLDR release the data was taken
// from. A tag resolves through its parents (`en-US` to `en`) and `NotFound` past them;
// `canonical_tag` fixes case and separators (`EN_us` becomes `en-US`) and refuses a tag
// that is not BCP 47 shaped. No process-global locale exists: every call is given one.
//
// Numbers are built from integers: `format_i64` groups and signs; `format_f64` rounds
// half away from zero at `maximum_fraction` places and trims to `minimum_fraction`;
// `parse_f64` takes the locale's separators (grouping ignored) and consumes the whole
// input. ponytail: `format_f64` scales through an i64, so a magnitude past about 9e18
// divided by 10^maximum_fraction is `Invalid`; a shortest-representation printer
// belongs in `e.str`, not here. `format_currency` quantises the decimal to the
// currency's minor units (2, or 0 and 3 for the ISO 4217 exceptions) half away from
// zero, then lays the symbol out as the locale's pattern says, a code the locale has no
// symbol for standing in as itself with a no-break space. Dates take LDML patterns
// (`y yy M MM MMM MMMM d dd EEE EEEE h hh H HH mm ss a`, quoted text) for the four styles
// and the locale's glue between date and time.
//
// `compare` is a case-insensitive natural order with the code-point order breaking ties
// (ponytail: no accent-level tailoring; UCA belongs beside `e.text.collate`). `lower`
// and `upper` are Unicode's simple mappings, with the Turkish and Azeri dotted and
// dotless i and the full `ß` to `SS`.

use e.algo.decimal
use e.mem
use e.time.calendar
use e.text.collate
use e.text.unicode

type Database = struct { state: *void }
type Locale = struct { state: *const void }
type NumberOptions = struct { minimum_fraction: u8, maximum_fraction: u8, grouping: bool, sign_always: bool }
type CurrencyOptions = struct { code: str, accounting: bool }
type DateStyle = enum u8 { Short, Medium, Long, Full }
error InvalidData
error NotFound
error Invalid

const MAX_LOCALES: usize = 64usize
const BUF: usize = 256usize

type Record = struct {
    tag: str,
    decimal: str,
    group: str,
    minus: str,
    plus: str,
    grouping: u8,
    min_grouping: u8,
    currency: str,
    accounting: str,
    symbols: str,
    months: str,
    months_short: str,
    days: str,
    days_short: str,
    date_short: str,
    date_medium: str,
    date_long: str,
    date_full: str,
    time_short: str,
    time_long: str,
    glue_short: str,
    glue_long: str,
    am: str,
    pm: str,
    turkic: bool,
}

type Db = struct { version: str, records: []Record, count: usize }

// One `locale` block per line group. `n` stands for the number in the currency patterns,
// `¤` for the symbol; `{1}` and `{0}` are the date and the time in the glue; `parent`
// copies an earlier block before the overrides.
fn builtin_data() -> str {
    ret "version 47\nlocale en\ndecimal .\ngroup ,\nminus -\nplus +\ngrouping 3\nmin_grouping 1\ncurrency ¤n\naccounting (¤n)\nsymbols USD $ EUR € GBP £ JPY ¥ CAD CA$ AUD A$ INR ₹ CNY CN¥ KRW ₩ TRY TRY\nmonths January February March April May June July August September October November December\nmonths_short Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec\ndays Sunday Monday Tuesday Wednesday Thursday Friday Saturday\ndays_short Sun Mon Tue Wed Thu Fri Sat\ndate_short M/d/yy\ndate_medium MMM d, y\ndate_long MMMM d, y\ndate_full EEEE, MMMM d, y\ntime_short h:mm a\ntime_long h:mm:ss a\nglue_short {1}, {0}\nglue_long {1} 'at' {0}\nam AM\npm PM\nlocale en-GB\nparent en\nsymbols GBP £ USD US$ EUR € JPY JP¥\ndate_short dd/MM/y\ndate_medium d MMM y\ndate_long d MMMM y\ndate_full EEEE, d MMMM y\ntime_short HH:mm\ntime_long HH:mm:ss\nam am\npm pm\nlocale de\ndecimal ,\ngroup .\ncurrency n\xc2\xa0¤\naccounting n\xc2\xa0¤\nsymbols EUR € USD $ GBP £ JPY ¥ CHF CHF\nmonths Januar Februar März April Mai Juni Juli August September Oktober November Dezember\nmonths_short Jan. Feb. März Apr. Mai Juni Juli Aug. Sept. Okt. Nov. Dez.\ndays Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag\ndays_short So. Mo. Di. Mi. Do. Fr. Sa.\ndate_short dd.MM.yy\ndate_medium dd.MM.y\ndate_long d. MMMM y\ndate_full EEEE, d. MMMM y\ntime_short HH:mm\ntime_long HH:mm:ss\nglue_short {1}, {0}\nglue_long {1} 'um' {0}\nlocale fr\ndecimal ,\ngroup \xe2\x80\xaf\ncurrency n\xc2\xa0¤\naccounting (n\xc2\xa0¤)\nsymbols EUR € USD $US GBP £GB JPY JPY CHF CHF\nmonths janvier février mars avril mai juin juillet août septembre octobre novembre décembre\nmonths_short janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.\ndays dimanche lundi mardi mercredi jeudi vendredi samedi\ndays_short dim. lun. mar. mer. jeu. ven. sam.\ndate_short dd/MM/y\ndate_medium d MMM y\ndate_long d MMMM y\ndate_full EEEE d MMMM y\ntime_short HH:mm\ntime_long HH:mm:ss\nglue_short {1} {0}\nglue_long {1} 'à' {0}\nlocale es\ndecimal ,\ngroup .\nmin_grouping 2\ncurrency n\xc2\xa0¤\naccounting n\xc2\xa0¤\nsymbols EUR € USD US$ GBP £ JPY JPY MXN MXN\nmonths enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre\nmonths_short ene feb mar abr may jun jul ago sept oct nov dic\ndays domingo lunes martes miércoles jueves viernes sábado\ndays_short dom lun mar mié jue vie sáb\ndate_short d/M/yy\ndate_medium d MMM y\ndate_long d 'de' MMMM 'de' y\ndate_full EEEE, d 'de' MMMM 'de' y\ntime_short H:mm\ntime_long H:mm:ss\nglue_short {1}, {0}\nglue_long {1}, {0}\nlocale it\ndecimal ,\ngroup .\ncurrency n\xc2\xa0¤\naccounting n\xc2\xa0¤\nsymbols EUR € USD USD GBP £ JPY JPY\nmonths gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre\nmonths_short gen feb mar apr mag giu lug ago set ott nov dic\ndays domenica lunedì martedì mercoledì giovedì venerdì sabato\ndays_short dom lun mar mer gio ven sab\ndate_short dd/MM/yy\ndate_medium d MMM y\ndate_long d MMMM y\ndate_full EEEE d MMMM y\ntime_short HH:mm\ntime_long HH:mm:ss\nglue_short {1}, {0}\nglue_long {1} 'alle' 'ore' {0}\nlocale pt\ndecimal ,\ngroup .\ncurrency ¤\xc2\xa0n\naccounting ¤\xc2\xa0n\nsymbols BRL R$ EUR € USD US$ GBP £ JPY JP¥\nmonths janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro\nmonths_short jan. fev. mar. abr. mai. jun. jul. ago. set. out. nov. dez.\ndays domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado\ndays_short dom. seg. ter. qua. qui. sex. sáb.\ndate_short dd/MM/y\ndate_medium d 'de' MMM 'de' y\ndate_long d 'de' MMMM 'de' y\ndate_full EEEE, d 'de' MMMM 'de' y\ntime_short HH:mm\ntime_long HH:mm:ss\nglue_short {1}, {0}\nglue_long {1} 'às' {0}\nlocale ja\ncurrency ¤n\naccounting (¤n)\nsymbols JPY ￥ USD $ EUR € GBP £ CNY 元 KRW ₩\nmonths 1月 2月 3月 4月 5月 6月 7月 8月 9月 10月 11月 12月\nmonths_short 1月 2月 3月 4月 5月 6月 7月 8月 9月 10月 11月 12月\ndays 日曜日 月曜日 火曜日 水曜日 木曜日 金曜日 土曜日\ndays_short 日 月 火 水 木 金 土\ndate_short y/MM/dd\ndate_medium y/MM/dd\ndate_long y年M月d日\ndate_full y年M月d日EEEE\ntime_short H:mm\ntime_long H:mm:ss\nglue_short {1} {0}\nglue_long {1} {0}\nlocale tr\ndecimal ,\ngroup .\ncurrency ¤n\naccounting (¤n)\nsymbols TRY ₺ EUR € USD $ GBP £ JPY ¥\nmonths Ocak Şubat Mart Nisan Mayıs Haziran Temmuz Ağustos Eylül Ekim Kasım Aralık\nmonths_short Oca Şub Mar Nis May Haz Tem Ağu Eyl Eki Kas Ara\ndays Pazar Pazartesi Salı Çarşamba Perşembe Cuma Cumartesi\ndays_short Paz Pzt Sal Çar Per Cum Cmt\ndate_short d.MM.y\ndate_medium d MMM y\ndate_long d MMMM y\ndate_full d MMMM y EEEE\ntime_short HH:mm\ntime_long HH:mm:ss\nglue_short {1} {0}\nglue_long {1} {0}\nturkic 1\n"
}

fn same(a: str, b: str) -> bool {
    ret mem.eq[u8](a, b)
}

// The defaults every block starts from: CLDR's root, whose numbers are `en`'s and whose
// date patterns are ISO-like; a block overrides what it names.
fn root() -> Record {
    ret Record {
        tag: "root", decimal: ".", group: ",", minus: "-", plus: "+", grouping: 3u8, min_grouping: 1u8,
        currency: "¤n", accounting: "(¤n)", symbols: "",
        months: "M01 M02 M03 M04 M05 M06 M07 M08 M09 M10 M11 M12", months_short: "M01 M02 M03 M04 M05 M06 M07 M08 M09 M10 M11 M12",
        days: "Sun Mon Tue Wed Thu Fri Sat", days_short: "Sun Mon Tue Wed Thu Fri Sat",
        date_short: "y-MM-dd", date_medium: "y MMM d", date_long: "y MMMM d", date_full: "y MMMM d, EEEE",
        time_short: "HH:mm", time_long: "HH:mm:ss", glue_short: "{1} {0}", glue_long: "{1} {0}", am: "AM", pm: "PM", turkic: false,
    }
}

fn apply(a: *mem.Arena, r: *Record, key: str, raw: str) -> err {
    let unused = a
    let value = raw
    if same(key, "decimal") { r.decimal = value }
    if same(key, "group") { r.group = value }
    if same(key, "minus") { r.minus = value }
    if same(key, "plus") { r.plus = value }
    if same(key, "grouping") { r.grouping = u8(value[0] - 48u8) }
    if same(key, "min_grouping") { r.min_grouping = u8(value[0] - 48u8) }
    if same(key, "currency") { r.currency = value }
    if same(key, "accounting") { r.accounting = value }
    if same(key, "symbols") { r.symbols = value }
    if same(key, "months") { r.months = value }
    if same(key, "months_short") { r.months_short = value }
    if same(key, "days") { r.days = value }
    if same(key, "days_short") { r.days_short = value }
    if same(key, "date_short") { r.date_short = value }
    if same(key, "date_medium") { r.date_medium = value }
    if same(key, "date_long") { r.date_long = value }
    if same(key, "date_full") { r.date_full = value }
    if same(key, "time_short") { r.time_short = value }
    if same(key, "time_long") { r.time_long = value }
    if same(key, "glue_short") { r.glue_short = value }
    if same(key, "glue_long") { r.glue_long = value }
    if same(key, "am") { r.am = value }
    if same(key, "pm") { r.pm = value }
    if same(key, "turkic") { r.turkic = value[0] == 49u8 }
    ret ok
}

fn load(a: *mem.Arena, source: []const u8) -> (Database, err) {
    let (dbs, db_error) = mem.alloc[Db](a, 1usize)
    if db_error != ok { ret (zero, db_error) }
    let (records, records_error) = mem.alloc[Record](a, MAX_LOCALES)
    if records_error != ok { ret (zero, records_error) }
    var count = 0usize
    var release = ""
    var at = 0usize
    while at < source.len {
        var stop = at
        while stop < source.len && source[stop] != 10u8 { stop += 1usize }
        var line = source[at..stop]
        if line.len > 0usize && line[line.len - 1usize] == 13u8 { line = line[..line.len - 1usize] }
        at = stop + 1usize
        if line.len == 0usize { continue }
        var space = 0usize
        while space < line.len && line[space] != 32u8 { space += 1usize }
        let key = line[..space]
        var value = ""
        if space < line.len { value = line[space + 1usize..] }
        if same(key, "version") {
            release = value
            continue
        }
        if same(key, "locale") {
            if value.len == 0usize || count >= MAX_LOCALES { ret (zero, InvalidData) }
            records[count] = root()
            records[count].tag = value
            records[count].symbols = ""
            count += 1usize
            continue
        }
        if count == 0usize { ret (zero, InvalidData) }
        if same(key, "parent") {
            var found = false
            var i = 0usize
            while i + 1usize < count {
                if same(records[i].tag, value) {
                    let own = records[count - 1usize].tag
                    records[count - 1usize] = records[i]
                    records[count - 1usize].tag = own
                    found = true
                }
                i += 1usize
            }
            if !found { ret (zero, InvalidData) }
            continue
        }
        let apply_error = apply(a, &records[count - 1usize], key, value)
        if apply_error != ok { ret (zero, apply_error) }
    }
    if release.len == 0usize { ret (zero, InvalidData) }
    dbs[0usize] = Db { version: release, records: records, count: count }
    ret (Database { state: mem.cast[*void](&dbs[0usize]) }, ok)
}

fn builtin(a: *mem.Arena) -> (Database, err) {
    let (db, db_error) = load(a, builtin_data())
    ret (db, db_error)
}

fn version(db: *const Database) -> str {
    let d = mem.cast[*Db](db.state)
    ret d.version
}

fn is_alnum(b: u8) -> bool {
    ret (b >= 48u8 && b <= 57u8) || (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8)
}

fn is_digit(b: u8) -> bool {
    ret b >= 48u8 && b <= 57u8
}

// BCP 47 case: language lower, a four-letter script titled, a region upper, `-` between.
fn canonical_tag(a: *mem.Arena, tag: str) -> (str, err) {
    if tag.len == 0usize || tag.len > 64usize { ret ("", Invalid) }
    let (out, out_error) = mem.alloc[u8](a, tag.len)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    var index = 0usize
    while at <= tag.len {
        var stop = at
        while stop < tag.len && tag[stop] != 45u8 && tag[stop] != 95u8 { stop += 1usize }
        let part = tag[at..stop]
        if part.len == 0usize || part.len > 8usize { ret ("", Invalid) }
        var i = 0usize
        while i < part.len {
            if !is_alnum(part[i]) { ret ("", Invalid) }
            i += 1usize
        }
        if index == 0usize && (is_digit(part[0]) || part.len == 1usize) { ret ("", Invalid) }
        let script = index > 0usize && part.len == 4usize && !is_digit(part[0])
        let region = index > 0usize && ((part.len == 2usize && !is_digit(part[0])) || (part.len == 3usize && is_digit(part[0])))
        i = 0usize
        while i < part.len {
            var b = part[i]
            if b >= 65u8 && b <= 90u8 { b = b + 32u8 }
            if (region || (script && i == 0usize)) && b >= 97u8 && b <= 122u8 { b = b - 32u8 }
            out[at + i] = b
            i += 1usize
        }
        if stop < tag.len { out[stop] = 45u8 }
        at = stop + 1usize
        index += 1usize
    }
    ret (out[..tag.len], ok)
}

fn locale(db: *const Database, tag: str) -> (Locale, err) {
    let d = mem.cast[*Db](db.state)
    var buf: [64]u8 = zero
    var arena = mem.arena_from(buf[0..])
    let (canonical, canonical_error) = canonical_tag(&arena, tag)
    if canonical_error != ok { ret (zero, canonical_error) }
    var want = canonical
    while want.len > 0usize {
        var i = 0usize
        while i < d.count {
            if same(d.records[i].tag, want) { ret (Locale { state: mem.cast[*const void](&d.records[i]) }, ok) }
            i += 1usize
        }
        var cut = want.len
        while cut > 0usize && want[cut - 1usize] != 45u8 { cut -= 1usize }
        if cut == 0usize { break }
        want = want[..cut - 1usize]
    }
    ret (zero, NotFound)
}

fn record(selected_locale: Locale) -> *const Record {
    ret mem.cast[*const Record](selected_locale.state)
}

// A byte sink over a fixed buffer, copied to the arena once the text is complete.
type Sink = struct { bytes: [512]u8, len: usize, overflow: bool }

fn put(s: *Sink, text: str) {
    if s.len + text.len > 512usize {
        s.overflow = true
        ret
    }
    mem.copy[u8](s.bytes[s.len..s.len + text.len], text)
    s.len += text.len
}

fn put_byte(s: *Sink, b: u8) {
    if s.len >= 512usize {
        s.overflow = true
        ret
    }
    s.bytes[s.len] = b
    s.len += 1usize
}

fn finish(a: *mem.Arena, s: *Sink) -> (str, err) {
    if s.overflow { ret ("", Invalid) }
    let (out, out_error) = mem.alloc[u8](a, s.len)
    if out_error != ok { ret ("", out_error) }
    mem.copy[u8](out, s.bytes[..s.len])
    ret (out, ok)
}

// The digits of `magnitude`, grouped as the locale says, then the fraction digits.
fn put_number(s: *Sink, r: *const Record, magnitude: u64, fraction: u64, fraction_digits: usize, grouping: bool) {
    var digits: [24]u8 = zero
    var count = 0usize
    var rest = magnitude
    while rest > 0u64 || count == 0usize {
        digits[count] = u8(rest % 10u64) + 48u8
        rest = rest / 10u64
        count += 1usize
    }
    let grouped = grouping && r.grouping > 0u8 && count >= usize(r.grouping) + usize(r.min_grouping)
    var i = count
    while i > 0usize {
        i -= 1usize
        put_byte(s, digits[i])
        if grouped && i > 0usize && i % usize(r.grouping) == 0usize { put(s, r.group) }
    }
    if fraction_digits > 0usize {
        put(s, r.decimal)
        var scale = 1u64
        var k = 1usize
        while k < fraction_digits {
            scale *= 10u64
            k += 1usize
        }
        var f = fraction
        while scale > 0u64 {
            put_byte(s, u8(f / scale) + 48u8)
            f = f % scale
            scale = scale / 10u64
        }
    }
}

fn put_sign(s: *Sink, r: *const Record, negative: bool, always: bool) {
    if negative {
        put(s, r.minus)
    } else if always {
        put(s, r.plus)
    }
}

fn format_i64(a: *mem.Arena, selected_locale: Locale, value: i64, options: NumberOptions) -> (str, err) {
    let r = record(selected_locale)
    var s: Sink = zero
    var magnitude = 0u64
    if value < 0i64 {
        magnitude = 0u64 -% mem.bitcast[u64](value)
    } else {
        magnitude = u64(value)
    }
    put_sign(&s, r, value < 0i64, options.sign_always)
    var fraction_digits = usize(options.minimum_fraction)
    put_number(&s, r, magnitude, 0u64, fraction_digits, options.grouping)
    let (out, out_error) = finish(a, &s)
    ret (out, out_error)
}

fn pow10(n: usize) -> u64 {
    var p = 1u64
    var i = 0usize
    while i < n {
        p *= 10u64
        i += 1usize
    }
    ret p
}

fn format_f64(a: *mem.Arena, selected_locale: Locale, value: f64, options: NumberOptions) -> (str, err) {
    let r = record(selected_locale)
    if value != value || options.maximum_fraction > 18u8 || options.minimum_fraction > options.maximum_fraction { ret ("", Invalid) }
    let negative = value < 0.0
    var magnitude: f64 = value
    if negative { magnitude = 0.0 - value }
    let scale = pow10(usize(options.maximum_fraction))
    let scaled = magnitude * f64(scale) + 0.5
    if scaled >= 9.2e18 { ret ("", Invalid) }
    var units = u64(scaled)
    var fraction_digits = usize(options.maximum_fraction)
    while fraction_digits > usize(options.minimum_fraction) && units % 10u64 == 0u64 {
        units = units / 10u64
        fraction_digits -= 1usize
    }
    let divisor = pow10(fraction_digits)
    var s: Sink = zero
    put_sign(&s, r, negative && units != 0u64, options.sign_always)
    put_number(&s, r, units / divisor, units % divisor, fraction_digits, options.grouping)
    let (out, out_error) = finish(a, &s)
    ret (out, out_error)
}

fn starts_at(text: str, at: usize, piece: str) -> bool {
    if piece.len == 0usize || at + piece.len > text.len { ret false }
    ret same(text[at..at + piece.len], piece)
}

fn parse_f64(selected_locale: Locale, value: str) -> (f64, err) {
    let r = record(selected_locale)
    var at = 0usize
    var negative = false
    if starts_at(value, at, r.minus) {
        negative = true
        at += r.minus.len
    } else if starts_at(value, at, "-") {
        negative = true
        at += 1usize
    } else if starts_at(value, at, r.plus) {
        at += r.plus.len
    }
    var whole: f64 = 0.0
    var digits = 0usize
    var fraction_scale: f64 = 1.0
    var in_fraction = false
    while at < value.len {
        let b = value[at]
        if is_digit(b) {
            if in_fraction {
                fraction_scale = fraction_scale * 10.0
                whole = whole + f64(b - 48u8) / fraction_scale
            } else {
                whole = whole * 10.0 + f64(b - 48u8)
            }
            digits += 1usize
            at += 1usize
            continue
        }
        if !in_fraction && starts_at(value, at, r.decimal) {
            in_fraction = true
            at += r.decimal.len
            continue
        }
        if !in_fraction && digits > 0usize && starts_at(value, at, r.group) {
            at += r.group.len
            continue
        }
        ret (0.0, Invalid)
    }
    if digits == 0usize { ret (0.0, Invalid) }
    if negative { whole = 0.0 - whole }
    ret (whole, ok)
}

fn currency_digits(code: str) -> u8 {
    if same(code, "JPY") || same(code, "KRW") || same(code, "VND") || same(code, "CLP") || same(code, "ISK") || same(code, "HUF") { ret 0u8 }
    if same(code, "BHD") || same(code, "KWD") || same(code, "JOD") || same(code, "OMR") || same(code, "TND") || same(code, "IQD") { ret 3u8 }
    ret 2u8
}

// The locale's symbol for a code, from its `symbols` line of code/symbol pairs.
fn currency_symbol(r: *const Record, code: str) -> (str, bool) {
    let line = r.symbols
    var at = 0usize
    while at < line.len {
        var stop = at
        while stop < line.len && line[stop] != 32u8 { stop += 1usize }
        let key = line[at..stop]
        if stop >= line.len { break }
        var value_end = stop + 1usize
        while value_end < line.len && line[value_end] != 32u8 { value_end += 1usize }
        if same(key, code) { ret (line[stop + 1usize..value_end], true) }
        at = value_end + 1usize
    }
    ret (code, false)
}

fn is_letter(b: u8) -> bool {
    ret (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8)
}

fn format_currency(a: *mem.Arena, selected_locale: Locale, value: decimal.Decimal, options: CurrencyOptions) -> (str, err) {
    let r = record(selected_locale)
    if options.code.len != 3usize || !is_letter(options.code[0]) || !is_letter(options.code[1]) || !is_letter(options.code[2]) { ret ("", Invalid) }
    let digits = currency_digits(options.code)
    let (minor, quantize_error) = decimal.quantize(value, digits, .AwayFromZero)
    if quantize_error != ok { ret ("", Invalid) }
    let c = minor.coefficient
    var negative = false
    var magnitude = 0u64
    if c.high == 0i64 && c.low <= 9223372036854775807u64 {
        magnitude = c.low
    } else if c.high == -1i64 && c.low >= 9223372036854775808u64 {
        negative = true
        magnitude = 0u64 -% c.low
    } else {
        ret ("", Invalid)
    }
    let (symbol, known) = currency_symbol(r, options.code)
    var pattern = r.currency
    if options.accounting { pattern = r.accounting }
    var s: Sink = zero
    let parenthesised = negative && options.accounting && pattern.len > 0usize && pattern[0] == 40u8
    if negative && !parenthesised { put(&s, r.minus) }
    var at = 0usize
    while at < pattern.len {
        let b = pattern[at]
        if b == 40u8 || b == 41u8 {
            if parenthesised { put_byte(&s, b) }
            at += 1usize
            continue
        }
        if b == 110u8 {
            let scale = pow10(usize(digits))
            put_number(&s, r, magnitude / scale, magnitude % scale, usize(digits), true)
            at += 1usize
            continue
        }
        if starts_at(pattern, at, "¤") {
            // A code stands as itself, held off the digits by a no-break space.
            let symbol_first = at + 2usize < pattern.len
            let spaced_before = s.len > 0usize && s.bytes[s.len - 1usize] == 160u8
            let spaced_after = at + 3usize < pattern.len && pattern[at + 2usize] == 194u8
            if !known && !symbol_first && !spaced_before { put(&s, "\xc2\xa0") }
            put(&s, symbol)
            if !known && symbol_first && !spaced_after { put(&s, "\xc2\xa0") }
            at += 2usize
            continue
        }
        put_byte(&s, b)
        at += 1usize
    }
    let (out, out_error) = finish(a, &s)
    ret (out, out_error)
}

// The `index`th space-separated word of a name list.
fn word(list: str, index: usize) -> str {
    var at = 0usize
    var seen = 0usize
    while at < list.len {
        var stop = at
        while stop < list.len && list[stop] != 32u8 { stop += 1usize }
        if seen == index { ret list[at..stop] }
        seen += 1usize
        at = stop + 1usize
    }
    ret ""
}

fn put_padded(s: *Sink, value: u32, width: usize) {
    var digits: [12]u8 = zero
    var count = 0usize
    var rest = value
    while rest > 0u32 || count == 0usize {
        digits[count] = u8(rest % 10u32) + 48u8
        rest = rest / 10u32
        count += 1usize
    }
    while count < width {
        digits[count] = 48u8
        count += 1usize
    }
    while count > 0usize {
        count -= 1usize
        put_byte(s, digits[count])
    }
}

fn put_pattern(s: *Sink, r: *const Record, pattern: str, value: calendar.DateTime) {
    let (day, day_error) = calendar.weekday(value.date)
    var weekday_index = 0usize
    if day_error == ok { weekday_index = usize((calendar.weekday_index(day) + 1i64) % 7i64) }
    var at = 0usize
    while at < pattern.len {
        let b = pattern[at]
        if b == 39u8 {
            at += 1usize
            while at < pattern.len && pattern[at] != 39u8 {
                put_byte(s, pattern[at])
                at += 1usize
            }
            at += 1usize
            continue
        }
        if !is_letter(b) {
            put_byte(s, b)
            at += 1usize
            continue
        }
        var run = 1usize
        while at + run < pattern.len && pattern[at + run] == b { run += 1usize }
        if b == 121u8 {
            var year = value.date.year
            if year < 0i32 { year = 0i32 - year }
            if run == 2usize { put_padded(s, u32(year % 100i32), 2usize) } else { put_padded(s, u32(year), 1usize) }
        } else if b == 77u8 {
            if run >= 4usize {
                put(s, word(r.months, usize(value.date.month) - 1usize))
            } else if run == 3usize {
                put(s, word(r.months_short, usize(value.date.month) - 1usize))
            } else {
                put_padded(s, u32(value.date.month), run)
            }
        } else if b == 100u8 {
            put_padded(s, u32(value.date.day), run)
        } else if b == 69u8 {
            if run >= 4usize { put(s, word(r.days, weekday_index)) } else { put(s, word(r.days_short, weekday_index)) }
        } else if b == 72u8 {
            put_padded(s, u32(value.time.hour), run)
        } else if b == 104u8 {
            var hour = u32(value.time.hour) % 12u32
            if hour == 0u32 { hour = 12u32 }
            put_padded(s, hour, run)
        } else if b == 109u8 {
            put_padded(s, u32(value.time.minute), run)
        } else if b == 115u8 {
            put_padded(s, u32(value.time.second), run)
        } else if b == 97u8 {
            if value.time.hour < 12u8 { put(s, r.am) } else { put(s, r.pm) }
        } else {
            put(s, pattern[at..at + run])
        }
        at += run
    }
}

fn format_date(a: *mem.Arena, selected_locale: Locale, value: calendar.DateTime, style: DateStyle) -> (str, err) {
    let r = record(selected_locale)
    if value.date.month < 1u8 || value.date.month > 12u8 || value.date.day < 1u8 || value.date.day > 31u8 || value.time.hour > 23u8 || value.time.minute > 59u8 || value.time.second > 60u8 { ret ("", Invalid) }
    var date_pattern = r.date_short
    var time_pattern = r.time_short
    var glue = r.glue_short
    if style == .Medium {
        date_pattern = r.date_medium
        time_pattern = r.time_long
    }
    if style == .Long {
        date_pattern = r.date_long
        time_pattern = r.time_long
        glue = r.glue_long
    }
    if style == .Full {
        date_pattern = r.date_full
        time_pattern = r.time_long
        glue = r.glue_long
    }
    var s: Sink = zero
    var at = 0usize
    while at < glue.len {
        if starts_at(glue, at, "{1}") {
            put_pattern(&s, r, date_pattern, value)
            at += 3usize
        } else if starts_at(glue, at, "{0}") {
            put_pattern(&s, r, time_pattern, value)
            at += 3usize
        } else if glue[at] == 39u8 {
            at += 1usize
            while at < glue.len && glue[at] != 39u8 {
                put_byte(&s, glue[at])
                at += 1usize
            }
            at += 1usize
        } else {
            put_byte(&s, glue[at])
            at += 1usize
        }
    }
    let (out, out_error) = finish(a, &s)
    ret (out, out_error)
}

fn compare(selected_locale: Locale, a: str, b: str) -> i32 {
    let unused = selected_locale
    let natural = collate.natural_cmp(a, b, collate.Options { case_sensitive: false, numeric: true })
    if natural != 0i32 { ret natural }
    ret collate.codepoint_cmp(a, b)
}

fn map_case(a: *mem.Arena, r: *const Record, value: str, to_upper: bool) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, value.len * 3usize + 4usize)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var at = 0usize
    while at < value.len {
        let (scalar, width) = unicode.read_utf8(value, at)
        at += width
        var mapped = scalar
        if to_upper {
            if scalar == 223u32 {
                out[used] = 83u8
                out[used + 1usize] = 83u8
                used += 2usize
                continue
            }
            if r.turkic && scalar == 105u32 {
                mapped = 304u32
            } else if scalar == 305u32 {
                mapped = 73u32
            } else {
                mapped = unicode.to_upper_simple(scalar)
            }
        } else {
            if r.turkic && scalar == 73u32 {
                mapped = 305u32
            } else if scalar == 304u32 {
                mapped = 105u32
            } else {
                mapped = unicode.to_lower_simple(scalar)
            }
        }
        used = unicode.write_utf8(mapped, out, used)
    }
    ret (out[..used], ok)
}

fn lower(a: *mem.Arena, selected_locale: Locale, value: str) -> (str, err) {
    let (out, out_error) = map_case(a, record(selected_locale), value, false)
    ret (out, out_error)
}

fn upper(a: *mem.Arena, selected_locale: Locale, value: str) -> (str, err) {
    let (out, out_error) = map_case(a, record(selected_locale), value, true)
    ret (out, out_error)
}
