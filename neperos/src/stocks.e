// Stocks (D2213, live data D2251): the app behind the Stocks icon -- a watchlist (ticker, name, a
// sparkline, the price and the day's change in green or red), a detail screen per ticker (the price, the
// change over the chosen range, a line chart with its area, range chips 1W / 1M / 2M, and the high, low,
// start and previous close, and Remove), an Add sheet and a Key sheet on the on-screen keyboard. Dark
// ground, cream rows and amber chips, like the other apps (appkit.e, ui.e, taps from the compositor, the
// five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// Data: the watchlist starts on SAMPLE data -- a seeded random walk of 60 days per ticker, said so on
// screen -- and Sync replaces a ticker's series with real daily closes: crypto from Coinbase Exchange's
// public candles (no key), stocks from Twelve Data's time_series with the API key typed in the Key sheet.
// Both go through the network server's socket capability (httpc.e); with no network, or on any error, the
// ticker keeps what it had and the status line says why. Daily closes, delayed, not real time; Yahoo's
// unofficial endpoints are left alone and Stooq's CSV now sits behind a bot check.
// The stock provider is chosen in the Key sheet: Twelve Data, Alpha Vantage (TIME_SERIES_DAILY) or Polygon
// (/v2/aggs), each with its own key; changing it clears the key. Finnhub is not offered: its free tier has
// no daily history. The Add sheet's Find lists stock symbols matching what was typed (Twelve Data's
// symbol_search, no key); crypto has no search, a pair is typed.
// ponytail: the key lives in this process only, so it is asked for again each time the app opens -- an app
// cannot reach storage yet (queue items C116 Secure and C125 Files hold the encrypted home for it).
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use e.fmt.json as json
use appkit
use text
use ui
use httpc

const MAX_TICKERS: usize = 9usize
const SYMBOL_BYTES: usize = 10usize
const NAME_BYTES: usize = 24usize
const DAYS: usize = 60usize
const LIST_SCREEN: usize = 0usize
const DETAIL_SCREEN: usize = 1usize
const ADD_SCREEN: usize = 2usize
const KEY_SCREEN: usize = 3usize
const JOB_NONE: usize = 0usize
const JOB_REFRESH: usize = 1usize
const JOB_ADD: usize = 2usize
const JOB_FIND: usize = 3usize
const FOUND_MAX: usize = 5usize
const PROVIDER_TWELVE: usize = 0usize
const PROVIDER_ALPHA: usize = 1usize
const PROVIDER_POLYGON: usize = 2usize

const ID_ROW: usize = 100usize
const ID_ADD: usize = 200usize
const ID_KEY: usize = 201usize
const ID_SYNC: usize = 202usize
const ID_BACK: usize = 500usize
const ID_RANGE: usize = 600usize
const ID_REMOVE: usize = 700usize
const ID_STOCK_KIND: usize = 800usize
const ID_CRYPTO_KIND: usize = 801usize
const ID_CANCEL: usize = 802usize
const ID_CLEAR_KEY: usize = 900usize
const ID_FIND: usize = 803usize
const ID_PROVIDER: usize = 810usize
const ID_MATCH: usize = 1300usize

type State = struct {
    prices: [540]f32,
    symbols: [90]u8,
    symbol_len: [9]usize,
    names: [216]u8,
    name_len: [9]usize,
    crypto: [9]bool,
    live: [9]bool,
    count: usize,
    selected: usize,
    range: usize,
    screen: usize,
    entry: ui.Field,
    key: ui.Field,
    add_crypto: bool,
    provider: usize,
    found: usize,
    found_symbol: [50]u8,
    found_symbol_len: [5]usize,
    found_name: [120]u8,
    found_name_len: [5]usize,
    hits: ui.Hits,
    status: [72]u8,
    status_len: usize,
    job: usize,
    job_next: usize,
    job_ok: usize,
    job_failed: usize,
    job_skipped: usize,
    reason: usize,
}

// ----------------------------------------------------------------------------------------------
// Text helpers.

