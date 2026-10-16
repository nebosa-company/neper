// Date (browser tracker 5.9): time values in milliseconds, the spec's day/time algorithms, parsing of the ISO format and the
// `toString`/`toUTCString` formats, and the getters and setters. Local time is UTC (the host zone is not consulted yet).

use e.js.interp as js
use e.mem
use e.str
use e.time

fn ms_per_day() -> f64 { ret 86400000.0f64 }

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

fn fmod(x: f64, y: f64) -> f64 {
    var r = x - js.floor(x / y) * y
    if r < 0.0f64 { r = r + y }
    if r >= y { r = r - y }
    ret r
}

fn day_of(t: f64) -> f64 { ret js.floor(t / ms_per_day()) }
fn time_within_day(t: f64) -> f64 { ret fmod(t, ms_per_day()) }

fn days_in_year(y: f64) -> f64 {
    if fmod(y, 4.0f64) != 0.0f64 { ret 365.0f64 }
    if fmod(y, 100.0f64) != 0.0f64 { ret 366.0f64 }
    if fmod(y, 400.0f64) != 0.0f64 { ret 365.0f64 }
    ret 366.0f64
}

fn day_from_year(y: f64) -> f64 {
    ret 365.0f64 * (y - 1970.0f64) + js.floor((y - 1969.0f64) / 4.0f64) - js.floor((y - 1901.0f64) / 100.0f64) + js.floor((y - 1601.0f64) / 400.0f64)
}

fn time_from_year(y: f64) -> f64 { ret ms_per_day() * day_from_year(y) }

fn year_from_time(t: f64) -> f64 {
    var y = js.floor(t / (ms_per_day() * 365.2425f64)) + 1970.0f64
    while time_from_year(y) > t { y -= 1.0f64 }
    while time_from_year(y + 1.0f64) <= t { y += 1.0f64 }
    ret y
}

fn in_leap_year(t: f64) -> bool { ret days_in_year(year_from_time(t)) == 366.0f64 }

fn day_within_year(t: f64) -> f64 { ret day_of(t) - day_from_year(year_from_time(t)) }

fn month_start(m: i32, leap: bool) -> f64 {
    var starts: [13]f64 = zero
    starts[0usize] = 0.0f64
    starts[1usize] = 31.0f64
    starts[2usize] = 59.0f64
    starts[3usize] = 90.0f64
    starts[4usize] = 120.0f64
    starts[5usize] = 151.0f64
    starts[6usize] = 181.0f64
    starts[7usize] = 212.0f64
    starts[8usize] = 243.0f64
    starts[9usize] = 273.0f64
    starts[10usize] = 304.0f64
    starts[11usize] = 334.0f64
    starts[12usize] = 365.0f64
    var v = starts[usize(m)]
    if leap && m >= 2i32 { v += 1.0f64 }
    ret v
}

fn month_from_time(t: f64) -> f64 {
    let d = day_within_year(t)
    let leap = in_leap_year(t)
    var m = 0i32
    while m < 11i32 && d >= month_start(m + 1i32, leap) { m += 1i32 }
    ret f64(m)
}

fn date_from_time(t: f64) -> f64 {
    let d = day_within_year(t)
    let leap = in_leap_year(t)
    let m = i32(month_from_time(t))
    ret d - month_start(m, leap) + 1.0f64
}

fn week_day(t: f64) -> f64 { ret fmod(day_of(t) + 4.0f64, 7.0f64) }
fn hour_from_time(t: f64) -> f64 { ret fmod(js.floor(t / 3600000.0f64), 24.0f64) }
fn min_from_time(t: f64) -> f64 { ret fmod(js.floor(t / 60000.0f64), 60.0f64) }
fn sec_from_time(t: f64) -> f64 { ret fmod(js.floor(t / 1000.0f64), 60.0f64) }
fn ms_from_time(t: f64) -> f64 { ret fmod(t, 1000.0f64) }

fn make_time(hour: f64, min: f64, sec: f64, ms: f64) -> f64 {
    if !js.is_finite(hour) || !js.is_finite(min) || !js.is_finite(sec) || !js.is_finite(ms) { ret js.nan() }
    ret js.to_integer(hour) * 3600000.0f64 + js.to_integer(min) * 60000.0f64 + js.to_integer(sec) * 1000.0f64 + js.to_integer(ms)
}

