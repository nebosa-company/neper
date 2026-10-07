// The lock screen's date and the Moon's phase, from the wall clock (D2204): the civil month and day of
// a Unix time, and the Moon's age, illumination and phase name from the mean synodic month counted
// from the new moon of 6 January 2000 18:14 UTC. The mean month is good to about a day, which is all
// a "waning gibbous, 93% illuminated" line needs.
use e.math

// The civil month (0 = January) and day of month (1-based) of `seconds` since the Unix epoch
// (Howard Hinnant's days-to-civil).
fn month_day(seconds: usize) -> (usize, usize) {
    let z = i64(seconds / 86400usize) + 719468i64
    let era = z / 146097i64
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    let day = doy - (153i64 * mp + 2i64) / 5i64 + 1i64
    var month = mp + 3i64
    if month > 12i64 { month = month - 12i64 }
    ret (usize(month) - 1usize, usize(day))
}

fn month_name(month: usize) -> str {
    if month == 0usize { ret "January" }
    if month == 1usize { ret "February" }
    if month == 2usize { ret "March" }
    if month == 3usize { ret "April" }
    if month == 4usize { ret "May" }
    if month == 5usize { ret "June" }
    if month == 6usize { ret "July" }
    if month == 7usize { ret "August" }
    if month == 8usize { ret "September" }
    if month == 9usize { ret "October" }
    if month == 10usize { ret "November" }
    ret "December"
}

// The Moon's age in days (0 at new moon) and its illuminated percentage.
fn moon_age(seconds: usize) -> f32 {
    let since = f64(seconds) - 947182440.0f64
    let days = since / 86400.0f64
    let months = days / 29.530588853f64
    let fraction = months - f64(i64(months))
    var age = fraction * 29.530588853f64
    if age < 0.0f64 { age = age + 29.530588853f64 }
    ret f32(age)
}

fn moon_percent(age: f32) -> usize {
    let angle = 6.2831855 * age / 29.530589
    let lit = (1.0 - math.cos[f32](angle)) / 2.0
    ret usize(lit * 100.0 + 0.5)
}

fn moon_phase(age: f32) -> str {
    if age < 1.85 { ret "New Moon" }
    if age < 5.54 { ret "Waxing Crescent" }
    if age < 9.22 { ret "First Quarter" }
    if age < 12.91 { ret "Waxing Gibbous" }
    if age < 16.61 { ret "Full Moon" }
    if age < 20.30 { ret "Waning Gibbous" }
    if age < 23.99 { ret "Last Quarter" }
    if age < 27.68 { ret "Waning Crescent" }
    ret "New Moon"
}
