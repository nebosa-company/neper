// `e.time.calendars` Coptic and Ethiopic against convertdate (scripts/gen_african_calendars_test.py): the date
// of 550 day counts, the count of each date back, month lengths and leap years. Every check has its own exit code.
use e.os
use e.mem
use e.time
use e.time.calendars as calendars

fn expect(cal: calendars.Calendar, days: i64, year: i32, month: u8, day: u8) -> bool {
    let (date, e) = calendars.from_days(cal, days)
    if e != ok || date.year != year || date.month != month || date.day != day { ret false }
    let (back, be) = calendars.to_days(cal, date)
    ret be == ok && back == days
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !expect(.Coptic, 95161i64, 1946i32, 11u8, 9u8) { os.exit(1) }
    if !expect(.Ethiopic, 95161i64, 2222i32, 11u8, 9u8) { os.exit(2) }
    if !expect(.Coptic, 0i64 - 340880i64, 753i32, 1u8, 11u8) { os.exit(3) }
    if !expect(.Ethiopic, 0i64 - 340880i64, 1029i32, 1u8, 11u8) { os.exit(4) }
    if !expect(.Coptic, 0i64 - 128589i64, 1334i32, 4u8, 2u8) { os.exit(5) }
    if !expect(.Ethiopic, 0i64 - 128589i64, 1610i32, 4u8, 2u8) { os.exit(6) }
    if !expect(.Coptic, 0i64 - 401975i64, 585i32, 10u8, 8u8) { os.exit(7) }
    if !expect(.Ethiopic, 0i64 - 401975i64, 861i32, 10u8, 8u8) { os.exit(8) }
    if !expect(.Coptic, 0i64 - 517425i64, 269i32, 9u8, 7u8) { os.exit(9) }
    if !expect(.Ethiopic, 0i64 - 517425i64, 545i32, 9u8, 7u8) { os.exit(10) }
    if !expect(.Coptic, 69254i64, 1875i32, 12u8, 5u8) { os.exit(11) }
    if !expect(.Ethiopic, 69254i64, 2151i32, 12u8, 5u8) { os.exit(12) }
    if !expect(.Coptic, 267952i64, 2419i32, 12u8, 7u8) { os.exit(13) }
    if !expect(.Ethiopic, 267952i64, 2695i32, 12u8, 7u8) { os.exit(14) }
    if !expect(.Coptic, 284620i64, 2465i32, 7u8, 23u8) { os.exit(15) }
    if !expect(.Ethiopic, 284620i64, 2741i32, 7u8, 23u8) { os.exit(16) }
    if !expect(.Coptic, 201487i64, 2237i32, 12u8, 17u8) { os.exit(17) }
    if !expect(.Ethiopic, 201487i64, 2513i32, 12u8, 17u8) { os.exit(18) }
    if !expect(.Coptic, 0i64 - 278016i64, 925i32, 2u8, 22u8) { os.exit(19) }
    if !expect(.Ethiopic, 0i64 - 278016i64, 1201i32, 2u8, 22u8) { os.exit(20) }
    if !expect(.Coptic, 277442i64, 2445i32, 11u8, 30u8) { os.exit(21) }
    if !expect(.Ethiopic, 277442i64, 2721i32, 11u8, 30u8) { os.exit(22) }
    if !expect(.Coptic, 0i64 - 246832i64, 1010i32, 7u8, 10u8) { os.exit(23) }
    if !expect(.Ethiopic, 0i64 - 246832i64, 1286i32, 7u8, 10u8) { os.exit(24) }
    if !expect(.Coptic, 147935i64, 2091i32, 5u8, 2u8) { os.exit(25) }
    if !expect(.Ethiopic, 147935i64, 2367i32, 5u8, 2u8) { os.exit(26) }
    if !expect(.Coptic, 117611i64, 2008i32, 4u8, 23u8) { os.exit(27) }
    if !expect(.Ethiopic, 117611i64, 2284i32, 4u8, 23u8) { os.exit(28) }
    if !expect(.Coptic, 0i64 - 301672i64, 860i32, 5u8, 17u8) { os.exit(29) }
    if !expect(.Ethiopic, 0i64 - 301672i64, 1136i32, 5u8, 17u8) { os.exit(30) }
    if !expect(.Coptic, 246349i64, 2360i32, 10u8, 13u8) { os.exit(31) }
    if !expect(.Ethiopic, 246349i64, 2636i32, 10u8, 13u8) { os.exit(32) }
    if !expect(.Coptic, 0i64 - 572089i64, 120i32, 1u8, 5u8) { os.exit(33) }
    if !expect(.Ethiopic, 0i64 - 572089i64, 396i32, 1u8, 5u8) { os.exit(34) }
    if !expect(.Coptic, 0i64 - 322951i64, 802i32, 2u8, 13u8) { os.exit(35) }
    if !expect(.Ethiopic, 0i64 - 322951i64, 1078i32, 2u8, 13u8) { os.exit(36) }
    if !expect(.Coptic, 0i64 - 187783i64, 1172i32, 3u8, 8u8) { os.exit(37) }
    if !expect(.Ethiopic, 0i64 - 187783i64, 1448i32, 3u8, 8u8) { os.exit(38) }
    if !expect(.Coptic, 0i64 - 195638i64, 1150i32, 9u8, 9u8) { os.exit(39) }
    if !expect(.Ethiopic, 0i64 - 195638i64, 1426i32, 9u8, 9u8) { os.exit(40) }
    if !expect(.Coptic, 0i64 - 64945i64, 1508i32, 7u8, 2u8) { os.exit(41) }
    if !expect(.Ethiopic, 0i64 - 64945i64, 1784i32, 7u8, 2u8) { os.exit(42) }
    if !expect(.Coptic, 0i64 - 322690i64, 802i32, 11u8, 4u8) { os.exit(43) }
    if !expect(.Ethiopic, 0i64 - 322690i64, 1078i32, 11u8, 4u8) { os.exit(44) }
    if !expect(.Coptic, 0i64 - 288341i64, 896i32, 11u8, 19u8) { os.exit(45) }
    if !expect(.Ethiopic, 0i64 - 288341i64, 1172i32, 11u8, 19u8) { os.exit(46) }
    if !expect(.Coptic, 4856i64, 1699i32, 8u8, 11u8) { os.exit(47) }
    if !expect(.Ethiopic, 4856i64, 1975i32, 8u8, 11u8) { os.exit(48) }
    if !expect(.Coptic, 0i64 - 371841i64, 668i32, 4u8, 6u8) { os.exit(49) }
    if !expect(.Ethiopic, 0i64 - 371841i64, 944i32, 4u8, 6u8) { os.exit(50) }
    if !expect(.Coptic, 0i64 - 539660i64, 208i32, 10u8, 22u8) { os.exit(51) }
    if !expect(.Ethiopic, 0i64 - 539660i64, 484i32, 10u8, 22u8) { os.exit(52) }
    if !expect(.Coptic, 280114i64, 2453i32, 3u8, 20u8) { os.exit(53) }
    if !expect(.Ethiopic, 280114i64, 2729i32, 3u8, 20u8) { os.exit(54) }
    if !expect(.Coptic, 0i64 - 73950i64, 1483i32, 11u8, 9u8) { os.exit(55) }
    if !expect(.Ethiopic, 0i64 - 73950i64, 1759i32, 11u8, 9u8) { os.exit(56) }
    if !expect(.Coptic, 0i64 - 194875i64, 1152i32, 10u8, 11u8) { os.exit(57) }
    if !expect(.Ethiopic, 0i64 - 194875i64, 1428i32, 10u8, 11u8) { os.exit(58) }
    if !expect(.Coptic, 0i64 - 345419i64, 740i32, 8u8, 10u8) { os.exit(59) }
    if !expect(.Ethiopic, 0i64 - 345419i64, 1016i32, 8u8, 10u8) { os.exit(60) }
    if !expect(.Coptic, 0i64 - 471534i64, 395i32, 4u8, 27u8) { os.exit(61) }
    if !expect(.Ethiopic, 0i64 - 471534i64, 671i32, 4u8, 27u8) { os.exit(62) }
    if !expect(.Coptic, 0i64 - 133213i64, 1321i32, 8u8, 6u8) { os.exit(63) }
    if !expect(.Ethiopic, 0i64 - 133213i64, 1597i32, 8u8, 6u8) { os.exit(64) }
    if !expect(.Coptic, 0i64 - 339673i64, 756i32, 5u8, 2u8) { os.exit(65) }
    if !expect(.Ethiopic, 0i64 - 339673i64, 1032i32, 5u8, 2u8) { os.exit(66) }
    if !expect(.Coptic, 26121i64, 1757i32, 11u8, 1u8) { os.exit(67) }
    if !expect(.Ethiopic, 26121i64, 2033i32, 11u8, 1u8) { os.exit(68) }
    if !expect(.Coptic, 34795i64, 1781i32, 7u8, 29u8) { os.exit(69) }
    if !expect(.Ethiopic, 34795i64, 2057i32, 7u8, 29u8) { os.exit(70) }
    if !expect(.Coptic, 0i64 - 433488i64, 499i32, 6u8, 27u8) { os.exit(71) }
    if !expect(.Ethiopic, 0i64 - 433488i64, 775i32, 6u8, 27u8) { os.exit(72) }
    if !expect(.Coptic, 0i64 - 361709i64, 696i32, 1u8, 1u8) { os.exit(73) }
    if !expect(.Ethiopic, 0i64 - 361709i64, 972i32, 1u8, 1u8) { os.exit(74) }
    if !expect(.Coptic, 0i64 - 515948i64, 273i32, 9u8, 23u8) { os.exit(75) }
    if !expect(.Ethiopic, 0i64 - 515948i64, 549i32, 9u8, 23u8) { os.exit(76) }
    if !expect(.Coptic, 0i64 - 228931i64, 1059i32, 7u8, 14u8) { os.exit(77) }
    if !expect(.Ethiopic, 0i64 - 228931i64, 1335i32, 7u8, 14u8) { os.exit(78) }
    if !expect(.Coptic, 123565i64, 2024i32, 8u8, 13u8) { os.exit(79) }
    if !expect(.Ethiopic, 123565i64, 2300i32, 8u8, 13u8) { os.exit(80) }
    if !expect(.Coptic, 0i64 - 127727i64, 1336i32, 8u8, 13u8) { os.exit(81) }
    if !expect(.Ethiopic, 0i64 - 127727i64, 1612i32, 8u8, 13u8) { os.exit(82) }
    if !expect(.Coptic, 0i64 - 474028i64, 388i32, 6u8, 29u8) { os.exit(83) }
    if !expect(.Ethiopic, 0i64 - 474028i64, 664i32, 6u8, 29u8) { os.exit(84) }
    if !expect(.Coptic, 142959i64, 2077i32, 9u8, 19u8) { os.exit(85) }
    if !expect(.Ethiopic, 142959i64, 2353i32, 9u8, 19u8) { os.exit(86) }
    if !expect(.Coptic, 94916i64, 1946i32, 3u8, 4u8) { os.exit(87) }
    if !expect(.Ethiopic, 94916i64, 2222i32, 3u8, 4u8) { os.exit(88) }
    if !expect(.Coptic, 0i64 - 366802i64, 682i32, 1u8, 22u8) { os.exit(89) }
    if !expect(.Ethiopic, 0i64 - 366802i64, 958i32, 1u8, 22u8) { os.exit(90) }
    if !expect(.Coptic, 0i64 - 400685i64, 589i32, 4u8, 17u8) { os.exit(91) }
    if !expect(.Ethiopic, 0i64 - 400685i64, 865i32, 4u8, 17u8) { os.exit(92) }
    if !expect(.Coptic, 0i64 - 211548i64, 1107i32, 2u8, 15u8) { os.exit(93) }
    if !expect(.Ethiopic, 0i64 - 211548i64, 1383i32, 2u8, 15u8) { os.exit(94) }
    if !expect(.Coptic, 80941i64, 1907i32, 12u8, 4u8) { os.exit(95) }
    if !expect(.Ethiopic, 80941i64, 2183i32, 12u8, 4u8) { os.exit(96) }
    if !expect(.Coptic, 0i64 - 432450i64, 502i32, 4u8, 29u8) { os.exit(97) }
    if !expect(.Ethiopic, 0i64 - 432450i64, 778i32, 4u8, 29u8) { os.exit(98) }
    if !expect(.Coptic, 0i64 - 463023i64, 418i32, 8u8, 17u8) { os.exit(99) }
    if !expect(.Ethiopic, 0i64 - 463023i64, 694i32, 8u8, 17u8) { os.exit(100) }
    if !expect(.Coptic, 0i64 - 572399i64, 119i32, 3u8, 1u8) { os.exit(101) }
    if !expect(.Ethiopic, 0i64 - 572399i64, 395i32, 3u8, 1u8) { os.exit(102) }
    if !expect(.Coptic, 172966i64, 2159i32, 11u8, 16u8) { os.exit(103) }
    if !expect(.Ethiopic, 172966i64, 2435i32, 11u8, 16u8) { os.exit(104) }
    if !expect(.Coptic, 0i64 - 126274i64, 1340i32, 8u8, 5u8) { os.exit(105) }
    if !expect(.Ethiopic, 0i64 - 126274i64, 1616i32, 8u8, 5u8) { os.exit(106) }
    if !expect(.Coptic, 207369i64, 2254i32, 1u8, 20u8) { os.exit(107) }
    if !expect(.Ethiopic, 207369i64, 2530i32, 1u8, 20u8) { os.exit(108) }
    if !expect(.Coptic, 0i64 - 514689i64, 277i32, 3u8, 1u8) { os.exit(109) }
    if !expect(.Ethiopic, 0i64 - 514689i64, 553i32, 3u8, 1u8) { os.exit(110) }
    if !expect(.Coptic, 0i64 - 79208i64, 1469i32, 6u8, 14u8) { os.exit(111) }
    if !expect(.Ethiopic, 0i64 - 79208i64, 1745i32, 6u8, 14u8) { os.exit(112) }
    if !expect(.Coptic, 172476i64, 2158i32, 7u8, 11u8) { os.exit(113) }
    if !expect(.Ethiopic, 172476i64, 2434i32, 7u8, 11u8) { os.exit(114) }
    if !expect(.Coptic, 0i64 - 566108i64, 136i32, 5u8, 22u8) { os.exit(115) }
    if !expect(.Ethiopic, 0i64 - 566108i64, 412i32, 5u8, 22u8) { os.exit(116) }
    if !expect(.Coptic, 0i64 - 488374i64, 349i32, 3u8, 18u8) { os.exit(117) }
    if !expect(.Ethiopic, 0i64 - 488374i64, 625i32, 3u8, 18u8) { os.exit(118) }
    if !expect(.Coptic, 269546i64, 2424i32, 4u8, 14u8) { os.exit(119) }
    if !expect(.Ethiopic, 269546i64, 2700i32, 4u8, 14u8) { os.exit(120) }
    if !expect(.Coptic, 0i64 - 364044i64, 689i32, 8u8, 13u8) { os.exit(121) }
    if !expect(.Ethiopic, 0i64 - 364044i64, 965i32, 8u8, 13u8) { os.exit(122) }
    if !expect(.Coptic, 196752i64, 2224i32, 12u8, 30u8) { os.exit(123) }
    if !expect(.Ethiopic, 196752i64, 2500i32, 12u8, 30u8) { os.exit(124) }
    if !expect(.Coptic, 0i64 - 543418i64, 198i32, 7u8, 7u8) { os.exit(125) }
    if !expect(.Ethiopic, 0i64 - 543418i64, 474i32, 7u8, 7u8) { os.exit(126) }
    if !expect(.Coptic, 0i64 - 131536i64, 1326i32, 3u8, 7u8) { os.exit(127) }
    if !expect(.Ethiopic, 0i64 - 131536i64, 1602i32, 3u8, 7u8) { os.exit(128) }
    if !expect(.Coptic, 0i64 - 469952i64, 399i32, 8u8, 28u8) { os.exit(129) }
    if !expect(.Ethiopic, 0i64 - 469952i64, 675i32, 8u8, 28u8) { os.exit(130) }
    if !expect(.Coptic, 12968i64, 1721i32, 10u8, 27u8) { os.exit(131) }
    if !expect(.Ethiopic, 12968i64, 1997i32, 10u8, 27u8) { os.exit(132) }
    if !expect(.Coptic, 0i64 - 239971i64, 1029i32, 4u8, 21u8) { os.exit(133) }
    if !expect(.Ethiopic, 0i64 - 239971i64, 1305i32, 4u8, 21u8) { os.exit(134) }
    if !expect(.Coptic, 126325i64, 2032i32, 3u8, 1u8) { os.exit(135) }
    if !expect(.Ethiopic, 126325i64, 2308i32, 3u8, 1u8) { os.exit(136) }
    if !expect(.Coptic, 0i64 - 420752i64, 534i32, 5u8, 9u8) { os.exit(137) }
    if !expect(.Ethiopic, 0i64 - 420752i64, 810i32, 5u8, 9u8) { os.exit(138) }
    if !expect(.Coptic, 180520i64, 2180i32, 7u8, 19u8) { os.exit(139) }
    if !expect(.Ethiopic, 180520i64, 2456i32, 7u8, 19u8) { os.exit(140) }
    if !expect(.Coptic, 264122i64, 2409i32, 6u8, 9u8) { os.exit(141) }
    if !expect(.Ethiopic, 264122i64, 2685i32, 6u8, 9u8) { os.exit(142) }
    if !expect(.Coptic, 0i64 - 346536i64, 737i32, 7u8, 19u8) { os.exit(143) }
    if !expect(.Ethiopic, 0i64 - 346536i64, 1013i32, 7u8, 19u8) { os.exit(144) }
    if !expect(.Coptic, 0i64 - 448523i64, 458i32, 4u8, 27u8) { os.exit(145) }
    if !expect(.Ethiopic, 0i64 - 448523i64, 734i32, 4u8, 27u8) { os.exit(146) }
    if !expect(.Coptic, 241192i64, 2346i32, 8u8, 30u8) { os.exit(147) }
    if !expect(.Ethiopic, 241192i64, 2622i32, 8u8, 30u8) { os.exit(148) }
    if !expect(.Coptic, 0i64 - 455987i64, 437i32, 11u8, 23u8) { os.exit(149) }
    if !expect(.Ethiopic, 0i64 - 455987i64, 713i32, 11u8, 23u8) { os.exit(150) }
    if !expect(.Coptic, 0i64 - 409301i64, 565i32, 9u8, 17u8) { os.exit(151) }
    if !expect(.Ethiopic, 0i64 - 409301i64, 841i32, 9u8, 17u8) { os.exit(152) }
    if !expect(.Coptic, 101414i64, 1963i32, 12u8, 23u8) { os.exit(153) }
    if !expect(.Ethiopic, 101414i64, 2239i32, 12u8, 23u8) { os.exit(154) }
    if !expect(.Coptic, 0i64 - 443738i64, 471i32, 6u8, 4u8) { os.exit(155) }
    if !expect(.Ethiopic, 0i64 - 443738i64, 747i32, 6u8, 4u8) { os.exit(156) }
    if !expect(.Coptic, 0i64 - 357606i64, 707i32, 3u8, 27u8) { os.exit(157) }
    if !expect(.Ethiopic, 0i64 - 357606i64, 983i32, 3u8, 27u8) { os.exit(158) }
    if !expect(.Coptic, 121136i64, 2017i32, 12u8, 21u8) { os.exit(159) }
    if !expect(.Ethiopic, 121136i64, 2293i32, 12u8, 21u8) { os.exit(160) }
    if !expect(.Coptic, 0i64 - 148995i64, 1278i32, 5u8, 20u8) { os.exit(161) }
    if !expect(.Ethiopic, 0i64 - 148995i64, 1554i32, 5u8, 20u8) { os.exit(162) }
    if !expect(.Coptic, 24394i64, 1753i32, 2u8, 5u8) { os.exit(163) }
    if !expect(.Ethiopic, 24394i64, 2029i32, 2u8, 5u8) { os.exit(164) }
    if !expect(.Coptic, 0i64 - 118588i64, 1361i32, 8u8, 21u8) { os.exit(165) }
    if !expect(.Ethiopic, 0i64 - 118588i64, 1637i32, 8u8, 21u8) { os.exit(166) }
    if !expect(.Coptic, 277181i64, 2445i32, 3u8, 9u8) { os.exit(167) }
    if !expect(.Ethiopic, 277181i64, 2721i32, 3u8, 9u8) { os.exit(168) }
    if !expect(.Coptic, 0i64 - 15012i64, 1645i32, 3u8, 16u8) { os.exit(169) }
    if !expect(.Ethiopic, 0i64 - 15012i64, 1921i32, 3u8, 16u8) { os.exit(170) }
    if !expect(.Coptic, 36102i64, 1785i32, 2u8, 25u8) { os.exit(171) }
    if !expect(.Ethiopic, 36102i64, 2061i32, 2u8, 25u8) { os.exit(172) }
    if !expect(.Coptic, 0i64 - 65744i64, 1506i32, 4u8, 24u8) { os.exit(173) }
    if !expect(.Ethiopic, 0i64 - 65744i64, 1782i32, 4u8, 24u8) { os.exit(174) }
    if !expect(.Coptic, 0i64 - 37701i64, 1583i32, 2u8, 3u8) { os.exit(175) }
    if !expect(.Ethiopic, 0i64 - 37701i64, 1859i32, 2u8, 3u8) { os.exit(176) }
    if !expect(.Coptic, 0i64 - 436134i64, 492i32, 3u8, 27u8) { os.exit(177) }
    if !expect(.Ethiopic, 0i64 - 436134i64, 768i32, 3u8, 27u8) { os.exit(178) }
    if !expect(.Coptic, 0i64 - 207562i64, 1118i32, 1u8, 13u8) { os.exit(179) }
    if !expect(.Ethiopic, 0i64 - 207562i64, 1394i32, 1u8, 13u8) { os.exit(180) }
    if !expect(.Coptic, 154943i64, 2110i32, 7u8, 10u8) { os.exit(181) }
    if !expect(.Ethiopic, 154943i64, 2386i32, 7u8, 10u8) { os.exit(182) }
    if !expect(.Coptic, 276324i64, 2442i32, 11u8, 8u8) { os.exit(183) }
    if !expect(.Ethiopic, 276324i64, 2718i32, 11u8, 8u8) { os.exit(184) }
    if !expect(.Coptic, 57362i64, 1843i32, 5u8, 11u8) { os.exit(185) }
    if !expect(.Ethiopic, 57362i64, 2119i32, 5u8, 11u8) { os.exit(186) }
    if !expect(.Coptic, 234247i64, 2327i32, 8u8, 25u8) { os.exit(187) }
    if !expect(.Ethiopic, 234247i64, 2603i32, 8u8, 25u8) { os.exit(188) }
    if !expect(.Coptic, 123032i64, 2023i32, 2u8, 26u8) { os.exit(189) }
    if !expect(.Ethiopic, 123032i64, 2299i32, 2u8, 26u8) { os.exit(190) }
    if !expect(.Coptic, 0i64 - 479944i64, 372i32, 4u8, 17u8) { os.exit(191) }
    if !expect(.Ethiopic, 0i64 - 479944i64, 648i32, 4u8, 17u8) { os.exit(192) }
    if !expect(.Coptic, 0i64 - 438180i64, 486i32, 8u8, 23u8) { os.exit(193) }
    if !expect(.Ethiopic, 0i64 - 438180i64, 762i32, 8u8, 23u8) { os.exit(194) }
    if !expect(.Coptic, 8650i64, 1709i32, 13u8, 2u8) { os.exit(195) }
    if !expect(.Ethiopic, 8650i64, 1985i32, 13u8, 2u8) { os.exit(196) }
    if !expect(.Coptic, 0i64 - 230778i64, 1054i32, 6u8, 23u8) { os.exit(197) }
    if !expect(.Ethiopic, 0i64 - 230778i64, 1330i32, 6u8, 23u8) { os.exit(198) }
    if !expect(.Coptic, 0i64 - 115340i64, 1370i32, 7u8, 12u8) { os.exit(199) }
    if !expect(.Ethiopic, 0i64 - 115340i64, 1646i32, 7u8, 12u8) { os.exit(200) }
    if !expect(.Coptic, 0i64 - 389520i64, 619i32, 11u8, 15u8) { os.exit(201) }
    if !expect(.Ethiopic, 0i64 - 389520i64, 895i32, 11u8, 15u8) { os.exit(202) }
    if !expect(.Coptic, 0i64 - 337025i64, 763i32, 8u8, 4u8) { os.exit(203) }
    if !expect(.Ethiopic, 0i64 - 337025i64, 1039i32, 8u8, 4u8) { os.exit(204) }
    if !expect(.Coptic, 0i64 - 153165i64, 1266i32, 12u8, 23u8) { os.exit(205) }
    if !expect(.Ethiopic, 0i64 - 153165i64, 1542i32, 12u8, 23u8) { os.exit(206) }
    if !expect(.Coptic, 112523i64, 1994i32, 5u8, 19u8) { os.exit(207) }
    if !expect(.Ethiopic, 112523i64, 2270i32, 5u8, 19u8) { os.exit(208) }
    if !expect(.Coptic, 377i64, 1687i32, 5u8, 5u8) { os.exit(209) }
    if !expect(.Ethiopic, 377i64, 1963i32, 5u8, 5u8) { os.exit(210) }
    if !expect(.Coptic, 0i64 - 492149i64, 338i32, 11u8, 21u8) { os.exit(211) }
    if !expect(.Ethiopic, 0i64 - 492149i64, 614i32, 11u8, 21u8) { os.exit(212) }
    if !expect(.Coptic, 0i64 - 300840i64, 862i32, 8u8, 29u8) { os.exit(213) }
    if !expect(.Ethiopic, 0i64 - 300840i64, 1138i32, 8u8, 29u8) { os.exit(214) }
    if !expect(.Coptic, 0i64 - 86385i64, 1449i32, 10u8, 22u8) { os.exit(215) }
    if !expect(.Ethiopic, 0i64 - 86385i64, 1725i32, 10u8, 22u8) { os.exit(216) }
    if !expect(.Coptic, 43709i64, 1805i32, 12u8, 27u8) { os.exit(217) }
    if !expect(.Ethiopic, 43709i64, 2081i32, 12u8, 27u8) { os.exit(218) }
    if !expect(.Coptic, 58886i64, 1847i32, 7u8, 14u8) { os.exit(219) }
    if !expect(.Ethiopic, 58886i64, 2123i32, 7u8, 14u8) { os.exit(220) }
    if !expect(.Coptic, 151788i64, 2101i32, 11u8, 22u8) { os.exit(221) }
    if !expect(.Ethiopic, 151788i64, 2377i32, 11u8, 22u8) { os.exit(222) }
    if !expect(.Coptic, 0i64 - 474303i64, 387i32, 9u8, 30u8) { os.exit(223) }
    if !expect(.Ethiopic, 0i64 - 474303i64, 663i32, 9u8, 30u8) { os.exit(224) }
    if !expect(.Coptic, 0i64 - 324461i64, 797i32, 12u8, 29u8) { os.exit(225) }
    if !expect(.Ethiopic, 0i64 - 324461i64, 1073i32, 12u8, 29u8) { os.exit(226) }
    if !expect(.Coptic, 288953i64, 2477i32, 6u8, 3u8) { os.exit(227) }
    if !expect(.Ethiopic, 288953i64, 2753i32, 6u8, 3u8) { os.exit(228) }
    if !expect(.Coptic, 178740i64, 2175i32, 9u8, 6u8) { os.exit(229) }
    if !expect(.Ethiopic, 178740i64, 2451i32, 9u8, 6u8) { os.exit(230) }
    if !expect(.Coptic, 0i64 - 303603i64, 855i32, 2u8, 3u8) { os.exit(231) }
    if !expect(.Ethiopic, 0i64 - 303603i64, 1131i32, 2u8, 3u8) { os.exit(232) }
    if !expect(.Coptic, 0i64 - 274209i64, 935i32, 7u8, 27u8) { os.exit(233) }
    if !expect(.Ethiopic, 0i64 - 274209i64, 1211i32, 7u8, 27u8) { os.exit(234) }
    if !expect(.Coptic, 0i64 - 298844i64, 868i32, 2u8, 13u8) { os.exit(235) }
    if !expect(.Ethiopic, 0i64 - 298844i64, 1144i32, 2u8, 13u8) { os.exit(236) }
    if !expect(.Coptic, 222618i64, 2295i32, 10u8, 24u8) { os.exit(237) }
    if !expect(.Ethiopic, 222618i64, 2571i32, 10u8, 24u8) { os.exit(238) }
    if !expect(.Coptic, 0i64 - 251968i64, 996i32, 6u8, 17u8) { os.exit(239) }
    if !expect(.Ethiopic, 0i64 - 251968i64, 1272i32, 6u8, 17u8) { os.exit(240) }
    if !expect(.Coptic, 0i64 - 161277i64, 1244i32, 10u8, 6u8) { os.exit(241) }
    if !expect(.Ethiopic, 0i64 - 161277i64, 1520i32, 10u8, 6u8) { os.exit(242) }
    if !expect(.Coptic, 0i64 - 197201i64, 1146i32, 5u8, 27u8) { os.exit(243) }
    if !expect(.Ethiopic, 0i64 - 197201i64, 1422i32, 5u8, 27u8) { os.exit(244) }
    if !expect(.Coptic, 0i64 - 489915i64, 344i32, 13u8, 3u8) { os.exit(245) }
    if !expect(.Ethiopic, 0i64 - 489915i64, 620i32, 13u8, 3u8) { os.exit(246) }
    if !expect(.Coptic, 3846i64, 1696i32, 11u8, 6u8) { os.exit(247) }
    if !expect(.Ethiopic, 3846i64, 1972i32, 11u8, 6u8) { os.exit(248) }
    if !expect(.Coptic, 0i64 - 101022i64, 1409i32, 9u8, 25u8) { os.exit(249) }
    if !expect(.Ethiopic, 0i64 - 101022i64, 1685i32, 9u8, 25u8) { os.exit(250) }
    if !expect(.Coptic, 289835i64, 2479i32, 11u8, 5u8) { os.exit(251) }
    if !expect(.Ethiopic, 289835i64, 2755i32, 11u8, 5u8) { os.exit(252) }
    if !expect(.Coptic, 215299i64, 2275i32, 10u8, 10u8) { os.exit(253) }
    if !expect(.Ethiopic, 215299i64, 2551i32, 10u8, 10u8) { os.exit(254) }
    if !expect(.Coptic, 284794i64, 2466i32, 1u8, 12u8) { os.exit(255) }
    if !expect(.Ethiopic, 284794i64, 2742i32, 1u8, 12u8) { os.exit(256) }
    if !expect(.Coptic, 0i64 - 200491i64, 1137i32, 5u8, 24u8) { os.exit(257) }
    if !expect(.Ethiopic, 0i64 - 200491i64, 1413i32, 5u8, 24u8) { os.exit(258) }
    if !expect(.Coptic, 55090i64, 1837i32, 2u8, 20u8) { os.exit(259) }
    if !expect(.Ethiopic, 55090i64, 2113i32, 2u8, 20u8) { os.exit(260) }
    if !expect(.Coptic, 0i64 - 385466i64, 630i32, 12u8, 21u8) { os.exit(261) }
    if !expect(.Ethiopic, 0i64 - 385466i64, 906i32, 12u8, 21u8) { os.exit(262) }
    if !expect(.Coptic, 267490i64, 2418i32, 8u8, 30u8) { os.exit(263) }
    if !expect(.Ethiopic, 267490i64, 2694i32, 8u8, 30u8) { os.exit(264) }
    if !expect(.Coptic, 0i64 - 438689i64, 485i32, 3u8, 29u8) { os.exit(265) }
    if !expect(.Ethiopic, 0i64 - 438689i64, 761i32, 3u8, 29u8) { os.exit(266) }
    if !expect(.Coptic, 0i64 - 568933i64, 128i32, 8u8, 29u8) { os.exit(267) }
    if !expect(.Ethiopic, 0i64 - 568933i64, 404i32, 8u8, 29u8) { os.exit(268) }
    if !expect(.Coptic, 0i64 - 421716i64, 531i32, 9u8, 21u8) { os.exit(269) }
    if !expect(.Ethiopic, 0i64 - 421716i64, 807i32, 9u8, 21u8) { os.exit(270) }
    if !expect(.Coptic, 0i64 - 371131i64, 670i32, 3u8, 16u8) { os.exit(271) }
    if !expect(.Ethiopic, 0i64 - 371131i64, 946i32, 3u8, 16u8) { os.exit(272) }
    if !expect(.Coptic, 52716i64, 1830i32, 8u8, 23u8) { os.exit(273) }
    if !expect(.Ethiopic, 52716i64, 2106i32, 8u8, 23u8) { os.exit(274) }
    if !expect(.Coptic, 0i64 - 198977i64, 1141i32, 7u8, 17u8) { os.exit(275) }
    if !expect(.Ethiopic, 0i64 - 198977i64, 1417i32, 7u8, 17u8) { os.exit(276) }
    if !expect(.Coptic, 0i64 - 33410i64, 1594i32, 11u8, 6u8) { os.exit(277) }
    if !expect(.Ethiopic, 0i64 - 33410i64, 1870i32, 11u8, 6u8) { os.exit(278) }
    if !expect(.Coptic, 269635i64, 2424i32, 7u8, 13u8) { os.exit(279) }
    if !expect(.Ethiopic, 269635i64, 2700i32, 7u8, 13u8) { os.exit(280) }
    if !expect(.Coptic, 0i64 - 258806i64, 977i32, 9u8, 29u8) { os.exit(281) }
    if !expect(.Ethiopic, 0i64 - 258806i64, 1253i32, 9u8, 29u8) { os.exit(282) }
    if !expect(.Coptic, 0i64 - 212313i64, 1105i32, 1u8, 10u8) { os.exit(283) }
    if !expect(.Ethiopic, 0i64 - 212313i64, 1381i32, 1u8, 10u8) { os.exit(284) }
    if !expect(.Coptic, 0i64 - 294395i64, 880i32, 4u8, 19u8) { os.exit(285) }
    if !expect(.Ethiopic, 0i64 - 294395i64, 1156i32, 4u8, 19u8) { os.exit(286) }
    if !expect(.Coptic, 0i64 - 309094i64, 840i32, 1u8, 20u8) { os.exit(287) }
    if !expect(.Ethiopic, 0i64 - 309094i64, 1116i32, 1u8, 20u8) { os.exit(288) }
    if !expect(.Coptic, 0i64 - 87903i64, 1445i32, 8u8, 25u8) { os.exit(289) }
    if !expect(.Ethiopic, 0i64 - 87903i64, 1721i32, 8u8, 25u8) { os.exit(290) }
    if !expect(.Coptic, 0i64 - 289185i64, 894i32, 7u8, 26u8) { os.exit(291) }
    if !expect(.Ethiopic, 0i64 - 289185i64, 1170i32, 7u8, 26u8) { os.exit(292) }
    if !expect(.Coptic, 0i64 - 560499i64, 151i32, 10u8, 3u8) { os.exit(293) }
    if !expect(.Ethiopic, 0i64 - 560499i64, 427i32, 10u8, 3u8) { os.exit(294) }
    if !expect(.Coptic, 0i64 - 124882i64, 1344i32, 5u8, 26u8) { os.exit(295) }
    if !expect(.Ethiopic, 0i64 - 124882i64, 1620i32, 5u8, 26u8) { os.exit(296) }
    if !expect(.Coptic, 0i64 - 362641i64, 693i32, 6u8, 15u8) { os.exit(297) }
    if !expect(.Ethiopic, 0i64 - 362641i64, 969i32, 6u8, 15u8) { os.exit(298) }
    if !expect(.Coptic, 0i64 - 559241i64, 155i32, 3u8, 10u8) { os.exit(299) }
    if !expect(.Ethiopic, 0i64 - 559241i64, 431i32, 3u8, 10u8) { os.exit(300) }
    if !expect(.Coptic, 0i64 - 466957i64, 407i32, 11u8, 11u8) { os.exit(301) }
    if !expect(.Ethiopic, 0i64 - 466957i64, 683i32, 11u8, 11u8) { os.exit(302) }
    if !expect(.Coptic, 215501i64, 2276i32, 4u8, 26u8) { os.exit(303) }
    if !expect(.Ethiopic, 215501i64, 2552i32, 4u8, 26u8) { os.exit(304) }
    if !expect(.Coptic, 0i64 - 204037i64, 1127i32, 9u8, 11u8) { os.exit(305) }
    if !expect(.Ethiopic, 0i64 - 204037i64, 1403i32, 9u8, 11u8) { os.exit(306) }
    if !expect(.Coptic, 0i64 - 211343i64, 1107i32, 9u8, 10u8) { os.exit(307) }
    if !expect(.Ethiopic, 0i64 - 211343i64, 1383i32, 9u8, 10u8) { os.exit(308) }
    if !expect(.Coptic, 0i64 - 553164i64, 171i32, 11u8, 3u8) { os.exit(309) }
    if !expect(.Ethiopic, 0i64 - 553164i64, 447i32, 11u8, 3u8) { os.exit(310) }
    if !expect(.Coptic, 234260i64, 2327i32, 9u8, 8u8) { os.exit(311) }
    if !expect(.Ethiopic, 234260i64, 2603i32, 9u8, 8u8) { os.exit(312) }
    if !expect(.Coptic, 0i64 - 408834i64, 566i32, 12u8, 29u8) { os.exit(313) }
    if !expect(.Ethiopic, 0i64 - 408834i64, 842i32, 12u8, 29u8) { os.exit(314) }
    if !expect(.Coptic, 0i64 - 423821i64, 525i32, 12u8, 17u8) { os.exit(315) }
    if !expect(.Ethiopic, 0i64 - 423821i64, 801i32, 12u8, 17u8) { os.exit(316) }
    if !expect(.Coptic, 0i64 - 359258i64, 702i32, 9u8, 21u8) { os.exit(317) }
    if !expect(.Ethiopic, 0i64 - 359258i64, 978i32, 9u8, 21u8) { os.exit(318) }
    if !expect(.Coptic, 119614i64, 2013i32, 10u8, 20u8) { os.exit(319) }
    if !expect(.Ethiopic, 119614i64, 2289i32, 10u8, 20u8) { os.exit(320) }
    if !expect(.Coptic, 0i64 - 209910i64, 1111i32, 8u8, 12u8) { os.exit(321) }
    if !expect(.Ethiopic, 0i64 - 209910i64, 1387i32, 8u8, 12u8) { os.exit(322) }
    if !expect(.Coptic, 25864i64, 1757i32, 2u8, 14u8) { os.exit(323) }
    if !expect(.Ethiopic, 25864i64, 2033i32, 2u8, 14u8) { os.exit(324) }
    if !expect(.Coptic, 0i64 - 407564i64, 570i32, 6u8, 18u8) { os.exit(325) }
    if !expect(.Ethiopic, 0i64 - 407564i64, 846i32, 6u8, 18u8) { os.exit(326) }
    if !expect(.Coptic, 234286i64, 2327i32, 10u8, 4u8) { os.exit(327) }
    if !expect(.Ethiopic, 234286i64, 2603i32, 10u8, 4u8) { os.exit(328) }
    if !expect(.Coptic, 0i64 - 247393i64, 1008i32, 12u8, 29u8) { os.exit(329) }
    if !expect(.Ethiopic, 0i64 - 247393i64, 1284i32, 12u8, 29u8) { os.exit(330) }
    if !expect(.Coptic, 92897i64, 1940i32, 8u8, 26u8) { os.exit(331) }
    if !expect(.Ethiopic, 92897i64, 2216i32, 8u8, 26u8) { os.exit(332) }
    if !expect(.Coptic, 235905i64, 2332i32, 3u8, 6u8) { os.exit(333) }
    if !expect(.Ethiopic, 235905i64, 2608i32, 3u8, 6u8) { os.exit(334) }
    if !expect(.Coptic, 0i64 - 539920i64, 208i32, 2u8, 2u8) { os.exit(335) }
    if !expect(.Ethiopic, 0i64 - 539920i64, 484i32, 2u8, 2u8) { os.exit(336) }
    if !expect(.Coptic, 0i64 - 24264i64, 1619i32, 11u8, 21u8) { os.exit(337) }
    if !expect(.Ethiopic, 0i64 - 24264i64, 1895i32, 11u8, 21u8) { os.exit(338) }
    if !expect(.Coptic, 292754i64, 2487i32, 11u8, 2u8) { os.exit(339) }
    if !expect(.Ethiopic, 292754i64, 2763i32, 11u8, 2u8) { os.exit(340) }
    if !expect(.Coptic, 85542i64, 1920i32, 7u8, 6u8) { os.exit(341) }
    if !expect(.Ethiopic, 85542i64, 2196i32, 7u8, 6u8) { os.exit(342) }
    if !expect(.Coptic, 0i64 - 337648i64, 761i32, 11u8, 21u8) { os.exit(343) }
    if !expect(.Ethiopic, 0i64 - 337648i64, 1037i32, 11u8, 21u8) { os.exit(344) }
    if !expect(.Coptic, 0i64 - 493675i64, 334i32, 9u8, 16u8) { os.exit(345) }
    if !expect(.Ethiopic, 0i64 - 493675i64, 610i32, 9u8, 16u8) { os.exit(346) }
    if !expect(.Coptic, 90327i64, 1933i32, 8u8, 13u8) { os.exit(347) }
    if !expect(.Ethiopic, 90327i64, 2209i32, 8u8, 13u8) { os.exit(348) }
    if !expect(.Coptic, 0i64 - 163538i64, 1238i32, 7u8, 27u8) { os.exit(349) }
    if !expect(.Ethiopic, 0i64 - 163538i64, 1514i32, 7u8, 27u8) { os.exit(350) }
    if !expect(.Coptic, 0i64 - 146969i64, 1283i32, 12u8, 10u8) { os.exit(351) }
    if !expect(.Ethiopic, 0i64 - 146969i64, 1559i32, 12u8, 10u8) { os.exit(352) }
    if !expect(.Coptic, 283643i64, 2462i32, 11u8, 22u8) { os.exit(353) }
    if !expect(.Ethiopic, 283643i64, 2738i32, 11u8, 22u8) { os.exit(354) }
    if !expect(.Coptic, 0i64 - 413266i64, 554i32, 11u8, 10u8) { os.exit(355) }
    if !expect(.Ethiopic, 0i64 - 413266i64, 830i32, 11u8, 10u8) { os.exit(356) }
    if !expect(.Coptic, 0i64 - 321145i64, 807i32, 1u8, 23u8) { os.exit(357) }
    if !expect(.Ethiopic, 0i64 - 321145i64, 1083i32, 1u8, 23u8) { os.exit(358) }
    if !expect(.Coptic, 0i64 - 8990i64, 1661i32, 9u8, 14u8) { os.exit(359) }
    if !expect(.Ethiopic, 0i64 - 8990i64, 1937i32, 9u8, 14u8) { os.exit(360) }
    if !expect(.Coptic, 0i64 - 354480i64, 715i32, 10u8, 21u8) { os.exit(361) }
    if !expect(.Ethiopic, 0i64 - 354480i64, 991i32, 10u8, 21u8) { os.exit(362) }
    if !expect(.Coptic, 0i64 - 531078i64, 232i32, 4u8, 18u8) { os.exit(363) }
    if !expect(.Ethiopic, 0i64 - 531078i64, 508i32, 4u8, 18u8) { os.exit(364) }
    if !expect(.Coptic, 0i64 - 472223i64, 393i32, 6u8, 8u8) { os.exit(365) }
    if !expect(.Ethiopic, 0i64 - 472223i64, 669i32, 6u8, 8u8) { os.exit(366) }
    if !expect(.Coptic, 0i64 - 135462i64, 1315i32, 6u8, 9u8) { os.exit(367) }
    if !expect(.Ethiopic, 0i64 - 135462i64, 1591i32, 6u8, 9u8) { os.exit(368) }
    if !expect(.Coptic, 0i64 - 69706i64, 1495i32, 6u8, 20u8) { os.exit(369) }
    if !expect(.Ethiopic, 0i64 - 69706i64, 1771i32, 6u8, 20u8) { os.exit(370) }
    if !expect(.Coptic, 0i64 - 43302i64, 1567i32, 10u8, 6u8) { os.exit(371) }
    if !expect(.Ethiopic, 0i64 - 43302i64, 1843i32, 10u8, 6u8) { os.exit(372) }
    if !expect(.Coptic, 43067i64, 1804i32, 3u8, 20u8) { os.exit(373) }
    if !expect(.Ethiopic, 43067i64, 2080i32, 3u8, 20u8) { os.exit(374) }
    if !expect(.Coptic, 0i64 - 274286i64, 935i32, 5u8, 10u8) { os.exit(375) }
    if !expect(.Ethiopic, 0i64 - 274286i64, 1211i32, 5u8, 10u8) { os.exit(376) }
    if !expect(.Coptic, 207074i64, 2253i32, 3u8, 30u8) { os.exit(377) }
    if !expect(.Ethiopic, 207074i64, 2529i32, 3u8, 30u8) { os.exit(378) }
    if !expect(.Coptic, 208612i64, 2257i32, 6u8, 17u8) { os.exit(379) }
    if !expect(.Ethiopic, 208612i64, 2533i32, 6u8, 17u8) { os.exit(380) }
    if !expect(.Coptic, 0i64 - 423700i64, 526i32, 4u8, 13u8) { os.exit(381) }
    if !expect(.Ethiopic, 0i64 - 423700i64, 802i32, 4u8, 13u8) { os.exit(382) }
    if !expect(.Coptic, 0i64 - 441822i64, 476i32, 9u8, 3u8) { os.exit(383) }
    if !expect(.Ethiopic, 0i64 - 441822i64, 752i32, 9u8, 3u8) { os.exit(384) }
    if !expect(.Coptic, 149517i64, 2095i32, 9u8, 3u8) { os.exit(385) }
    if !expect(.Ethiopic, 149517i64, 2371i32, 9u8, 3u8) { os.exit(386) }
    if !expect(.Coptic, 0i64 - 402042i64, 585i32, 8u8, 1u8) { os.exit(387) }
    if !expect(.Ethiopic, 0i64 - 402042i64, 861i32, 8u8, 1u8) { os.exit(388) }
    if !expect(.Coptic, 0i64 - 500221i64, 316i32, 10u8, 14u8) { os.exit(389) }
    if !expect(.Ethiopic, 0i64 - 500221i64, 592i32, 10u8, 14u8) { os.exit(390) }
    if !expect(.Coptic, 0i64 - 250799i64, 999i32, 9u8, 1u8) { os.exit(391) }
    if !expect(.Ethiopic, 0i64 - 250799i64, 1275i32, 9u8, 1u8) { os.exit(392) }
    if !expect(.Coptic, 0i64 - 440826i64, 479i32, 5u8, 24u8) { os.exit(393) }
    if !expect(.Ethiopic, 0i64 - 440826i64, 755i32, 5u8, 24u8) { os.exit(394) }
    if !expect(.Coptic, 0i64 - 314i64, 1685i32, 6u8, 14u8) { os.exit(395) }
    if !expect(.Ethiopic, 0i64 - 314i64, 1961i32, 6u8, 14u8) { os.exit(396) }
    if !expect(.Coptic, 262147i64, 2404i32, 1u8, 10u8) { os.exit(397) }
    if !expect(.Ethiopic, 262147i64, 2680i32, 1u8, 10u8) { os.exit(398) }
    if !expect(.Coptic, 0i64 - 458520i64, 430i32, 12u8, 17u8) { os.exit(399) }
    if !expect(.Ethiopic, 0i64 - 458520i64, 706i32, 12u8, 17u8) { os.exit(400) }
    if !expect(.Coptic, 0i64 - 289344i64, 894i32, 2u8, 17u8) { os.exit(401) }
    if !expect(.Ethiopic, 0i64 - 289344i64, 1170i32, 2u8, 17u8) { os.exit(402) }
    if !expect(.Coptic, 0i64 - 492606i64, 337i32, 8u8, 19u8) { os.exit(403) }
    if !expect(.Ethiopic, 0i64 - 492606i64, 613i32, 8u8, 19u8) { os.exit(404) }
    if !expect(.Coptic, 133504i64, 2051i32, 11u8, 1u8) { os.exit(405) }
    if !expect(.Ethiopic, 133504i64, 2327i32, 11u8, 1u8) { os.exit(406) }
    if !expect(.Coptic, 61655i64, 1855i32, 2u8, 11u8) { os.exit(407) }
    if !expect(.Ethiopic, 61655i64, 2131i32, 2u8, 11u8) { os.exit(408) }
    if !expect(.Coptic, 0i64 - 154623i64, 1262i32, 12u8, 26u8) { os.exit(409) }
    if !expect(.Ethiopic, 0i64 - 154623i64, 1538i32, 12u8, 26u8) { os.exit(410) }
    if !expect(.Coptic, 218763i64, 2285i32, 4u8, 1u8) { os.exit(411) }
    if !expect(.Ethiopic, 218763i64, 2561i32, 4u8, 1u8) { os.exit(412) }
    if !expect(.Coptic, 50060i64, 1823i32, 5u8, 14u8) { os.exit(413) }
    if !expect(.Ethiopic, 50060i64, 2099i32, 5u8, 14u8) { os.exit(414) }
    if !expect(.Coptic, 0i64 - 326514i64, 792i32, 5u8, 12u8) { os.exit(415) }
    if !expect(.Ethiopic, 0i64 - 326514i64, 1068i32, 5u8, 12u8) { os.exit(416) }
    if !expect(.Coptic, 0i64 - 20631i64, 1629i32, 11u8, 1u8) { os.exit(417) }
    if !expect(.Ethiopic, 0i64 - 20631i64, 1905i32, 11u8, 1u8) { os.exit(418) }
    if !expect(.Coptic, 0i64 - 558552i64, 157i32, 1u8, 28u8) { os.exit(419) }
    if !expect(.Ethiopic, 0i64 - 558552i64, 433i32, 1u8, 28u8) { os.exit(420) }
    if !expect(.Coptic, 0i64 - 396757i64, 600i32, 1u8, 17u8) { os.exit(421) }
    if !expect(.Ethiopic, 0i64 - 396757i64, 876i32, 1u8, 17u8) { os.exit(422) }
    if !expect(.Coptic, 191369i64, 2210i32, 4u8, 1u8) { os.exit(423) }
    if !expect(.Ethiopic, 191369i64, 2486i32, 4u8, 1u8) { os.exit(424) }
    if !expect(.Coptic, 0i64 - 551015i64, 177i32, 9u8, 20u8) { os.exit(425) }
    if !expect(.Ethiopic, 0i64 - 551015i64, 453i32, 9u8, 20u8) { os.exit(426) }
    if !expect(.Coptic, 0i64 - 240065i64, 1029i32, 1u8, 17u8) { os.exit(427) }
    if !expect(.Ethiopic, 0i64 - 240065i64, 1305i32, 1u8, 17u8) { os.exit(428) }
    if !expect(.Coptic, 0i64 - 19165i64, 1633i32, 11u8, 6u8) { os.exit(429) }
    if !expect(.Ethiopic, 0i64 - 19165i64, 1909i32, 11u8, 6u8) { os.exit(430) }
    if !expect(.Coptic, 21501i64, 1745i32, 3u8, 4u8) { os.exit(431) }
    if !expect(.Ethiopic, 21501i64, 2021i32, 3u8, 4u8) { os.exit(432) }
    if !expect(.Coptic, 102550i64, 1967i32, 1u8, 28u8) { os.exit(433) }
    if !expect(.Ethiopic, 102550i64, 2243i32, 1u8, 28u8) { os.exit(434) }
    if !expect(.Coptic, 0i64 - 33625i64, 1594i32, 4u8, 1u8) { os.exit(435) }
    if !expect(.Ethiopic, 0i64 - 33625i64, 1870i32, 4u8, 1u8) { os.exit(436) }
    if !expect(.Coptic, 125473i64, 2029i32, 11u8, 5u8) { os.exit(437) }
    if !expect(.Ethiopic, 125473i64, 2305i32, 11u8, 5u8) { os.exit(438) }
    if !expect(.Coptic, 0i64 - 171708i64, 1216i32, 3u8, 12u8) { os.exit(439) }
    if !expect(.Ethiopic, 0i64 - 171708i64, 1492i32, 3u8, 12u8) { os.exit(440) }
    if !expect(.Coptic, 0i64 - 402796i64, 583i32, 7u8, 8u8) { os.exit(441) }
    if !expect(.Ethiopic, 0i64 - 402796i64, 859i32, 7u8, 8u8) { os.exit(442) }
    if !expect(.Coptic, 0i64 - 518588i64, 266i32, 6u8, 30u8) { os.exit(443) }
    if !expect(.Ethiopic, 0i64 - 518588i64, 542i32, 6u8, 30u8) { os.exit(444) }
    if !expect(.Coptic, 0i64 - 182156i64, 1187i32, 8u8, 7u8) { os.exit(445) }
    if !expect(.Ethiopic, 0i64 - 182156i64, 1463i32, 8u8, 7u8) { os.exit(446) }
    if !expect(.Coptic, 0i64 - 126773i64, 1339i32, 3u8, 22u8) { os.exit(447) }
    if !expect(.Ethiopic, 0i64 - 126773i64, 1615i32, 3u8, 22u8) { os.exit(448) }
    if !expect(.Coptic, 166762i64, 2142i32, 11u8, 21u8) { os.exit(449) }
    if !expect(.Ethiopic, 166762i64, 2418i32, 11u8, 21u8) { os.exit(450) }
    if !expect(.Coptic, 172903i64, 2159i32, 9u8, 13u8) { os.exit(451) }
    if !expect(.Ethiopic, 172903i64, 2435i32, 9u8, 13u8) { os.exit(452) }
    if !expect(.Coptic, 203426i64, 2243i32, 4u8, 5u8) { os.exit(453) }
    if !expect(.Ethiopic, 203426i64, 2519i32, 4u8, 5u8) { os.exit(454) }
    if !expect(.Coptic, 242318i64, 2349i32, 9u8, 30u8) { os.exit(455) }
    if !expect(.Ethiopic, 242318i64, 2625i32, 9u8, 30u8) { os.exit(456) }
    if !expect(.Coptic, 0i64 - 169220i64, 1223i32, 1u8, 4u8) { os.exit(457) }
    if !expect(.Ethiopic, 0i64 - 169220i64, 1499i32, 1u8, 4u8) { os.exit(458) }
    if !expect(.Coptic, 71888i64, 1883i32, 2u8, 17u8) { os.exit(459) }
    if !expect(.Ethiopic, 71888i64, 2159i32, 2u8, 17u8) { os.exit(460) }
    if !expect(.Coptic, 103786i64, 1970i32, 6u8, 18u8) { os.exit(461) }
    if !expect(.Ethiopic, 103786i64, 2246i32, 6u8, 18u8) { os.exit(462) }
    if !expect(.Coptic, 81842i64, 1910i32, 5u8, 19u8) { os.exit(463) }
    if !expect(.Ethiopic, 81842i64, 2186i32, 5u8, 19u8) { os.exit(464) }
    if !expect(.Coptic, 83632i64, 1915i32, 4u8, 13u8) { os.exit(465) }
    if !expect(.Ethiopic, 83632i64, 2191i32, 4u8, 13u8) { os.exit(466) }
    if !expect(.Coptic, 261069i64, 2401i32, 1u8, 28u8) { os.exit(467) }
    if !expect(.Ethiopic, 261069i64, 2677i32, 1u8, 28u8) { os.exit(468) }
    if !expect(.Coptic, 0i64 - 59704i64, 1522i32, 11u8, 10u8) { os.exit(469) }
    if !expect(.Ethiopic, 0i64 - 59704i64, 1798i32, 11u8, 10u8) { os.exit(470) }
    if !expect(.Coptic, 0i64 - 488363i64, 349i32, 3u8, 29u8) { os.exit(471) }
    if !expect(.Ethiopic, 0i64 - 488363i64, 625i32, 3u8, 29u8) { os.exit(472) }
    if !expect(.Coptic, 0i64 - 85413i64, 1452i32, 6u8, 18u8) { os.exit(473) }
    if !expect(.Ethiopic, 0i64 - 85413i64, 1728i32, 6u8, 18u8) { os.exit(474) }
    if !expect(.Coptic, 0i64 - 28795i64, 1607i32, 6u8, 23u8) { os.exit(475) }
    if !expect(.Ethiopic, 0i64 - 28795i64, 1883i32, 6u8, 23u8) { os.exit(476) }
    if !expect(.Coptic, 0i64 - 47670i64, 1555i32, 10u8, 21u8) { os.exit(477) }
    if !expect(.Ethiopic, 0i64 - 47670i64, 1831i32, 10u8, 21u8) { os.exit(478) }
    if !expect(.Coptic, 0i64 - 547434i64, 187i32, 7u8, 9u8) { os.exit(479) }
    if !expect(.Ethiopic, 0i64 - 547434i64, 463i32, 7u8, 9u8) { os.exit(480) }
    if !expect(.Coptic, 218176i64, 2283i32, 8u8, 25u8) { os.exit(481) }
    if !expect(.Ethiopic, 218176i64, 2559i32, 8u8, 25u8) { os.exit(482) }
    if !expect(.Coptic, 0i64 - 80585i64, 1465i32, 9u8, 8u8) { os.exit(483) }
    if !expect(.Ethiopic, 0i64 - 80585i64, 1741i32, 9u8, 8u8) { os.exit(484) }
    if !expect(.Coptic, 188495i64, 2202i32, 5u8, 19u8) { os.exit(485) }
    if !expect(.Ethiopic, 188495i64, 2478i32, 5u8, 19u8) { os.exit(486) }
    if !expect(.Coptic, 265349i64, 2412i32, 10u8, 20u8) { os.exit(487) }
    if !expect(.Ethiopic, 265349i64, 2688i32, 10u8, 20u8) { os.exit(488) }
    if !expect(.Coptic, 0i64 - 472621i64, 392i32, 5u8, 5u8) { os.exit(489) }
    if !expect(.Ethiopic, 0i64 - 472621i64, 668i32, 5u8, 5u8) { os.exit(490) }
    if !expect(.Coptic, 0i64 - 179806i64, 1194i32, 1u8, 10u8) { os.exit(491) }
    if !expect(.Ethiopic, 0i64 - 179806i64, 1470i32, 1u8, 10u8) { os.exit(492) }
    if !expect(.Coptic, 0i64 - 392112i64, 612i32, 10u8, 9u8) { os.exit(493) }
    if !expect(.Ethiopic, 0i64 - 392112i64, 888i32, 10u8, 9u8) { os.exit(494) }
    if !expect(.Coptic, 0i64 - 28589i64, 1608i32, 1u8, 13u8) { os.exit(495) }
    if !expect(.Ethiopic, 0i64 - 28589i64, 1884i32, 1u8, 13u8) { os.exit(496) }
    if !expect(.Coptic, 227573i64, 2309i32, 5u8, 15u8) { os.exit(497) }
    if !expect(.Ethiopic, 227573i64, 2585i32, 5u8, 15u8) { os.exit(498) }
    if !expect(.Coptic, 0i64 - 36708i64, 1585i32, 10u8, 25u8) { os.exit(499) }
    if !expect(.Ethiopic, 0i64 - 36708i64, 1861i32, 10u8, 25u8) { os.exit(500) }
    if !expect(.Coptic, 202091i64, 2239i32, 8u8, 11u8) { os.exit(501) }
    if !expect(.Ethiopic, 202091i64, 2515i32, 8u8, 11u8) { os.exit(502) }
    if !expect(.Coptic, 131467i64, 2046i32, 3u8, 30u8) { os.exit(503) }
    if !expect(.Ethiopic, 131467i64, 2322i32, 3u8, 30u8) { os.exit(504) }
    if !expect(.Coptic, 0i64 - 192971i64, 1157i32, 12u8, 29u8) { os.exit(505) }
    if !expect(.Ethiopic, 0i64 - 192971i64, 1433i32, 12u8, 29u8) { os.exit(506) }
    if !expect(.Coptic, 0i64 - 425064i64, 522i32, 7u8, 20u8) { os.exit(507) }
    if !expect(.Ethiopic, 0i64 - 425064i64, 798i32, 7u8, 20u8) { os.exit(508) }
    if !expect(.Coptic, 0i64 - 394188i64, 607i32, 1u8, 30u8) { os.exit(509) }
    if !expect(.Ethiopic, 0i64 - 394188i64, 883i32, 1u8, 30u8) { os.exit(510) }
    if !expect(.Coptic, 0i64 - 347211i64, 735i32, 9u8, 15u8) { os.exit(511) }
    if !expect(.Ethiopic, 0i64 - 347211i64, 1011i32, 9u8, 15u8) { os.exit(512) }
    if !expect(.Coptic, 0i64 - 54242i64, 1537i32, 10u8, 23u8) { os.exit(513) }
    if !expect(.Ethiopic, 0i64 - 54242i64, 1813i32, 10u8, 23u8) { os.exit(514) }
    if !expect(.Coptic, 251819i64, 2375i32, 10u8, 5u8) { os.exit(515) }
    if !expect(.Ethiopic, 251819i64, 2651i32, 10u8, 5u8) { os.exit(516) }
    if !expect(.Coptic, 0i64 - 208542i64, 1115i32, 5u8, 9u8) { os.exit(517) }
    if !expect(.Ethiopic, 0i64 - 208542i64, 1391i32, 5u8, 9u8) { os.exit(518) }
    if !expect(.Coptic, 97282i64, 1952i32, 8u8, 28u8) { os.exit(519) }
    if !expect(.Ethiopic, 97282i64, 2228i32, 8u8, 28u8) { os.exit(520) }
    if !expect(.Coptic, 19241i64, 1738i32, 13u8, 1u8) { os.exit(521) }
    if !expect(.Coptic, 19245i64, 1738i32, 13u8, 5u8) { os.exit(522) }
    if !expect(.Coptic, 19246i64, 1739i32, 1u8, 1u8) { os.exit(523) }
    if !expect(.Ethiopic, 0i64 - 81568i64, 1738i32, 13u8, 1u8) { os.exit(524) }
    if !expect(.Ethiopic, 0i64 - 81564i64, 1738i32, 13u8, 5u8) { os.exit(525) }
    if !expect(.Ethiopic, 0i64 - 81563i64, 1739i32, 1u8, 1u8) { os.exit(526) }
    if !expect(.Coptic, 19606i64, 1739i32, 13u8, 1u8) { os.exit(527) }
    if !expect(.Coptic, 19611i64, 1739i32, 13u8, 6u8) { os.exit(528) }
    if !expect(.Coptic, 19612i64, 1740i32, 1u8, 1u8) { os.exit(529) }
    if !expect(.Ethiopic, 0i64 - 81203i64, 1739i32, 13u8, 1u8) { os.exit(530) }
    if !expect(.Ethiopic, 0i64 - 81198i64, 1739i32, 13u8, 6u8) { os.exit(531) }
    if !expect(.Ethiopic, 0i64 - 81197i64, 1740i32, 1u8, 1u8) { os.exit(532) }
    if !expect(.Coptic, 19972i64, 1740i32, 13u8, 1u8) { os.exit(533) }
    if !expect(.Coptic, 19976i64, 1740i32, 13u8, 5u8) { os.exit(534) }
    if !expect(.Coptic, 19977i64, 1741i32, 1u8, 1u8) { os.exit(535) }
    if !expect(.Ethiopic, 0i64 - 80837i64, 1740i32, 13u8, 1u8) { os.exit(536) }
    if !expect(.Ethiopic, 0i64 - 80833i64, 1740i32, 13u8, 5u8) { os.exit(537) }
    if !expect(.Ethiopic, 0i64 - 80832i64, 1741i32, 1u8, 1u8) { os.exit(538) }
    if !expect(.Coptic, 20337i64, 1741i32, 13u8, 1u8) { os.exit(539) }
    if !expect(.Coptic, 20341i64, 1741i32, 13u8, 5u8) { os.exit(540) }
    if !expect(.Coptic, 20342i64, 1742i32, 1u8, 1u8) { os.exit(541) }
    if !expect(.Ethiopic, 0i64 - 80472i64, 1741i32, 13u8, 1u8) { os.exit(542) }
    if !expect(.Ethiopic, 0i64 - 80468i64, 1741i32, 13u8, 5u8) { os.exit(543) }
    if !expect(.Ethiopic, 0i64 - 80467i64, 1742i32, 1u8, 1u8) { os.exit(544) }
    if !expect(.Coptic, 20702i64, 1742i32, 13u8, 1u8) { os.exit(545) }
    if !expect(.Coptic, 20706i64, 1742i32, 13u8, 5u8) { os.exit(546) }
    if !expect(.Coptic, 20707i64, 1743i32, 1u8, 1u8) { os.exit(547) }
    if !expect(.Ethiopic, 0i64 - 80107i64, 1742i32, 13u8, 1u8) { os.exit(548) }
    if !expect(.Ethiopic, 0i64 - 80103i64, 1742i32, 13u8, 5u8) { os.exit(549) }
    if !expect(.Ethiopic, 0i64 - 80102i64, 1743i32, 1u8, 1u8) { os.exit(550) }
    if !expect(.ThaiBuddhist, 22310i64, 2574i32, 1u8, 31u8) { os.exit(551) }
    if !expect(.ThaiBuddhist, 17625i64, 2561i32, 4u8, 4u8) { os.exit(552) }
    if !expect(.ThaiBuddhist, 3585i64, 2522i32, 10u8, 26u8) { os.exit(553) }
    if !expect(.ThaiBuddhist, 14467i64, 2552i32, 8u8, 11u8) { os.exit(554) }
    if !expect(.ThaiBuddhist, 29770i64, 2594i32, 7u8, 5u8) { os.exit(555) }
    if !expect(.ThaiBuddhist, 4162i64, 2524i32, 5u8, 25u8) { os.exit(556) }
    if !expect(.ThaiBuddhist, 0i64 - 7748i64, 2491i32, 10u8, 15u8) { os.exit(557) }
    if !expect(.ThaiBuddhist, 27717i64, 2588i32, 11u8, 20u8) { os.exit(558) }
    if !expect(.ThaiBuddhist, 0i64 - 1850i64, 2507i32, 12u8, 8u8) { os.exit(559) }
    if !expect(.ThaiBuddhist, 29598i64, 2594i32, 1u8, 14u8) { os.exit(560) }
    if !expect(.ThaiBuddhist, 0i64 - 2703i64, 2505i32, 8u8, 8u8) { os.exit(561) }
    if !expect(.ThaiBuddhist, 39689i64, 2621i32, 8u8, 31u8) { os.exit(562) }
    if !expect(.ThaiBuddhist, 0i64 - 3224i64, 2504i32, 3u8, 5u8) { os.exit(563) }
    if !expect(.ThaiBuddhist, 25374i64, 2582i32, 6u8, 22u8) { os.exit(564) }
    if !expect(.ThaiBuddhist, 770i64, 2515i32, 2u8, 10u8) { os.exit(565) }
    if !expect(.ThaiBuddhist, 8023i64, 2534i32, 12u8, 20u8) { os.exit(566) }
    if !expect(.ThaiBuddhist, 0i64 - 4880i64, 2499i32, 8u8, 22u8) { os.exit(567) }
    if !expect(.ThaiBuddhist, 0i64 - 7634i64, 2492i32, 2u8, 6u8) { os.exit(568) }
    if !expect(.ThaiBuddhist, 29737i64, 2594i32, 6u8, 2u8) { os.exit(569) }
    if !expect(.ThaiBuddhist, 0i64 - 7245i64, 2493i32, 3u8, 2u8) { os.exit(570) }
    if !expect(.ThaiBuddhist, 27492i64, 2588i32, 4u8, 9u8) { os.exit(571) }
    if !expect(.ThaiBuddhist, 18534i64, 2563i32, 9u8, 29u8) { os.exit(572) }
    if !expect(.ThaiBuddhist, 0i64 - 6765i64, 2494i32, 6u8, 25u8) { os.exit(573) }
    if !expect(.ThaiBuddhist, 24615i64, 2580i32, 5u8, 24u8) { os.exit(574) }
    if !expect(.ThaiBuddhist, 25219i64, 2582i32, 1u8, 18u8) { os.exit(575) }
    if !expect(.ThaiBuddhist, 32423i64, 2601i32, 10u8, 9u8) { os.exit(576) }
    if !expect(.ThaiBuddhist, 9789i64, 2539i32, 10u8, 20u8) { os.exit(577) }
    if !expect(.ThaiBuddhist, 38000i64, 2617i32, 1u8, 15u8) { os.exit(578) }
    if !expect(.ThaiBuddhist, 14336i64, 2552i32, 4u8, 2u8) { os.exit(579) }
    if !expect(.ThaiBuddhist, 22144i64, 2573i32, 8u8, 18u8) { os.exit(580) }
    if !expect(.ThaiBuddhist, 10797i64, 2542i32, 7u8, 25u8) { os.exit(581) }
    if !expect(.ThaiBuddhist, 33616i64, 2605i32, 1u8, 14u8) { os.exit(582) }
    if !expect(.ThaiBuddhist, 6732i64, 2531i32, 6u8, 7u8) { os.exit(583) }
    if !expect(.ThaiBuddhist, 14087i64, 2551i32, 7u8, 27u8) { os.exit(584) }
    if !expect(.ThaiBuddhist, 5740i64, 2528i32, 9u8, 19u8) { os.exit(585) }
    if !expect(.ThaiBuddhist, 29544i64, 2593i32, 11u8, 21u8) { os.exit(586) }
    if !expect(.ThaiBuddhist, 21376i64, 2571i32, 7u8, 11u8) { os.exit(587) }
    if !expect(.ThaiBuddhist, 0i64 - 3961i64, 2502i32, 2u8, 27u8) { os.exit(588) }
    if !expect(.ThaiBuddhist, 0i64 - 3853i64, 2502i32, 6u8, 15u8) { os.exit(589) }
    if !expect(.ThaiBuddhist, 28874i64, 2592i32, 1u8, 20u8) { os.exit(590) }
    if !expect(.ThaiBuddhist, 11923i64, 2545i32, 8u8, 24u8) { os.exit(591) }
    if !expect(.ThaiBuddhist, 23362i64, 2576i32, 12u8, 18u8) { os.exit(592) }
    if !expect(.ThaiBuddhist, 23980i64, 2578i32, 8u8, 28u8) { os.exit(593) }
    if !expect(.ThaiBuddhist, 32457i64, 2601i32, 11u8, 12u8) { os.exit(594) }
    if !expect(.ThaiBuddhist, 14701i64, 2553i32, 4u8, 2u8) { os.exit(595) }
    if !expect(.ThaiBuddhist, 141i64, 2513i32, 5u8, 22u8) { os.exit(596) }
    if !expect(.ThaiBuddhist, 22147i64, 2573i32, 8u8, 21u8) { os.exit(597) }
    if !expect(.ThaiBuddhist, 4493i64, 2525i32, 4u8, 21u8) { os.exit(598) }
    if !expect(.ThaiBuddhist, 37429i64, 2615i32, 6u8, 23u8) { os.exit(599) }
    if !expect(.ThaiBuddhist, 13413i64, 2549i32, 9u8, 22u8) { os.exit(600) }
    if !expect(.ThaiBuddhist, 25687i64, 2583i32, 4u8, 30u8) { os.exit(601) }
    if !expect(.ThaiBuddhist, 7813i64, 2534i32, 5u8, 24u8) { os.exit(602) }
    if !expect(.ThaiBuddhist, 15058i64, 2554i32, 3u8, 25u8) { os.exit(603) }
    if !expect(.ThaiBuddhist, 27632i64, 2588i32, 8u8, 27u8) { os.exit(604) }
    if !expect(.ThaiBuddhist, 14385i64, 2552i32, 5u8, 21u8) { os.exit(605) }
    if !expect(.ThaiBuddhist, 0i64 - 4225i64, 2501i32, 6u8, 8u8) { os.exit(606) }
    if !expect(.ThaiBuddhist, 23209i64, 2576i32, 7u8, 18u8) { os.exit(607) }
    if !expect(.ThaiBuddhist, 25030i64, 2581i32, 7u8, 13u8) { os.exit(608) }
    if !expect(.ThaiBuddhist, 0i64 - 8347i64, 2490i32, 2u8, 24u8) { os.exit(609) }
    if !expect(.ThaiBuddhist, 36108i64, 2611i32, 11u8, 10u8) { os.exit(610) }
    if !expect(.ThaiBuddhist, 0i64 - 5935i64, 2496i32, 10u8, 2u8) { os.exit(611) }
    if !expect(.ThaiBuddhist, 31154i64, 2598i32, 4u8, 19u8) { os.exit(612) }
    if !expect(.ThaiBuddhist, 11946i64, 2545i32, 9u8, 16u8) { os.exit(613) }
    if !expect(.ThaiBuddhist, 0i64 - 3518i64, 2503i32, 5u8, 15u8) { os.exit(614) }
    if !expect(.ThaiBuddhist, 34141i64, 2606i32, 6u8, 23u8) { os.exit(615) }
    if !expect(.ThaiBuddhist, 17786i64, 2561i32, 9u8, 12u8) { os.exit(616) }
    if !expect(.ThaiBuddhist, 0i64 - 5366i64, 2498i32, 4u8, 24u8) { os.exit(617) }
    if !expect(.ThaiBuddhist, 0i64 - 1793i64, 2508i32, 2u8, 3u8) { os.exit(618) }
    if !expect(.ThaiBuddhist, 8332i64, 2535i32, 10u8, 24u8) { os.exit(619) }
    if !expect(.ThaiBuddhist, 0i64 - 3453i64, 2503i32, 7u8, 19u8) { os.exit(620) }
    if !expect(.ThaiBuddhist, 11100i64, 2543i32, 5u8, 23u8) { os.exit(621) }
    if !expect(.ThaiBuddhist, 11935i64, 2545i32, 9u8, 5u8) { os.exit(622) }
    if !expect(.ThaiBuddhist, 0i64 - 2694i64, 2505i32, 8u8, 17u8) { os.exit(623) }
    if !expect(.ThaiBuddhist, 33275i64, 2604i32, 2u8, 7u8) { os.exit(624) }
    if !expect(.ThaiBuddhist, 36790i64, 2613i32, 9u8, 23u8) { os.exit(625) }
    if !expect(.ThaiBuddhist, 1568i64, 2517i32, 4u8, 18u8) { os.exit(626) }
    if !expect(.ThaiBuddhist, 33226i64, 2603i32, 12u8, 20u8) { os.exit(627) }
    if !expect(.ThaiBuddhist, 11784i64, 2545i32, 4u8, 7u8) { os.exit(628) }
    if !expect(.ThaiBuddhist, 16483i64, 2558i32, 2u8, 17u8) { os.exit(629) }
    if !expect(.ThaiBuddhist, 38750i64, 2619i32, 2u8, 4u8) { os.exit(630) }
    if !expect(.ThaiBuddhist, 2867i64, 2520i32, 11u8, 7u8) { os.exit(631) }
    if !expect(.ThaiBuddhist, 3782i64, 2523i32, 5u8, 10u8) { os.exit(632) }
    if !expect(.ThaiBuddhist, 32396i64, 2601i32, 9u8, 12u8) { os.exit(633) }
    if !expect(.ThaiBuddhist, 12304i64, 2546i32, 9u8, 9u8) { os.exit(634) }
    if !expect(.ThaiBuddhist, 3593i64, 2522i32, 11u8, 3u8) { os.exit(635) }
    if !expect(.ThaiBuddhist, 25656i64, 2583i32, 3u8, 30u8) { os.exit(636) }
    if !expect(.ThaiBuddhist, 33904i64, 2605i32, 10u8, 29u8) { os.exit(637) }
    if !expect(.ThaiBuddhist, 0i64 - 9424i64, 2487i32, 3u8, 14u8) { os.exit(638) }
    if !expect(.ThaiBuddhist, 8848i64, 2537i32, 3u8, 24u8) { os.exit(639) }
    if !expect(.ThaiBuddhist, 0i64 - 5207i64, 2498i32, 9u8, 30u8) { os.exit(640) }
    if !expect(.ThaiBuddhist, 3969i64, 2523i32, 11u8, 13u8) { os.exit(641) }
    if !expect(.ThaiBuddhist, 33598i64, 2604i32, 12u8, 27u8) { os.exit(642) }
    if !expect(.ThaiBuddhist, 0i64 - 5642i64, 2497i32, 7u8, 22u8) { os.exit(643) }
    if !expect(.ThaiBuddhist, 23311i64, 2576i32, 10u8, 28u8) { os.exit(644) }
    if !expect(.ThaiBuddhist, 33029i64, 2603i32, 6u8, 6u8) { os.exit(645) }
    if !expect(.ThaiBuddhist, 0i64 - 4306i64, 2501i32, 3u8, 19u8) { os.exit(646) }
    if !expect(.ThaiBuddhist, 29078i64, 2592i32, 8u8, 12u8) { os.exit(647) }
    if !expect(.ThaiBuddhist, 0i64 - 9145i64, 2487i32, 12u8, 18u8) { os.exit(648) }
    if !expect(.ThaiBuddhist, 9785i64, 2539i32, 10u8, 16u8) { os.exit(649) }
    if !expect(.ThaiBuddhist, 25497i64, 2582i32, 10u8, 23u8) { os.exit(650) }
    if !expect(.ThaiBuddhist, 27180i64, 2587i32, 6u8, 1u8) { os.exit(651) }
    if !expect(.ThaiBuddhist, 6463i64, 2530i32, 9u8, 12u8) { os.exit(652) }
    if !expect(.ThaiBuddhist, 20476i64, 2569i32, 1u8, 23u8) { os.exit(653) }
    if !expect(.ThaiBuddhist, 35763i64, 2610i32, 12u8, 1u8) { os.exit(654) }
    if !expect(.ThaiBuddhist, 27294i64, 2587i32, 9u8, 23u8) { os.exit(655) }
    if !expect(.ThaiBuddhist, 34547i64, 2607i32, 8u8, 2u8) { os.exit(656) }
    if !expect(.ThaiBuddhist, 2192i64, 2519i32, 1u8, 2u8) { os.exit(657) }
    if !expect(.ThaiBuddhist, 16293i64, 2557i32, 8u8, 11u8) { os.exit(658) }
    if !expect(.ThaiBuddhist, 32564i64, 2602i32, 2u8, 27u8) { os.exit(659) }
    if !expect(.ThaiBuddhist, 22474i64, 2574i32, 7u8, 14u8) { os.exit(660) }
    if !expect(.ThaiBuddhist, 31627i64, 2599i32, 8u8, 4u8) { os.exit(661) }
    if !expect(.ThaiBuddhist, 34576i64, 2607i32, 8u8, 31u8) { os.exit(662) }
    if !expect(.ThaiBuddhist, 7081i64, 2532i32, 5u8, 22u8) { os.exit(663) }
    if !expect(.ThaiBuddhist, 5532i64, 2528i32, 2u8, 23u8) { os.exit(664) }
    if !expect(.ThaiBuddhist, 28033i64, 2589i32, 10u8, 2u8) { os.exit(665) }
    if !expect(.ThaiBuddhist, 35506i64, 2610i32, 3u8, 19u8) { os.exit(666) }
    if !expect(.ThaiBuddhist, 0i64 - 774i64, 2510i32, 11u8, 19u8) { os.exit(667) }
    if !expect(.ThaiBuddhist, 23514i64, 2577i32, 5u8, 19u8) { os.exit(668) }
    if !expect(.ThaiBuddhist, 35501i64, 2610i32, 3u8, 14u8) { os.exit(669) }
    if !expect(.ThaiBuddhist, 15969i64, 2556i32, 9u8, 21u8) { os.exit(670) }
    if !calendars.is_leap_year(.ThaiBuddhist, 2567i32) || calendars.is_leap_year(.ThaiBuddhist, 2566i32) || calendars.is_leap_year(.ThaiBuddhist, 2643i32) { os.exit(671) }
    let (feb, feb_e) = calendars.days_in_month(.ThaiBuddhist, 2567i32, 2u8)
    if feb_e != ok || feb != 29u8 { os.exit(672) }
    let (l672, le672) = calendars.days_in_month(.Coptic, 1i32, 1u8)
    if le672 != ok || l672 != 30u8 { os.exit(673) }
    let (l673, le673) = calendars.days_in_month(.Coptic, 1i32, 6u8)
    if le673 != ok || l673 != 30u8 { os.exit(674) }
    let (l674, le674) = calendars.days_in_month(.Coptic, 1i32, 12u8)
    if le674 != ok || l674 != 30u8 { os.exit(675) }
    let (l675, le675) = calendars.days_in_month(.Coptic, 1i32, 13u8)
    if le675 != ok || l675 != 5u8 { os.exit(676) }
    let (l676, le676) = calendars.days_in_month(.Coptic, 2i32, 1u8)
    if le676 != ok || l676 != 30u8 { os.exit(677) }
    let (l677, le677) = calendars.days_in_month(.Coptic, 2i32, 6u8)
    if le677 != ok || l677 != 30u8 { os.exit(678) }
    let (l678, le678) = calendars.days_in_month(.Coptic, 2i32, 12u8)
    if le678 != ok || l678 != 30u8 { os.exit(679) }
    let (l679, le679) = calendars.days_in_month(.Coptic, 2i32, 13u8)
    if le679 != ok || l679 != 5u8 { os.exit(680) }
    let (l680, le680) = calendars.days_in_month(.Coptic, 3i32, 1u8)
    if le680 != ok || l680 != 30u8 { os.exit(681) }
    let (l681, le681) = calendars.days_in_month(.Coptic, 3i32, 6u8)
    if le681 != ok || l681 != 30u8 { os.exit(682) }
    let (l682, le682) = calendars.days_in_month(.Coptic, 3i32, 12u8)
    if le682 != ok || l682 != 30u8 { os.exit(683) }
    let (l683, le683) = calendars.days_in_month(.Coptic, 3i32, 13u8)
    if le683 != ok || l683 != 6u8 { os.exit(684) }
    let (l684, le684) = calendars.days_in_month(.Coptic, 4i32, 1u8)
    if le684 != ok || l684 != 30u8 { os.exit(685) }
    let (l685, le685) = calendars.days_in_month(.Coptic, 4i32, 6u8)
    if le685 != ok || l685 != 30u8 { os.exit(686) }
    let (l686, le686) = calendars.days_in_month(.Coptic, 4i32, 12u8)
    if le686 != ok || l686 != 30u8 { os.exit(687) }
    let (l687, le687) = calendars.days_in_month(.Coptic, 4i32, 13u8)
    if le687 != ok || l687 != 5u8 { os.exit(688) }
    let (l688, le688) = calendars.days_in_month(.Coptic, 5i32, 1u8)
    if le688 != ok || l688 != 30u8 { os.exit(689) }
    let (l689, le689) = calendars.days_in_month(.Coptic, 5i32, 6u8)
    if le689 != ok || l689 != 30u8 { os.exit(690) }
    let (l690, le690) = calendars.days_in_month(.Coptic, 5i32, 12u8)
    if le690 != ok || l690 != 30u8 { os.exit(691) }
    let (l691, le691) = calendars.days_in_month(.Coptic, 5i32, 13u8)
    if le691 != ok || l691 != 5u8 { os.exit(692) }
    let (l692, le692) = calendars.days_in_month(.Coptic, 6i32, 1u8)
    if le692 != ok || l692 != 30u8 { os.exit(693) }
    let (l693, le693) = calendars.days_in_month(.Coptic, 6i32, 6u8)
    if le693 != ok || l693 != 30u8 { os.exit(694) }
    let (l694, le694) = calendars.days_in_month(.Coptic, 6i32, 12u8)
    if le694 != ok || l694 != 30u8 { os.exit(695) }
    let (l695, le695) = calendars.days_in_month(.Coptic, 6i32, 13u8)
    if le695 != ok || l695 != 5u8 { os.exit(696) }
    let (l696, le696) = calendars.days_in_month(.Coptic, 7i32, 1u8)
    if le696 != ok || l696 != 30u8 { os.exit(697) }
    let (l697, le697) = calendars.days_in_month(.Coptic, 7i32, 6u8)
    if le697 != ok || l697 != 30u8 { os.exit(698) }
    let (l698, le698) = calendars.days_in_month(.Coptic, 7i32, 12u8)
    if le698 != ok || l698 != 30u8 { os.exit(699) }
    let (l699, le699) = calendars.days_in_month(.Coptic, 7i32, 13u8)
    if le699 != ok || l699 != 6u8 { os.exit(700) }
    let (l700, le700) = calendars.days_in_month(.Coptic, 8i32, 1u8)
    if le700 != ok || l700 != 30u8 { os.exit(701) }
    let (l701, le701) = calendars.days_in_month(.Coptic, 8i32, 6u8)
    if le701 != ok || l701 != 30u8 { os.exit(702) }
    let (l702, le702) = calendars.days_in_month(.Coptic, 8i32, 12u8)
    if le702 != ok || l702 != 30u8 { os.exit(703) }
    let (l703, le703) = calendars.days_in_month(.Coptic, 8i32, 13u8)
    if le703 != ok || l703 != 5u8 { os.exit(704) }
    let (l704, le704) = calendars.days_in_month(.Coptic, 9i32, 1u8)
    if le704 != ok || l704 != 30u8 { os.exit(705) }
    let (l705, le705) = calendars.days_in_month(.Coptic, 9i32, 6u8)
    if le705 != ok || l705 != 30u8 { os.exit(706) }
    let (l706, le706) = calendars.days_in_month(.Coptic, 9i32, 12u8)
    if le706 != ok || l706 != 30u8 { os.exit(707) }
    let (l707, le707) = calendars.days_in_month(.Coptic, 9i32, 13u8)
    if le707 != ok || l707 != 5u8 { os.exit(708) }
    let (l708, le708) = calendars.days_in_month(.Coptic, 10i32, 1u8)
    if le708 != ok || l708 != 30u8 { os.exit(709) }
    let (l709, le709) = calendars.days_in_month(.Coptic, 10i32, 6u8)
    if le709 != ok || l709 != 30u8 { os.exit(710) }
    let (l710, le710) = calendars.days_in_month(.Coptic, 10i32, 12u8)
    if le710 != ok || l710 != 30u8 { os.exit(711) }
    let (l711, le711) = calendars.days_in_month(.Coptic, 10i32, 13u8)
    if le711 != ok || l711 != 5u8 { os.exit(712) }
    let (l712, le712) = calendars.days_in_month(.Coptic, 11i32, 1u8)
    if le712 != ok || l712 != 30u8 { os.exit(713) }
    let (l713, le713) = calendars.days_in_month(.Coptic, 11i32, 6u8)
    if le713 != ok || l713 != 30u8 { os.exit(714) }
    let (l714, le714) = calendars.days_in_month(.Coptic, 11i32, 12u8)
    if le714 != ok || l714 != 30u8 { os.exit(715) }
    let (l715, le715) = calendars.days_in_month(.Coptic, 11i32, 13u8)
    if le715 != ok || l715 != 6u8 { os.exit(716) }
    let (l716, le716) = calendars.days_in_month(.Ethiopic, 1i32, 1u8)
    if le716 != ok || l716 != 30u8 { os.exit(717) }
    let (l717, le717) = calendars.days_in_month(.Ethiopic, 1i32, 6u8)
    if le717 != ok || l717 != 30u8 { os.exit(718) }
    let (l718, le718) = calendars.days_in_month(.Ethiopic, 1i32, 12u8)
    if le718 != ok || l718 != 30u8 { os.exit(719) }
    let (l719, le719) = calendars.days_in_month(.Ethiopic, 1i32, 13u8)
    if le719 != ok || l719 != 5u8 { os.exit(720) }
    let (l720, le720) = calendars.days_in_month(.Ethiopic, 2i32, 1u8)
    if le720 != ok || l720 != 30u8 { os.exit(721) }
    let (l721, le721) = calendars.days_in_month(.Ethiopic, 2i32, 6u8)
    if le721 != ok || l721 != 30u8 { os.exit(722) }
    let (l722, le722) = calendars.days_in_month(.Ethiopic, 2i32, 12u8)
    if le722 != ok || l722 != 30u8 { os.exit(723) }
    let (l723, le723) = calendars.days_in_month(.Ethiopic, 2i32, 13u8)
    if le723 != ok || l723 != 5u8 { os.exit(724) }
    let (l724, le724) = calendars.days_in_month(.Ethiopic, 3i32, 1u8)
    if le724 != ok || l724 != 30u8 { os.exit(725) }
    let (l725, le725) = calendars.days_in_month(.Ethiopic, 3i32, 6u8)
    if le725 != ok || l725 != 30u8 { os.exit(726) }
    let (l726, le726) = calendars.days_in_month(.Ethiopic, 3i32, 12u8)
    if le726 != ok || l726 != 30u8 { os.exit(727) }
    let (l727, le727) = calendars.days_in_month(.Ethiopic, 3i32, 13u8)
    if le727 != ok || l727 != 6u8 { os.exit(728) }
    let (l728, le728) = calendars.days_in_month(.Ethiopic, 4i32, 1u8)
    if le728 != ok || l728 != 30u8 { os.exit(729) }
    let (l729, le729) = calendars.days_in_month(.Ethiopic, 4i32, 6u8)
    if le729 != ok || l729 != 30u8 { os.exit(730) }
    let (l730, le730) = calendars.days_in_month(.Ethiopic, 4i32, 12u8)
    if le730 != ok || l730 != 30u8 { os.exit(731) }
    let (l731, le731) = calendars.days_in_month(.Ethiopic, 4i32, 13u8)
    if le731 != ok || l731 != 5u8 { os.exit(732) }
    let (l732, le732) = calendars.days_in_month(.Ethiopic, 5i32, 1u8)
    if le732 != ok || l732 != 30u8 { os.exit(733) }
    let (l733, le733) = calendars.days_in_month(.Ethiopic, 5i32, 6u8)
    if le733 != ok || l733 != 30u8 { os.exit(734) }
    let (l734, le734) = calendars.days_in_month(.Ethiopic, 5i32, 12u8)
    if le734 != ok || l734 != 30u8 { os.exit(735) }
    let (l735, le735) = calendars.days_in_month(.Ethiopic, 5i32, 13u8)
    if le735 != ok || l735 != 5u8 { os.exit(736) }
    let (l736, le736) = calendars.days_in_month(.Ethiopic, 6i32, 1u8)
    if le736 != ok || l736 != 30u8 { os.exit(737) }
    let (l737, le737) = calendars.days_in_month(.Ethiopic, 6i32, 6u8)
    if le737 != ok || l737 != 30u8 { os.exit(738) }
    let (l738, le738) = calendars.days_in_month(.Ethiopic, 6i32, 12u8)
    if le738 != ok || l738 != 30u8 { os.exit(739) }
    let (l739, le739) = calendars.days_in_month(.Ethiopic, 6i32, 13u8)
    if le739 != ok || l739 != 5u8 { os.exit(740) }
    let (l740, le740) = calendars.days_in_month(.Ethiopic, 7i32, 1u8)
    if le740 != ok || l740 != 30u8 { os.exit(741) }
    let (l741, le741) = calendars.days_in_month(.Ethiopic, 7i32, 6u8)
    if le741 != ok || l741 != 30u8 { os.exit(742) }
    let (l742, le742) = calendars.days_in_month(.Ethiopic, 7i32, 12u8)
    if le742 != ok || l742 != 30u8 { os.exit(743) }
    let (l743, le743) = calendars.days_in_month(.Ethiopic, 7i32, 13u8)
    if le743 != ok || l743 != 6u8 { os.exit(744) }
    let (l744, le744) = calendars.days_in_month(.Ethiopic, 8i32, 1u8)
    if le744 != ok || l744 != 30u8 { os.exit(745) }
    let (l745, le745) = calendars.days_in_month(.Ethiopic, 8i32, 6u8)
    if le745 != ok || l745 != 30u8 { os.exit(746) }
    let (l746, le746) = calendars.days_in_month(.Ethiopic, 8i32, 12u8)
    if le746 != ok || l746 != 30u8 { os.exit(747) }
    let (l747, le747) = calendars.days_in_month(.Ethiopic, 8i32, 13u8)
    if le747 != ok || l747 != 5u8 { os.exit(748) }
    let (l748, le748) = calendars.days_in_month(.Ethiopic, 9i32, 1u8)
    if le748 != ok || l748 != 30u8 { os.exit(749) }
    let (l749, le749) = calendars.days_in_month(.Ethiopic, 9i32, 6u8)
    if le749 != ok || l749 != 30u8 { os.exit(750) }
    let (l750, le750) = calendars.days_in_month(.Ethiopic, 9i32, 12u8)
    if le750 != ok || l750 != 30u8 { os.exit(751) }
    let (l751, le751) = calendars.days_in_month(.Ethiopic, 9i32, 13u8)
    if le751 != ok || l751 != 5u8 { os.exit(752) }
    let (l752, le752) = calendars.days_in_month(.Ethiopic, 10i32, 1u8)
    if le752 != ok || l752 != 30u8 { os.exit(753) }
    let (l753, le753) = calendars.days_in_month(.Ethiopic, 10i32, 6u8)
    if le753 != ok || l753 != 30u8 { os.exit(754) }
    let (l754, le754) = calendars.days_in_month(.Ethiopic, 10i32, 12u8)
    if le754 != ok || l754 != 30u8 { os.exit(755) }
    let (l755, le755) = calendars.days_in_month(.Ethiopic, 10i32, 13u8)
    if le755 != ok || l755 != 5u8 { os.exit(756) }
    let (l756, le756) = calendars.days_in_month(.Ethiopic, 11i32, 1u8)
    if le756 != ok || l756 != 30u8 { os.exit(757) }
    let (l757, le757) = calendars.days_in_month(.Ethiopic, 11i32, 6u8)
    if le757 != ok || l757 != 30u8 { os.exit(758) }
    let (l758, le758) = calendars.days_in_month(.Ethiopic, 11i32, 12u8)
    if le758 != ok || l758 != 30u8 { os.exit(759) }
    let (l759, le759) = calendars.days_in_month(.Ethiopic, 11i32, 13u8)
    if le759 != ok || l759 != 6u8 { os.exit(760) }
    if !calendars.is_leap_year(.Coptic, 3i32) || !calendars.is_leap_year(.Coptic, 1739i32) || calendars.is_leap_year(.Coptic, 1740i32) { os.exit(761) }
    if !calendars.is_leap_year(.Ethiopic, 3i32) || !calendars.is_leap_year(.Ethiopic, 1739i32) || calendars.is_leap_year(.Ethiopic, 1740i32) { os.exit(762) }
    let (c1, ce1) = calendars.convert(.Coptic, .Julian, time.Date{ year: 1i32, month: 1u8, day: 1u8 })
    if ce1 != ok || c1.year != 284i32 || c1.month != 8u8 || c1.day != 29u8 { os.exit(763) }
    let (e1, ee1) = calendars.convert(.Ethiopic, .Julian, time.Date{ year: 1i32, month: 1u8, day: 1u8 })
    if ee1 != ok || e1.year != 8i32 || e1.month != 8u8 || e1.day != 29u8 { os.exit(764) }
    let (bad, bade) = calendars.days_in_month(.Coptic, 0i32, 1u8)
    if bade == ok { os.exit(765) }
    ret ok
}