fn make_day(year: f64, month: f64, date: f64) -> f64 {
    if !js.is_finite(year) || !js.is_finite(month) || !js.is_finite(date) { ret js.nan() }
    let y = js.to_integer(year)
    let m = js.to_integer(month)
    let dt = js.to_integer(date)
    let ym = y + js.floor(m / 12.0f64)
    if ym > 400000.0f64 || ym < -400000.0f64 { ret js.nan() }
    let mn = fmod(m, 12.0f64)
    let leap = days_in_year(ym) == 366.0f64
    let day = day_from_year(ym) + month_start(i32(mn), leap)
    ret day + dt - 1.0f64
}

fn make_date(day: f64, tms: f64) -> f64 {
    if !js.is_finite(day) || !js.is_finite(tms) { ret js.nan() }
    let tv = day * ms_per_day() + tms
    if !js.is_finite(tv) { ret js.nan() }
    ret tv
}

fn time_clip(t: f64) -> f64 {
    if !js.is_finite(t) { ret js.nan() }
    if t > 8.64e15f64 || t < -8.64e15f64 { ret js.nan() }
    let r = js.to_integer(t)
    if r == 0.0f64 { ret 0.0f64 }
    ret r
}

fn now_ms() -> f64 {
    let (t, te) = time.now()
    if te != ok { ret 0.0f64 }
    ret js.floor(f64(t.nanos) / 1000000.0f64)
}

fn this_time(it: *js.Interp, v: js.Value) -> (*js.Obj, err) {
    if js.is_object(v) && js.as_object(v).class == js.C_DATE { ret (js.as_object(v), ok) }
    ret (js.null_obj(), js.throw_type(it, "this is not a Date object."))
}

// --- parsing

fn digits(s: str, at: usize, n: usize) -> (f64, bool) {
    if at + n > s.len { ret (0.0f64, false) }
    var v = 0.0f64
    var i = 0usize
    while i < n {
        let c = s[at + i]
        if c < 48u8 || c > 57u8 { ret (0.0f64, false) }
        v = v * 10.0f64 + f64(c - 48u8)
        i += 1usize
    }
    ret (v, true)
}

