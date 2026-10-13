// The scripted battery (C176): what a power-supply driver would read from the fuel gauge, until the Pixel's is behind
// the same call. A day with a charger: unplugged and full at 07:00, one percent less every ten minutes until 23:00
// (4%), then on the charger, one percent more every five minutes, full again at 07:00. It is a function of the wall
// clock's time of day, so a boot that pins the guest clock (NEPEROS_RTC) sees a known level and a known change, and
// a boot that does not sees whatever time it is. The background services process reads it once a second and tells
// the status service when the level or the charging state changed.
const DAY: usize = 86400usize
const UNPLUGGED_AT: usize = 25200usize
const PLUGGED_AT: usize = 82800usize
const SECONDS_PER_PERCENT_DOWN: usize = 600usize
const SECONDS_PER_PERCENT_UP: usize = 300usize
const LOW: usize = 15usize
const CRITICAL: usize = 5usize

// The level (0 to 100) and whether the charger is in, at `day_seconds` of the day.
fn level_at(day_seconds: usize) -> (usize, bool) {
    let t = day_seconds % DAY
    if t >= UNPLUGGED_AT && t < PLUGGED_AT {
        ret (100usize - (t - UNPLUGGED_AT) / SECONDS_PER_PERCENT_DOWN, false)
    }
    var since = 0usize
    if t >= PLUGGED_AT { since = t - PLUGGED_AT } else { since = t + DAY - PLUGGED_AT }
    let level = 4usize + since / SECONDS_PER_PERCENT_UP
    if level >= 100usize { ret (100usize, false) }
    ret (level, true)
}
