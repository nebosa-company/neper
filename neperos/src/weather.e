// Weather (D2214, live data D2286): the app behind the Weather icon, after Google's Weather -- places as
// chips, the temperature now with its condition icon, the day's high and low, an hourly strip (a
// condition and a chance of rain for each hour), a seven-day list with a range bar and the chance of rain
// per day, a row of Feels like, Humidity, Wind and UV, and a row of Sunrise, Sunset and Rain today. A chip
// changes the place; the C/F chip changes the unit (and km/h to mph); Remove drops the place; Add opens a
// sheet where a name is searched and a match becomes a place. Dark ground, cream cards and amber, like the
// other apps (appkit.e, ui.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at
// the bottom leaves the app.
// Data: each place starts on SAMPLE data -- a seeded forecast, the same on every run, said so on screen --
// and the app asks Open-Meteo (keyless, api.open-meteo.com) for the real one: the current conditions, 24
// hours and 7 days in the place's own time zone, so the hours, weekdays, sunrise and sunset are that
// place's. Places are found with Open-Meteo's geocoding search. Both go through the network server's socket
// capability (httpc.e); with no network, or on any error, the place keeps its sample and the status line
// says why. The screen says "Updated 22:15, Europe/Oslo" (the place's own clock) when the data is real.
// ponytail: the places and the unit live in this process only, so they are the four defaults each time the
// app opens -- an app cannot reach storage yet (queue items C116 Secure and C125 Files). There is no
// "current location" (no GPS yet, C131) and no weather alerts: Open-Meteo has none, and the Norwegian
// MetAlerts feed covers Norway only.
use e.mem
use e.os
use e.time
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

const PLACES: usize = 4usize
const HOURS: usize = 24usize
const DAYS: usize = 7usize
const FOUND_MAX: usize = 5usize
const NAME_BYTES: usize = 16usize
const WHERE_BYTES: usize = 24usize
const MAIN_SCREEN: usize = 0usize
const ADD_SCREEN: usize = 1usize
const JOB_NONE: usize = 0usize
const JOB_FETCH: usize = 1usize
const JOB_SEARCH: usize = 2usize
const JOB_ADD: usize = 3usize

const ID_CHIP: usize = 100usize
const ID_UNIT: usize = 700usize
const ID_ADD: usize = 701usize
const ID_REMOVE: usize = 702usize
const ID_CANCEL: usize = 703usize
const ID_RESULT: usize = 800usize

type Forecast = struct {
    live: bool,
    now_temp: f32,
    feels: f32,
    code: usize,
    humidity: usize,
    wind: f32,
    uv: usize,
    night: bool,
    hour0: usize,
    weekday0: usize,
    updated: usize,
    zone: [32]u8,
    zone_len: usize,
    htemp: [24]f32,
    hcode: [24]usize,
    hpop: [24]usize,
    dhigh: [7]f32,
    dlow: [7]f32,
    dcode: [7]usize,
    dpop: [7]usize,
    sunrise: [7]usize,
    sunset: [7]usize,
}

type State = struct {
    count: usize,
    place: usize,
    names: [64]u8,
    name_len: [4]usize,
    lat: [4]i32,
    lon: [4]i32,
    fc: [4]Forecast,
    fahrenheit: bool,
    weekday: usize,
    hour: usize,
    screen: usize,
    entry: ui.Field,
    found: usize,
    found_name: [80]u8,
    found_name_len: [5]usize,
    found_where: [120]u8,
    found_where_len: [5]usize,
    found_lat: [5]i32,
    found_lon: [5]i32,
    job: usize,
    job_place: usize,
    job_pick: usize,
    reason: usize,
    hits: ui.Hits,
    status: [72]u8,
    status_len: usize,
}

// ----------------------------------------------------------------------------------------------
// Text helpers.

fn set_text(into: []u8, at: usize, limit: usize, value: str) -> usize {
    var n = 0usize
    while n < value.len && n < limit {
        into[at + n] = value[n]
        n += 1usize
    }
    ret n
}

fn say_status(s: *State, line: str) {
    s.status_len = set_text(s.status[0usize..], 0usize, 72usize, line)
}

fn place_name(s: *State, p: usize) -> str {
    ret s.names[p * NAME_BYTES..p * NAME_BYTES + s.name_len[p]]
}

// "-3°" or "21°": a temperature in Celsius, shown in Fahrenheit when `fahrenheit`.
fn temp_text(a: *mem.Arena, celsius: f32, fahrenheit: bool) -> str {
    var v = celsius
    if fahrenheit { v = celsius * 1.8 + 32.0 }
    var sign = ""
    var magnitude = v
    if v < 0.0 {
        sign = "-"
        magnitude = 0.0 - v
    }
    ret ui.join(a, sign, ui.number(a, usize(magnitude + 0.5)), "\xC2\xB0")
}

fn hour_text(a: *mem.Arena, hour: usize) -> str {
    let h = hour % 24usize
    var h12 = h % 12usize
    if h12 == 0usize { h12 = 12usize }
    var suffix = " AM"
    if h >= 12usize { suffix = " PM" }
    ret ui.join(a, ui.number(a, h12), suffix, "")
}

// "6:41" for minute 401 of the day.
fn minute_text(a: *mem.Arena, minute: usize) -> str {
    ret ui.join(a, ui.number(a, minute / 60usize), ":", ui.two(a, minute % 60usize))
}