fn parse_iso(s: str) -> f64 {
    var at = 0usize
    var sign = 1.0f64
    var year = 0.0f64
    var ok_y = false
    if s.len > 0usize && (s[0usize] == 43u8 || s[0usize] == 45u8) {
        if s[0usize] == 45u8 { sign = -1.0f64 }
        let (y6, g6) = digits(s, 1usize, 6usize)
        if !g6 { ret js.nan() }
        if sign < 0.0f64 && y6 == 0.0f64 { ret js.nan() }
        year = sign * y6
        at = 7usize
        ok_y = true
    } else {
        let (y4, g4) = digits(s, 0usize, 4usize)
        if !g4 { ret js.nan() }
        year = y4
        at = 4usize
        ok_y = true
    }
    var month = 1.0f64
    var day = 1.0f64
    if at < s.len && s[at] == 45u8 {
        let (m, gm) = digits(s, at + 1usize, 2usize)
        if !gm { ret js.nan() }
        month = m
        at += 3usize
        if at < s.len && s[at] == 45u8 {
            let (d, gd) = digits(s, at + 1usize, 2usize)
            if !gd { ret js.nan() }
            day = d
            at += 3usize
        }
    }
    var hour = 0.0f64
    var min = 0.0f64
    var sec = 0.0f64
    var ms = 0.0f64
    var tz = 0.0f64
    var has_time = false
    var has_tz = false
    if at < s.len && (s[at] == 84u8 || s[at] == 116u8 || s[at] == 32u8) {
        has_time = true
        let (h, gh) = digits(s, at + 1usize, 2usize)
        if !gh || at + 3usize >= s.len || s[at + 3usize] != 58u8 { ret js.nan() }
        let (mi, gmi) = digits(s, at + 4usize, 2usize)
        if !gmi { ret js.nan() }
        hour = h
        min = mi
        at += 6usize
        if at < s.len && s[at] == 58u8 {
            let (se, gse) = digits(s, at + 1usize, 2usize)
            if !gse { ret js.nan() }
            sec = se
            at += 3usize
            if at < s.len && (s[at] == 46u8 || s[at] == 44u8) {
                var n = 0usize
                var frac = 0.0f64
                var scale = 100.0f64
                at += 1usize
                while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 {
                    if n < 3usize {
                        frac += f64(s[at] - 48u8) * scale
                        scale = scale / 10.0f64
                    }
                    n += 1usize
                    at += 1usize
                }
                if n == 0usize { ret js.nan() }
                ms = js.floor(frac)
            }
        }
        if at < s.len && (s[at] == 90u8 || s[at] == 122u8) {
            has_tz = true
            at += 1usize
        } else if at < s.len && (s[at] == 43u8 || s[at] == 45u8) {
            has_tz = true
            var ts = 1.0f64
            if s[at] == 45u8 { ts = -1.0f64 }
            let (th, gth) = digits(s, at + 1usize, 2usize)
            if !gth || at + 3usize >= s.len || s[at + 3usize] != 58u8 { ret js.nan() }
            let (tm, gtm) = digits(s, at + 4usize, 2usize)
            if !gtm { ret js.nan() }
            tz = ts * (th * 60.0f64 + tm)
            at += 6usize
        }
    }
    if at != s.len { ret js.nan() }
    if month < 1.0f64 || month > 12.0f64 || day < 1.0f64 || day > 31.0f64 { ret js.nan() }
    if hour > 24.0f64 || min > 59.0f64 || sec > 59.0f64 { ret js.nan() }
    if hour == 24.0f64 && (min != 0.0f64 || sec != 0.0f64 || ms != 0.0f64) { ret js.nan() }
    // A day past the month's length is invalid.
    let dd = make_day(year, month - 1.0f64, day)
    let check = make_day(year, month - 1.0f64, 1.0f64)
    let leap = days_in_year(year) == 366.0f64
    let mi = i32(month - 1.0f64)
    var mlen = month_start(mi + 1i32, leap) - month_start(mi, leap)
    if day > mlen { ret js.nan() }
    var t = make_date(dd, make_time(hour, min, sec, ms))
    if has_tz { t = t - tz * 60000.0f64 }
    ret time_clip(t)
}

fn month_index(s: str) -> i32 {
    let names = "JanFebMarAprMayJunJulAugSepOctNovDec"
    var m = 0usize
    while m < 12usize {
        if str.eq(s, names[m * 3usize..m * 3usize + 3usize]) { ret i32(m) }
        m += 1usize
    }
    ret -1i32
}

