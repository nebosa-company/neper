// The world clock's cities with their daylight-saving rules (C146): each city is a POSIX TZ rule -- its standard
// time, its summer time and the two Mm.w.d transitions -- parsed by e.tz, so the offset follows the instant: a
// city in summer time is an hour further on, across the transition and in either hemisphere. Cities without
// daylight time are the plain rule. The rules are the IANA ones as of 2026.
use e.tz as tz

fn rule_text(city: usize) -> str {
    if city == 0usize { ret "UTC0" }
    if city == 1usize { ret "GMT0BST,M3.5.0/1,M10.5.0" }
    if city == 2usize { ret "CET-1CEST,M3.5.0,M10.5.0/3" }
    if city == 3usize { ret "EET-2EEST,M4.5.5/0,M10.5.4/24" }
    if city == 4usize { ret "MSK-3" }
    if city == 5usize { ret "GST-4" }
    if city == 6usize { ret "IST-5:30" }
    if city == 7usize { ret "SGT-8" }
    if city == 8usize { ret "JST-9" }
    if city == 9usize { ret "AEST-10AEDT,M10.1.0,M4.1.0/3" }
    if city == 10usize { ret "NZST-12NZDT,M9.5.0,M4.1.0/3" }
    if city == 11usize { ret "HST10" }
    if city == 12usize { ret "PST8PDT,M3.2.0,M11.1.0" }
    if city == 13usize { ret "CST6CDT,M3.2.0,M11.1.0" }
    if city == 14usize { ret "EST5EDT,M3.2.0,M11.1.0" }
    ret "BRT3"
}

// The city's offset from UTC, in minutes, at `utc_seconds` since the epoch.
fn offset_minutes(city: usize, utc_seconds: i64) -> i64 {
    let (rule, parsed) = tz.parse_rule(rule_text(city))
    if !parsed { ret 0i64 }
    let offset = tz.rule_offset(rule, utc_seconds)
    ret i64(offset.seconds) / 60i64
}

// Whether the city is on summer time at `utc_seconds`.
fn in_daylight(city: usize, utc_seconds: i64) -> bool {
    let (rule, parsed) = tz.parse_rule(rule_text(city))
    if !parsed { ret false }
    let offset = tz.rule_offset(rule, utc_seconds)
    ret offset.daylight
}
