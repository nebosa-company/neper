// `e.tz`: the builtin database against Python's zoneinfo (tzdata 2025c, reference.py
// beside this fixture builds the pack) -- offsets, daylight flags, abbreviations and
// local times from the transition block and from the footer rule, at both edges of
// a US change, in the southern hemisphere, with a half-hour DST, a 5:45 offset and a
// pre-1900 local mean time; `resolve` unique, ambiguous and in a gap; `load` refusing
// a bad pack and `zone` a missing name. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.time
use e.tz

fn check(z: tz.Zone, seconds: i64, offset: i32, daylight: bool, abbreviation: str, date: str, code: i32) {
    let instant = time.Timestamp { nanos: seconds * 1000000000i64 }
    let got = tz.offset_at(z, instant)
    if got.seconds != offset || got.daylight != daylight || !str.eq(got.abbreviation, abbreviation) { os.exit(code) }
    let local = tz.to_local(z, instant)
    var text: [19]u8 = zero
    var year = i64(local.date.year)
    var i = 3usize
    while true {
        text[i] = u8(48i64 + year % 10i64)
        year = year / 10i64
        if i == 0usize { break }
        i -= 1usize
    }
    text[4] = 45u8
    text[5] = 48u8 + local.date.month / 10u8
    text[6] = 48u8 + local.date.month % 10u8
    text[7] = 45u8
    text[8] = 48u8 + local.date.day / 10u8
    text[9] = 48u8 + local.date.day % 10u8
    text[10] = 32u8
    text[11] = 48u8 + local.time.hour / 10u8
    text[12] = 48u8 + local.time.hour % 10u8
    text[13] = 58u8
    text[14] = 48u8 + local.time.minute / 10u8
    text[15] = 48u8 + local.time.minute % 10u8
    text[16] = 58u8
    text[17] = 48u8 + local.time.second / 10u8
    text[18] = 48u8 + local.time.second % 10u8
    if !str.eq(text[0..], date) { os.exit(code + 1) }
}