// "Tue Mar 01 2022 10:20:30 GMT+0000 (UTC)" and "Tue, 01 Mar 2022 10:20:30 GMT".
fn parse_text(s: str) -> f64 {
    var toks: [10]str = zero
    var n = 0usize
    var i = 0usize
    while i < s.len && n < 10usize {
        while i < s.len && (s[i] == 32u8 || s[i] == 44u8) { i += 1usize }
        let start = i
        while i < s.len && s[i] != 32u8 && s[i] != 44u8 { i += 1usize }
        if i > start {
            toks[n] = s[start..i]
            n += 1usize
        }
    }
    if n < 4usize { ret js.nan() }
    var k = 1usize
    var month = -1i32
    var day = 0.0f64
    var year = 0.0f64
    // Either "Mon DD YYYY" or "DD Mon YYYY" after the weekday.
    let m1 = month_index(toks[k])
    if m1 >= 0i32 {
        month = m1
        let (d, gd) = digits(toks[k + 1usize], 0usize, toks[k + 1usize].len)
        if !gd { ret js.nan() }
        day = d
        let (y, gy) = digits(toks[k + 2usize], 0usize, toks[k + 2usize].len)
        if !gy { ret js.nan() }
        year = y
    } else {
        let (d2, gd2) = digits(toks[k], 0usize, toks[k].len)
        if !gd2 { ret js.nan() }
        day = d2
        month = month_index(toks[k + 1usize])
        if month < 0i32 { ret js.nan() }
        let (y2, gy2) = digits(toks[k + 2usize], 0usize, toks[k + 2usize].len)
        if !gy2 { ret js.nan() }
        year = y2
    }
    var hour = 0.0f64
    var min = 0.0f64
    var sec = 0.0f64
    if n > k + 3usize {
        let t = toks[k + 3usize]
        let (h, gh) = digits(t, 0usize, 2usize)
        let (mi, gmi) = digits(t, 3usize, 2usize)
        if !gh || !gmi { ret js.nan() }
        hour = h
        min = mi
        if t.len >= 8usize {
            let (se, gse) = digits(t, 6usize, 2usize)
            if !gse { ret js.nan() }
            sec = se
        }
    }
    var off = 0.0f64
    if n > k + 4usize {
        let z = toks[k + 4usize]
        if z.len >= 8usize && str.starts_with(z, "GMT") && (z[3usize] == 43u8 || z[3usize] == 45u8) {
            let (oh, goh) = digits(z, 4usize, 2usize)
            let (om, gom) = digits(z, 6usize, 2usize)
            if goh && gom {
                off = oh * 60.0f64 + om
                if z[3usize] == 45u8 { off = -off }
            }
        }
    }
    let t2 = make_date(make_day(year, f64(month), day), make_time(hour, min, sec, 0.0f64)) - off * 60000.0f64
    ret time_clip(t2)
}

fn parse_date(s_in: str) -> f64 {
    let s = js.trim_js(s_in)
    let iso = parse_iso(s)
    if !js.is_nan(iso) { ret iso }
    ret parse_text(s)
}

// --- formatting

fn pad(it: *js.Interp, v: f64, width: usize) -> str {
    let (b, be) = str.builder(it.a, 12usize)
    if be != ok { ret "" }
    var out = b
    var x = v
    var neg = false
    if x < 0.0f64 {
        neg = true
        x = -x
    }
    let digits_s = js.number_to_string(it.a, x)
    // number_to_string allocated above the builder start; rebuild after it.
    let (b2, be2) = str.builder(it.a, 16usize)
    if be2 != ok { ret "" }
    var o2 = b2
    if neg { let pn = str.push_byte(&o2, 45u8) }
    var z = digits_s.len
    while z < width {
        let pz = str.push_byte(&o2, 48u8)
        z += 1usize
    }
    let pd = str.push(&o2, digits_s)
    ret str.done(&o2)
}

fn day_name(t: f64) -> str {
    let names = "SunMonTueWedThuFriSat"
    let d = usize(i64(week_day(t)))
    ret names[d * 3usize..d * 3usize + 3usize]
}

fn month_name(t: f64) -> str {
    let names = "JanFebMarAprMayJunJulAugSepOctNovDec"
    let m = usize(i64(month_from_time(t)))
    ret names[m * 3usize..m * 3usize + 3usize]
}

fn date_string(it: *js.Interp, t: f64) -> str {
    let y = year_from_time(t)
    var ys = pad(it, y, 4usize)
    ret js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, day_name(t), " "), month_name(t)), " "), pad(it, date_from_time(t), 2usize)), js.str_concat(it, " ", ys))
}

fn time_string(it: *js.Interp, t: f64) -> str {
    let hms = js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, pad(it, hour_from_time(t), 2usize), ":"), pad(it, min_from_time(t), 2usize)), ":"), pad(it, sec_from_time(t), 2usize))
    ret js.str_concat(it, hms, " GMT+0000 (UTC)")
}

fn to_date_string_full(it: *js.Interp, t: f64) -> str {
    if js.is_nan(t) { ret "Invalid Date" }
    ret js.str_concat3(it, date_string(it, t), " ", time_string(it, t))
}

fn utc_string(it: *js.Interp, t: f64) -> str {
    if js.is_nan(t) { ret "Invalid Date" }
    let part1 = js.str_concat(it, js.str_concat(it, js.str_concat(it, day_name(t), ", "), pad(it, date_from_time(t), 2usize)), js.str_concat(it, " ", month_name(t)))
    let part2 = js.str_concat(it, js.str_concat(it, " ", pad(it, year_from_time(t), 4usize)), " ")
    let hms = js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, pad(it, hour_from_time(t), 2usize), ":"), pad(it, min_from_time(t), 2usize)), ":"), pad(it, sec_from_time(t), 2usize))
    ret js.str_concat(it, js.str_concat(it, js.str_concat(it, part1, part2), hms), " GMT")
}