// 5991 as "59.91", -12233 as "-122.33".
fn centi_text(a: *mem.Arena, v: i32) -> str {
    var magnitude = 0usize
    var sign = ""
    let wide = i64(v)
    if wide < 0i64 {
        magnitude = usize(0i64 - wide)
        sign = "-"
    } else {
        magnitude = usize(wide)
    }
    ret ui.join(a, sign, ui.join(a, ui.number(a, magnitude / 100usize), ".", ""), ui.two(a, magnitude % 100usize))
}

fn digits_at(text_value: str, at: usize, n: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < n && at + i < text_value.len {
        let c = text_value[at + i]
        if c >= 48u8 && c <= 57u8 { v = v * 10usize + usize(c - 48u8) }
        i += 1usize
    }
    ret v
}

// The weekday (0 = Monday) of a calendar date.
fn weekday_of(year: usize, month: usize, day: usize) -> usize {
    var shifted = year
    if month <= 2usize { shifted = year - 1usize }
    let era = shifted / 400usize
    let yoe = shifted - era * 400usize
    var from_march = month + 9usize
    if month > 2usize { from_march = month - 3usize }
    let doy = (153usize * from_march + 2usize) / 5usize + day - 1usize
    let doe = yoe * 365usize + yoe / 4usize - yoe / 100usize + doy
    let days = era * 146097usize + doe - 719468usize
    ret (days + 3usize) % 7usize
}

// ----------------------------------------------------------------------------------------------
// The sample forecast: everything is a pure function of the place and the day.

fn cond_name(cond: usize) -> str {
    if cond == 0usize { ret "Sunny" }
    if cond == 1usize { ret "Partly cloudy" }
    if cond == 2usize { ret "Cloudy" }
    if cond == 3usize { ret "Rain" }
    if cond == 4usize { ret "Thunderstorms" }
    ret "Snow"
}

// The typical high of a sample place and how far its low sits below it.
fn base_high(place: usize) -> f32 {
    if place == 0usize { ret 14.0 }
    if place == 1usize { ret 33.0 }
    if place == 2usize { ret 22.0 }
    ret 2.0
}

fn base_range(place: usize) -> f32 {
    if place == 0usize { ret 6.0 }
    if place == 1usize { ret 13.0 }
    if place == 2usize { ret 8.0 }
    ret 5.0
}

fn mix(first: usize, second: usize) -> usize {
    var x = first * 7919usize + second * 104729usize + 12345usize
    x = (x * 1103515245usize + 12345usize) & 2147483647usize
    x = (x * 1103515245usize + 12345usize) & 2147483647usize
    ret x >> 8usize
}

// A repeatable number between -1 and 1.
fn noise(place: usize, day: usize, salt: usize) -> f32 {
    ret f32(mix(place * 100usize + day, salt) % 2001usize) / 1000.0 - 1.0
}

fn sample_high(place: usize, day: usize) -> f32 {
    ret base_high(place) + noise(place, day, 1usize) * 3.5
}

fn sample_low(place: usize, day: usize) -> f32 {
    ret sample_high(place, day) - base_range(place) - (noise(place, day, 2usize) + 1.0) * 1.5
}

fn sample_cond(place: usize, day: usize) -> usize {
    let r = mix(place * 100usize + day, 3usize) % 10usize
    var cond = 2usize
    if place == 0usize {
        if r < 2usize { cond = 0usize } else if r < 4usize { cond = 1usize } else if r < 6usize { cond = 2usize } else if r < 9usize { cond = 3usize } else { cond = 4usize }
    } else if place == 1usize {
        if r < 7usize { cond = 0usize } else if r < 9usize { cond = 1usize } else { cond = 2usize }
    } else if place == 2usize {
        if r < 3usize { cond = 0usize } else if r < 5usize { cond = 1usize } else if r < 7usize { cond = 2usize } else if r < 9usize { cond = 3usize } else { cond = 4usize }
    } else {
        if r < 1usize { cond = 0usize } else if r < 3usize { cond = 1usize } else if r < 6usize { cond = 2usize } else { cond = 5usize }
    }
    ret cond
}

// The temperature at `hour` (0..23) of day `day`: the low before sunrise, the high mid-afternoon.
fn sample_temp(place: usize, day: usize, hour: usize) -> f32 {
    let h = hour % 24usize
    var away = 0usize
    if h >= 15usize { away = h - 15usize } else { away = 15usize - h }
    if away > 12usize { away = 24usize - away }
    var warmth: f32 = 0.0
    if away < 9usize { warmth = 1.0 - f32(away) / 9.0 }
    let low = sample_low(place, day)
    ret low + (sample_high(place, day) - low) * warmth
}

fn sample_pop(cond: usize) -> usize {
    if cond == 0usize { ret 5usize }
    if cond == 1usize { ret 15usize }
    if cond == 2usize { ret 30usize }
    if cond == 3usize { ret 70usize }
    if cond == 4usize { ret 80usize }
    ret 60usize
}

// Is `hour` (0..23) between dusk and dawn?
fn is_night(hour: usize) -> bool {
    ret hour < 6usize || hour >= 20usize
}