fn zone_of(db: *const tz.Database, name: str, code: i32) -> tz.Zone {
    let (z, zone_error) = tz.zone(db, name)
    if zone_error != ok { os.exit(code) }
    ret z
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (db, e1) = tz.builtin(a)
    if e1 != ok { os.exit(1) }
    if !str.eq(tz.version(&db), "2025c") { os.exit(2) }
    if tz.names(&db).len != 13usize || !str.eq(tz.names(&db)[2], "Europe/Sofia") { os.exit(3) }
    let sofia = zone_of(&db, "Europe/Sofia", 4)
    check(sofia, 1719835200i64, 10800i32, true, "EEST", "2024-07-01 15:00:00", 10)
    check(sofia, 1705320000i64, 7200i32, false, "EET", "2024-01-15 14:00:00", 12)
    check(sofia, 489067200i64, 10800i32, true, "EEST", "1985-07-01 15:00:00", 14)
    let new_york = zone_of(&db, "America/New_York", 5)
    check(new_york, 1741503599i64, -18000i32, false, "EST", "2025-03-09 01:59:59", 16)
    check(new_york, 1741503600i64, -14400i32, true, "EDT", "2025-03-09 03:00:00", 18)
    check(new_york, 1762063199i64, -14400i32, true, "EDT", "2025-11-02 01:59:59", 20)
    check(new_york, 1762063200i64, -18000i32, false, "EST", "2025-11-02 01:00:00", 22)
    let sydney = zone_of(&db, "Australia/Sydney", 6)
    check(sydney, 1894233600i64, 39600i32, true, "AEDT", "2030-01-10 11:00:00", 24)
    check(sydney, 1909872000i64, 36000i32, false, "AEST", "2030-07-10 10:00:00", 26)
    let lord_howe = zone_of(&db, "Australia/Lord_Howe", 7)
    check(lord_howe, 1767225600i64, 39600i32, true, "+11", "2026-01-01 11:00:00", 28)
    check(lord_howe, 1782864000i64, 37800i32, false, "+1030", "2026-07-01 10:30:00", 30)
    let kathmandu = zone_of(&db, "Asia/Kathmandu", 8)
    check(kathmandu, 1767225600i64, 20700i32, false, "+0545", "2026-01-01 05:45:00", 32)
    let kolkata = zone_of(&db, "Asia/Kolkata", 9)
    check(kolkata, -2208988800i64, 19270i32, false, "MMT", "1900-01-01 05:21:10", 34)
    let london = zone_of(&db, "Europe/London", 9)
    check(london, 13046400i64, 3600i32, false, "BST", "1970-06-01 01:00:00", 36)
    check(london, -3786825600i64, 0i32, false, "GMT", "1850-01-01 00:00:00", 38)
    let utc = zone_of(&db, "UTC", 9)
    check(utc, 946684800i64, 0i32, false, "UTC", "2000-01-01 00:00:00", 40)
    let auckland = zone_of(&db, "Pacific/Auckland", 9)
    check(auckland, 1829692800i64, 46800i32, true, "NZDT", "2027-12-25 13:00:00", 42)
    let sao_paulo = zone_of(&db, "America/Sao_Paulo", 9)
    check(sao_paulo, 1767225600i64, -10800i32, false, "-03", "2025-12-31 21:00:00", 44)
    // Resolve.
    let ambiguous = tz.Local { date: time.Date { year: 2024, month: 10u8, day: 27u8 }, time: time.Time { hour: 3u8, minute: 30u8, second: 0u8, nanos: 0u32 } }
    let (r1, e2) = tz.resolve(sofia, ambiguous)
    if e2 != ok { os.exit(50) }
    switch r1 {
    case .Ambiguous as pair:
        if pair[0].nanos != 1729989000i64 * 1000000000i64 || pair[1].nanos != 1729992600i64 * 1000000000i64 { os.exit(51) }
    default:
        os.exit(52)
    }
    let unique = tz.Local { date: time.Date { year: 2024, month: 6u8, day: 1u8 }, time: time.Time { hour: 12u8, minute: 0u8, second: 0u8, nanos: 0u32 } }
    let (r2, e3) = tz.resolve(sofia, unique)
    if e3 != ok { os.exit(53) }
    switch r2 {
    case .Unique as instant:
        if instant.nanos != 1717232400i64 * 1000000000i64 { os.exit(54) }
    default:
        os.exit(55)
    }
    let missing = tz.Local { date: time.Date { year: 2024, month: 3u8, day: 31u8 }, time: time.Time { hour: 3u8, minute: 30u8, second: 0u8, nanos: 0u32 } }
    let (r3, e4) = tz.resolve(sofia, missing)
    if e4 != ok { os.exit(56) }
    switch r3 {
    case .Missing as edges:
        if edges[1].nanos != 1711846800i64 * 1000000000i64 || edges[0].nanos != edges[1].nanos - 1i64 { os.exit(57) }
    default:
        os.exit(58)
    }
    let (r4, e5) = tz.resolve(utc, unique)
    if e5 != ok { os.exit(59) }
    switch r4 {
    case .Unique as instant:
        if instant.nanos != 1717243200i64 * 1000000000i64 { os.exit(60) }
    default:
        os.exit(61)
    }
    // Refusals.
    let (none, e6) = tz.zone(&db, "Mars/Olympus")
    if e6 != tz.NotFound { os.exit(62) }
    let (bad, e7) = tz.load(a, "not a pack at all")
    if e7 != tz.InvalidData { os.exit(63) }
    let (bad2, e8) = tz.load(a, "NPTZ\x05\x002025c\x01\x00\x00\x00\x03\x00UTC\x04\x00\x00\x00junk")
    if e8 != tz.InvalidData { os.exit(64) }
    ret ok
}
