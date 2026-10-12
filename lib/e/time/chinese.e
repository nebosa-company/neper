// The Chinese lunisolar calendar over `e.time`'s day count (days from 1970-01-01), reckoned
// from astronomy the way the modern calendar is: a month starts on the day (in China
// Standard Time, UTC+8 from 1929 and Beijing local mean time, UTC+7:45:40, before) that
// holds a new moon; month 11 is the month that holds the winter solstice (sun at 270
// degrees); a year between two such months of 13 months has a leap month, the first one
// after month 11 that holds no major solar term (sun at a multiple of 30 degrees), and
// it repeats the number of the month before it.
//
// New moons are Meeus ch. 49 (full periodic terms and planetary corrections, to a few
// seconds), the sun's longitude is Meeus ch. 25 with the planetary and lunar terms, both
// in dynamical time and reduced to universal time with the Espenak and Meeus delta-T
// polynomials. Solar terms are read in UTC+8 for every year; new moons in Beijing mean
// time before 1929. The result is exact except when a new moon or a term falls within
// about ten minutes of midnight (1906 and 2057 disagree with the references).
//
// A `Date` carries the year as the Gregorian year its new year falls in (1984 is a
// Jiazi year), the month 1..12, whether it is the leap month of that number, and the day
// 1..30. Years 1900..2100 are served; outside them the answer is `OutOfRange`.

use e.math
use e.time

error OutOfRange

type Date = struct { year: i32, month: u8, leap: bool, day: u8 }

const FIRST_YEAR: i32 = 1900i32
const LAST_YEAR: i32 = 2100i32

fn sin_deg(deg: f64) -> f64 {
    ret math.sin64(deg * 0.017453292519943295f64)
}

fn cos_deg(deg: f64) -> f64 {
    ret math.cos64(deg * 0.017453292519943295f64)
}

// TD - UT in seconds for the year (Espenak and Meeus, 1900..2150).
fn delta_t(y: f64) -> f64 {
    if y < 1920.0f64 {
        let t = y - 1900.0f64
        ret -2.79f64 + 1.494119f64 * t - 0.0598939f64 * t * t + 0.0061966f64 * t * t * t - 0.000197f64 * t * t * t * t
    }
    if y < 1941.0f64 {
        let t = y - 1920.0f64
        ret 21.20f64 + 0.84493f64 * t - 0.076100f64 * t * t + 0.0020936f64 * t * t * t
    }
    if y < 1961.0f64 {
        let t = y - 1950.0f64
        ret 29.07f64 + 0.407f64 * t - t * t / 233.0f64 + t * t * t / 2547.0f64
    }
    if y < 1986.0f64 {
        let t = y - 1975.0f64
        ret 45.45f64 + 1.067f64 * t - t * t / 260.0f64 - t * t * t / 718.0f64
    }
    if y < 2005.0f64 {
        let t = y - 2000.0f64
        ret 63.86f64 + 0.3345f64 * t - 0.060374f64 * t * t + 0.0017275f64 * t * t * t + 0.000651814f64 * t * t * t * t + 0.00002373599f64 * t * t * t * t * t
    }
    if y < 2050.0f64 {
        let t = y - 2000.0f64
        ret 62.92f64 + 0.32217f64 * t + 0.005589f64 * t * t
    }
    let u = (y - 1820.0f64) / 100.0f64
    ret -20.0f64 + 32.0f64 * u * u - 0.5628f64 * (2150.0f64 - y)
}

// The year as a number, from a day count (universal time, days from 1970-01-01).
fn year_of(days: f64) -> f64 {
    ret 1970.0f64 + days / 365.2425f64
}

// The standard-time offset in days at that day count: UTC+8 from 1929-01-01, Beijing mean time before.
fn offset_days(days: f64) -> f64 {
    if days >= f64(time.days_from_civil(1929i64, 1i64, 1i64)) { ret 0.3333333333333333f64 }
    ret 0.32337962962962965f64
}