fn iso_string(it: *js.Interp, t: f64) -> str {
    var y = year_from_time(t)
    var ys = ""
    if y >= 0.0f64 && y <= 9999.0f64 { ys = pad(it, y, 4usize) } else {
        var sgn = "+"
        if y < 0.0f64 {
            sgn = "-"
            y = -y
        }
        ys = js.str_concat(it, sgn, pad(it, y, 6usize))
    }
    let d = js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, ys, "-"), pad(it, month_from_time(t) + 1.0f64, 2usize)), "-"), pad(it, date_from_time(t), 2usize))
    let tm = js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, "T", pad(it, hour_from_time(t), 2usize)), ":"), pad(it, min_from_time(t), 2usize)), ":"), pad(it, sec_from_time(t), 2usize))
    ret js.str_concat(it, js.str_concat(it, js.str_concat(it, js.str_concat(it, d, tm), "."), pad(it, ms_from_time(t), 3usize)), "Z")
}

// --- constructor and statics

fn date_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !it.has_new_target { ret (js.str_value(to_date_string_full(it, now_ms())), ok) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, it.protos.date)
    if pe != ok { ret (js.undefv(), pe) }
    let o = js.new_obj(it, js.C_DATE, proto)
    var tv = js.nan()
    if args.len == 0usize {
        tv = now_ms()
    } else if args.len == 1usize {
        let v = args[0usize]
        if js.is_object(v) && js.as_object(v).class == js.C_DATE {
            tv = js.as_object(v).num
        } else {
            let (p, pre) = js.to_primitive(it, v, "default")
            if pre != ok { ret (js.undefv(), pre) }
            if js.is_string(p) {
                tv = parse_date(js.value_str(p))
            } else {
                let (n, ne) = js.to_number(it, p)
                if ne != ok { ret (js.undefv(), ne) }
                tv = time_clip(n)
            }
        }
    } else {
        var nums: [7]f64 = zero
        nums[2usize] = 1.0f64
        var i = 0usize
        while i < args.len && i < 7usize {
            let (n2, ne2) = js.to_number(it, args[i])
            if ne2 != ok { ret (js.undefv(), ne2) }
            nums[i] = n2
            i += 1usize
        }
        var y = nums[0usize]
        if !js.is_nan(y) {
            let yi = js.to_integer(y)
            if yi >= 0.0f64 && yi <= 99.0f64 { y = 1900.0f64 + yi }
        }
        tv = time_clip(make_date(make_day(y, nums[1usize], nums[2usize]), make_time(nums[3usize], nums[4usize], nums[5usize], nums[6usize])))
    }
    o.num = tv
    ret (js.obj_value(o), ok)
}

fn date_now(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (js.num_value(now_ms()), ok) }

fn date_parse_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    ret (js.num_value(parse_date(s)), ok)
}

fn date_utc(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var nums: [7]f64 = zero
    nums[2usize] = 1.0f64
    var i = 0usize
    while i < args.len && i < 7usize {
        let (n, ne) = js.to_number(it, args[i])
        if ne != ok { ret (js.undefv(), ne) }
        nums[i] = n
        i += 1usize
    }
    if args.len == 0usize { ret (js.num_value(js.nan()), ok) }
    var y = nums[0usize]
    if !js.is_nan(y) {
        let yi = js.to_integer(y)
        if yi >= 0.0f64 && yi <= 99.0f64 { y = 1900.0f64 + yi }
    }
    ret (js.num_value(time_clip(make_date(make_day(y, nums[1usize], nums[2usize]), make_time(nums[3usize], nums[4usize], nums[5usize], nums[6usize])))), ok)
}

// --- getters: kind selects the field.

