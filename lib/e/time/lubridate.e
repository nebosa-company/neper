// R lubridate and timeDate, the date part, on the day count of `e.time` (days since 1970-01-01): Easter
// (timeDate::Easter), month arithmetic with the two month-end rules (`%m+%` and `add_with_rollback` clamp to the last
// day; `roll_to_first` moves to the first day of the next month), `quarter`,
// `semester`, `decimal_date`, `epiweek` and `epiyear` (weeks from Sunday, week 1 holds at least four days of the
// year), `isoweek` and `isoyear`, and `floor_date` / `ceiling_date` of a date to a week (any week start), month,
// quarter, semester or year.
//
// Not here: parse_date_time and its order heuristic, periods and durations, intervals, time zones, the financial
// holiday calendars, isBizday, timeNthNdayInMonth, date-times.

use e.time

fn civil(count: i64) -> (i64, i64, i64) {
    let (y, m, d) = time.civil_from_days(count)
    ret (y, m, d)
}

fn leap(y: i64) -> bool { ret time.is_leap(y) }

fn month_days(y: i64, m: i64) -> i64 {
    if m == 2i64 {
        if leap(y) { ret 29i64 }
        ret 28i64
    }
    if m == 4i64 || m == 6i64 || m == 9i64 || m == 11i64 { ret 30i64 }
    ret 31i64
}

// the Gregorian Easter Sunday of a year (anonymous algorithm)
fn easter(y: i64) -> i64 {
    let a = y % 19i64
    let b = y / 100i64
    let c = y % 100i64
    let d = b / 4i64
    let e = b % 4i64
    let f = (b + 8i64) / 25i64
    let g = (b - f + 1i64) / 3i64
    let h = (19i64 * a + b - d - g + 15i64) % 30i64
    let i = c / 4i64
    let k = c % 4i64
    let l = (32i64 + 2i64 * e + 2i64 * i - h - k) % 7i64
    let m = (a + 11i64 * h + 22i64 * l) / 451i64
    let month = (h + l - 7i64 * m + 114i64) / 31i64
    let day = (h + l - 7i64 * m + 114i64) % 31i64 + 1i64
    ret time.days_from_civil(y, month, day)
}

// mode 0 `%m+%` and add_with_rollback (clamp to the month's last day), 2 add_with_rollback with roll_to_first
fn add_months(count: i64, months: i64, mode: u8) -> i64 {
    let (y, m, d) = civil(count)
    let total = y * 12i64 + (m - 1i64) + months
    let ny = time.floor_div(total, 12i64)
    let nm = time.floor_mod(total, 12i64) + 1i64
    let len = month_days(ny, nm)
    if d <= len { ret time.days_from_civil(ny, nm, d) }
    if mode == 2u8 { ret time.days_from_civil(ny, nm, len) + 1i64 }
    ret time.days_from_civil(ny, nm, len)
}

fn quarter(count: i64) -> i64 {
    let (_, m, _) = civil(count)
    ret (m - 1i64) / 3i64 + 1i64
}

fn semester(count: i64) -> i64 {
    let (_, m, _) = civil(count)
    ret (m - 1i64) / 6i64 + 1i64
}

fn decimal_date(count: i64) -> f64 {
    let (y, _, _) = civil(count)
    let first = time.days_from_civil(y, 1i64, 1i64)
    var n = 365.0f64
    if leap(y) { n = 366.0f64 }
    ret f64(y) + f64(count - first) / n
}

// Sunday = 0
fn sunday_index(count: i64) -> i64 { ret time.floor_mod(count + 4i64, 7i64) }

// the Sunday that starts epi-week 1 of year y
fn epi_start(y: i64) -> i64 {
    let jan1 = time.days_from_civil(y, 1i64, 1i64)
    let wd = sunday_index(jan1)
    if wd <= 3i64 { ret jan1 - wd }
    ret jan1 - wd + 7i64
}

fn epiyear(count: i64) -> i64 {
    let (y, _, _) = civil(count)
    if count < epi_start(y) { ret y - 1i64 }
    if count >= epi_start(y + 1i64) { ret y + 1i64 }
    ret y
}

fn epiweek(count: i64) -> i64 { ret (count - epi_start(epiyear(count))) / 7i64 + 1i64 }

// ISO week-year and week: the year of the Thursday of the week
fn isoyear(count: i64) -> i64 {
    let mon = time.floor_mod(count + 3i64, 7i64)
    let (y, _, _) = civil(count - mon + 3i64)
    ret y
}

fn isoweek(count: i64) -> i64 {
    let mon = time.floor_mod(count + 3i64, 7i64)
    let thursday = count - mon + 3i64
    let (y, _, _) = civil(thursday)
    ret (thursday - time.days_from_civil(y, 1i64, 1i64)) / 7i64 + 1i64
}

// unit 0 week (week_start 1 = Monday .. 7 = Sunday), 1 month, 2 quarter, 3 semester, 4 year
fn floor_date(count: i64, unit: u8, week_start: i64) -> i64 {
    if unit == 0u8 {
        let mon = time.floor_mod(count + 3i64, 7i64)
        ret count - time.floor_mod(mon - (week_start - 1i64), 7i64)
    }
    let (y, m, _) = civil(count)
    if unit == 1u8 { ret time.days_from_civil(y, m, 1i64) }
    if unit == 2u8 { ret time.days_from_civil(y, (m - 1i64) / 3i64 * 3i64 + 1i64, 1i64) }
    if unit == 3u8 { ret time.days_from_civil(y, (m - 1i64) / 6i64 * 6i64 + 1i64, 1i64) }
    ret time.days_from_civil(y, 1i64, 1i64)
}

// the next unit boundary strictly after the floor, unless the date already is one (change_on_boundary = FALSE)
fn ceiling_date(count: i64, unit: u8, week_start: i64) -> i64 {
    let f = floor_date(count, unit, week_start)
    if f == count { ret count }
    if unit == 0u8 { ret f + 7i64 }
    var step = 12i64
    if unit == 1u8 { step = 1i64 }
    if unit == 2u8 { step = 3i64 }
    if unit == 3u8 { step = 6i64 }
    ret add_months(f, step, 0u8)
}