// The dynamical Julian day of lunation `k` (k = 0 is the new moon of 2000-01-06).
fn new_moon_jde(k: i64) -> f64 {
    let kk = f64(k)
    let t = kk / 1236.85f64
    let t2 = t * t
    let t3 = t2 * t
    let t4 = t3 * t
    let jde = 2451550.09766f64 + 29.530588861f64 * kk + 0.00015437f64 * t2 - 0.00000015f64 * t3 + 0.00000000073f64 * t4
    let e = 1.0f64 - 0.002516f64 * t - 0.0000074f64 * t2
    let ms = 2.5534f64 + 29.10535670f64 * kk - 0.0000014f64 * t2 - 0.00000011f64 * t3
    let mm = 201.5643f64 + 385.81693528f64 * kk + 0.0107582f64 * t2 + 0.00001238f64 * t3 - 0.000000058f64 * t4
    let f = 160.7108f64 + 390.67050284f64 * kk - 0.0016118f64 * t2 - 0.00000227f64 * t3 + 0.000000011f64 * t4
    let om = 124.7746f64 - 1.56375588f64 * kk + 0.0020672f64 * t2 + 0.00000215f64 * t3
    var c = -0.40720f64 * sin_deg(mm) + 0.17241f64 * e * sin_deg(ms) + 0.01608f64 * sin_deg(2.0f64 * mm)
    c += 0.01039f64 * sin_deg(2.0f64 * f) + 0.00739f64 * e * sin_deg(mm - ms) - 0.00514f64 * e * sin_deg(mm + ms)
    c += 0.00208f64 * e * e * sin_deg(2.0f64 * ms) - 0.00111f64 * sin_deg(mm - 2.0f64 * f) - 0.00057f64 * sin_deg(mm + 2.0f64 * f)
    c += 0.00056f64 * e * sin_deg(2.0f64 * mm + ms) - 0.00042f64 * sin_deg(3.0f64 * mm) + 0.00042f64 * e * sin_deg(ms + 2.0f64 * f)
    c += 0.00038f64 * e * sin_deg(ms - 2.0f64 * f) - 0.00024f64 * e * sin_deg(2.0f64 * mm - ms) - 0.00017f64 * sin_deg(om)
    c += -0.00007f64 * sin_deg(mm + 2.0f64 * ms) + 0.00004f64 * sin_deg(2.0f64 * mm - 2.0f64 * f) + 0.00004f64 * sin_deg(3.0f64 * ms)
    c += 0.00003f64 * sin_deg(mm + ms - 2.0f64 * f) + 0.00003f64 * sin_deg(2.0f64 * mm + 2.0f64 * f) - 0.00003f64 * sin_deg(mm + ms + 2.0f64 * f)
    c += 0.00003f64 * sin_deg(mm - ms + 2.0f64 * f) - 0.00002f64 * sin_deg(mm - ms - 2.0f64 * f) - 0.00002f64 * sin_deg(3.0f64 * mm + ms)
    c += 0.00002f64 * sin_deg(4.0f64 * mm)
    c += 0.000325f64 * sin_deg(299.77f64 + 0.107408f64 * kk - 0.009173f64 * t2) + 0.000165f64 * sin_deg(251.88f64 + 0.016321f64 * kk)
    c += 0.000164f64 * sin_deg(251.83f64 + 26.651886f64 * kk) + 0.000126f64 * sin_deg(349.42f64 + 36.412478f64 * kk)
    c += 0.000110f64 * sin_deg(84.66f64 + 18.206239f64 * kk) + 0.000062f64 * sin_deg(141.74f64 + 53.303771f64 * kk)
    c += 0.000060f64 * sin_deg(207.14f64 + 2.453732f64 * kk) + 0.000056f64 * sin_deg(154.84f64 + 7.306860f64 * kk)
    c += 0.000047f64 * sin_deg(34.52f64 + 27.261239f64 * kk) + 0.000042f64 * sin_deg(207.19f64 + 0.121824f64 * kk)
    c += 0.000040f64 * sin_deg(291.34f64 + 1.844379f64 * kk) + 0.000037f64 * sin_deg(161.72f64 + 24.198154f64 * kk)
    c += 0.000035f64 * sin_deg(239.56f64 + 25.513099f64 * kk) + 0.000023f64 * sin_deg(331.55f64 + 3.592518f64 * kk)
    ret jde + c
}