fn getter(it: *js.Interp, this_val: js.Value, kind: u8) -> (js.Value, err) {
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let t = o.num
    if js.is_nan(t) { ret (js.num_value(js.nan()), ok) }
    var r = 0.0f64
    if kind == 0u8 { r = year_from_time(t) } else if kind == 1u8 { r = month_from_time(t) } else if kind == 2u8 { r = date_from_time(t) } else if kind == 3u8 { r = week_day(t) } else if kind == 4u8 { r = hour_from_time(t) } else if kind == 5u8 { r = min_from_time(t) } else if kind == 6u8 { r = sec_from_time(t) } else if kind == 7u8 { r = ms_from_time(t) } else if kind == 8u8 { r = t } else if kind == 9u8 { r = year_from_time(t) - 1900.0f64 } else if kind == 10u8 { r = 0.0f64 }
    ret (js.num_value(r), ok)
}

fn get_full_year(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 0u8)
    ret (r, e) }
fn get_month(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 1u8)
    ret (r, e) }
fn get_date(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 2u8)
    ret (r, e) }
fn get_day(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 3u8)
    ret (r, e) }
fn get_hours(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 4u8)
    ret (r, e) }
fn get_minutes(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 5u8)
    ret (r, e) }
fn get_seconds(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 6u8)
    ret (r, e) }
fn get_milliseconds(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 7u8)
    ret (r, e) }
fn get_time(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 8u8)
    ret (r, e) }
fn get_year(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 9u8)
    ret (r, e) }
fn get_timezone_offset(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = getter(it, this_val, 10u8)
    ret (r, e) }

// --- setters: apply new fields to the broken-down time.

fn setter(it: *js.Interp, this_val: js.Value, args: []const js.Value, first: u8, max_args: usize) -> (js.Value, err) {
    // first: 0 year(year, month, date), 1 month(month, date), 2 date(date), 3 hours(h, m, s, ms), 4 minutes(m, s, ms),
    // 5 seconds(s, ms), 6 milliseconds(ms).
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    var t = o.num
    var nums: [4]f64 = zero
    var count = 0usize
    var i = 0usize
    while i < args.len && i < max_args {
        let (n, ne) = js.to_number(it, args[i])
        if ne != ok { ret (js.undefv(), ne) }
        nums[i] = n
        count += 1usize
        i += 1usize
    }
    if args.len == 0usize { nums[0usize] = js.nan() }
    if js.is_nan(t) {
        if first != 0u8 { ret (js.num_value(js.nan()), ok) }
        t = 0.0f64
    }
    var year = year_from_time(t)
    var month = month_from_time(t)
    var date = date_from_time(t)
    var hour = hour_from_time(t)
    var min = min_from_time(t)
    var sec = sec_from_time(t)
    var ms = ms_from_time(t)
    if first == 0u8 {
        year = nums[0usize]
        if count > 1usize { month = nums[1usize] }
        if count > 2usize { date = nums[2usize] }
    } else if first == 1u8 {
        month = nums[0usize]
        if count > 1usize { date = nums[1usize] }
    } else if first == 2u8 {
        date = nums[0usize]
    } else if first == 3u8 {
        hour = nums[0usize]
        if count > 1usize { min = nums[1usize] }
        if count > 2usize { sec = nums[2usize] }
        if count > 3usize { ms = nums[3usize] }
    } else if first == 4u8 {
        min = nums[0usize]
        if count > 1usize { sec = nums[1usize] }
        if count > 2usize { ms = nums[2usize] }
    } else if first == 5u8 {
        sec = nums[0usize]
        if count > 1usize { ms = nums[1usize] }
    } else {
        ms = nums[0usize]
    }
    let nt = time_clip(make_date(make_day(year, month, date), make_time(hour, min, sec, ms)))
    o.num = nt
    ret (js.num_value(nt), ok)
}

fn set_full_year(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = setter(it, this_val, args, 0u8, 3usize)
    ret (r, e) }
fn set_month(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = setter(it, this_val, args, 1u8, 2usize)
    ret (r, e) }
fn set_date(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = setter(it, this_val, args, 2u8, 1usize)
    ret (r, e) }
fn set_hours(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = setter(it, this_val, args, 3u8, 4usize)
    ret (r, e) }