fn emit(buffer: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len && n < buffer.len {
        buffer[n] = piece[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

fn emit_num(buffer: []u8, at: usize, value: usize) -> usize {
    var digits: [20]u8 = zero
    var d = 20usize
    var rest = value
    var open = true
    while open {
        d -= 1usize
        digits[d] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    ret emit(buffer, at, digits[d..20usize])
}

// Two digits of a hundredth count: 5 -> "05".
fn cents_text(a: *mem.Arena, cents: usize) -> str {
    var tens = ""
    if cents < 10usize { tens = "0" }
    ret ui.join(a, tens, ui.number(a, cents), "")
}

// "$189.52".
fn price_text(a: *mem.Arena, value: f32) -> str {
    let total = usize(value * 100.0 + 0.5)
    ret ui.join(a, ui.join(a, "$", ui.number(a, total / 100usize), "."), cents_text(a, total % 100usize), "")
}

// "+1.23%" or "-0.40%" from a fraction.
fn percent_text(a: *mem.Arena, fraction: f32) -> str {
    var sign = "+"
    var magnitude = fraction
    if fraction < 0.0 {
        sign = "-"
        magnitude = 0.0 - fraction
    }
    let basis = usize(magnitude * 10000.0 + 0.5)
    ret ui.join(a, ui.join(a, sign, ui.number(a, basis / 100usize), "."), cents_text(a, basis % 100usize), "%")
}

// "+2.31" or "-0.40": a price difference.
fn delta_text(a: *mem.Arena, difference: f32) -> str {
    var sign = "+"
    var magnitude = difference
    if difference < 0.0 {
        sign = "-"
        magnitude = 0.0 - difference
    }
    let total = usize(magnitude * 100.0 + 0.5)
    ret ui.join(a, ui.join(a, sign, ui.number(a, total / 100usize), "."), cents_text(a, total % 100usize), "")
}

fn gain_on_cream(up: bool) -> paint.Color {
    if up { ret paint.Color { red: 0.13, green: 0.52, blue: 0.28, alpha: 1.0 } }
    ret paint.Color { red: 0.72, green: 0.22, blue: 0.18, alpha: 1.0 }
}

fn gain_on_dark(up: bool) -> paint.Color {
    if up { ret paint.Color { red: 0.45, green: 0.80, blue: 0.55, alpha: 1.0 } }
    ret paint.Color { red: 0.95, green: 0.50, blue: 0.45, alpha: 1.0 }
}

// ----------------------------------------------------------------------------------------------
// The watchlist and its sample data.

fn symbol_of(s: *State, t: usize) -> str {
    ret s.symbols[t * SYMBOL_BYTES..t * SYMBOL_BYTES + s.symbol_len[t]]
}

fn name_of(s: *State, t: usize) -> str {
    ret s.names[t * NAME_BYTES..t * NAME_BYTES + s.name_len[t]]
}

fn set_text(into: []u8, at: usize, limit: usize, value: str) -> usize {
    var n = 0usize
    while n < value.len && n < limit {
        into[at + n] = value[n]
        n += 1usize
    }
    ret n
}

// A ticker at slot `t`: its symbol (as typed, capitals), a name and its kind.
fn set_ticker(s: *State, t: usize, symbol: str, name: str, crypto: bool) {
    s.symbol_len[t] = set_text(s.symbols[0usize..], t * SYMBOL_BYTES, SYMBOL_BYTES, symbol)
    s.name_len[t] = set_text(s.names[0usize..], t * NAME_BYTES, NAME_BYTES, name)
    s.crypto[t] = crypto
    s.live[t] = false
}

// Where each sample series ends and how restless it is.
fn sample_series(s: *State, t: usize, base: f32, vol: f32) {
    var seed = 12345usize + t * 7919usize
    var price: f32 = base * 0.93
    var d = 0usize
    while d < DAYS {
        seed = (seed * 1103515245usize + 12345usize) & 2147483647usize
        let r = f32(seed >> 8usize) / 8388608.0
        price = price * (1.0 + (r - 0.5) * 2.0 * vol + 0.0012)
        s.prices[t * DAYS + d] = price
        d += 1usize
    }
}

fn fill_sample(s: *State) {
    set_ticker(s, 0usize, "AAPL", "Apple Inc.", false)
    sample_series(s, 0usize, 189.5, 0.012)
    set_ticker(s, 1usize, "MSFT", "Microsoft Corp.", false)
    sample_series(s, 1usize, 412.3, 0.010)
    set_ticker(s, 2usize, "GOOGL", "Alphabet Inc.", false)
    sample_series(s, 2usize, 141.8, 0.014)
    set_ticker(s, 3usize, "AMZN", "Amazon.com Inc.", false)
    sample_series(s, 3usize, 178.2, 0.016)
    set_ticker(s, 4usize, "TSLA", "Tesla Inc.", false)
    sample_series(s, 4usize, 245.7, 0.034)
    set_ticker(s, 5usize, "NVDA", "NVIDIA Corp.", false)
    sample_series(s, 5usize, 877.4, 0.028)
    set_ticker(s, 6usize, "META", "Meta Platforms", false)
    sample_series(s, 6usize, 486.1, 0.020)
    set_ticker(s, 7usize, "BTC-USD", "Bitcoin", true)
    sample_series(s, 7usize, 64000.0, 0.030)
    set_ticker(s, 8usize, "ETH-USD", "Ethereum", true)
    sample_series(s, 8usize, 3100.0, 0.035)
    s.count = 9usize
}

// The days a range shows: 1W 7, 1M 30, 2M 60.
fn range_days(range: usize) -> usize {
    if range == 0usize { ret 7usize }
    if range == 1usize { ret 30usize }
    ret 60usize
}

fn price_at(s: *State, t: usize, day: usize) -> f32 {
    ret s.prices[t * DAYS + day]
}

fn day_change(s: *State, t: usize) -> f32 {
    ret price_at(s, t, DAYS - 1usize) - price_at(s, t, DAYS - 2usize)
}

fn any_live(s: *State) -> bool {
    var t = 0usize
    while t < s.count {
        if s.live[t] { ret true }
        t += 1usize
    }
    ret false
}

fn say_status(s: *State, line: str) {
    s.status_len = set_text(s.status[0usize..], 0usize, 72usize, line)
}

// Take a ticker out of the list, closing the gap.
fn remove_ticker(s: *State, t: usize) {
    var i = t
    while i + 1usize < s.count {
        var j = 0usize
        while j < DAYS {
            s.prices[i * DAYS + j] = s.prices[(i + 1usize) * DAYS + j]
            j += 1usize
        }
        j = 0usize
        while j < SYMBOL_BYTES {
            s.symbols[i * SYMBOL_BYTES + j] = s.symbols[(i + 1usize) * SYMBOL_BYTES + j]
            j += 1usize
        }
        j = 0usize
        while j < NAME_BYTES {
            s.names[i * NAME_BYTES + j] = s.names[(i + 1usize) * NAME_BYTES + j]
            j += 1usize
        }
        s.symbol_len[i] = s.symbol_len[i + 1usize]
        s.name_len[i] = s.name_len[i + 1usize]
        s.crypto[i] = s.crypto[i + 1usize]
        s.live[i] = s.live[i + 1usize]
        i += 1usize
    }
    s.count -= 1usize
}

// ----------------------------------------------------------------------------------------------
// Live data.

// The member named `key` of a JSON object.
fn member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < members.len {
        if ui.same(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    var none: json.Value = zero
    ret (none, false)
}

// A JSON number, or a string holding one ("189.52"), as a price.
fn price_of(a: *mem.Arena, v: json.Value) -> (f32, bool) {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok { ret (0.0, false) }
        ret (f32(x), true)
    case .String as lexeme:
        let (n, number_error) = json.number(lexeme)
        if number_error != ok { ret (0.0, false) }
        let (x, e) = json.number_f64(n)
        if e != ok { ret (0.0, false) }
        ret (f32(x), true)
    default:
        ret (0.0, false)
    }
}

// Why the last fetch failed, for the status line.
fn reason_text(reason: usize) -> str {
    if reason == 1usize { ret "no network" }
    if reason == 2usize { ret "server unreachable" }
    if reason == 3usize { ret "certificate refused" }
    if reason == 4usize { ret "bad reply" }
    if reason == 5usize { ret "key refused" }
    if reason == 6usize { ret "not enough history" }
    if reason == 7usize { ret "needs an API key" }
    if reason == 8usize { ret "symbol unknown" }
    ret "failed"
}

fn reason_of(e: err) -> usize {
    if e == httpc.NoNetwork { ret 1usize }
    if e == httpc.Unreachable { ret 2usize }
    if e == httpc.TlsFailed { ret 3usize }
    ret 4usize
}

// Coinbase Exchange daily candles, newest first: [time, low, high, open, close, volume].
fn fetch_crypto(a: *mem.Arena, s: *State, t: usize) -> bool {
    let mark = mem.mark(a)
    let path = ui.join(a, "/products/", symbol_of(s, t), "/candles?granularity=86400")
    let (reply, get_error) = httpc.get(a, "api.exchange.coinbase.com", path, "")
    if get_error != ok {
        s.reason = reason_of(get_error)
        mem.reset(a, mark)
        ret false
    }
    if reply.status != 200usize {
        s.reason = 4usize
        mem.reset(a, mark)
        ret false
    }
    let (parsed, parse_error) = json.parse(a, reply.body, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
    if parse_error != ok {
        s.reason = 4usize
        mem.reset(a, mark)
        ret false
    }
    var good = false
    switch parsed {
    case .Array as candles:
        if candles.len >= DAYS {
            good = true
            var d = 0usize
            while d < DAYS && good {
                switch candles[DAYS - 1usize - d] {
                case .Array as candle:
                    if candle.len < 5usize {
                        good = false
                    } else {
                        let (close, close_ok) = price_of(a, candle[4usize])
                        if close_ok && close > 0.0 { s.prices[t * DAYS + d] = close } else { good = false }
                    }
                default:
                    good = false
                }
                d += 1usize
            }
        } else {
            s.reason = 6usize
        }
    default:
        s.reason = 4usize
    }
    mem.reset(a, mark)
    if !good && s.reason == 0usize { s.reason = 4usize }
    ret good
}

fn provider_name(p: usize) -> str {
    if p == PROVIDER_ALPHA { ret "Alpha Vantage" }
    if p == PROVIDER_POLYGON { ret "Polygon" }
    ret "Twelve Data"
}

// One GET answered with a JSON document; on failure s.reason says why and the value is empty. A 401 or 403
// is a refused key (Polygon answers its key errors with a status); other statuses than 200 are a bad reply.
// The parsed value lives in `a` above the caller's mark.
fn fetch_json(a: *mem.Arena, s: *State, host: str, path: str) -> (json.Value, bool) {
    var none: json.Value = zero
    let (reply, get_error) = httpc.get(a, host, path, "")
    if get_error != ok {
        s.reason = reason_of(get_error)
        ret (none, false)
    }
    if reply.status == 401usize || reply.status == 403usize {
        s.reason = 5usize
        ret (none, false)
    }
    if reply.status != 200usize {
        s.reason = 4usize
        ret (none, false)
    }
    let (parsed, parse_error) = json.parse(a, reply.body, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
    if parse_error != ok {
        s.reason = 4usize
        ret (none, false)
    }
    ret (parsed, true)
}

// Alpha Vantage TIME_SERIES_DAILY (compact: the newest 100 days), an object keyed by date, newest first:
// {"Time Series (Daily)": {"2026-10-08": {"4. close": "226.6100", ...}, ...}}. A refused or rate-limited key
// gets {"Information": ...} or {"Note": ...}, an unknown symbol {"Error Message": ...}.
fn fetch_alpha(a: *mem.Arena, s: *State, t: usize) -> bool {
    let mark = mem.mark(a)
    var path = ui.join(a, "/query?function=TIME_SERIES_DAILY&symbol=", symbol_of(s, t), "&apikey=")
    path = ui.join(a, path, ui.field_text(a, &s.key), "")
    let (parsed, fetched) = fetch_json(a, s, "www.alphavantage.co", path)
    if !fetched {
        mem.reset(a, mark)
        ret false
    }
    var good = false
    switch parsed {
    case .Object as fields:
        let (series, has_series) = member(fields, "Time Series (Daily)")
        if has_series {
            switch series {
            case .Object as days:
                if days.len >= DAYS {
                    good = true
                    var d = 0usize
                    while d < DAYS && good {
                        switch days[DAYS - 1usize - d].value {
                        case .Object as row:
                            let (closing, has_close) = member(row, "4. close")
                            if has_close {
                                let (close, close_ok) = price_of(a, closing)
                                if close_ok && close > 0.0 { s.prices[t * DAYS + d] = close } else { good = false }
                            } else {
                                good = false
                            }
                        default:
                            good = false
                        }
                        d += 1usize
                    }
                } else {
                    s.reason = 6usize
                }
            default:
                s.reason = 4usize
            }
        } else {
            let (unused, has_error) = member(fields, "Error Message")
            if has_error { s.reason = 8usize } else { s.reason = 5usize }
        }
    default:
        s.reason = 4usize
    }
    mem.reset(a, mark)
    if !good && s.reason == 0usize { s.reason = 4usize }
    ret good
}

// Polygon /v2/aggs daily bars, newest first (sort=desc): {"results": [{"c": 189.52, "t": ...}, ...],
// "resultsCount": 60, "status": "OK"}. The range runs from 2020 to 2099, so `limit` decides what comes back.
fn fetch_polygon(a: *mem.Arena, s: *State, t: usize) -> bool {
    let mark = mem.mark(a)
    var path = ui.join(a, "/v2/aggs/ticker/", symbol_of(s, t), "/range/1/day/2020-01-01/2099-12-31?adjusted=true&sort=desc&limit=60&apiKey=")
    path = ui.join(a, path, ui.field_text(a, &s.key), "")
    let (parsed, fetched) = fetch_json(a, s, "api.polygon.io", path)
    if !fetched {
        mem.reset(a, mark)
        ret false
    }
    var good = false
    switch parsed {
    case .Object as fields:
        let (results, has_results) = member(fields, "results")
        if has_results {
            switch results {
            case .Array as bars:
                if bars.len >= DAYS {
                    good = true
                    var d = 0usize
                    while d < DAYS && good {
                        switch bars[DAYS - 1usize - d] {
                        case .Object as bar:
                            let (closing, has_close) = member(bar, "c")
                            if has_close {
                                let (close, close_ok) = price_of(a, closing)
                                if close_ok && close > 0.0 { s.prices[t * DAYS + d] = close } else { good = false }
                            } else {
                                good = false
                            }
                        default:
                            good = false
                        }
                        d += 1usize
                    }
                } else {
                    s.reason = 6usize
                }
            default:
                s.reason = 4usize
            }
        } else {
            // A valid key and a symbol it finds nothing for: status OK and no "results".
            s.reason = 8usize
        }
    default:
        s.reason = 4usize
    }
    mem.reset(a, mark)
    if !good && s.reason == 0usize { s.reason = 4usize }
    ret good
}

// Twelve Data time_series, newest first: {"values": [{"datetime": ..., "close": "189.52", ...}], "status": "ok"}.
fn fetch_twelve(a: *mem.Arena, s: *State, t: usize) -> bool {
    if s.key.len == 0usize {
        s.reason = 7usize
        ret false
    }
    let mark = mem.mark(a)
    var path = ui.join(a, "/time_series?symbol=", symbol_of(s, t), "&interval=1day&outputsize=60")
    path = ui.join(a, path, "&apikey=", ui.field_text(a, &s.key))
    let (reply, get_error) = httpc.get(a, "api.twelvedata.com", path, "")
    if get_error != ok {
        s.reason = reason_of(get_error)
        mem.reset(a, mark)
        ret false
    }
    let (parsed, parse_error) = json.parse(a, reply.body, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
    if parse_error != ok {
        s.reason = 4usize
        mem.reset(a, mark)
        ret false
    }
    var good = false
    switch parsed {
    case .Object as fields:
        let (values, has_values) = member(fields, "values")
        if has_values {
            switch values {
            case .Array as rows:
                if rows.len >= DAYS {
                    good = true
                    var d = 0usize
                    while d < DAYS && good {
                        switch rows[DAYS - 1usize - d] {
                        case .Object as row:
                            let (closing, has_close) = member(row, "close")
                            if has_close {
                                let (close, close_ok) = price_of(a, closing)
                                if close_ok && close > 0.0 { s.prices[t * DAYS + d] = close } else { good = false }
                            } else {
                                good = false
                            }
                        default:
                            good = false
                        }
                        d += 1usize
                    }
                } else {
                    s.reason = 6usize
                }
            default:
                s.reason = 4usize
            }
        } else {
            // {"code": 401, "message": "...", "status": "error"}: a refused key or a symbol it does not know.
            s.reason = 5usize
        }
    default:
        s.reason = 4usize
    }
    mem.reset(a, mark)
    if !good && s.reason == 0usize { s.reason = 4usize }
    ret good
}

fn fetch_stock(a: *mem.Arena, s: *State, t: usize) -> bool {
    if s.key.len == 0usize {
        s.reason = 7usize
        ret false
    }
    if s.provider == PROVIDER_ALPHA { ret fetch_alpha(a, s, t) }
    if s.provider == PROVIDER_POLYGON { ret fetch_polygon(a, s, t) }
    ret fetch_twelve(a, s, t)
}

fn fetch_ticker(a: *mem.Arena, s: *State, t: usize) -> bool {
    s.reason = 0usize
    if s.crypto[t] { ret fetch_crypto(a, s, t) }
    ret fetch_stock(a, s, t)
}

// Twelve Data symbol_search for what is typed in the Add sheet (no key): up to FOUND_MAX distinct symbols with
// their names, in `found_*`. {"data": [{"symbol": "APP", "instrument_name": "AppLovin ..."}, ...], "status": "ok"}.
fn find_symbols(a: *mem.Arena, s: *State) -> bool {
    s.found = 0usize
    s.reason = 0usize
    let mark = mem.mark(a)
    // Only letters, digits, '-' and '.' go into the URL.
    var term: [32]u8 = zero
    var n = 0usize
    var i = 0usize
    while i < s.entry.len && n < 32usize {
        let c = s.entry.bytes[i]
        if (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 45u8 || c == 46u8 {
            term[n] = c
            n += 1usize
        }
        i += 1usize
    }
    let (word, word_error) = mem.alloc[u8](a, n)
    if word_error != ok { ret false }
    i = 0usize
    while i < n {
        word[i] = term[i]
        i += 1usize
    }
    let path = ui.join(a, "/symbol_search?outputsize=30&symbol=", word[0usize..n], "")
    let (parsed, fetched) = fetch_json(a, s, "api.twelvedata.com", path)
    if !fetched {
        mem.reset(a, mark)
        ret false
    }
    switch parsed {
    case .Object as fields:
        let (data, has_data) = member(fields, "data")
        if has_data {
            switch data {
            case .Array as matches:
                var m = 0usize
                while m < matches.len && s.found < FOUND_MAX {
                    switch matches[m] {
                    case .Object as row:
                        let (symbol, got_symbol) = member(row, "symbol")
                        let (name, got_name) = member(row, "instrument_name")
                        if got_symbol && got_name {
                            switch symbol {
                            case .String as symbol_text:
                                switch name {
                                case .String as name_text:
                                    var seen = false
                                    var f = 0usize
                                    while f < s.found {
                                        if ui.same(s.found_symbol[f * SYMBOL_BYTES..f * SYMBOL_BYTES + s.found_symbol_len[f]], symbol_text) { seen = true }
                                        f += 1usize
                                    }
                                    if !seen && symbol_text.len <= SYMBOL_BYTES && symbol_text.len > 0usize {
                                        s.found_symbol_len[s.found] = set_text(s.found_symbol[0usize..], s.found * SYMBOL_BYTES, SYMBOL_BYTES, symbol_text)
                                        s.found_name_len[s.found] = set_text(s.found_name[0usize..], s.found * NAME_BYTES, NAME_BYTES, name_text)
                                        s.found += 1usize
                                    }
                                default:
                                    s.reason = 0usize
                                }
                            default:
                                s.reason = 0usize
                            }
                        }
                    default:
                        s.reason = 0usize
                    }
                    m += 1usize
                }
            default:
                s.reason = 4usize
            }
        } else {
            s.reason = 4usize
        }
    default:
        s.reason = 4usize
    }
    mem.reset(a, mark)
    ret s.reason == 0usize
}

// One step of the running job, done on a tick: Sync fetches the next ticker, Add looks the new one up.
fn job_step(a: *mem.Arena, s: *State) {
    if s.job == JOB_REFRESH {
        let t = s.job_next
        if t >= s.count {
            s.job = JOB_NONE
            if s.job_ok > 0usize {
                say_status(s, ui.join(a, ui.join(a, "Live ", ui.number(a, s.job_ok), " updated, daily close, delayed"), "", ""))
            } else {
                say_status(s, ui.join(a, "Sample data, not live (", reason_text(s.reason), ")"))
            }
            ui.say("stocks refresh live ")
            ui.say_num(s.job_ok)
            ui.say(" failed ")
            ui.say_num(s.job_failed)
            ui.say(" skipped ")
            ui.say_num(s.job_skipped)
            ui.say("\n")
            ret
        }
        s.job_next += 1usize
        if !s.crypto[t] && s.key.len == 0usize {
            s.job_skipped += 1usize
            s.reason = 7usize
            say_status(s, ui.join(a, "Syncing ", ui.number(a, s.job_next), " of ..."))
            ret
        }
        if fetch_ticker(a, s, t) {
            s.live[t] = true
            s.job_ok += 1usize
        } else {
            s.job_failed += 1usize
        }
        say_status(s, ui.join(a, ui.join(a, "Syncing ", ui.number(a, s.job_next), " of "), ui.number(a, s.count), ""))
        ret
    }
    if s.job == JOB_FIND {
        s.job = JOB_NONE
        if find_symbols(a, s) {
            if s.found == 0usize { say_status(s, "No symbol matches that") } else { say_status(s, "Tap a match to use it") }
        } else {
            say_status(s, ui.join(a, "Search failed: ", reason_text(s.reason), ""))
        }
        ui.say("stocks found ")
        ui.say_num(s.found)
        ui.say("\n")
        ret
    }
    if s.job == JOB_ADD {
        s.job = JOB_NONE
        let t = s.count
        // The new ticker is built in the next free slot; it joins the list only if its data arrives.
        var symbol: [10]u8 = zero
        var n = 0usize
        while n < s.entry.len && n < SYMBOL_BYTES {
            var c = s.entry.bytes[n]
            if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
            symbol[n] = c
            n += 1usize
        }
        let crypto = s.add_crypto
        var label = "Stock"
        if crypto { label = "Crypto" }
        set_ticker(s, t, symbol[0usize..n], label, crypto)
        if fetch_ticker(a, s, t) {
            s.live[t] = true
            s.count += 1usize
            s.selected = t
            s.screen = LIST_SCREEN
            say_status(s, ui.join(a, "Added ", symbol_of(s, t), ", live daily close"))
            ui.say("stocks added ")
            ui.say_text(symbol_of(s, t))
            ui.say("\n")
        } else {
            s.screen = ADD_SCREEN
            say_status(s, ui.join(a, "No data for that symbol: ", reason_text(s.reason), ""))
            ui.say("stocks add failed ")
            ui.say_text(reason_text(s.reason))
            ui.say("\n")
        }
        ret
    }
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn back_icon() -> str {
    ret ui.back_icon()
}

// The line (or, with `area`, the filled area under it) of `days` closing prices of ticker `t`, as an
// svg document of `w` x `h` whole units: high at the top, low at the bottom.
fn chart_svg(a: *mem.Arena, s: *State, t: usize, days: usize, w: usize, h: usize, area: bool, stroke: usize) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, 1600usize)
    if buffer_error != ok { ret "" }
    let first = DAYS - days
    var low = price_at(s, t, first)
    var high = low
    var d = first
    while d < DAYS {
        let v = price_at(s, t, d)
        if v < low { low = v }
        if v > high { high = v }
        d += 1usize
    }
    var span = high - low
    if span < 0.0001 { span = 1.0 }
    var n = 0usize
    n = emit(buffer, n, "<svg viewBox='0 0 ")
    n = emit_num(buffer, n, w)
    n = emit(buffer, n, " ")
    n = emit_num(buffer, n, h)
    n = emit(buffer, n, "'><path d='")
    if area {
        n = emit(buffer, n, "M0 ")
        n = emit_num(buffer, n, h)
    }
    d = 0usize
    while d < days {
        let v = price_at(s, t, first + d)
        let x = d * w / (days - 1usize)
        let y = 2usize + usize((high - v) / span * f32(h - 4usize))
        if d == 0usize && !area { n = emit(buffer, n, "M") } else { n = emit(buffer, n, " L") }
        n = emit_num(buffer, n, x)
        n = emit(buffer, n, " ")
        n = emit_num(buffer, n, y)
        d += 1usize
    }
    if area {
        n = emit(buffer, n, " L")
        n = emit_num(buffer, n, w)
        n = emit(buffer, n, " ")
        n = emit_num(buffer, n, h)
        n = emit(buffer, n, " Z' fill='currentColor' stroke='none'/></svg>")
    } else {
        n = emit(buffer, n, "' fill='none' stroke='currentColor' stroke-width='")
        n = emit_num(buffer, n, stroke)
        n = emit(buffer, n, "' stroke-linecap='round' stroke-linejoin='round'/></svg>")
    }
    ret buffer[0usize..n]
}

// What the screen says about where its numbers come from.
fn source_line(s: *State, t: usize) -> str {
    if t != ui.NONE && s.live[t] { ret "Live daily close, delayed" }
    ret "Sample data, not live"
}

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 34.0, "Stocks", 24.0, 40.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, ID_ADD, 190.0, 38.0, 60.0, 32.0, "Add", ui.amber(), 15.0)
    try ui.pill(a, builder, &s.hits, faces, ID_KEY, 256.0, 38.0, 56.0, 32.0, "Key", ui.soft(), 15.0)
    try ui.pill(a, builder, &s.hits, faces, ID_SYNC, 318.0, 38.0, 78.0, 32.0, "Sync", ui.amber(), 15.0)
    var line = "Sample data, not live"
    if s.status_len > 0usize { line = s.status[0usize..s.status_len] } else if any_live(s) { line = "Live daily close, delayed" }
    try ui.clipped(a, builder, faces.grotesk, 12.0, line, 24.0, 86.0, 372.0, ui.light_muted())
    var t = 0usize
    while t < s.count {
        let y: f32 = 108.0 + f32(t) * 84.0
        let change = day_change(s, t)
        let up = change >= 0.0
        let last = price_at(s, t, DAYS - 1usize)
        let previous = price_at(s, t, DAYS - 2usize)
        try ui.card(a, builder, 16.0, y, 380.0, 72.0, 20.0, ui.cream())
        try ui.put(a, builder, faces.jost_bold, 19.0, symbol_of(s, t), 32.0, y + 12.0, ui.ink())
        try ui.clipped(a, builder, faces.grotesk, 12.0, name_of(s, t), 32.0, y + 42.0, 124.0, ui.muted())
        try svg.draw(a, builder, chart_svg(a, s, t, 30usize, 80usize, 32usize, false, 2usize), geometry.rect(164.0, y + 20.0, 80.0, 32.0), gain_on_cream(up))
        try ui.put_right(a, builder, faces.jost_bold, 19.0, price_text(a, last), 380.0, y + 12.0, ui.ink())
        try ui.put_right(a, builder, faces.grotesk, 13.0, percent_text(a, change / previous), 380.0, y + 42.0, gain_on_cream(up))
        if s.live[t] { try ui.disc(a, builder, 26.0, y + 8.0, 3.5, gain_on_cream(true)) }
        ui.hit(&s.hits, ID_ROW + t, 16.0, y, 380.0, 72.0)
        t += 1usize
    }
    ret ok
}

fn stat(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, label: str, value: f32, x: f32, y: f32) -> err {
    try ui.put(a, builder, faces.grotesk, 12.0, label, x, y, ui.muted())
    try ui.put(a, builder, faces.jost, 20.0, price_text(a, value), x, y + 18.0, ui.ink())
    ret ok
}

fn draw_detail(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let t = s.selected
    let days = range_days(s.range)
    let first = DAYS - days
    let last = price_at(s, t, DAYS - 1usize)
    let start = price_at(s, t, first)
    var low = start
    var high = start
    var d = first
    while d < DAYS {
        let v = price_at(s, t, d)
        if v < low { low = v }
        if v > high { high = v }
        d += 1usize
    }
    let change = last - start
    let up = change >= 0.0
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 36.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, ID_BACK, 0.0, 20.0, 66.0, 60.0)
    try ui.put(a, builder, faces.jost_bold, 26.0, symbol_of(s, t), 64.0, 26.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 13.0, name_of(s, t), 64.0, 62.0, ui.light_muted())
    try ui.put(a, builder, faces.jost_bold, 46.0, price_text(a, last), 24.0, 96.0, ui.light())
    try ui.put(a, builder, faces.jost, 18.0, ui.join(a, delta_text(a, change), "  ", percent_text(a, change / start)), 24.0, 156.0, gain_on_dark(up))
    // The range chips.
    var chip = 0usize
    while chip < 3usize {
        var label = "1W"
        if chip == 1usize { label = "1M" }
        if chip == 2usize { label = "2M" }
        var fill = ui.soft()
        if chip == s.range { fill = ui.amber() }
        let x: f32 = 16.0 + f32(chip) * 84.0
        try ui.card(a, builder, x, 196.0, 76.0, 36.0, 18.0, fill)
        try ui.centred(a, builder, faces.jost, 15.0, label, x + 38.0, 196.0 + 18.0 - 9.0, ui.ink())
        ui.hit(&s.hits, ID_RANGE + chip, x, 196.0, 76.0, 36.0)
        chip += 1usize
    }
    // The chart: the area under the line, then the line; the high above it and the low below.
    try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "High ", price_text(a, high), ""), 16.0, 244.0, ui.light_muted())
    try svg.draw(a, builder, chart_svg(a, s, t, days, 380usize, 200usize, true, 3usize), geometry.rect(16.0, 264.0, 380.0, 200.0), paint.Color { red: gain_on_dark(up).red, green: gain_on_dark(up).green, blue: gain_on_dark(up).blue, alpha: 0.2 })
    try svg.draw(a, builder, chart_svg(a, s, t, days, 380usize, 200usize, false, 3usize), geometry.rect(16.0, 264.0, 380.0, 200.0), gain_on_dark(up))
    try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "Low ", price_text(a, low), ""), 16.0, 472.0, ui.light_muted())
    // The numbers.
    try ui.card(a, builder, 16.0, 516.0, 380.0, 132.0, 20.0, ui.cream())
    try stat(a, builder, faces, "Range high", high, 36.0, 534.0)
    try stat(a, builder, faces, "Range low", low, 216.0, 534.0)
    try stat(a, builder, faces, "Range start", start, 36.0, 592.0)
    try stat(a, builder, faces, "Previous close", price_at(s, t, DAYS - 2usize), 216.0, 592.0)
    try ui.centred(a, builder, faces.grotesk, 12.0, source_line(s, t), 206.0, 664.0, ui.light_muted())
    try ui.pill(a, builder, &s.hits, faces, ID_REMOVE, 146.0, 700.0, 120.0, 36.0, "Remove", ui.soft(), 15.0)
    ret ok
}