// Slot `p`'s forecast as sample data, with the hours and weekdays of the clock (UTC).
fn fill_sample(s: *State, p: usize) {
    var f: Forecast = zero
    f.live = false
    f.hour0 = s.hour
    f.weekday0 = s.weekday
    f.code = sample_cond(p, 0usize)
    f.now_temp = sample_temp(p, 0usize, s.hour)
    f.humidity = 40usize + mix(p, 11usize) % 45usize
    f.wind = f32(6usize + mix(p, 12usize) % 22usize)
    f.feels = f.now_temp - f.wind / 15.0
    f.night = is_night(s.hour)
    var uv = 1usize
    if f.code == 0usize { uv = 7usize }
    if f.code == 1usize { uv = 5usize }
    if f.code == 2usize { uv = 3usize }
    if p == 3usize && uv > 2usize { uv -= 2usize }
    f.uv = uv
    var h = 0usize
    while h < HOURS {
        f.htemp[h] = sample_temp(p, 0usize, (s.hour + h) % 24usize)
        f.hcode[h] = f.code
        f.hpop[h] = sample_pop(f.code)
        h += 1usize
    }
    var d = 0usize
    while d < DAYS {
        f.dhigh[d] = sample_high(p, d)
        f.dlow[d] = sample_low(p, d)
        f.dcode[d] = sample_cond(p, d)
        f.dpop[d] = sample_pop(f.dcode[d])
        f.sunrise[d] = 390usize
        f.sunset[d] = 1170usize
        if p == 3usize {
            f.sunrise[d] = 450usize
            f.sunset[d] = 1050usize
        }
        d += 1usize
    }
    s.fc[p] = f
}

fn set_place(s: *State, p: usize, name: str, lat: i32, lon: i32) {
    s.name_len[p] = set_text(s.names[0usize..], p * NAME_BYTES, NAME_BYTES, name)
    s.lat[p] = lat
    s.lon[p] = lon
    fill_sample(s, p)
}

// ----------------------------------------------------------------------------------------------
// Live data: Open-Meteo.