// The sun's apparent longitude in degrees [0, 360) at a dynamical Julian day.
fn sun_longitude(jde: f64) -> f64 {
    let t = (jde - 2451545.0f64) / 36525.0f64
    let l0 = 280.46646f64 + 36000.76983f64 * t + 0.0003032f64 * t * t
    let m = 357.52911f64 + 35999.05029f64 * t - 0.0001537f64 * t * t
    let c = (1.914602f64 - 0.004817f64 * t - 0.000014f64 * t * t) * sin_deg(m) + (0.019993f64 - 0.000101f64 * t) * sin_deg(2.0f64 * m) + 0.000289f64 * sin_deg(3.0f64 * m)
    let pert = 0.00134f64 * cos_deg(153.23f64 + 22518.7541f64 * t) + 0.00154f64 * cos_deg(216.57f64 + 45037.5082f64 * t) + 0.00200f64 * cos_deg(312.69f64 + 32964.3577f64 * t) + 0.00179f64 * sin_deg(350.74f64 + 445267.1142f64 * t - 0.00144f64 * t * t) + 0.00178f64 * sin_deg(231.19f64 + 20.20f64 * t)
    let lon = l0 + c + pert - 0.00569f64 - 0.00478f64 * sin_deg(125.04f64 - 1934.136f64 * t)
    ret lon - 360.0f64 * math.floor[f64](lon / 360.0f64)
}

// The day (count from 1970-01-01, standard time) that holds new moon `k`.
fn new_moon_day(k: i64) -> i64 {
    let jde = new_moon_jde(k)
    let ut = jde - 2440587.5f64
    let corrected = ut - delta_t(year_of(ut)) / 86400.0f64
    ret i64(math.floor[f64](corrected + offset_days(corrected)))
}

// The sun's longitude at the start (midnight, standard time) of a day.
fn longitude_at_start(day: i64) -> f64 {
    // UTC+8 throughout: the published calendars of 1900..1928 put their leap months by it (1917, 1922).
    let ut = f64(day) - 0.3333333333333333f64
    ret sun_longitude(ut + delta_t(year_of(ut)) / 86400.0f64 + 2440587.5f64)
}

// The lunation nearest a day.
fn lunation_near(day: i64) -> i64 {
    ret i64(math.floor[f64]((f64(day) + 2440587.5f64 - 2451550.09766f64) / 29.530588861f64 + 0.5f64))
}

// The lunation of month 11 of the year that starts in December of `y`: the month that holds the solstice.
fn solstice_lunation(y: i64) -> i64 {
    let k0 = lunation_near(time.days_from_civil(y, 12i64, 21i64))
    var k = k0 - 2i64
    while k <= k0 + 2i64 {
        if longitude_at_start(new_moon_day(k)) < 270.0f64 && longitude_at_start(new_moon_day(k + 1i64)) >= 270.0f64 { ret k }
        k += 1i64
    }
    ret k0
}

// Whether the month between two new-moon days holds a major solar term.
fn has_term(first: i64, next_first: i64) -> bool {
    ret math.floor[f64](longitude_at_start(first) / 30.0f64) != math.floor[f64](longitude_at_start(next_first) / 30.0f64)
}

// In a 13-month year starting at lunation `k0` the index (1..12) of its leap month, else 0.
fn leap_index(k0: i64, months: i64) -> i64 {
    if months != 13i64 { ret 0i64 }
    var i = 1i64
    while i <= 12i64 {
        if !has_term(new_moon_day(k0 + i), new_moon_day(k0 + i + 1i64)) { ret i }
        i += 1i64
    }
    ret 0i64
}

// The month number of the month at index `i` from month 11.
fn number_at(i: i64, leap_i: i64) -> i64 {
    var j = i
    if leap_i != 0i64 && i >= leap_i { j = i - 1i64 }
    ret (10i64 + j) - ((10i64 + j) / 12i64) * 12i64 + 1i64
}

// The Chinese year of the month at index `i` in the year that starts in December of `y`.
fn year_at(y: i64, i: i64, leap_i: i64) -> i64 {
    if number_at(i, leap_i) >= 11i64 { ret y }
    ret y + 1i64
}