fn set_minutes(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = setter(it, this_val, args, 4u8, 3usize)
    ret (r, e) }
fn set_seconds(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = setter(it, this_val, args, 5u8, 2usize)
    ret (r, e) }
fn set_milliseconds(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = setter(it, this_val, args, 6u8, 1usize)
    ret (r, e) }

fn set_time(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    o.num = time_clip(n)
    ret (js.num_value(o.num), ok)
}

// --- string conversions

fn to_string_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.str_value(to_date_string_full(it, o.num)), ok)
}

fn to_date_string_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(o.num) { ret (js.str_value("Invalid Date"), ok) }
    ret (js.str_value(date_string(it, o.num)), ok)
}

fn to_time_string_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(o.num) { ret (js.str_value("Invalid Date"), ok) }
    ret (js.str_value(time_string(it, o.num)), ok)
}

fn to_utc_string_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.str_value(utc_string(it, o.num)), ok)
}

fn to_iso_string_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(o.num) { ret (js.undefv(), js.throw_range(it, "Invalid time value")) }
    ret (js.str_value(iso_string(it, o.num)), ok)
}

fn to_json_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (tv, te) = js.to_primitive(it, js.obj_value(o), "number")
    if te != ok { ret (js.undefv(), te) }
    if js.is_number(tv) && !js.is_finite(js.num_of(tv)) { ret (js.null_value(), ok) }
    let (f, fe) = js.get_prop(it, o, js.key_of("toISOString"), js.obj_value(o))
    if fe != ok { ret (js.undefv(), fe) }
    if !js.is_callable(f) { ret (js.undefv(), js.throw_type(it, "toISOString is not a function")) }
    let (r, re) = js.call_function(it, f, js.obj_value(o), js.zero_args())
    ret (r, re)
}

fn value_of_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, e) = this_time(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.num_value(o.num), ok)
}

fn to_primitive_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "Date.prototype[Symbol.toPrimitive] called on non-object")) }
    let hint = arg(args, 0usize)
    if !js.is_string(hint) { ret (js.undefv(), js.throw_type(it, "Invalid hint")) }
    let h = js.value_str(hint)
    var first = "valueOf"
    var second = "toString"
    if str.eq(h, "string") || str.eq(h, "default") {
        first = "toString"
        second = "valueOf"
    } else if !str.eq(h, "number") {
        ret (js.undefv(), js.throw_type(it, "Invalid hint"))
    }
    let o = js.as_object(this_val)
    let (m1, e1) = js.get_prop(it, o, js.key_of(first), this_val)
    if e1 != ok { ret (js.undefv(), e1) }
    if js.is_callable(m1) {
        let (r1, re1) = js.call_function(it, m1, this_val, js.zero_args())
        if re1 != ok { ret (js.undefv(), re1) }
        if !js.is_object(r1) { ret (r1, ok) }
    }
    let (m2, e2) = js.get_prop(it, o, js.key_of(second), this_val)
    if e2 != ok { ret (js.undefv(), e2) }
    if js.is_callable(m2) {
        let (r2, re2) = js.call_function(it, m2, this_val, js.zero_args())
        if re2 != ok { ret (js.undefv(), re2) }
        if !js.is_object(r2) { ret (r2, ok) }
    }
    ret (js.undefv(), js.throw_type(it, "Cannot convert object to primitive value"))
}

