// The world clock's city rules (neperos/src/zones.e) against Python's zoneinfo (written by
// scripts/gen_zones_test.py): every city in January and July 2026, and the second before and after each
// 2026 transition of the cities with daylight time. Every check has its own exit code.
use e.os
use e.mem
use zones

fn main(a: *mem.Arena, args: []str) -> err {
    if zones.offset_minutes(0usize, 1768478400i64) != 0i64 { os.exit(1) }
    if zones.offset_minutes(0usize, 1784116800i64) != 0i64 { os.exit(2) }
    if zones.offset_minutes(1usize, 1768478400i64) != 0i64 { os.exit(3) }
    if zones.offset_minutes(1usize, 1784116800i64) != 60i64 { os.exit(4) }
    if zones.offset_minutes(1usize, 1774745999i64) != 0i64 { os.exit(5) }
    if zones.offset_minutes(1usize, 1774746000i64) != 60i64 { os.exit(6) }
    if zones.offset_minutes(1usize, 1792889999i64) != 60i64 { os.exit(7) }
    if zones.offset_minutes(1usize, 1792890000i64) != 0i64 { os.exit(8) }
    if zones.offset_minutes(2usize, 1768478400i64) != 60i64 { os.exit(9) }
    if zones.offset_minutes(2usize, 1784116800i64) != 120i64 { os.exit(10) }
    if zones.offset_minutes(2usize, 1774745999i64) != 60i64 { os.exit(11) }
    if zones.offset_minutes(2usize, 1774746000i64) != 120i64 { os.exit(12) }
    if zones.offset_minutes(2usize, 1792889999i64) != 120i64 { os.exit(13) }
    if zones.offset_minutes(2usize, 1792890000i64) != 60i64 { os.exit(14) }
    if zones.offset_minutes(3usize, 1768478400i64) != 120i64 { os.exit(15) }
    if zones.offset_minutes(3usize, 1784116800i64) != 180i64 { os.exit(16) }
    if zones.offset_minutes(3usize, 1776981599i64) != 120i64 { os.exit(17) }
    if zones.offset_minutes(3usize, 1776981600i64) != 180i64 { os.exit(18) }
    if zones.offset_minutes(3usize, 1793307599i64) != 180i64 { os.exit(19) }
    if zones.offset_minutes(3usize, 1793307600i64) != 120i64 { os.exit(20) }
    if zones.offset_minutes(4usize, 1768478400i64) != 180i64 { os.exit(21) }
    if zones.offset_minutes(4usize, 1784116800i64) != 180i64 { os.exit(22) }
    if zones.offset_minutes(5usize, 1768478400i64) != 240i64 { os.exit(23) }
    if zones.offset_minutes(5usize, 1784116800i64) != 240i64 { os.exit(24) }
    if zones.offset_minutes(6usize, 1768478400i64) != 330i64 { os.exit(25) }
    if zones.offset_minutes(6usize, 1784116800i64) != 330i64 { os.exit(26) }
    if zones.offset_minutes(7usize, 1768478400i64) != 480i64 { os.exit(27) }
    if zones.offset_minutes(7usize, 1784116800i64) != 480i64 { os.exit(28) }
    if zones.offset_minutes(8usize, 1768478400i64) != 540i64 { os.exit(29) }
    if zones.offset_minutes(8usize, 1784116800i64) != 540i64 { os.exit(30) }
    if zones.offset_minutes(9usize, 1768478400i64) != 660i64 { os.exit(31) }
    if zones.offset_minutes(9usize, 1784116800i64) != 600i64 { os.exit(32) }
    if zones.offset_minutes(9usize, 1775318399i64) != 660i64 { os.exit(33) }
    if zones.offset_minutes(9usize, 1775318400i64) != 600i64 { os.exit(34) }
    if zones.offset_minutes(9usize, 1791043199i64) != 600i64 { os.exit(35) }
    if zones.offset_minutes(9usize, 1791043200i64) != 660i64 { os.exit(36) }
    if zones.offset_minutes(10usize, 1768478400i64) != 780i64 { os.exit(37) }
    if zones.offset_minutes(10usize, 1784116800i64) != 720i64 { os.exit(38) }
    if zones.offset_minutes(10usize, 1775311199i64) != 780i64 { os.exit(39) }
    if zones.offset_minutes(10usize, 1775311200i64) != 720i64 { os.exit(40) }
    if zones.offset_minutes(10usize, 1790431199i64) != 720i64 { os.exit(41) }
    if zones.offset_minutes(10usize, 1790431200i64) != 780i64 { os.exit(42) }
    if zones.offset_minutes(11usize, 1768478400i64) != 0i64 - 600i64 { os.exit(43) }
    if zones.offset_minutes(11usize, 1784116800i64) != 0i64 - 600i64 { os.exit(44) }
    if zones.offset_minutes(12usize, 1768478400i64) != 0i64 - 480i64 { os.exit(45) }
    if zones.offset_minutes(12usize, 1784116800i64) != 0i64 - 420i64 { os.exit(46) }
    if zones.offset_minutes(12usize, 1772963999i64) != 0i64 - 480i64 { os.exit(47) }
    if zones.offset_minutes(12usize, 1772964000i64) != 0i64 - 420i64 { os.exit(48) }
    if zones.offset_minutes(12usize, 1793523599i64) != 0i64 - 420i64 { os.exit(49) }
    if zones.offset_minutes(12usize, 1793523600i64) != 0i64 - 480i64 { os.exit(50) }
    if zones.offset_minutes(13usize, 1768478400i64) != 0i64 - 360i64 { os.exit(51) }
    if zones.offset_minutes(13usize, 1784116800i64) != 0i64 - 300i64 { os.exit(52) }
    if zones.offset_minutes(13usize, 1772956799i64) != 0i64 - 360i64 { os.exit(53) }
    if zones.offset_minutes(13usize, 1772956800i64) != 0i64 - 300i64 { os.exit(54) }
    if zones.offset_minutes(13usize, 1793516399i64) != 0i64 - 300i64 { os.exit(55) }
    if zones.offset_minutes(13usize, 1793516400i64) != 0i64 - 360i64 { os.exit(56) }
    if zones.offset_minutes(14usize, 1768478400i64) != 0i64 - 300i64 { os.exit(57) }
    if zones.offset_minutes(14usize, 1784116800i64) != 0i64 - 240i64 { os.exit(58) }
    if zones.offset_minutes(14usize, 1772953199i64) != 0i64 - 300i64 { os.exit(59) }
    if zones.offset_minutes(14usize, 1772953200i64) != 0i64 - 240i64 { os.exit(60) }
    if zones.offset_minutes(14usize, 1793512799i64) != 0i64 - 240i64 { os.exit(61) }
    if zones.offset_minutes(14usize, 1793512800i64) != 0i64 - 300i64 { os.exit(62) }
    if zones.offset_minutes(15usize, 1768478400i64) != 0i64 - 180i64 { os.exit(63) }
    if zones.offset_minutes(15usize, 1784116800i64) != 0i64 - 180i64 { os.exit(64) }
    ret ok
}