fn in_range(year: i64) -> bool {
    ret year >= i64(FIRST_YEAR) && year <= i64(LAST_YEAR)
}

fn from_days(count: i64) -> (Date, err) {
    let blank = Date{ year: 0i32, month: 0u8, leap: false, day: 0u8 }
    let (civil_year, civil_month, civil_day) = time.civil_from_days(count)
    if civil_year < i64(FIRST_YEAR) || civil_year > i64(LAST_YEAR) + 1i64 { ret (blank, OutOfRange) }
    var y = civil_year
    if new_moon_day(solstice_lunation(y)) > count { y = y - 1i64 }
    let k0 = solstice_lunation(y)
    let k1 = solstice_lunation(y + 1i64)
    let leap_i = leap_index(k0, k1 - k0)
    var i = 0i64
    while i < k1 - k0 - 1i64 && new_moon_day(k0 + i + 1i64) <= count { i += 1i64 }
    let start = new_moon_day(k0 + i)
    if count < start || !in_range(year_at(y, i, leap_i)) { ret (blank, OutOfRange) }
    let number = number_at(i, leap_i)
    ret (Date{ year: i32(year_at(y, i, leap_i)), month: u8(number), leap: leap_i != 0i64 && i == leap_i, day: u8(count - start + 1i64) }, ok)
}

fn to_days(date: Date) -> (i64, err) {
    if !in_range(i64(date.year)) { ret (0i64, OutOfRange) }
    if date.month < 1u8 || date.month > 12u8 || date.day < 1u8 || date.day > 30u8 { ret (0i64, OutOfRange) }
    var y = i64(date.year) - 1i64
    if date.month >= 11u8 { y = i64(date.year) }
    let k0 = solstice_lunation(y)
    let k1 = solstice_lunation(y + 1i64)
    let leap_i = leap_index(k0, k1 - k0)
    var i = 0i64
    while i < k1 - k0 {
        let leap_here = leap_i != 0i64 && i == leap_i
        if number_at(i, leap_i) == i64(date.month) && leap_here == date.leap {
            let start = new_moon_day(k0 + i)
            if i64(date.day) > new_moon_day(k0 + i + 1i64) - start { ret (0i64, OutOfRange) }
            ret (start + i64(date.day) - 1i64, ok)
        }
        i += 1i64
    }
    ret (0i64, OutOfRange)
}

// The day count of the new year (month 1, day 1) of a Chinese year.
fn new_year(year: i32) -> (i64, err) {
    let (days, e) = to_days(Date{ year: year, month: 1u8, leap: false, day: 1u8 })
    ret (days, e)
}

// The number of the leap month of a Chinese year, 0 when it has none.
fn leap_month(year: i32) -> u8 {
    var y = i64(year) - 1i64
    while y <= i64(year) {
        let k0 = solstice_lunation(y)
        let k1 = solstice_lunation(y + 1i64)
        let leap_i = leap_index(k0, k1 - k0)
        if leap_i != 0i64 && year_at(y, leap_i, leap_i) == i64(year) { ret u8(number_at(leap_i, leap_i)) }
        y += 1i64
    }
    ret 0u8
}

// The length of a month, 29 or 30.
fn month_length(year: i32, month: u8, leap: bool) -> (u8, err) {
    let (first, first_e) = to_days(Date{ year: year, month: month, leap: leap, day: 1u8 })
    if first_e != ok { ret (0u8, first_e) }
    let (civil_year, civil_month, civil_day) = time.civil_from_days(first)
    let k = lunation_near(first)
    var found = k - 1i64
    while found <= k + 1i64 {
        if new_moon_day(found) == first { ret (u8(new_moon_day(found + 1i64) - first), ok) }
        found += 1i64
    }
    ret (0u8, OutOfRange)
}

// The sexagenary stem (0 Jia .. 9 Gui) and branch (0 Zi .. 11 Hai) of a Chinese year.
fn stem_branch(year: i32) -> (u8, u8) {
    let n = i64(year) - 4i64
    ret (u8(time.floor_mod(n, 10i64)), u8(time.floor_mod(n, 12i64)))
}