fn member(members: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < members.len {
        if ui.same(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    var none: json.Value = zero
    ret (none, false)
}

fn object_of(members: []const json.Member, key: str) -> ([]const json.Member, bool) {
    let (v, found) = member(members, key)
    var none: []const json.Member = zero
    if !found { ret (none, false) }
    switch v {
    case .Object as inner:
        ret (inner, true)
    default:
        ret (none, false)
    }
}

fn array_of(members: []const json.Member, key: str) -> ([]const json.Value, bool) {
    let (v, found) = member(members, key)
    var none: []const json.Value = zero
    if !found { ret (none, false) }
    switch v {
    case .Array as inner:
        ret (inner, true)
    default:
        ret (none, false)
    }
}

fn number_of(v: json.Value) -> (f32, bool) {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok { ret (0.0, false) }
        ret (f32(x), true)
    default:
        ret (0.0, false)
    }
}

// A JSON number, or 0 when it is null or missing.
fn number_or_zero(v: json.Value) -> f32 {
    let (x, good) = number_of(v)
    if good { ret x }
    ret 0.0
}

fn string_of(v: json.Value) -> (str, bool) {
    switch v {
    case .String as t:
        ret (t, true)
    default:
        ret ("", false)
    }
}

// WMO weather code to the six sample conditions.
fn wmo_cond(code: usize) -> usize {
    if code == 0usize { ret 0usize }
    if code <= 2usize { ret 1usize }
    if code == 3usize || code == 45usize || code == 48usize { ret 2usize }
    if code >= 95usize { ret 4usize }
    if (code >= 71usize && code <= 77usize) || code == 85usize || code == 86usize { ret 5usize }
    if code >= 51usize { ret 3usize }
    ret 2usize
}

fn reason_text(reason: usize) -> str {
    if reason == 1usize { ret "no network" }
    if reason == 2usize { ret "server unreachable" }
    if reason == 3usize { ret "certificate refused" }
    if reason == 4usize { ret "bad reply" }
    if reason == 5usize { ret "no such place" }
    ret "failed"
}

fn reason_of(e: err) -> usize {
    if e == httpc.NoNetwork { ret 1usize }
    if e == httpc.Unreachable { ret 2usize }
    if e == httpc.TlsFailed { ret 3usize }
    ret 4usize
}

// One GET answered with a JSON document, or the reason in s.reason. The value lives in `a` above the caller's mark.
fn fetch_json(a: *mem.Arena, s: *State, host: str, path: str) -> (json.Value, bool) {
    var none: json.Value = zero
    let (reply, get_error) = httpc.get(a, host, path, "")
    if get_error != ok {
        s.reason = reason_of(get_error)
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

// Open-Meteo's forecast for a place into `f`: {"timezone": ..., "current": {...}, "hourly": {"time": [...], ...},
// "daily": {...}}, every time a local "2026-10-09T22:15".
fn read_forecast(fields: []const json.Member, f: *Forecast) -> bool {
    var zone_text = ""
    let (zone, has_zone) = member(fields, "timezone")
    if has_zone {
        let (named, named_ok) = string_of(zone)
        if named_ok { zone_text = named }
    }
    f.zone_len = set_text(f.zone[0usize..], 0usize, 32usize, zone_text)
    let (current, has_current) = object_of(fields, "current")
    let (hourly, has_hourly) = object_of(fields, "hourly")
    let (daily, has_daily) = object_of(fields, "daily")
    if !has_current || !has_hourly || !has_daily { ret false }
    let (now_time, has_now) = member(current, "time")
    if !has_now { ret false }
    let (stamp, stamp_ok) = string_of(now_time)
    if !stamp_ok || stamp.len < 16usize { ret false }
    f.updated = digits_at(stamp, 11usize, 2usize) * 60usize + digits_at(stamp, 14usize, 2usize)
    let (temperature, has_temperature) = member(current, "temperature_2m")
    let (feels, has_feels) = member(current, "apparent_temperature")
    let (humid, has_humid) = member(current, "relative_humidity_2m")
    let (code, has_code) = member(current, "weather_code")
    let (blow, has_blow) = member(current, "wind_speed_10m")
    let (index, has_index) = member(current, "uv_index")
    let (day_flag, has_day) = member(current, "is_day")
    if !has_temperature || !has_feels || !has_humid || !has_code || !has_blow || !has_index || !has_day { ret false }
    f.now_temp = number_or_zero(temperature)
    f.feels = number_or_zero(feels)
    f.humidity = usize(number_or_zero(humid) + 0.5)
    f.code = wmo_cond(usize(number_or_zero(code)))
    f.wind = number_or_zero(blow)
    f.uv = usize(number_or_zero(index) + 0.5)
    f.night = number_or_zero(day_flag) < 0.5
    let (h_time, has_h_time) = array_of(hourly, "time")
    let (h_temp, has_h_temp) = array_of(hourly, "temperature_2m")
    let (h_code, has_h_code) = array_of(hourly, "weather_code")
    let (h_pop, has_h_pop) = array_of(hourly, "precipitation_probability")
    if !has_h_time || !has_h_temp || !has_h_code || !has_h_pop { ret false }
    if h_time.len < HOURS || h_temp.len < HOURS || h_code.len < HOURS || h_pop.len < HOURS { ret false }
    let (first_hour, first_ok) = string_of(h_time[0usize])
    if !first_ok || first_hour.len < 13usize { ret false }
    f.hour0 = digits_at(first_hour, 11usize, 2usize)
    var h = 0usize
    while h < HOURS {
        f.htemp[h] = number_or_zero(h_temp[h])
        f.hcode[h] = wmo_cond(usize(number_or_zero(h_code[h])))
        f.hpop[h] = usize(number_or_zero(h_pop[h]) + 0.5)
        h += 1usize
    }
    let (d_time, has_d_time) = array_of(daily, "time")
    let (d_code, has_d_code) = array_of(daily, "weather_code")
    let (d_high, has_d_high) = array_of(daily, "temperature_2m_max")
    let (d_low, has_d_low) = array_of(daily, "temperature_2m_min")
    let (d_rise, has_d_rise) = array_of(daily, "sunrise")
    let (d_set, has_d_set) = array_of(daily, "sunset")
    let (d_pop, has_d_pop) = array_of(daily, "precipitation_probability_max")
    if !has_d_time || !has_d_code || !has_d_high || !has_d_low || !has_d_rise || !has_d_set || !has_d_pop { ret false }
    if d_time.len < DAYS || d_code.len < DAYS || d_high.len < DAYS || d_low.len < DAYS || d_rise.len < DAYS || d_set.len < DAYS || d_pop.len < DAYS { ret false }
    let (first_day, day_ok) = string_of(d_time[0usize])
    if !day_ok || first_day.len < 10usize { ret false }
    f.weekday0 = weekday_of(digits_at(first_day, 0usize, 4usize), digits_at(first_day, 5usize, 2usize), digits_at(first_day, 8usize, 2usize))
    var d = 0usize
    while d < DAYS {
        f.dhigh[d] = number_or_zero(d_high[d])
        f.dlow[d] = number_or_zero(d_low[d])
        f.dcode[d] = wmo_cond(usize(number_or_zero(d_code[d])))
        f.dpop[d] = usize(number_or_zero(d_pop[d]) + 0.5)
        let (rise, rise_ok) = string_of(d_rise[d])
        let (set, set_ok) = string_of(d_set[d])
        if !rise_ok || !set_ok || rise.len < 16usize || set.len < 16usize { ret false }
        f.sunrise[d] = digits_at(rise, 11usize, 2usize) * 60usize + digits_at(rise, 14usize, 2usize)
        f.sunset[d] = digits_at(set, 11usize, 2usize) * 60usize + digits_at(set, 14usize, 2usize)
        d += 1usize
    }
    f.live = true
    ret true
}

// The forecast of coordinates (lat, lon in hundredths of a degree) into slot `p`; false with s.reason on a failure.
fn fetch_forecast(a: *mem.Arena, s: *State, p: usize) -> bool {
    s.reason = 0usize
    let mark = mem.mark(a)
    var path = ui.join(a, "/v1/forecast?latitude=", centi_text(a, s.lat[p]), "&longitude=")
    path = ui.join(a, path, centi_text(a, s.lon[p]), "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,uv_index,is_day")
    path = ui.join(a, path, "&hourly=temperature_2m,weather_code,precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max", "")
    path = ui.join(a, path, "&timezone=auto&forecast_days=7&forecast_hours=24", "")
    let (parsed, fetched) = fetch_json(a, s, "api.open-meteo.com", path)
    if !fetched {
        mem.reset(a, mark)
        ret false
    }
    var good = false
    var fresh: Forecast = zero
    switch parsed {
    case .Object as fields:
        good = read_forecast(fields, &fresh)
    default:
        good = false
    }
    mem.reset(a, mark)
    if good {
        s.fc[p] = fresh
    } else {
        s.reason = 4usize
    }
    ret good
}

// Open-Meteo's geocoding search for the typed name: up to FOUND_MAX places, with where they are, in `found_*`.
fn search_places(a: *mem.Arena, s: *State) -> bool {
    s.found = 0usize
    s.reason = 0usize
    let mark = mem.mark(a)
    // Letters, digits, '-' and '.' go into the URL as they are, a space as %20.
    let (word, word_error) = mem.alloc[u8](a, s.entry.len * 3usize + 1usize)
    if word_error != ok { ret false }
    var n = 0usize
    var i = 0usize
    while i < s.entry.len {
        let c = s.entry.bytes[i]
        if (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 45u8 || c == 46u8 {
            word[n] = c
            n += 1usize
        } else if c == 32u8 {
            word[n] = 37u8
            word[n + 1usize] = 50u8
            word[n + 2usize] = 48u8
            n += 3usize
        }
        i += 1usize
    }
    let path = ui.join(a, "/v1/search?count=5&language=en&format=json&name=", word[0usize..n], "")
    let (parsed, fetched) = fetch_json(a, s, "geocoding-api.open-meteo.com", path)
    if !fetched {
        mem.reset(a, mark)
        ret false
    }
    switch parsed {
    case .Object as fields:
        let (results, has_results) = array_of(fields, "results")
        if has_results {
            var m = 0usize
            while m < results.len && s.found < FOUND_MAX {
                switch results[m] {
                case .Object as row:
                    let (name_value, got_name) = member(row, "name")
                    let (lat_value, got_lat) = member(row, "latitude")
                    let (lon_value, got_lon) = member(row, "longitude")
                    let (name_text, name_ok) = string_of(name_value)
                    let (lat_x, lat_ok) = number_of(lat_value)
                    let (lon_x, lon_ok) = number_of(lon_value)
                    if got_name && got_lat && got_lon && name_ok && lat_ok && lon_ok && name_text.len > 0usize {
                        var admin = ""
                        var country = ""
                        let (admin_value, got_admin) = member(row, "admin1")
                        if got_admin {
                            let (admin_text, admin_ok) = string_of(admin_value)
                            if admin_ok { admin = admin_text }
                        }
                        let (country_value, got_country) = member(row, "country")
                        if got_country {
                            let (country_text, country_ok) = string_of(country_value)
                            if country_ok { country = country_text }
                        }
                        var where_text = country
                        if admin.len > 0usize && country.len > 0usize { where_text = ui.join(a, admin, ", ", country) }
                        if admin.len > 0usize && country.len == 0usize { where_text = admin }
                        let k = s.found
                        s.found_name_len[k] = set_text(s.found_name[0usize..], k * NAME_BYTES, NAME_BYTES, name_text)
                        s.found_where_len[k] = set_text(s.found_where[0usize..], k * WHERE_BYTES, WHERE_BYTES, where_text)
                        s.found_lat[k] = round_centi(lat_x)
                        s.found_lon[k] = round_centi(lon_x)
                        s.found += 1usize
                    }
                default:
                    s.reason = 0usize
                }
                m += 1usize
            }
        }
    default:
        s.reason = 4usize
    }
    mem.reset(a, mark)
    ret s.reason == 0usize
}

// Degrees to hundredths of a degree, rounded.
fn round_centi(degrees: f32) -> i32 {
    let x = degrees * 100.0
    if x < 0.0 { ret 0i32 - i32(0.0 - x + 0.5) }
    ret i32(x + 0.5)
}

// ----------------------------------------------------------------------------------------------
// The places.

fn remove_place(s: *State, p: usize) {
    var q = p
    while q + 1usize < s.count {
        s.name_len[q] = s.name_len[q + 1usize]
        s.lat[q] = s.lat[q + 1usize]
        s.lon[q] = s.lon[q + 1usize]
        s.fc[q] = s.fc[q + 1usize]
        var n = 0usize
        while n < NAME_BYTES {
            s.names[q * NAME_BYTES + n] = s.names[(q + 1usize) * NAME_BYTES + n]
            n += 1usize
        }
        q += 1usize
    }
    s.count -= 1usize
    if s.place >= s.count { s.place = s.count - 1usize }
}

// One step of the running job, done on a tick.
fn job_step(a: *mem.Arena, s: *State) {
    if s.job == JOB_FETCH {
        s.job = JOB_NONE
        let p = s.job_place
        if p >= s.count { ret }
        if fetch_forecast(a, s, p) {
            say_status(s, ui.join(a, "Updated ", minute_text(a, s.fc[p].updated), ""))
            ui.say("weather live ")
            ui.say_text(place_name(s, p))
            ui.say(" ")
            ui.say_text(minute_text(a, s.fc[p].updated))
            ui.say("\n")
        } else {
            say_status(s, ui.join(a, "Sample data, not live (", reason_text(s.reason), ")"))
            ui.say("weather sample ")
            ui.say_text(place_name(s, p))
            ui.say(" ")
            ui.say_text(reason_text(s.reason))
            ui.say("\n")
        }
        ret
    }
    if s.job == JOB_SEARCH {
        s.job = JOB_NONE
        if search_places(a, s) {
            if s.found == 0usize { say_status(s, "No place has that name") } else { say_status(s, "Tap a place to add it") }
        } else {
            say_status(s, ui.join(a, "Search failed: ", reason_text(s.reason), ""))
        }
        ui.say("weather found ")
        ui.say_num(s.found)
        ui.say("\n")
        ret
    }
    if s.job == JOB_ADD {
        s.job = JOB_NONE
        let k = s.job_pick
        let p = s.count
        set_place(s, p, s.found_name[k * NAME_BYTES..k * NAME_BYTES + s.found_name_len[k]], s.found_lat[k], s.found_lon[k])
        if fetch_forecast(a, s, p) {
            s.count += 1usize
            s.place = p
            s.screen = MAIN_SCREEN
            say_status(s, ui.join(a, "Updated ", minute_text(a, s.fc[p].updated), ""))
            ui.say("weather added ")
            ui.say_text(place_name(s, p))
            ui.say("\n")
            ui.say("weather live ")
            ui.say_text(place_name(s, p))
            ui.say(" ")
            ui.say_text(minute_text(a, s.fc[p].updated))
            ui.say("\n")
        } else {
            say_status(s, ui.join(a, "No forecast for that place: ", reason_text(s.reason), ""))
            ui.say("weather add failed ")
            ui.say_text(reason_text(s.reason))
            ui.say("\n")
        }
        ret
    }
}

// ----------------------------------------------------------------------------------------------
// Drawing.

// A condition icon on a 48 x 48 grid: the sun in amber, the cloud pale on the dark ground and slate on
// the cream cards. `night` swaps a clear sky for a crescent.
fn weather_svg(a: *mem.Arena, cond: usize, dark: bool, night: bool) -> str {
    var sun = "#e49a1f"
    var cloud = "#7f8da3"
    if dark {
        sun = "#e0b36a"
        cloud = "#e8ebf0"
    }
    let head = "<svg viewBox='0 0 48 48'>"
    let cloud_path = ui.join(a, "<path d='M14 34 a8 8 0 0 1 -1 -16 a11 11 0 0 1 21 3 a7 7 0 0 1 0 13 z' fill='", cloud, "'/>")
    let high_cloud = ui.join(a, "<path d='M14 28 a8 8 0 0 1 -1 -16 a11 11 0 0 1 21 3 a7 7 0 0 1 0 13 z' fill='", cloud, "'/>")
    if cond == 0usize {
        if night { ret ui.join(a, head, ui.join(a, "<path d='M30 8 a16 16 0 1 0 10 28 a13 13 0 0 1 -10 -28 z' fill='", sun, "'/>"), "</svg>") }
        ret ui.join(a, head, ui.join(a, ui.join(a, "<circle cx='24' cy='24' r='9' fill='", sun, "'/><g stroke='"), ui.join(a, sun, "' stroke-width='3' stroke-linecap='round'><path d='M24 5v5M24 38v5M5 24h5M38 24h5M10.5 10.5l3.5 3.5M34 34l3.5 3.5M37.5 10.5L34 14M14 34l-3.5 3.5'/></g>", ""), ""), "</svg>")
    }
    if cond == 1usize { ret ui.join(a, head, ui.join(a, ui.join(a, "<circle cx='18' cy='17' r='8' fill='", sun, "'/>"), cloud_path, ""), "</svg>") }
    if cond == 2usize { ret ui.join(a, head, cloud_path, "</svg>") }
    if cond == 3usize { ret ui.join(a, head, ui.join(a, high_cloud, "<path d='M16 36l-2 6M25 36l-2 6M34 36l-2 6' stroke='#7ea6d6' stroke-width='3' stroke-linecap='round'/>", ""), "</svg>") }
    if cond == 4usize { ret ui.join(a, head, ui.join(a, high_cloud, ui.join(a, "<path d='M26 29l-6 9h5l-2 8 9-11h-6l3-6z' fill='", sun, "'/>"), ""), "</svg>") }
    ret ui.join(a, head, ui.join(a, high_cloud, "<g fill='#9db4d6'><circle cx='16' cy='38' r='2.4'/><circle cx='25' cy='41' r='2.4'/><circle cx='34' cy='38' r='2.4'/></g>", ""), "</svg>")
}

fn icon(a: *mem.Arena, builder: *scene.Builder, cond: usize, dark: bool, night: bool, x: f32, y: f32, size: f32) -> err {
    try svg.draw(a, builder, weather_svg(a, cond, dark, night), geometry.rect(x, y, size, size), ui.ink())
    ret ok
}

// Is `hour` dark at this place today: before sunrise or after sunset (a sample uses the fixed hours).
fn dark_at(f: *Forecast, hour: usize) -> bool {
    ret hour * 60usize < f.sunrise[0usize] || hour * 60usize >= f.sunset[0usize]
}

fn draw_main(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let place = s.place
    let f = s.fahrenheit
    let fc = &s.fc[place]
    // The places.
    var chip = 0usize
    while chip < s.count {
        var fill = ui.soft()
        if chip == place { fill = ui.amber() }
        let x: f32 = 16.0 + f32(chip) * 76.0
        try ui.card(a, builder, x, 24.0, 70.0, 34.0, 17.0, fill)
        try ui.centred(a, builder, faces.jost, 14.0, place_name(s, chip), x + 35.0, 24.0 + 17.0 - 9.0, ui.ink())
        ui.hit(&s.hits, ID_CHIP + chip, x, 24.0, 70.0, 34.0)
        chip += 1usize
    }
    try ui.pill(a, builder, &s.hits, faces, ID_ADD, 330.0, 24.0, 66.0, 34.0, "Add", ui.amber(), 14.0)
    // Now.
    try ui.put(a, builder, faces.jost_bold, 84.0, temp_text(a, fc.now_temp, f), 24.0, 70.0, ui.light())
    try ui.put(a, builder, faces.jost, 22.0, cond_name(fc.code), 28.0, 176.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 15.0, ui.join(a, ui.join(a, "H ", temp_text(a, fc.dhigh[0usize], f), "   L "), temp_text(a, fc.dlow[0usize], f), ""), 28.0, 212.0, ui.light_muted())
    try icon(a, builder, fc.code, true, fc.night, 268.0, 72.0, 128.0)
    var unit = "C"
    if f { unit = "F" }
    try ui.pill(a, builder, &s.hits, faces, ID_REMOVE, 224.0, 206.0, 84.0, 32.0, "Remove", ui.soft(), 14.0)
    try ui.pill(a, builder, &s.hits, faces, ID_UNIT, 316.0, 206.0, 80.0, 32.0, ui.join(a, "\xC2\xB0", unit, ""), ui.soft(), 15.0)
    // The next eight hours, each with its own condition and chance of rain.
    try ui.card(a, builder, 16.0, 250.0, 380.0, 118.0, 20.0, ui.cream())
    var col = 0usize
    while col < 8usize {
        let h = fc.hour0 + col
        let cx: f32 = 16.0 + 23.75 + f32(col) * 47.5
        var label = "Now"
        if col > 0usize { label = hour_text(a, h) }
        try ui.centred(a, builder, faces.grotesk, 11.0, label, cx, 260.0, ui.muted())
        try icon(a, builder, fc.hcode[col], false, dark_at(fc, h % 24usize) && fc.hcode[col] == 0usize, cx - 14.0, 276.0, 28.0)
        try ui.centred(a, builder, faces.jost, 16.0, temp_text(a, fc.htemp[col], f), cx, 312.0, ui.ink())
        if fc.hpop[col] > 0usize { try ui.centred(a, builder, faces.grotesk, 11.0, ui.join(a, ui.number(a, fc.hpop[col]), "%", ""), cx, 340.0, paint.Color { red: 0.27, green: 0.45, blue: 0.70, alpha: 1.0 }) }
        col += 1usize
    }
    // The seven days.
    try ui.card(a, builder, 16.0, 380.0, 380.0, 336.0, 20.0, ui.cream())
    var week_low = fc.dlow[0usize]
    var week_high = fc.dhigh[0usize]
    var d = 1usize
    while d < DAYS {
        if fc.dlow[d] < week_low { week_low = fc.dlow[d] }
        if fc.dhigh[d] > week_high { week_high = fc.dhigh[d] }
        d += 1usize
    }
    var span = week_high - week_low
    if span < 1.0 { span = 1.0 }
    d = 0usize
    while d < DAYS {
        let y: f32 = 392.0 + f32(d) * 46.0
        var name = "Today"
        if d > 0usize { name = ui.weekday_short((fc.weekday0 + d) % 7usize) }
        try ui.put(a, builder, faces.jost, 17.0, name, 32.0, y + 10.0, ui.ink())
        try icon(a, builder, fc.dcode[d], false, false, 108.0, y + 4.0, 32.0)
        try ui.put_right(a, builder, faces.jost, 16.0, temp_text(a, fc.dlow[d], f), 204.0, y + 11.0, ui.muted())
        let from: f32 = 216.0 + (fc.dlow[d] - week_low) / span * 108.0
        let to: f32 = 216.0 + (fc.dhigh[d] - week_low) / span * 108.0
        try ui.card(a, builder, 216.0, y + 17.0, 108.0, 5.0, 2.5, ui.soft())
        try ui.card(a, builder, from, y + 17.0, to - from + 5.0, 5.0, 2.5, ui.amber())
        try ui.put(a, builder, faces.jost, 16.0, temp_text(a, fc.dhigh[d], f), 338.0, y + 11.0, ui.ink())
        if fc.dpop[d] > 0usize { try ui.put_right(a, builder, faces.grotesk, 11.0, ui.join(a, ui.number(a, fc.dpop[d]), "%", ""), 388.0, y + 15.0, paint.Color { red: 0.27, green: 0.45, blue: 0.70, alpha: 1.0 }) }
        d += 1usize
    }
    // Feels like, humidity, wind and UV.
    try ui.card(a, builder, 16.0, 730.0, 380.0, 60.0, 20.0, ui.cream())
    var wind_text = ui.join(a, ui.number(a, usize(fc.wind + 0.5)), " km/h", "")
    if f { wind_text = ui.join(a, ui.number(a, usize(fc.wind * 0.621 + 0.5)), " mph", "") }
    var stat = 0usize
    while stat < 4usize {
        var label = "Feels like"
        var value = temp_text(a, fc.feels, f)
        if stat == 1usize {
            label = "Humidity"
            value = ui.join(a, ui.number(a, fc.humidity), "%", "")
        }
        if stat == 2usize {
            label = "Wind"
            value = wind_text
        }
        if stat == 3usize {
            label = "UV index"
            value = ui.number(a, fc.uv)
        }
        let cx: f32 = 16.0 + 47.5 + f32(stat) * 95.0
        try ui.centred(a, builder, faces.grotesk, 11.0, label, cx, 738.0, ui.muted())
        try ui.centred(a, builder, faces.jost, 17.0, value, cx, 756.0, ui.ink())
        stat += 1usize
    }
    // Sunrise, sunset and the chance of rain today.
    try ui.card(a, builder, 16.0, 798.0, 380.0, 60.0, 20.0, ui.cream())
    stat = 0usize
    while stat < 3usize {
        var label = "Sunrise"
        var value = minute_text(a, fc.sunrise[0usize])
        if stat == 1usize {
            label = "Sunset"
            value = minute_text(a, fc.sunset[0usize])
        }
        if stat == 2usize {
            label = "Rain today"
            value = ui.join(a, ui.number(a, fc.dpop[0usize]), "%", "")
        }
        let cx: f32 = 16.0 + 63.3 + f32(stat) * 126.7
        try ui.centred(a, builder, faces.grotesk, 11.0, label, cx, 806.0, ui.muted())
        try ui.centred(a, builder, faces.jost, 17.0, value, cx, 824.0, ui.ink())
        stat += 1usize
    }
    var line = "Sample data, not live"
    if fc.live { line = ui.join(a, ui.join(a, "Updated ", minute_text(a, fc.updated), ", "), fc.zone[0usize..fc.zone_len], "") }
    if !fc.live && s.status_len > 0usize { line = s.status[0usize..s.status_len] }
    try ui.centred(a, builder, faces.grotesk, 12.0, line, 206.0, 872.0, ui.light_muted())
    ret ok
}

fn draw_add(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Add place", 24.0, 36.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, ID_CANCEL, 300.0, 40.0, 96.0, 32.0, "Cancel", ui.soft(), 15.0)
    try ui.card(a, builder, 16.0, 96.0, 380.0, 56.0, 16.0, ui.cream())
    let shown = ui.field_text(a, &s.entry)
    if shown.len == 0usize {
        try ui.put(a, builder, faces.jost, 22.0, "City name", 32.0, 112.0, ui.muted())
    } else {
        try ui.put(a, builder, faces.jost, 22.0, shown, 32.0, 112.0, ui.ink())
    }
    if s.found > 0usize {
        var m = 0usize
        while m < s.found {
            let y: f32 = 170.0 + f32(m) * 54.0
            try ui.card(a, builder, 16.0, y, 380.0, 46.0, 14.0, ui.cream())
            try ui.put(a, builder, faces.jost_bold, 18.0, s.found_name[m * NAME_BYTES..m * NAME_BYTES + s.found_name_len[m]], 30.0, y + 5.0, ui.ink())
            try ui.clipped(a, builder, faces.grotesk, 12.0, s.found_where[m * WHERE_BYTES..m * WHERE_BYTES + s.found_where_len[m]], 30.0, y + 27.0, 340.0, ui.muted())
            ui.hit(&s.hits, ID_RESULT + m, 16.0, y, 380.0, 46.0)
            m += 1usize
        }
    } else {
        let (box_a, wrap_a) = ui.wrapped(a, builder, faces.grotesk, 13.0, "Type a city name and tap Search. A match becomes a place with its own forecast, in its own time zone.", 24.0, 176.0, 372.0, 4u32, ui.light_muted())
        if wrap_a != ok { ret wrap_a }
    }
    if s.status_len > 0usize { try ui.clipped(a, builder, faces.grotesk, 12.0, s.status[0usize..s.status_len], 24.0, 460.0, 372.0, ui.light_muted()) }
    try ui.keyboard(a, builder, &s.hits, faces, "Search")
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == MAIN_SCREEN { try draw_main(a, builder, s, faces) } else { try draw_add(a, builder, s, faces) }
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

// What a tap on button `id` did: true when the screen changed.
fn act(s: *State, id: usize) -> bool {
    // A pending forecast fetch is replaced by the next chip tap; a search or an add is let to finish.
    if s.job == JOB_SEARCH || s.job == JOB_ADD { ret false }
    if s.screen == ADD_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                if s.entry.len == 0usize {
                    say_status(s, "Type a city name first")
                    ret true
                }
                if s.count >= PLACES {
                    say_status(s, "The list is full: remove a place first")
                    ret true
                }
                s.job = JOB_SEARCH
                say_status(s, "Searching...")
                ret true
            }
            s.found = 0usize
            ret ui.field_key(&s.entry, id, false)
        }
        if id == ID_CANCEL {
            s.screen = MAIN_SCREEN
            s.status_len = 0usize
            ret true
        }
        if id >= ID_RESULT && id < ID_RESULT + s.found {
            s.job = JOB_ADD
            s.job_pick = id - ID_RESULT
            say_status(s, "Getting the forecast...")
            ret true
        }
        ret false
    }
    if id >= ID_CHIP && id < ID_CHIP + s.count {
        s.place = id - ID_CHIP
        ui.say("weather place ")
        ui.say_text(place_name(s, s.place))
        ui.say("\n")
        s.status_len = 0usize
        if !s.fc[s.place].live {
            s.job = JOB_FETCH
            s.job_place = s.place
        }
        ret true
    }
    if id == ID_UNIT {
        s.fahrenheit = !s.fahrenheit
        if s.fahrenheit { ui.say("weather unit F\n") } else { ui.say("weather unit C\n") }
        ret true
    }
    if id == ID_ADD {
        s.screen = ADD_SCREEN
        s.entry.len = 0usize
        s.found = 0usize
        s.status_len = 0usize
        ui.say("weather add sheet\n")
        ret true
    }
    if id == ID_REMOVE {
        if s.count <= 1usize { ret false }
        ui.say("weather removed ")
        ui.say_text(place_name(s, s.place))
        ui.say("\n")
        remove_place(s, s.place)
        s.status_len = 0usize
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "weather")
    if kit_error != ok {
        ui.say("weather open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("weather fonts absent\n")
        ret ok
    }
    var s: State = zero
    let (wall, wall_error) = time.now()
    if wall_error == ok {
        let seconds = usize(wall.nanos / 1000000000i64)
        s.hour = (seconds % 86400usize) / 3600usize
        // 1 January 1970 was a Thursday (3 with Monday as 0).
        s.weekday = (seconds / 86400usize + 3usize) % 7usize
    }
    s.count = PLACES
    set_place(&s, 0usize, "Seattle", 4761i32, 0i32 - 12233i32)
    set_place(&s, 1usize, "Cairo", 3004i32, 3124i32)
    set_place(&s, 2usize, "Tokyo", 3568i32, 13969i32)
    set_place(&s, 3usize, "Oslo", 5991i32, 1075i32)
    s.job = JOB_FETCH
    s.job_place = 0usize
    if !show(a, &kit, &s) {
        ui.say("weather present failed\n")
        ret ok
    }
    ui.say("weather shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            if s.job != JOB_NONE {
                job_step(a, &s)
                if !show(a, &kit, &s) {
                    ui.say("weather present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 && s.screen == MAIN_SCREEN {
            ui.say("weather home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    ui.say("weather present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