fn install_date(it: *js.Interp) {
    let proto = it.protos.date
    let ctor = js.make_native(it, "Date", 7u32, date_ctor)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("Date"), js.obj_value(ctor), js.P_HIDDEN)
    it.last = ctor
    js.add_method(it, it.last, "now", 0u32, date_now)
    js.add_method(it, it.last, "parse", 1u32, date_parse_fn)
    js.add_method(it, it.last, "UTC", 7u32, date_utc)
    js.add_method(it, it.protos.date, "getFullYear", 0u32, get_full_year)
    js.add_method(it, it.protos.date, "getUTCFullYear", 0u32, get_full_year)
    js.add_method(it, it.protos.date, "getMonth", 0u32, get_month)
    js.add_method(it, it.protos.date, "getUTCMonth", 0u32, get_month)
    js.add_method(it, it.protos.date, "getDate", 0u32, get_date)
    js.add_method(it, it.protos.date, "getUTCDate", 0u32, get_date)
    js.add_method(it, it.protos.date, "getDay", 0u32, get_day)
    js.add_method(it, it.protos.date, "getUTCDay", 0u32, get_day)
    js.add_method(it, it.protos.date, "getHours", 0u32, get_hours)
    js.add_method(it, it.protos.date, "getUTCHours", 0u32, get_hours)
    js.add_method(it, it.protos.date, "getMinutes", 0u32, get_minutes)
    js.add_method(it, it.protos.date, "getUTCMinutes", 0u32, get_minutes)
    js.add_method(it, it.protos.date, "getSeconds", 0u32, get_seconds)
    js.add_method(it, it.protos.date, "getUTCSeconds", 0u32, get_seconds)
    js.add_method(it, it.protos.date, "getMilliseconds", 0u32, get_milliseconds)
    js.add_method(it, it.protos.date, "getUTCMilliseconds", 0u32, get_milliseconds)
    js.add_method(it, it.protos.date, "getTime", 0u32, get_time)
    js.add_method(it, it.protos.date, "getYear", 0u32, get_year)
    js.add_method(it, it.protos.date, "getTimezoneOffset", 0u32, get_timezone_offset)
    js.add_method(it, it.protos.date, "setFullYear", 3u32, set_full_year)
    js.add_method(it, it.protos.date, "setUTCFullYear", 3u32, set_full_year)
    js.add_method(it, it.protos.date, "setMonth", 2u32, set_month)
    js.add_method(it, it.protos.date, "setUTCMonth", 2u32, set_month)
    js.add_method(it, it.protos.date, "setDate", 1u32, set_date)
    js.add_method(it, it.protos.date, "setUTCDate", 1u32, set_date)
    js.add_method(it, it.protos.date, "setHours", 4u32, set_hours)
    js.add_method(it, it.protos.date, "setUTCHours", 4u32, set_hours)
    js.add_method(it, it.protos.date, "setMinutes", 3u32, set_minutes)
    js.add_method(it, it.protos.date, "setUTCMinutes", 3u32, set_minutes)
    js.add_method(it, it.protos.date, "setSeconds", 2u32, set_seconds)
    js.add_method(it, it.protos.date, "setUTCSeconds", 2u32, set_seconds)
    js.add_method(it, it.protos.date, "setMilliseconds", 1u32, set_milliseconds)
    js.add_method(it, it.protos.date, "setUTCMilliseconds", 1u32, set_milliseconds)
    js.add_method(it, it.protos.date, "setTime", 1u32, set_time)
    js.add_method(it, it.protos.date, "toString", 0u32, to_string_m)
    js.add_method(it, it.protos.date, "toDateString", 0u32, to_date_string_m)
    js.add_method(it, it.protos.date, "toTimeString", 0u32, to_time_string_m)
    js.add_method(it, it.protos.date, "toLocaleString", 0u32, to_string_m)
    js.add_method(it, it.protos.date, "toLocaleDateString", 0u32, to_date_string_m)
    js.add_method(it, it.protos.date, "toLocaleTimeString", 0u32, to_time_string_m)
    js.add_method(it, it.protos.date, "toUTCString", 0u32, to_utc_string_m)
    js.add_method(it, it.protos.date, "toISOString", 0u32, to_iso_string_m)
    js.add_method(it, it.protos.date, "toJSON", 1u32, to_json_m)
    js.add_method(it, it.protos.date, "valueOf", 0u32, value_of_m)
    let (gv, gve) = js.get_prop(it, it.protos.date, js.key_of("toUTCString"), js.obj_value(it.protos.date))
    let e4 = js.define_data(it, it.protos.date, js.key_of("toGMTString"), gv, js.P_HIDDEN)
    let tp = js.make_native(it, "[Symbol.toPrimitive]", 1u32, to_primitive_m)
    let e5 = js.define_data(it, it.protos.date, js.key_of_symbol(it.sym_to_primitive), js.obj_value(tp), js.P_CONFIGURABLE)
}