// The sheet that asks for a symbol (or, with `key`, the API key) on the keyboard.
fn draw_sheet(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, key: bool) -> err {
    var title = "Add ticker"
    if key { title = "API key" }
    try ui.put(a, builder, faces.jost_bold, 30.0, title, 24.0, 36.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, ID_CANCEL, 300.0, 40.0, 96.0, 32.0, "Cancel", ui.soft(), 15.0)
    var shown = ""
    if key { shown = ui.field_text(a, &s.key) } else { shown = ui.field_text(a, &s.entry) }
    try ui.card(a, builder, 16.0, 96.0, 380.0, 56.0, 16.0, ui.cream())
    if shown.len == 0usize {
        var hint = "AAPL or BTC-USD"
        if key { hint = ui.join(a, provider_name(s.provider), " API key", "") }
        try ui.put(a, builder, faces.jost, 22.0, hint, 32.0, 112.0, ui.muted())
    } else {
        try ui.put(a, builder, faces.jost, 22.0, shown, 32.0, 112.0, ui.ink())
    }
    if key {
        var p = 0usize
        while p < 3usize {
            var fill = ui.soft()
            if s.provider == p { fill = ui.amber() }
            let x: f32 = 16.0 + f32(p) * 126.0
            try ui.pill(a, builder, &s.hits, faces, ID_PROVIDER + p, x, 172.0, 118.0, 34.0, provider_name(p), fill, 14.0)
            p += 1usize
        }
        var about = "From twelvedata.com (a free key works)."
        if s.provider == PROVIDER_ALPHA { about = "From alphavantage.co (a free key works; the demo key serves IBM)." }
        if s.provider == PROVIDER_POLYGON { about = "From polygon.io (the free plan is rate-limited)." }
        let (box_a, wrap_a) = ui.wrapped(a, builder, faces.grotesk, 13.0, ui.join(a, about, " Changing the provider clears the key. Kept only while this app is open; stocks need it, crypto does not.", ""), 24.0, 222.0, 372.0, 5u32, ui.light_muted())
        if wrap_a != ok { ret wrap_a }
        if s.key.len > 0usize { try ui.pill(a, builder, &s.hits, faces, ID_CLEAR_KEY, 24.0, 330.0, 120.0, 34.0, "Clear key", ui.soft(), 14.0) }
    } else {
        var stock_fill = ui.soft()
        var crypto_fill = ui.soft()
        if s.add_crypto { crypto_fill = ui.amber() } else { stock_fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, ID_STOCK_KIND, 16.0, 172.0, 110.0, 36.0, "Stock", stock_fill, 15.0)
        try ui.pill(a, builder, &s.hits, faces, ID_CRYPTO_KIND, 134.0, 172.0, 110.0, 36.0, "Crypto", crypto_fill, 15.0)
        if !s.add_crypto { try ui.pill(a, builder, &s.hits, faces, ID_FIND, 300.0, 172.0, 96.0, 36.0, "Find", ui.soft(), 15.0) }
        if !s.add_crypto && s.found > 0usize {
            var m = 0usize
            while m < s.found {
                let y: f32 = 222.0 + f32(m) * 46.0
                try ui.card(a, builder, 16.0, y, 380.0, 40.0, 14.0, ui.cream())
                try ui.put(a, builder, faces.jost_bold, 17.0, s.found_symbol[m * SYMBOL_BYTES..m * SYMBOL_BYTES + s.found_symbol_len[m]], 30.0, y + 9.0, ui.ink())
                try ui.clipped(a, builder, faces.grotesk, 12.0, s.found_name[m * NAME_BYTES..m * NAME_BYTES + s.found_name_len[m]], 130.0, y + 12.0, 256.0, ui.muted())
                ui.hit(&s.hits, ID_MATCH + m, 16.0, y, 380.0, 40.0)
                m += 1usize
            }
        } else {
            var note = ui.join(a, "Stocks come from ", provider_name(s.provider), " and need its API key (Key). Type a symbol such as AAPL, or part of a name and tap Find.")
            if s.add_crypto { note = "Crypto comes from Coinbase with no key. Type a pair such as BTC-USD or ETH-USD." }
            let (box_b, wrap_b) = ui.wrapped(a, builder, faces.grotesk, 13.0, note, 24.0, 226.0, 372.0, 4u32, ui.light_muted())
            if wrap_b != ok { ret wrap_b }
        }
    }
    if s.status_len > 0usize { try ui.clipped(a, builder, faces.grotesk, 12.0, s.status[0usize..s.status_len], 24.0, 460.0, 372.0, ui.light_muted()) }
    var enter = "Add"
    if key { enter = "Save" }
    try ui.keyboard(a, builder, &s.hits, faces, enter)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == LIST_SCREEN {
        try draw_list(a, builder, s, faces)
    } else if s.screen == DETAIL_SCREEN {
        try draw_detail(a, builder, s, faces)
    } else if s.screen == ADD_SCREEN {
        try draw_sheet(a, builder, s, faces, false)
    } else {
        try draw_sheet(a, builder, s, faces, true)
    }
    try ui.handle(a, builder)
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

// Whether the typed symbol (in capitals) is already on the watchlist.
fn has_symbol(s: *State) -> bool {
    var t = 0usize
    while t < s.count {
        if s.symbol_len[t] == s.entry.len {
            var same = true
            var n = 0usize
            while n < s.entry.len {
                var c = s.entry.bytes[n]
                if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
                if c != s.symbols[t * SYMBOL_BYTES + n] { same = false }
                n += 1usize
            }
            if same { ret true }
        }
        t += 1usize
    }
    ret false
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.job != JOB_NONE { ret false }
    if ui.is_key(id) && (s.screen == ADD_SCREEN || s.screen == KEY_SCREEN) {
        if s.screen == ADD_SCREEN {
            if id == 1205usize {
                if s.entry.len == 0usize {
                    say_status(s, "Type a symbol first")
                    ret true
                }
                if s.count >= MAX_TICKERS {
                    say_status(s, "The list is full: remove one first")
                    ret true
                }
                if has_symbol(s) {
                    say_status(s, "That one is already in the list")
                    ret true
                }
                if !s.add_crypto && s.key.len == 0usize {
                    say_status(s, "Stocks need an API key: tap Cancel, then Key")
                    ret true
                }
                s.job = JOB_ADD
                say_status(s, "Looking it up...")
                ret true
            }
            s.found = 0usize
            ret ui.field_key(&s.entry, id, false)
        }
        if id == 1205usize {
            s.screen = LIST_SCREEN
            say_status(s, "API key saved for this session")
            ui.say("stocks key saved\n")
            ret true
        }
        ret ui.field_key(&s.key, id, false)
    }
    if s.screen == LIST_SCREEN {
        if id >= ID_ROW && id < ID_ROW + s.count {
            s.selected = id - ID_ROW
            s.screen = DETAIL_SCREEN
            ui.say("stocks opened ")
            ui.say_text(symbol_of(s, s.selected))
            ui.say("\n")
            ret true
        }
        if id == ID_ADD {
            s.screen = ADD_SCREEN
            s.entry.len = 0usize
            s.found = 0usize
            s.status_len = 0usize
            ui.say("stocks add sheet\n")
            ret true
        }
        if id == ID_KEY {
            s.screen = KEY_SCREEN
            s.status_len = 0usize
            ui.say("stocks key sheet\n")
            ret true
        }
        if id == ID_SYNC {
            s.job = JOB_REFRESH
            s.job_next = 0usize
            s.job_ok = 0usize
            s.job_failed = 0usize
            s.job_skipped = 0usize
            s.reason = 0usize
            say_status(s, "Syncing...")
            ui.say("stocks sync\n")
            ret true
        }
        ret false
    }
    if s.screen == DETAIL_SCREEN {
        if id == ID_BACK {
            s.screen = LIST_SCREEN
            ui.say("stocks back\n")
            ret true
        }
        if id >= ID_RANGE && id < ID_RANGE + 3usize {
            s.range = id - ID_RANGE
            ui.say("stocks range ")
            ui.say_num(range_days(s.range))
            ui.say("\n")
            ret true
        }
        if id == ID_REMOVE {
            ui.say("stocks removed ")
            ui.say_text(symbol_of(s, s.selected))
            ui.say("\n")
            remove_ticker(s, s.selected)
            s.screen = LIST_SCREEN
            s.selected = ui.NONE
            ret true
        }
        ret false
    }
    // The Add and Key sheets.
    if id == ID_CANCEL {
        s.screen = LIST_SCREEN
        s.status_len = 0usize
        ret true
    }
    if s.screen == ADD_SCREEN && id == ID_FIND && !s.add_crypto {
        if s.entry.len == 0usize {
            say_status(s, "Type part of a symbol or name first")
            ret true
        }
        s.job = JOB_FIND
        say_status(s, "Searching...")
        ret true
    }
    if s.screen == ADD_SCREEN && id >= ID_MATCH && id < ID_MATCH + s.found {
        let m = id - ID_MATCH
        var n = 0usize
        while n < s.found_symbol_len[m] {
            s.entry.bytes[n] = s.found_symbol[m * SYMBOL_BYTES + n]
            n += 1usize
        }
        s.entry.len = s.found_symbol_len[m]
        s.found = 0usize
        say_status(s, "Symbol filled in: tap Add")
        ui.say("stocks picked ")
        ui.say_text(s.entry.bytes[0usize..s.entry.len])
        ui.say("\n")
        ret true
    }
    if s.screen == KEY_SCREEN && id >= ID_PROVIDER && id < ID_PROVIDER + 3usize {
        let chosen = id - ID_PROVIDER
        if chosen != s.provider {
            s.provider = chosen
            s.key.len = 0usize
            say_status(s, ui.join(a, provider_name(chosen), " chosen, key cleared", ""))
            ui.say("stocks provider ")
            ui.say_num(chosen)
            ui.say("\n")
        }
        ret true
    }
    if s.screen == ADD_SCREEN {
        if id == ID_STOCK_KIND {
            s.add_crypto = false
            ret true
        }
        if id == ID_CRYPTO_KIND {
            s.add_crypto = true
            ret true
        }
    }
    if s.screen == KEY_SCREEN && id == ID_CLEAR_KEY {
        s.key.len = 0usize
        say_status(s, "API key cleared")
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "stocks")
    if kit_error != ok {
        ui.say("stocks open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("stocks fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.selected = ui.NONE
    s.range = 1usize
    fill_sample(&s)
    if !show(a, &kit, &s) {
        ui.say("stocks present failed\n")
        ret ok
    }
    ui.say("stocks shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            if s.job != JOB_NONE {
                job_step(a, &s)
                if !show(a, &kit, &s) {
                    ui.say("stocks present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 && s.screen != ADD_SCREEN && s.screen != KEY_SCREEN {
            ui.say("stocks home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("stocks present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
