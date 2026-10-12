// `e.time.calendars` Persian (33-year arithmetic) and Umm al-Qura against convertdate and hijridate
// (scripts/gen_persian_uq_test.py): 492 date/day-count pairs both ways, month lengths and leap years. Every check
// has its own exit code.
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

fn len_is(cal: calendars.Calendar, year: i32, month: u8, want: u8) -> bool {
    let (n, e) = calendars.days_in_month(cal, year, month)
    ret e == ok && n == want
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !expect(.Persian, 0i64 - 3384i64, 1339i32, 7u8, 4u8) { os.exit(1) }
    if !expect(.Persian, 42365i64, 1464i32, 10u8, 8u8) { os.exit(2) }
    if !expect(.Persian, 52409i64, 1492i32, 4u8, 8u8) { os.exit(3) }
    if !expect(.Persian, 37228i64, 1450i32, 9u8, 14u8) { os.exit(4) }
    if !expect(.Persian, 9162i64, 1373i32, 11u8, 12u8) { os.exit(5) }
    if !expect(.Persian, 30790i64, 1433i32, 1u8, 31u8) { os.exit(6) }
    if !expect(.Persian, 41514i64, 1462i32, 6u8, 8u8) { os.exit(7) }
    if !expect(.Persian, 20354i64, 1404i32, 7u8, 1u8) { os.exit(8) }
    if !expect(.Persian, 46232i64, 1475i32, 5u8, 9u8) { os.exit(9) }
    if !expect(.Persian, 0i64 - 20203i64, 1293i32, 6u8, 17u8) { os.exit(10) }
    if !expect(.Persian, 50795i64, 1487i32, 11u8, 7u8) { os.exit(11) }
    if !expect(.Persian, 31978i64, 1436i32, 4u8, 31u8) { os.exit(12) }
    if !expect(.Persian, 14891i64, 1389i32, 7u8, 17u8) { os.exit(13) }
    if !expect(.Persian, 0i64 - 10682i64, 1319i32, 7u8, 11u8) { os.exit(14) }
    if !expect(.Persian, 35636i64, 1446i32, 5u8, 5u8) { os.exit(15) }
    if !expect(.Persian, 7783i64, 1370i32, 2u8, 4u8) { os.exit(16) }
    if !expect(.Persian, 1092i64, 1351i32, 10u8, 7u8) { os.exit(17) }
    if !expect(.Persian, 32179i64, 1436i32, 11u8, 19u8) { os.exit(18) }
    if !expect(.Persian, 0i64 - 19420i64, 1295i32, 8u8, 9u8) { os.exit(19) }
    if !expect(.Persian, 41029i64, 1461i32, 2u8, 13u8) { os.exit(20) }
    if !expect(.Persian, 22382i64, 1410i32, 1u8, 24u8) { os.exit(21) }
    if !expect(.Persian, 0i64 - 1267i64, 1345i32, 4u8, 23u8) { os.exit(22) }
    if !expect(.Persian, 22810i64, 1411i32, 3u8, 25u8) { os.exit(23) }
    if !expect(.Persian, 12225i64, 1382i32, 4u8, 1u8) { os.exit(24) }
    if !expect(.Persian, 0i64 - 4863i64, 1335i32, 6u8, 17u8) { os.exit(25) }
    if !expect(.Persian, 26277i64, 1420i32, 9u8, 21u8) { os.exit(26) }
    if !expect(.Persian, 24508i64, 1415i32, 11u8, 18u8) { os.exit(27) }
    if !expect(.Persian, 31541i64, 1435i32, 2u8, 21u8) { os.exit(28) }
    if !expect(.Persian, 0i64 - 10725i64, 1319i32, 5u8, 30u8) { os.exit(29) }
    if !expect(.Persian, 0i64 - 10793i64, 1319i32, 3u8, 24u8) { os.exit(30) }
    if !expect(.Persian, 0i64 - 12875i64, 1313i32, 7u8, 10u8) { os.exit(31) }
    if !expect(.Persian, 23202i64, 1412i32, 4u8, 21u8) { os.exit(32) }
    if !expect(.Persian, 32495i64, 1437i32, 9u8, 29u8) { os.exit(33) }
    if !expect(.Persian, 5391i64, 1363i32, 7u8, 13u8) { os.exit(34) }
    if !expect(.Persian, 23474i64, 1413i32, 1u8, 20u8) { os.exit(35) }
    if !expect(.Persian, 41504i64, 1462i32, 5u8, 29u8) { os.exit(36) }
    if !expect(.Persian, 32732i64, 1438i32, 5u8, 23u8) { os.exit(37) }
    if !expect(.Persian, 18651i64, 1399i32, 11u8, 5u8) { os.exit(38) }
    if !expect(.Persian, 0i64 - 11348i64, 1317i32, 9u8, 16u8) { os.exit(39) }
    if !expect(.Persian, 51504i64, 1489i32, 10u8, 16u8) { os.exit(40) }
    if !expect(.Persian, 16054i64, 1392i32, 9u8, 24u8) { os.exit(41) }
    if !expect(.Persian, 0i64 - 918i64, 1346i32, 4u8, 7u8) { os.exit(42) }
    if !expect(.Persian, 44447i64, 1470i32, 6u8, 19u8) { os.exit(43) }
    if !expect(.Persian, 35286i64, 1445i32, 5u8, 21u8) { os.exit(44) }
    if !expect(.Persian, 4787i64, 1361i32, 11u8, 20u8) { os.exit(45) }
    if !expect(.Persian, 0i64 - 5944i64, 1332i32, 7u8, 1u8) { os.exit(46) }
    if !expect(.Persian, 3700i64, 1358i32, 11u8, 29u8) { os.exit(47) }
    if !expect(.Persian, 49725i64, 1484i32, 12u8, 3u8) { os.exit(48) }
    if !expect(.Persian, 9655i64, 1375i32, 3u8, 19u8) { os.exit(49) }
    if !expect(.Persian, 3969i64, 1359i32, 8u8, 22u8) { os.exit(50) }
    if !expect(.Persian, 7288i64, 1368i32, 9u8, 24u8) { os.exit(51) }
    if !expect(.Persian, 0i64 - 14365i64, 1309i32, 6u8, 12u8) { os.exit(52) }
    if !expect(.Persian, 0i64 - 6071i64, 1332i32, 2u8, 29u8) { os.exit(53) }
    if !expect(.Persian, 0i64 - 3753i64, 1338i32, 6u8, 31u8) { os.exit(54) }
    if !expect(.Persian, 51472i64, 1489i32, 9u8, 14u8) { os.exit(55) }
    if !expect(.Persian, 42626i64, 1465i32, 6u8, 25u8) { os.exit(56) }
    if !expect(.Persian, 6221i64, 1365i32, 10u8, 23u8) { os.exit(57) }
    if !expect(.Persian, 44214i64, 1469i32, 11u8, 1u8) { os.exit(58) }
    if !expect(.Persian, 52417i64, 1492i32, 4u8, 16u8) { os.exit(59) }
    if !expect(.Persian, 13261i64, 1385i32, 2u8, 3u8) { os.exit(60) }
    if !expect(.Persian, 29058i64, 1428i32, 5u8, 2u8) { os.exit(61) }
    if !expect(.Persian, 7920i64, 1370i32, 6u8, 17u8) { os.exit(62) }
    if !expect(.Persian, 0i64 - 18720i64, 1297i32, 7u8, 8u8) { os.exit(63) }
    if !expect(.Persian, 0i64 - 20821i64, 1291i32, 10u8, 9u8) { os.exit(64) }
    if !expect(.Persian, 26312i64, 1420i32, 10u8, 26u8) { os.exit(65) }
    if !expect(.Persian, 0i64 - 17728i64, 1300i32, 3u8, 29u8) { os.exit(66) }
    if !expect(.Persian, 17070i64, 1395i32, 7u8, 5u8) { os.exit(67) }
    if !expect(.Persian, 0i64 - 10038i64, 1321i32, 4u8, 18u8) { os.exit(68) }
    if !expect(.Persian, 0i64 - 10441i64, 1320i32, 3u8, 11u8) { os.exit(69) }
    if !expect(.Persian, 30127i64, 1431i32, 4u8, 6u8) { os.exit(70) }
    if !expect(.Persian, 26164i64, 1420i32, 5u8, 30u8) { os.exit(71) }
    if !expect(.Persian, 0i64 - 2780i64, 1341i32, 3u8, 2u8) { os.exit(72) }
    if !expect(.Persian, 34623i64, 1443i32, 7u8, 26u8) { os.exit(73) }
    if !expect(.Persian, 46374i64, 1475i32, 9u8, 29u8) { os.exit(74) }
    if !expect(.Persian, 0i64 - 20540i64, 1292i32, 7u8, 15u8) { os.exit(75) }
    if !expect(.Persian, 54568i64, 1498i32, 3u8, 7u8) { os.exit(76) }
    if !expect(.Persian, 43926i64, 1469i32, 1u8, 19u8) { os.exit(77) }
    if !expect(.Persian, 14121i64, 1387i32, 6u8, 9u8) { os.exit(78) }
    if !expect(.Persian, 49660i64, 1484i32, 9u8, 28u8) { os.exit(79) }
    if !expect(.Persian, 0i64 - 21155i64, 1290i32, 11u8, 10u8) { os.exit(80) }
    if !expect(.Persian, 43209i64, 1467i32, 2u8, 1u8) { os.exit(81) }
    if !expect(.Persian, 32192i64, 1436i32, 12u8, 2u8) { os.exit(82) }
    if !expect(.Persian, 0i64 - 22046i64, 1288i32, 6u8, 1u8) { os.exit(83) }
    if !expect(.Persian, 32203i64, 1436i32, 12u8, 13u8) { os.exit(84) }
    if !expect(.Persian, 48427i64, 1481i32, 5u8, 13u8) { os.exit(85) }
    if !expect(.Persian, 14438i64, 1388i32, 4u8, 22u8) { os.exit(86) }
    if !expect(.Persian, 17814i64, 1397i32, 7u8, 18u8) { os.exit(87) }
    if !expect(.Persian, 43937i64, 1469i32, 1u8, 30u8) { os.exit(88) }
    if !expect(.Persian, 0i64 - 20305i64, 1293i32, 3u8, 8u8) { os.exit(89) }
    if !expect(.Persian, 32896i64, 1438i32, 11u8, 5u8) { os.exit(90) }
    if !expect(.Persian, 0i64 - 12664i64, 1314i32, 2u8, 10u8) { os.exit(91) }
    if !expect(.Persian, 42447i64, 1465i32, 1u8, 1u8) { os.exit(92) }
    if !expect(.Persian, 43456i64, 1467i32, 10u8, 3u8) { os.exit(93) }
    if !expect(.Persian, 0i64 - 6566i64, 1330i32, 10u8, 19u8) { os.exit(94) }
    if !expect(.Persian, 24497i64, 1415i32, 11u8, 7u8) { os.exit(95) }
    if !expect(.Persian, 0i64 - 11081i64, 1318i32, 6u8, 8u8) { os.exit(96) }
    if !expect(.Persian, 0i64 - 11638i64, 1316i32, 12u8, 1u8) { os.exit(97) }
    if !expect(.Persian, 42484i64, 1465i32, 2u8, 7u8) { os.exit(98) }
    if !expect(.Persian, 0i64 - 10579i64, 1319i32, 10u8, 24u8) { os.exit(99) }
    if !expect(.Persian, 0i64 - 11341i64, 1317i32, 9u8, 23u8) { os.exit(100) }
    if !expect(.Persian, 32676i64, 1438i32, 3u8, 29u8) { os.exit(101) }
    if !expect(.Persian, 29605i64, 1429i32, 11u8, 1u8) { os.exit(102) }
    if !expect(.Persian, 15427i64, 1391i32, 1u8, 9u8) { os.exit(103) }
    if !expect(.Persian, 21114i64, 1406i32, 8u8, 1u8) { os.exit(104) }
    if !expect(.Persian, 43921i64, 1469i32, 1u8, 14u8) { os.exit(105) }
    if !expect(.Persian, 76i64, 1348i32, 12u8, 27u8) { os.exit(106) }
    if !expect(.Persian, 32807i64, 1438i32, 8u8, 6u8) { os.exit(107) }
    if !expect(.Persian, 35646i64, 1446i32, 5u8, 15u8) { os.exit(108) }
    if !expect(.Persian, 0i64 - 2732i64, 1341i32, 4u8, 19u8) { os.exit(109) }
    if !expect(.Persian, 10138i64, 1376i32, 7u8, 12u8) { os.exit(110) }
    if !expect(.Persian, 0i64 - 16917i64, 1302i32, 6u8, 16u8) { os.exit(111) }
    if !expect(.Persian, 21319i64, 1407i32, 2u8, 26u8) { os.exit(112) }
    if !expect(.Persian, 53659i64, 1495i32, 9u8, 9u8) { os.exit(113) }
    if !expect(.Persian, 38510i64, 1454i32, 3u8, 19u8) { os.exit(114) }
    if !expect(.Persian, 0i64 - 19776i64, 1294i32, 8u8, 18u8) { os.exit(115) }
    if !expect(.Persian, 37069i64, 1450i32, 4u8, 8u8) { os.exit(116) }
    if !expect(.Persian, 15092i64, 1390i32, 2u8, 8u8) { os.exit(117) }
    if !expect(.Persian, 3361i64, 1357i32, 12u8, 25u8) { os.exit(118) }
    if !expect(.Persian, 52364i64, 1492i32, 2u8, 25u8) { os.exit(119) }
    if !expect(.Persian, 0i64 - 20063i64, 1293i32, 11u8, 6u8) { os.exit(120) }
    if !expect(.Persian, 5778i64, 1364i32, 8u8, 5u8) { os.exit(121) }
    if !expect(.Persian, 41219i64, 1461i32, 8u8, 18u8) { os.exit(122) }
    if !expect(.Persian, 0i64 - 16608i64, 1303i32, 4u8, 22u8) { os.exit(123) }
    if !expect(.Persian, 18859i64, 1400i32, 5u8, 29u8) { os.exit(124) }
    if !expect(.Persian, 50992i64, 1488i32, 5u8, 21u8) { os.exit(125) }
    if !expect(.Persian, 7954i64, 1370i32, 7u8, 20u8) { os.exit(126) }
    if !expect(.Persian, 0i64 - 24024i64, 1283i32, 1u8, 4u8) { os.exit(127) }
    if !expect(.Persian, 45600i64, 1473i32, 8u8, 16u8) { os.exit(128) }
    if !expect(.Persian, 0i64 - 25068i64, 1280i32, 2u8, 25u8) { os.exit(129) }
    if !expect(.Persian, 1905i64, 1354i32, 1u8, 1u8) { os.exit(130) }
    if !expect(.Persian, 0i64 - 200i64, 1348i32, 3u8, 25u8) { os.exit(131) }
    if !expect(.Persian, 33691i64, 1441i32, 1u8, 11u8) { os.exit(132) }
    if !expect(.Persian, 43739i64, 1468i32, 7u8, 11u8) { os.exit(133) }
    if !expect(.Persian, 0i64 - 12262i64, 1315i32, 3u8, 16u8) { os.exit(134) }
    if !expect(.Persian, 0i64 - 24045i64, 1282i32, 12u8, 12u8) { os.exit(135) }
    if !expect(.Persian, 0i64 - 11195i64, 1318i32, 2u8, 18u8) { os.exit(136) }
    if !expect(.Persian, 0i64 - 9765i64, 1322i32, 1u8, 18u8) { os.exit(137) }
    if !expect(.Persian, 29766i64, 1430i32, 4u8, 10u8) { os.exit(138) }
    if !expect(.Persian, 52828i64, 1493i32, 5u8, 31u8) { os.exit(139) }
    if !expect(.Persian, 11945i64, 1381i32, 6u8, 24u8) { os.exit(140) }
    if !expect(.Persian, 0i64 - 14931i64, 1307i32, 11u8, 25u8) { os.exit(141) }
    if !expect(.Persian, 2891i64, 1356i32, 9u8, 10u8) { os.exit(142) }
    if !expect(.Persian, 32244i64, 1437i32, 1u8, 24u8) { os.exit(143) }
    if !expect(.Persian, 24083i64, 1414i32, 9u8, 18u8) { os.exit(144) }
    if !expect(.Persian, 0i64 - 182i64, 1348i32, 4u8, 12u8) { os.exit(145) }
    if !expect(.Persian, 22278i64, 1409i32, 10u8, 9u8) { os.exit(146) }
    if !expect(.Persian, 0i64 - 22054i64, 1288i32, 5u8, 24u8) { os.exit(147) }
    if !expect(.Persian, 0i64 - 16543i64, 1303i32, 6u8, 25u8) { os.exit(148) }
    if !expect(.Persian, 40107i64, 1458i32, 8u8, 1u8) { os.exit(149) }
    if !expect(.Persian, 2357i64, 1355i32, 3u8, 25u8) { os.exit(150) }
    if !expect(.Persian, 0i64 - 25853i64, 1278i32, 1u8, 1u8) { os.exit(151) }
    if !expect(.Persian, 0i64 - 25823i64, 1278i32, 1u8, 31u8) { os.exit(152) }
    if !expect(.Persian, 0i64 - 25698i64, 1278i32, 6u8, 1u8) { os.exit(153) }
    if !expect(.Persian, 0i64 - 25668i64, 1278i32, 6u8, 31u8) { os.exit(154) }
    if !expect(.Persian, 0i64 - 25667i64, 1278i32, 7u8, 1u8) { os.exit(155) }
    if !expect(.Persian, 0i64 - 25638i64, 1278i32, 7u8, 30u8) { os.exit(156) }
    if !expect(.Persian, 0i64 - 25547i64, 1278i32, 11u8, 1u8) { os.exit(157) }
    if !expect(.Persian, 0i64 - 25518i64, 1278i32, 11u8, 30u8) { os.exit(158) }
    if !expect(.Persian, 0i64 - 25517i64, 1278i32, 12u8, 1u8) { os.exit(159) }
    if !expect(.Persian, 0i64 - 25489i64, 1278i32, 12u8, 29u8) { os.exit(160) }
    if !expect(.Persian, 0i64 - 18183i64, 1299i32, 1u8, 1u8) { os.exit(161) }
    if !expect(.Persian, 0i64 - 18153i64, 1299i32, 1u8, 31u8) { os.exit(162) }
    if !expect(.Persian, 0i64 - 18028i64, 1299i32, 6u8, 1u8) { os.exit(163) }
    if !expect(.Persian, 0i64 - 17998i64, 1299i32, 6u8, 31u8) { os.exit(164) }
    if !expect(.Persian, 0i64 - 17997i64, 1299i32, 7u8, 1u8) { os.exit(165) }
    if !expect(.Persian, 0i64 - 17968i64, 1299i32, 7u8, 30u8) { os.exit(166) }
    if !expect(.Persian, 0i64 - 17877i64, 1299i32, 11u8, 1u8) { os.exit(167) }
    if !expect(.Persian, 0i64 - 17848i64, 1299i32, 11u8, 30u8) { os.exit(168) }
    if !expect(.Persian, 0i64 - 17847i64, 1299i32, 12u8, 1u8) { os.exit(169) }
    if !expect(.Persian, 0i64 - 17819i64, 1299i32, 12u8, 29u8) { os.exit(170) }
    if !expect(.Persian, 7749i64, 1370i32, 1u8, 1u8) { os.exit(171) }
    if !expect(.Persian, 7779i64, 1370i32, 1u8, 31u8) { os.exit(172) }
    if !expect(.Persian, 7904i64, 1370i32, 6u8, 1u8) { os.exit(173) }
    if !expect(.Persian, 7934i64, 1370i32, 6u8, 31u8) { os.exit(174) }
    if !expect(.Persian, 7935i64, 1370i32, 7u8, 1u8) { os.exit(175) }
    if !expect(.Persian, 7964i64, 1370i32, 7u8, 30u8) { os.exit(176) }
    if !expect(.Persian, 8055i64, 1370i32, 11u8, 1u8) { os.exit(177) }
    if !expect(.Persian, 8084i64, 1370i32, 11u8, 30u8) { os.exit(178) }
    if !expect(.Persian, 8085i64, 1370i32, 12u8, 1u8) { os.exit(179) }
    if !expect(.Persian, 8114i64, 1370i32, 12u8, 30u8) { os.exit(180) }
    if !expect(.Persian, 18341i64, 1399i32, 1u8, 1u8) { os.exit(181) }
    if !expect(.Persian, 18371i64, 1399i32, 1u8, 31u8) { os.exit(182) }
    if !expect(.Persian, 18496i64, 1399i32, 6u8, 1u8) { os.exit(183) }
    if !expect(.Persian, 18526i64, 1399i32, 6u8, 31u8) { os.exit(184) }
    if !expect(.Persian, 18527i64, 1399i32, 7u8, 1u8) { os.exit(185) }
    if !expect(.Persian, 18556i64, 1399i32, 7u8, 30u8) { os.exit(186) }
    if !expect(.Persian, 18647i64, 1399i32, 11u8, 1u8) { os.exit(187) }
    if !expect(.Persian, 18676i64, 1399i32, 11u8, 30u8) { os.exit(188) }
    if !expect(.Persian, 18677i64, 1399i32, 12u8, 1u8) { os.exit(189) }
    if !expect(.Persian, 18706i64, 1399i32, 12u8, 30u8) { os.exit(190) }
    if !expect(.Persian, 19802i64, 1403i32, 1u8, 1u8) { os.exit(191) }
    if !expect(.Persian, 19832i64, 1403i32, 1u8, 31u8) { os.exit(192) }
    if !expect(.Persian, 19957i64, 1403i32, 6u8, 1u8) { os.exit(193) }
    if !expect(.Persian, 19987i64, 1403i32, 6u8, 31u8) { os.exit(194) }
    if !expect(.Persian, 19988i64, 1403i32, 7u8, 1u8) { os.exit(195) }
    if !expect(.Persian, 20017i64, 1403i32, 7u8, 30u8) { os.exit(196) }
    if !expect(.Persian, 20108i64, 1403i32, 11u8, 1u8) { os.exit(197) }
    if !expect(.Persian, 20137i64, 1403i32, 11u8, 30u8) { os.exit(198) }
    if !expect(.Persian, 20138i64, 1403i32, 12u8, 1u8) { os.exit(199) }
    if !expect(.Persian, 20167i64, 1403i32, 12u8, 30u8) { os.exit(200) }
    if !expect(.Persian, 20168i64, 1404i32, 1u8, 1u8) { os.exit(201) }
    if !expect(.Persian, 20198i64, 1404i32, 1u8, 31u8) { os.exit(202) }
    if !expect(.Persian, 20323i64, 1404i32, 6u8, 1u8) { os.exit(203) }
    if !expect(.Persian, 20353i64, 1404i32, 6u8, 31u8) { os.exit(204) }
    if !expect(.Persian, 20354i64, 1404i32, 7u8, 1u8) { os.exit(205) }
    if !expect(.Persian, 20383i64, 1404i32, 7u8, 30u8) { os.exit(206) }
    if !expect(.Persian, 20474i64, 1404i32, 11u8, 1u8) { os.exit(207) }
    if !expect(.Persian, 20503i64, 1404i32, 11u8, 30u8) { os.exit(208) }
    if !expect(.Persian, 20504i64, 1404i32, 12u8, 1u8) { os.exit(209) }
    if !expect(.Persian, 20532i64, 1404i32, 12u8, 29u8) { os.exit(210) }
    if !expect(.Persian, 21628i64, 1408i32, 1u8, 1u8) { os.exit(211) }
    if !expect(.Persian, 21658i64, 1408i32, 1u8, 31u8) { os.exit(212) }
    if !expect(.Persian, 21783i64, 1408i32, 6u8, 1u8) { os.exit(213) }
    if !expect(.Persian, 21813i64, 1408i32, 6u8, 31u8) { os.exit(214) }
    if !expect(.Persian, 21814i64, 1408i32, 7u8, 1u8) { os.exit(215) }
    if !expect(.Persian, 21843i64, 1408i32, 7u8, 30u8) { os.exit(216) }
    if !expect(.Persian, 21934i64, 1408i32, 11u8, 1u8) { os.exit(217) }
    if !expect(.Persian, 21963i64, 1408i32, 11u8, 30u8) { os.exit(218) }
    if !expect(.Persian, 21964i64, 1408i32, 12u8, 1u8) { os.exit(219) }
    if !expect(.Persian, 21993i64, 1408i32, 12u8, 30u8) { os.exit(220) }
    if !expect(.Persian, 36969i64, 1450i32, 1u8, 1u8) { os.exit(221) }
    if !expect(.Persian, 36999i64, 1450i32, 1u8, 31u8) { os.exit(222) }
    if !expect(.Persian, 37124i64, 1450i32, 6u8, 1u8) { os.exit(223) }
    if !expect(.Persian, 37154i64, 1450i32, 6u8, 31u8) { os.exit(224) }
    if !expect(.Persian, 37155i64, 1450i32, 7u8, 1u8) { os.exit(225) }
    if !expect(.Persian, 37184i64, 1450i32, 7u8, 30u8) { os.exit(226) }
    if !expect(.Persian, 37275i64, 1450i32, 11u8, 1u8) { os.exit(227) }
    if !expect(.Persian, 37304i64, 1450i32, 11u8, 30u8) { os.exit(228) }
    if !expect(.Persian, 37305i64, 1450i32, 12u8, 1u8) { os.exit(229) }
    if !expect(.Persian, 37333i64, 1450i32, 12u8, 29u8) { os.exit(230) }
    if !expect(.Persian, 55231i64, 1500i32, 1u8, 1u8) { os.exit(231) }
    if !expect(.Persian, 55261i64, 1500i32, 1u8, 31u8) { os.exit(232) }
    if !expect(.Persian, 55386i64, 1500i32, 6u8, 1u8) { os.exit(233) }
    if !expect(.Persian, 55416i64, 1500i32, 6u8, 31u8) { os.exit(234) }
    if !expect(.Persian, 55417i64, 1500i32, 7u8, 1u8) { os.exit(235) }
    if !expect(.Persian, 55446i64, 1500i32, 7u8, 30u8) { os.exit(236) }
    if !expect(.Persian, 55537i64, 1500i32, 11u8, 1u8) { os.exit(237) }
    if !expect(.Persian, 55566i64, 1500i32, 11u8, 30u8) { os.exit(238) }
    if !expect(.Persian, 55567i64, 1500i32, 12u8, 1u8) { os.exit(239) }
    if !expect(.Persian, 55595i64, 1500i32, 12u8, 29u8) { os.exit(240) }
    if !expect(.UmmAlQura, 20748i64, 1448i32, 5u8, 11u8) { os.exit(241) }
    if !expect(.UmmAlQura, 13635i64, 1428i32, 4u8, 15u8) { os.exit(242) }
    if !expect(.UmmAlQura, 0i64 - 4260i64, 1377i32, 10u8, 15u8) { os.exit(243) }
    if !expect(.UmmAlQura, 10179i64, 1418i32, 7u8, 14u8) { os.exit(244) }
    if !expect(.UmmAlQura, 0i64 - 8934i64, 1364i32, 8u8, 7u8) { os.exit(245) }
    if !expect(.UmmAlQura, 16996i64, 1437i32, 10u8, 9u8) { os.exit(246) }
    if !expect(.UmmAlQura, 9910i64, 1417i32, 10u8, 11u8) { os.exit(247) }
    if !expect(.UmmAlQura, 33579i64, 1484i32, 7u8, 26u8) { os.exit(248) }
    if !expect(.UmmAlQura, 2766i64, 1397i32, 8u8, 13u8) { os.exit(249) }
    if !expect(.UmmAlQura, 9969i64, 1417i32, 12u8, 11u8) { os.exit(250) }
    if !expect(.UmmAlQura, 1647i64, 1394i32, 6u8, 16u8) { os.exit(251) }
    if !expect(.UmmAlQura, 34517i64, 1487i32, 3u8, 18u8) { os.exit(252) }
    if !expect(.UmmAlQura, 37579i64, 1495i32, 11u8, 10u8) { os.exit(253) }
    if !expect(.UmmAlQura, 36870i64, 1493i32, 11u8, 9u8) { os.exit(254) }
    if !expect(.UmmAlQura, 0i64 - 6858i64, 1370i32, 6u8, 15u8) { os.exit(255) }
    if !expect(.UmmAlQura, 9328i64, 1416i32, 2u8, 19u8) { os.exit(256) }
    if !expect(.UmmAlQura, 0i64 - 3424i64, 1380i32, 2u8, 24u8) { os.exit(257) }
    if !expect(.UmmAlQura, 6103i64, 1407i32, 1u8, 13u8) { os.exit(258) }
    if !expect(.UmmAlQura, 35842i64, 1490i32, 12u8, 15u8) { os.exit(259) }
    if !expect(.UmmAlQura, 13552i64, 1428i32, 1u8, 20u8) { os.exit(260) }
    if !expect(.UmmAlQura, 56i64, 1389i32, 12u8, 20u8) { os.exit(261) }
    if !expect(.UmmAlQura, 34994i64, 1488i32, 7u8, 23u8) { os.exit(262) }
    if !expect(.UmmAlQura, 0i64 - 2939i64, 1381i32, 7u8, 7u8) { os.exit(263) }
    if !expect(.UmmAlQura, 0i64 - 10954i64, 1358i32, 11u8, 25u8) { os.exit(264) }
    if !expect(.UmmAlQura, 1010i64, 1392i32, 8u8, 29u8) { os.exit(265) }
    if !expect(.UmmAlQura, 34092i64, 1486i32, 1u8, 6u8) { os.exit(266) }
    if !expect(.UmmAlQura, 12849i64, 1426i32, 1u8, 26u8) { os.exit(267) }
    if !expect(.UmmAlQura, 5344i64, 1404i32, 11u8, 22u8) { os.exit(268) }
    if !expect(.UmmAlQura, 10693i64, 1419i32, 12u8, 26u8) { os.exit(269) }
    if !expect(.UmmAlQura, 20845i64, 1448i32, 8u8, 19u8) { os.exit(270) }
    if !expect(.UmmAlQura, 30484i64, 1475i32, 11u8, 2u8) { os.exit(271) }
    if !expect(.UmmAlQura, 11703i64, 1422i32, 11u8, 2u8) { os.exit(272) }
    if !expect(.UmmAlQura, 8272i64, 1413i32, 2u8, 27u8) { os.exit(273) }
    if !expect(.UmmAlQura, 0i64 - 11583i64, 1357i32, 2u8, 16u8) { os.exit(274) }
    if !expect(.UmmAlQura, 0i64 - 4869i64, 1376i32, 1u8, 26u8) { os.exit(275) }
    if !expect(.UmmAlQura, 0i64 - 12230i64, 1355i32, 4u8, 18u8) { os.exit(276) }
    if !expect(.UmmAlQura, 0i64 - 3757i64, 1379i32, 3u8, 16u8) { os.exit(277) }
    if !expect(.UmmAlQura, 0i64 - 8062i64, 1367i32, 1u8, 23u8) { os.exit(278) }
    if !expect(.UmmAlQura, 1224i64, 1393i32, 4u8, 6u8) { os.exit(279) }
    if !expect(.UmmAlQura, 9426i64, 1416i32, 5u8, 29u8) { os.exit(280) }
    if !expect(.UmmAlQura, 4541i64, 1402i32, 8u8, 16u8) { os.exit(281) }
    if !expect(.UmmAlQura, 22098i64, 1452i32, 3u8, 2u8) { os.exit(282) }
    if !expect(.UmmAlQura, 8746i64, 1414i32, 6u8, 29u8) { os.exit(283) }
    if !expect(.UmmAlQura, 32753i64, 1482i32, 3u8, 27u8) { os.exit(284) }
    if !expect(.UmmAlQura, 0i64 - 9421i64, 1363i32, 3u8, 23u8) { os.exit(285) }
    if !expect(.UmmAlQura, 10877i64, 1420i32, 7u8, 4u8) { os.exit(286) }
    if !expect(.UmmAlQura, 0i64 - 4043i64, 1378i32, 5u8, 25u8) { os.exit(287) }
    if !expect(.UmmAlQura, 15004i64, 1432i32, 2u8, 26u8) { os.exit(288) }
    if !expect(.UmmAlQura, 0i64 - 1755i64, 1384i32, 11u8, 11u8) { os.exit(289) }
    if !expect(.UmmAlQura, 0i64 - 13636i64, 1351i32, 4u8, 29u8) { os.exit(290) }
    if !expect(.UmmAlQura, 0i64 - 12865i64, 1353i32, 7u8, 3u8) { os.exit(291) }
    if !expect(.UmmAlQura, 37631i64, 1496i32, 1u8, 3u8) { os.exit(292) }
    if !expect(.UmmAlQura, 30819i64, 1476i32, 10u8, 11u8) { os.exit(293) }
    if !expect(.UmmAlQura, 29620i64, 1473i32, 5u8, 23u8) { os.exit(294) }
    if !expect(.UmmAlQura, 32961i64, 1482i32, 10u8, 27u8) { os.exit(295) }
    if !expect(.UmmAlQura, 5181i64, 1404i32, 6u8, 7u8) { os.exit(296) }
    if !expect(.UmmAlQura, 28886i64, 1471i32, 4u8, 28u8) { os.exit(297) }
    if !expect(.UmmAlQura, 0i64 - 10198i64, 1361i32, 1u8, 13u8) { os.exit(298) }
    if !expect(.UmmAlQura, 5398i64, 1405i32, 1u8, 17u8) { os.exit(299) }
    if !expect(.UmmAlQura, 0i64 - 9204i64, 1363i32, 11u8, 4u8) { os.exit(300) }
    if !expect(.UmmAlQura, 35150i64, 1489i32, 1u8, 2u8) { os.exit(301) }
    if !expect(.UmmAlQura, 21959i64, 1451i32, 10u8, 11u8) { os.exit(302) }
    if !expect(.UmmAlQura, 0i64 - 6599i64, 1371i32, 3u8, 9u8) { os.exit(303) }
    if !expect(.UmmAlQura, 37260i64, 1494i32, 12u8, 16u8) { os.exit(304) }
    if !expect(.UmmAlQura, 16214i64, 1435i32, 7u8, 25u8) { os.exit(305) }
    if !expect(.UmmAlQura, 0i64 - 12481i64, 1354i32, 8u8, 3u8) { os.exit(306) }
    if !expect(.UmmAlQura, 5985i64, 1406i32, 9u8, 14u8) { os.exit(307) }
    if !expect(.UmmAlQura, 28407i64, 1469i32, 12u8, 21u8) { os.exit(308) }
    if !expect(.UmmAlQura, 27797i64, 1468i32, 4u8, 2u8) { os.exit(309) }
    if !expect(.UmmAlQura, 32022i64, 1480i32, 3u8, 4u8) { os.exit(310) }
    if !expect(.UmmAlQura, 31493i64, 1478i32, 9u8, 7u8) { os.exit(311) }
    if !expect(.UmmAlQura, 0i64 - 2996i64, 1381i32, 5u8, 9u8) { os.exit(312) }
    if !expect(.UmmAlQura, 15586i64, 1433i32, 10u8, 16u8) { os.exit(313) }
    if !expect(.UmmAlQura, 37169i64, 1494i32, 9u8, 13u8) { os.exit(314) }
    if !expect(.UmmAlQura, 0i64 - 11670i64, 1356i32, 11u8, 18u8) { os.exit(315) }
    if !expect(.UmmAlQura, 19495i64, 1444i32, 10u8, 28u8) { os.exit(316) }
    if !expect(.UmmAlQura, 0i64 - 5659i64, 1373i32, 11u8, 4u8) { os.exit(317) }
    if !expect(.UmmAlQura, 18819i64, 1442i32, 12u8, 1u8) { os.exit(318) }
    if !expect(.UmmAlQura, 781i64, 1392i32, 1u8, 6u8) { os.exit(319) }
    if !expect(.UmmAlQura, 944i64, 1392i32, 6u8, 22u8) { os.exit(320) }
    if !expect(.UmmAlQura, 5878i64, 1406i32, 5u8, 25u8) { os.exit(321) }
    if !expect(.UmmAlQura, 35793i64, 1490i32, 10u8, 24u8) { os.exit(322) }
    if !expect(.UmmAlQura, 28271i64, 1469i32, 8u8, 3u8) { os.exit(323) }
    if !expect(.UmmAlQura, 1739i64, 1394i32, 9u8, 20u8) { os.exit(324) }
    if !expect(.UmmAlQura, 35708i64, 1490i32, 7u8, 28u8) { os.exit(325) }
    if !expect(.UmmAlQura, 0i64 - 9319i64, 1363i32, 7u8, 7u8) { os.exit(326) }
    if !expect(.UmmAlQura, 13854i64, 1428i32, 11u8, 27u8) { os.exit(327) }
    if !expect(.UmmAlQura, 28522i64, 1470i32, 4u8, 19u8) { os.exit(328) }
    if !expect(.UmmAlQura, 0i64 - 5748i64, 1373i32, 8u8, 4u8) { os.exit(329) }
    if !expect(.UmmAlQura, 17699i64, 1439i32, 10u8, 3u8) { os.exit(330) }
    if !expect(.UmmAlQura, 8529i64, 1413i32, 11u8, 18u8) { os.exit(331) }
    if !expect(.UmmAlQura, 0i64 - 927i64, 1387i32, 3u8, 12u8) { os.exit(332) }
    if !expect(.UmmAlQura, 0i64 - 11603i64, 1357i32, 1u8, 26u8) { os.exit(333) }
    if !expect(.UmmAlQura, 20156i64, 1446i32, 9u8, 9u8) { os.exit(334) }
    if !expect(.UmmAlQura, 21005i64, 1449i32, 2u8, 2u8) { os.exit(335) }
    if !expect(.UmmAlQura, 7218i64, 1410i32, 3u8, 7u8) { os.exit(336) }
    if !expect(.UmmAlQura, 0i64 - 15280i64, 1346i32, 9u8, 10u8) { os.exit(337) }
    if !expect(.UmmAlQura, 19075i64, 1443i32, 8u8, 21u8) { os.exit(338) }
    if !expect(.UmmAlQura, 11395i64, 1421i32, 12u8, 19u8) { os.exit(339) }
    if !expect(.UmmAlQura, 3607i64, 1399i32, 12u8, 27u8) { os.exit(340) }
    if !expect(.UmmAlQura, 35911i64, 1491i32, 2u8, 25u8) { os.exit(341) }
    if !expect(.UmmAlQura, 29643i64, 1473i32, 6u8, 17u8) { os.exit(342) }
    if !expect(.UmmAlQura, 34161i64, 1486i32, 3u8, 17u8) { os.exit(343) }
    if !expect(.UmmAlQura, 19979i64, 1446i32, 3u8, 10u8) { os.exit(344) }
    if !expect(.UmmAlQura, 11487i64, 1422i32, 3u8, 22u8) { os.exit(345) }
    if !expect(.UmmAlQura, 8937i64, 1415i32, 1u8, 12u8) { os.exit(346) }
    if !expect(.UmmAlQura, 0i64 - 7167i64, 1369i32, 8u8, 2u8) { os.exit(347) }
    if !expect(.UmmAlQura, 0i64 - 11687i64, 1356i32, 11u8, 1u8) { os.exit(348) }
    if !expect(.UmmAlQura, 10084i64, 1418i32, 4u8, 8u8) { os.exit(349) }
    if !expect(.UmmAlQura, 32920i64, 1482i32, 9u8, 16u8) { os.exit(350) }
    if !expect(.UmmAlQura, 0i64 - 8504i64, 1365i32, 10u8, 24u8) { os.exit(351) }
    if !expect(.UmmAlQura, 22105i64, 1452i32, 3u8, 9u8) { os.exit(352) }
    if !expect(.UmmAlQura, 329i64, 1390i32, 9u8, 26u8) { os.exit(353) }
    if !expect(.UmmAlQura, 0i64 - 7645i64, 1368i32, 3u8, 27u8) { os.exit(354) }
    if !expect(.UmmAlQura, 38912i64, 1499i32, 8u8, 14u8) { os.exit(355) }
    if !expect(.UmmAlQura, 9053i64, 1415i32, 5u8, 10u8) { os.exit(356) }
    if !expect(.UmmAlQura, 2220i64, 1396i32, 1u8, 29u8) { os.exit(357) }
    if !expect(.UmmAlQura, 7284i64, 1410i32, 5u8, 13u8) { os.exit(358) }
    if !expect(.UmmAlQura, 5478i64, 1405i32, 4u8, 9u8) { os.exit(359) }
    if !expect(.UmmAlQura, 11954i64, 1423i32, 7u8, 17u8) { os.exit(360) }
    if !expect(.UmmAlQura, 23450i64, 1455i32, 12u8, 25u8) { os.exit(361) }
    if !expect(.UmmAlQura, 32458i64, 1481i32, 5u8, 27u8) { os.exit(362) }
    if !expect(.UmmAlQura, 35306i64, 1489i32, 6u8, 10u8) { os.exit(363) }
    if !expect(.UmmAlQura, 33449i64, 1484i32, 3u8, 14u8) { os.exit(364) }
    if !expect(.UmmAlQura, 20819i64, 1448i32, 7u8, 23u8) { os.exit(365) }
    if !expect(.UmmAlQura, 6295i64, 1407i32, 7u8, 28u8) { os.exit(366) }
    if !expect(.UmmAlQura, 27670i64, 1467i32, 11u8, 23u8) { os.exit(367) }
    if !expect(.UmmAlQura, 12732i64, 1425i32, 9u8, 27u8) { os.exit(368) }
    if !expect(.UmmAlQura, 7339i64, 1410i32, 7u8, 9u8) { os.exit(369) }
    if !expect(.UmmAlQura, 0i64 - 8535i64, 1365i32, 9u8, 23u8) { os.exit(370) }
    if !expect(.UmmAlQura, 15983i64, 1434i32, 11u8, 29u8) { os.exit(371) }
    if !expect(.UmmAlQura, 15664i64, 1434i32, 1u8, 6u8) { os.exit(372) }
    if !expect(.UmmAlQura, 10532i64, 1419i32, 7u8, 13u8) { os.exit(373) }
    if !expect(.UmmAlQura, 0i64 - 9891i64, 1361i32, 11u8, 25u8) { os.exit(374) }
    if !expect(.UmmAlQura, 2941i64, 1398i32, 2u8, 11u8) { os.exit(375) }
    if !expect(.UmmAlQura, 31050i64, 1477i32, 6u8, 7u8) { os.exit(376) }
    if !expect(.UmmAlQura, 9634i64, 1417i32, 1u8, 1u8) { os.exit(377) }
    if !expect(.UmmAlQura, 14845i64, 1431i32, 9u8, 14u8) { os.exit(378) }
    if !expect(.UmmAlQura, 30919i64, 1477i32, 1u8, 23u8) { os.exit(379) }
    if !expect(.UmmAlQura, 25064i64, 1460i32, 7u8, 15u8) { os.exit(380) }
    if !expect(.UmmAlQura, 0i64 - 1487i64, 1385i32, 8u8, 13u8) { os.exit(381) }
    if !expect(.UmmAlQura, 0i64 - 4564i64, 1376i32, 12u8, 6u8) { os.exit(382) }
    if !expect(.UmmAlQura, 10913i64, 1420i32, 8u8, 10u8) { os.exit(383) }
    if !expect(.UmmAlQura, 0i64 - 14895i64, 1347i32, 10u8, 11u8) { os.exit(384) }
    if !expect(.UmmAlQura, 0i64 - 4390i64, 1377i32, 6u8, 4u8) { os.exit(385) }
    if !expect(.UmmAlQura, 21i64, 1389i32, 11u8, 15u8) { os.exit(386) }
    if !expect(.UmmAlQura, 17688i64, 1439i32, 9u8, 22u8) { os.exit(387) }
    if !expect(.UmmAlQura, 20066i64, 1446i32, 6u8, 8u8) { os.exit(388) }
    if !expect(.UmmAlQura, 12196i64, 1424i32, 3u8, 23u8) { os.exit(389) }
    if !expect(.UmmAlQura, 5079i64, 1404i32, 2u8, 24u8) { os.exit(390) }
    if !expect(.UmmAlQura, 14157i64, 1429i32, 10u8, 5u8) { os.exit(391) }
    if !expect(.UmmAlQura, 23822i64, 1457i32, 1u8, 13u8) { os.exit(392) }
    if !expect(.UmmAlQura, 31810i64, 1479i32, 7u8, 29u8) { os.exit(393) }
    if !expect(.UmmAlQura, 10399i64, 1419i32, 2u8, 28u8) { os.exit(394) }
    if !expect(.UmmAlQura, 0i64 - 439i64, 1388i32, 7u8, 27u8) { os.exit(395) }
    if !expect(.UmmAlQura, 35581i64, 1490i32, 3u8, 20u8) { os.exit(396) }
    if !expect(.UmmAlQura, 0i64 - 5408i64, 1374i32, 7u8, 19u8) { os.exit(397) }
    if !expect(.UmmAlQura, 6977i64, 1409i32, 7u8, 1u8) { os.exit(398) }
    if !expect(.UmmAlQura, 0i64 - 12916i64, 1353i32, 5u8, 11u8) { os.exit(399) }
    if !expect(.UmmAlQura, 0i64 - 12295i64, 1355i32, 2u8, 12u8) { os.exit(400) }
    if !expect(.UmmAlQura, 15602i64, 1433i32, 11u8, 3u8) { os.exit(401) }
    if !expect(.UmmAlQura, 4469i64, 1402i32, 6u8, 3u8) { os.exit(402) }
    if !expect(.UmmAlQura, 20766i64, 1448i32, 5u8, 29u8) { os.exit(403) }
    if !expect(.UmmAlQura, 28792i64, 1471i32, 1u8, 22u8) { os.exit(404) }
    if !expect(.UmmAlQura, 0i64 - 6263i64, 1372i32, 2u8, 20u8) { os.exit(405) }
    if !expect(.UmmAlQura, 28136i64, 1469i32, 3u8, 17u8) { os.exit(406) }
    if !expect(.UmmAlQura, 31276i64, 1478i32, 1u8, 26u8) { os.exit(407) }
    if !expect(.UmmAlQura, 0i64 - 660i64, 1387i32, 12u8, 13u8) { os.exit(408) }
    if !expect(.UmmAlQura, 33103i64, 1483i32, 3u8, 23u8) { os.exit(409) }
    if !expect(.UmmAlQura, 5179i64, 1404i32, 6u8, 5u8) { os.exit(410) }
    if !expect(.UmmAlQura, 26643i64, 1464i32, 12u8, 29u8) { os.exit(411) }
    if !expect(.UmmAlQura, 0i64 - 5430i64, 1374i32, 6u8, 26u8) { os.exit(412) }
    if !expect(.UmmAlQura, 959i64, 1392i32, 7u8, 8u8) { os.exit(413) }
    if !expect(.UmmAlQura, 9167i64, 1415i32, 9u8, 7u8) { os.exit(414) }
    if !expect(.UmmAlQura, 0i64 - 3944i64, 1378i32, 9u8, 6u8) { os.exit(415) }
    if !expect(.UmmAlQura, 34443i64, 1487i32, 1u8, 3u8) { os.exit(416) }
    if !expect(.UmmAlQura, 31942i64, 1479i32, 12u8, 13u8) { os.exit(417) }
    if !expect(.UmmAlQura, 0i64 - 11745i64, 1356i32, 9u8, 1u8) { os.exit(418) }
    if !expect(.UmmAlQura, 32616i64, 1481i32, 11u8, 8u8) { os.exit(419) }
    if !expect(.UmmAlQura, 0i64 - 15025i64, 1347i32, 5u8, 29u8) { os.exit(420) }
    if !expect(.UmmAlQura, 8338i64, 1413i32, 5u8, 5u8) { os.exit(421) }
    if !expect(.UmmAlQura, 8803i64, 1414i32, 8u8, 27u8) { os.exit(422) }
    if !expect(.UmmAlQura, 0i64 - 2081i64, 1383i32, 12u8, 9u8) { os.exit(423) }
    if !expect(.UmmAlQura, 10826i64, 1420i32, 5u8, 12u8) { os.exit(424) }
    if !expect(.UmmAlQura, 0i64 - 14882i64, 1347i32, 10u8, 24u8) { os.exit(425) }
    if !expect(.UmmAlQura, 7513i64, 1411i32, 1u8, 6u8) { os.exit(426) }
    if !expect(.UmmAlQura, 37986i64, 1497i32, 1u8, 3u8) { os.exit(427) }
    if !expect(.UmmAlQura, 0i64 - 9840i64, 1362i32, 1u8, 17u8) { os.exit(428) }
    if !expect(.UmmAlQura, 11184i64, 1421i32, 5u8, 15u8) { os.exit(429) }
    if !expect(.UmmAlQura, 23549i64, 1456i32, 4u8, 7u8) { os.exit(430) }
    if !expect(.UmmAlQura, 24011i64, 1457i32, 7u8, 26u8) { os.exit(431) }
    if !expect(.UmmAlQura, 0i64 - 5824i64, 1373i32, 5u8, 16u8) { os.exit(432) }
    if !expect(.UmmAlQura, 13773i64, 1428i32, 9u8, 5u8) { os.exit(433) }
    if !expect(.UmmAlQura, 0i64 - 3003i64, 1381i32, 5u8, 2u8) { os.exit(434) }
    if !expect(.UmmAlQura, 30585i64, 1476i32, 2u8, 15u8) { os.exit(435) }
    if !expect(.UmmAlQura, 0i64 - 86i64, 1389i32, 7u8, 26u8) { os.exit(436) }
    if !expect(.UmmAlQura, 13703i64, 1428i32, 6u8, 24u8) { os.exit(437) }
    if !expect(.UmmAlQura, 0i64 - 11150i64, 1358i32, 5u8, 5u8) { os.exit(438) }
    if !expect(.UmmAlQura, 0i64 - 4475i64, 1377i32, 3u8, 7u8) { os.exit(439) }
    if !expect(.UmmAlQura, 12303i64, 1424i32, 7u8, 11u8) { os.exit(440) }
    if !expect(.UmmAlQura, 0i64 - 7944i64, 1367i32, 5u8, 23u8) { os.exit(441) }
    if !expect(.UmmAlQura, 17033i64, 1437i32, 11u8, 17u8) { os.exit(442) }
    if !expect(.UmmAlQura, 0i64 - 13202i64, 1352i32, 7u8, 21u8) { os.exit(443) }
    if !expect(.UmmAlQura, 34567i64, 1487i32, 5u8, 9u8) { os.exit(444) }
    if !expect(.UmmAlQura, 19221i64, 1444i32, 1u8, 19u8) { os.exit(445) }
    if !expect(.UmmAlQura, 0i64 - 8299i64, 1366i32, 5u8, 22u8) { os.exit(446) }
    if !expect(.UmmAlQura, 4129i64, 1401i32, 6u8, 18u8) { os.exit(447) }
    if !expect(.UmmAlQura, 18424i64, 1441i32, 10u8, 19u8) { os.exit(448) }
    if !expect(.UmmAlQura, 0i64 - 12684i64, 1354i32, 1u8, 7u8) { os.exit(449) }
    if !expect(.UmmAlQura, 8701i64, 1414i32, 5u8, 13u8) { os.exit(450) }
    if !expect(.UmmAlQura, 9925i64, 1417i32, 10u8, 26u8) { os.exit(451) }
    if !expect(.UmmAlQura, 0i64 - 15155i64, 1347i32, 1u8, 17u8) { os.exit(452) }
    if !expect(.UmmAlQura, 36010i64, 1491i32, 6u8, 6u8) { os.exit(453) }
    if !expect(.UmmAlQura, 0i64 - 16411i64, 1343i32, 7u8, 1u8) { os.exit(454) }
    if !expect(.UmmAlQura, 0i64 - 15110i64, 1347i32, 3u8, 4u8) { os.exit(455) }
    if !expect(.UmmAlQura, 24492i64, 1458i32, 12u8, 5u8) { os.exit(456) }
    if !expect(.UmmAlQura, 29918i64, 1474i32, 3u8, 26u8) { os.exit(457) }
    if !expect(.UmmAlQura, 38734i64, 1499i32, 2u8, 13u8) { os.exit(458) }
    if !expect(.UmmAlQura, 33470i64, 1484i32, 4u8, 6u8) { os.exit(459) }
    if !expect(.UmmAlQura, 6408i64, 1407i32, 11u8, 23u8) { os.exit(460) }
    if !expect(.UmmAlQura, 35965i64, 1491i32, 4u8, 20u8) { os.exit(461) }
    if !expect(.UmmAlQura, 0i64 - 906i64, 1387i32, 4u8, 3u8) { os.exit(462) }
    if !expect(.UmmAlQura, 0i64 - 8995i64, 1364i32, 6u8, 5u8) { os.exit(463) }
    if !expect(.UmmAlQura, 10184i64, 1418i32, 7u8, 19u8) { os.exit(464) }
    if !expect(.UmmAlQura, 23404i64, 1455i32, 11u8, 9u8) { os.exit(465) }
    if !expect(.UmmAlQura, 19911i64, 1446i32, 1u8, 1u8) { os.exit(466) }
    if !expect(.UmmAlQura, 13244i64, 1427i32, 3u8, 8u8) { os.exit(467) }
    if !expect(.UmmAlQura, 6526i64, 1408i32, 3u8, 23u8) { os.exit(468) }
    if !expect(.UmmAlQura, 32414i64, 1481i32, 4u8, 12u8) { os.exit(469) }
    if !expect(.UmmAlQura, 0i64 - 7413i64, 1368i32, 11u8, 23u8) { os.exit(470) }
    if !expect(.UmmAlQura, 11642i64, 1422i32, 9u8, 1u8) { os.exit(471) }
    if !expect(.UmmAlQura, 0i64 - 15546i64, 1345i32, 12u8, 10u8) { os.exit(472) }
    if !expect(.UmmAlQura, 0i64 - 3118i64, 1381i32, 1u8, 6u8) { os.exit(473) }
    if !expect(.UmmAlQura, 35473i64, 1489i32, 11u8, 30u8) { os.exit(474) }
    if !expect(.UmmAlQura, 7568i64, 1411i32, 3u8, 2u8) { os.exit(475) }
    if !expect(.UmmAlQura, 0i64 - 12242i64, 1355i32, 4u8, 6u8) { os.exit(476) }
    if !expect(.UmmAlQura, 26465i64, 1464i32, 6u8, 29u8) { os.exit(477) }
    if !expect(.UmmAlQura, 0i64 - 12198i64, 1355i32, 5u8, 21u8) { os.exit(478) }
    if !expect(.UmmAlQura, 7231i64, 1410i32, 3u8, 20u8) { os.exit(479) }
    if !expect(.UmmAlQura, 30894i64, 1476i32, 12u8, 28u8) { os.exit(480) }
    if !expect(.UmmAlQura, 12535i64, 1425i32, 3u8, 8u8) { os.exit(481) }
    if !expect(.UmmAlQura, 0i64 - 13879i64, 1350i32, 8u8, 23u8) { os.exit(482) }
    if !expect(.UmmAlQura, 33439i64, 1484i32, 3u8, 4u8) { os.exit(483) }
    if !expect(.UmmAlQura, 25589i64, 1462i32, 1u8, 9u8) { os.exit(484) }
    if !expect(.UmmAlQura, 0i64 - 2879i64, 1381i32, 9u8, 9u8) { os.exit(485) }
    if !expect(.UmmAlQura, 20169i64, 1446i32, 9u8, 22u8) { os.exit(486) }
    if !expect(.UmmAlQura, 2967i64, 1398i32, 3u8, 8u8) { os.exit(487) }
    if !expect(.UmmAlQura, 30273i64, 1475i32, 3u8, 27u8) { os.exit(488) }
    if !expect(.UmmAlQura, 0i64 - 16473i64, 1343i32, 4u8, 28u8) { os.exit(489) }
    if !expect(.UmmAlQura, 9605i64, 1416i32, 12u8, 2u8) { os.exit(490) }
    if !expect(.UmmAlQura, 0i64 - 16589i64, 1343i32, 1u8, 1u8) { os.exit(491) }
    if !expect(.UmmAlQura, 39401i64, 1500i32, 12u8, 30u8) { os.exit(492) }
    if !len_is(.UmmAlQura, 1343i32, 1u8, 30u8) { os.exit(493) }
    if !len_is(.UmmAlQura, 1343i32, 2u8, 29u8) { os.exit(494) }
    if !len_is(.UmmAlQura, 1343i32, 3u8, 30u8) { os.exit(495) }
    if !len_is(.UmmAlQura, 1343i32, 4u8, 30u8) { os.exit(496) }
    if !len_is(.UmmAlQura, 1343i32, 5u8, 29u8) { os.exit(497) }
    if !len_is(.UmmAlQura, 1343i32, 6u8, 30u8) { os.exit(498) }
    if !len_is(.UmmAlQura, 1343i32, 7u8, 30u8) { os.exit(499) }
    if !len_is(.UmmAlQura, 1343i32, 8u8, 30u8) { os.exit(500) }
    if !len_is(.UmmAlQura, 1343i32, 9u8, 28u8) { os.exit(501) }
    if !len_is(.UmmAlQura, 1343i32, 10u8, 30u8) { os.exit(502) }
    if !len_is(.UmmAlQura, 1343i32, 11u8, 30u8) { os.exit(503) }
    if !len_is(.UmmAlQura, 1343i32, 12u8, 30u8) { os.exit(504) }
    if !len_is(.UmmAlQura, 1344i32, 1u8, 29u8) { os.exit(505) }
    if !len_is(.UmmAlQura, 1344i32, 2u8, 29u8) { os.exit(506) }
    if !len_is(.UmmAlQura, 1344i32, 3u8, 30u8) { os.exit(507) }
    if !len_is(.UmmAlQura, 1344i32, 4u8, 29u8) { os.exit(508) }
    if !len_is(.UmmAlQura, 1344i32, 5u8, 30u8) { os.exit(509) }
    if !len_is(.UmmAlQura, 1344i32, 6u8, 29u8) { os.exit(510) }
    if !len_is(.UmmAlQura, 1344i32, 7u8, 30u8) { os.exit(511) }
    if !len_is(.UmmAlQura, 1344i32, 8u8, 29u8) { os.exit(512) }
    if !len_is(.UmmAlQura, 1344i32, 9u8, 30u8) { os.exit(513) }
    if !len_is(.UmmAlQura, 1344i32, 10u8, 29u8) { os.exit(514) }
    if !len_is(.UmmAlQura, 1344i32, 11u8, 30u8) { os.exit(515) }
    if !len_is(.UmmAlQura, 1344i32, 12u8, 29u8) { os.exit(516) }
    if !len_is(.UmmAlQura, 1350i32, 1u8, 29u8) { os.exit(517) }
    if !len_is(.UmmAlQura, 1350i32, 2u8, 30u8) { os.exit(518) }
    if !len_is(.UmmAlQura, 1350i32, 3u8, 29u8) { os.exit(519) }
    if !len_is(.UmmAlQura, 1350i32, 4u8, 30u8) { os.exit(520) }
    if !len_is(.UmmAlQura, 1350i32, 5u8, 29u8) { os.exit(521) }
    if !len_is(.UmmAlQura, 1350i32, 6u8, 29u8) { os.exit(522) }
    if !len_is(.UmmAlQura, 1350i32, 7u8, 30u8) { os.exit(523) }
    if !len_is(.UmmAlQura, 1350i32, 8u8, 29u8) { os.exit(524) }
    if !len_is(.UmmAlQura, 1350i32, 9u8, 30u8) { os.exit(525) }
    if !len_is(.UmmAlQura, 1350i32, 10u8, 30u8) { os.exit(526) }
    if !len_is(.UmmAlQura, 1350i32, 11u8, 29u8) { os.exit(527) }
    if !len_is(.UmmAlQura, 1350i32, 12u8, 30u8) { os.exit(528) }
    if !len_is(.UmmAlQura, 1389i32, 1u8, 30u8) { os.exit(529) }
    if !len_is(.UmmAlQura, 1389i32, 2u8, 29u8) { os.exit(530) }
    if !len_is(.UmmAlQura, 1389i32, 3u8, 30u8) { os.exit(531) }
    if !len_is(.UmmAlQura, 1389i32, 4u8, 29u8) { os.exit(532) }
    if !len_is(.UmmAlQura, 1389i32, 5u8, 30u8) { os.exit(533) }
    if !len_is(.UmmAlQura, 1389i32, 6u8, 29u8) { os.exit(534) }
    if !len_is(.UmmAlQura, 1389i32, 7u8, 30u8) { os.exit(535) }
    if !len_is(.UmmAlQura, 1389i32, 8u8, 29u8) { os.exit(536) }
    if !len_is(.UmmAlQura, 1389i32, 9u8, 30u8) { os.exit(537) }
    if !len_is(.UmmAlQura, 1389i32, 10u8, 29u8) { os.exit(538) }
    if !len_is(.UmmAlQura, 1389i32, 11u8, 30u8) { os.exit(539) }
    if !len_is(.UmmAlQura, 1389i32, 12u8, 30u8) { os.exit(540) }
    if !len_is(.UmmAlQura, 1400i32, 1u8, 30u8) { os.exit(541) }
    if !len_is(.UmmAlQura, 1400i32, 2u8, 30u8) { os.exit(542) }
    if !len_is(.UmmAlQura, 1400i32, 3u8, 29u8) { os.exit(543) }
    if !len_is(.UmmAlQura, 1400i32, 4u8, 30u8) { os.exit(544) }
    if !len_is(.UmmAlQura, 1400i32, 5u8, 29u8) { os.exit(545) }
    if !len_is(.UmmAlQura, 1400i32, 6u8, 29u8) { os.exit(546) }
    if !len_is(.UmmAlQura, 1400i32, 7u8, 30u8) { os.exit(547) }
    if !len_is(.UmmAlQura, 1400i32, 8u8, 29u8) { os.exit(548) }
    if !len_is(.UmmAlQura, 1400i32, 9u8, 30u8) { os.exit(549) }
    if !len_is(.UmmAlQura, 1400i32, 10u8, 29u8) { os.exit(550) }
    if !len_is(.UmmAlQura, 1400i32, 11u8, 30u8) { os.exit(551) }
    if !len_is(.UmmAlQura, 1400i32, 12u8, 30u8) { os.exit(552) }
    if !len_is(.UmmAlQura, 1445i32, 1u8, 29u8) { os.exit(553) }
    if !len_is(.UmmAlQura, 1445i32, 2u8, 30u8) { os.exit(554) }
    if !len_is(.UmmAlQura, 1445i32, 3u8, 30u8) { os.exit(555) }
    if !len_is(.UmmAlQura, 1445i32, 4u8, 30u8) { os.exit(556) }
    if !len_is(.UmmAlQura, 1445i32, 5u8, 29u8) { os.exit(557) }
    if !len_is(.UmmAlQura, 1445i32, 6u8, 30u8) { os.exit(558) }
    if !len_is(.UmmAlQura, 1445i32, 7u8, 29u8) { os.exit(559) }
    if !len_is(.UmmAlQura, 1445i32, 8u8, 29u8) { os.exit(560) }
    if !len_is(.UmmAlQura, 1445i32, 9u8, 30u8) { os.exit(561) }
    if !len_is(.UmmAlQura, 1445i32, 10u8, 29u8) { os.exit(562) }
    if !len_is(.UmmAlQura, 1445i32, 11u8, 29u8) { os.exit(563) }
    if !len_is(.UmmAlQura, 1445i32, 12u8, 30u8) { os.exit(564) }
    if !len_is(.UmmAlQura, 1446i32, 1u8, 29u8) { os.exit(565) }
    if !len_is(.UmmAlQura, 1446i32, 2u8, 30u8) { os.exit(566) }
    if !len_is(.UmmAlQura, 1446i32, 3u8, 30u8) { os.exit(567) }
    if !len_is(.UmmAlQura, 1446i32, 4u8, 30u8) { os.exit(568) }
    if !len_is(.UmmAlQura, 1446i32, 5u8, 29u8) { os.exit(569) }
    if !len_is(.UmmAlQura, 1446i32, 6u8, 30u8) { os.exit(570) }
    if !len_is(.UmmAlQura, 1446i32, 7u8, 30u8) { os.exit(571) }
    if !len_is(.UmmAlQura, 1446i32, 8u8, 29u8) { os.exit(572) }
    if !len_is(.UmmAlQura, 1446i32, 9u8, 29u8) { os.exit(573) }
    if !len_is(.UmmAlQura, 1446i32, 10u8, 30u8) { os.exit(574) }
    if !len_is(.UmmAlQura, 1446i32, 11u8, 29u8) { os.exit(575) }
    if !len_is(.UmmAlQura, 1446i32, 12u8, 29u8) { os.exit(576) }
    if !len_is(.UmmAlQura, 1500i32, 1u8, 30u8) { os.exit(577) }
    if !len_is(.UmmAlQura, 1500i32, 2u8, 30u8) { os.exit(578) }
    if !len_is(.UmmAlQura, 1500i32, 3u8, 29u8) { os.exit(579) }
    if !len_is(.UmmAlQura, 1500i32, 4u8, 29u8) { os.exit(580) }
    if !len_is(.UmmAlQura, 1500i32, 5u8, 30u8) { os.exit(581) }
    if !len_is(.UmmAlQura, 1500i32, 6u8, 29u8) { os.exit(582) }
    if !len_is(.UmmAlQura, 1500i32, 7u8, 29u8) { os.exit(583) }
    if !len_is(.UmmAlQura, 1500i32, 8u8, 30u8) { os.exit(584) }
    if !len_is(.UmmAlQura, 1500i32, 9u8, 29u8) { os.exit(585) }
    if !len_is(.UmmAlQura, 1500i32, 10u8, 30u8) { os.exit(586) }
    if !len_is(.UmmAlQura, 1500i32, 11u8, 30u8) { os.exit(587) }
    if !len_is(.UmmAlQura, 1500i32, 12u8, 30u8) { os.exit(588) }
    if !len_is(.Persian, 1399i32, 1u8, 31u8) { os.exit(589) }
    if !len_is(.Persian, 1399i32, 2u8, 31u8) { os.exit(590) }
    if !len_is(.Persian, 1399i32, 3u8, 31u8) { os.exit(591) }
    if !len_is(.Persian, 1399i32, 4u8, 31u8) { os.exit(592) }
    if !len_is(.Persian, 1399i32, 5u8, 31u8) { os.exit(593) }
    if !len_is(.Persian, 1399i32, 6u8, 31u8) { os.exit(594) }
    if !len_is(.Persian, 1399i32, 7u8, 30u8) { os.exit(595) }
    if !len_is(.Persian, 1399i32, 8u8, 30u8) { os.exit(596) }
    if !len_is(.Persian, 1399i32, 9u8, 30u8) { os.exit(597) }
    if !len_is(.Persian, 1399i32, 10u8, 30u8) { os.exit(598) }
    if !len_is(.Persian, 1399i32, 11u8, 30u8) { os.exit(599) }
    if !len_is(.Persian, 1399i32, 12u8, 30u8) { os.exit(600) }
    if !len_is(.Persian, 1399i32, 12u8, 30u8) { os.exit(601) }
    if !len_is(.Persian, 1400i32, 12u8, 29u8) { os.exit(602) }
    if !calendars.is_leap_year(.Persian, 1403i32) { os.exit(603) }
    if calendars.is_leap_year(.Persian, 1404i32) { os.exit(604) }
    if calendars.is_leap_year(.Persian, 1405i32) { os.exit(605) }
    if calendars.is_leap_year(.Persian, 1406i32) { os.exit(606) }
    if calendars.is_leap_year(.Persian, 1407i32) { os.exit(607) }
    if !calendars.is_leap_year(.Persian, 1408i32) { os.exit(608) }
    if calendars.is_leap_year(.Persian, 1409i32) { os.exit(609) }
    if calendars.is_leap_year(.Persian, 1410i32) { os.exit(610) }
    if calendars.is_leap_year(.Persian, 1411i32) { os.exit(611) }
    if !calendars.is_leap_year(.Persian, 1412i32) { os.exit(612) }
    if calendars.is_leap_year(.Persian, 1413i32) { os.exit(613) }
    if calendars.is_leap_year(.Persian, 1414i32) { os.exit(614) }
    if calendars.is_leap_year(.Persian, 1415i32) { os.exit(615) }
    if !calendars.is_leap_year(.Persian, 1416i32) { os.exit(616) }
    if calendars.is_leap_year(.Persian, 1417i32) { os.exit(617) }
    if calendars.is_leap_year(.Persian, 1418i32) { os.exit(618) }
    if calendars.is_leap_year(.Persian, 1419i32) { os.exit(619) }
    if !calendars.is_leap_year(.Persian, 1420i32) { os.exit(620) }
    if calendars.is_leap_year(.Persian, 1421i32) { os.exit(621) }
    if calendars.is_leap_year(.Persian, 1422i32) { os.exit(622) }
    if calendars.is_leap_year(.Persian, 1423i32) { os.exit(623) }
    if !calendars.is_leap_year(.Persian, 1424i32) { os.exit(624) }
    if calendars.is_leap_year(.Persian, 1425i32) { os.exit(625) }
    if calendars.is_leap_year(.Persian, 1426i32) { os.exit(626) }
    if calendars.is_leap_year(.Persian, 1427i32) { os.exit(627) }
    if !calendars.is_leap_year(.Persian, 1428i32) { os.exit(628) }
    if calendars.is_leap_year(.Persian, 1429i32) { os.exit(629) }
    if calendars.is_leap_year(.Persian, 1430i32) { os.exit(630) }
    if calendars.is_leap_year(.Persian, 1431i32) { os.exit(631) }
    if !calendars.is_leap_year(.Persian, 1432i32) { os.exit(632) }
    if calendars.is_leap_year(.Persian, 1433i32) { os.exit(633) }
    if calendars.is_leap_year(.Persian, 1434i32) { os.exit(634) }
    if calendars.is_leap_year(.Persian, 1435i32) { os.exit(635) }
    if calendars.year_ok(.UmmAlQura, 1342i32) || calendars.year_ok(.UmmAlQura, 1501i32) || !calendars.year_ok(.UmmAlQura, 1343i32) || !calendars.year_ok(.UmmAlQura, 1500i32) { os.exit(636) }
    let (before, before_e) = calendars.from_days(.UmmAlQura, 0i64 - 16590i64)
    if before_e == ok { os.exit(637) }
    let (after, after_e) = calendars.from_days(.UmmAlQura, 39402i64)
    if after_e == ok { os.exit(638) }
    let (zero_year, zero_e) = calendars.days_in_month(.Persian, 0i32, 1u8)
    if zero_e == ok { os.exit(639) }
    if !calendars.valid(.Persian, time.Date{ year: 1403i32, month: 12u8, day: 30u8 }) { os.exit(640) }
    if calendars.valid(.Persian, time.Date{ year: 1404i32, month: 12u8, day: 30u8 }) { os.exit(641) }
    let (nowruz, nowruz_e) = calendars.from_iso(.Persian, time.Date{ year: 2024i32, month: 3u8, day: 20u8 })
    if nowruz_e != ok || nowruz.year != 1403i32 || nowruz.month != 1u8 || nowruz.day != 1u8 { os.exit(642) }
    let (bumped, bumped_e) = calendars.add_months(.Persian, time.Date{ year: 1403i32, month: 6u8, day: 31u8 }, 1i64)
    if bumped_e != ok || bumped.month != 7u8 || bumped.day != 30u8 { os.exit(643) }
    let (shifted, shifted_e) = calendars.convert(.Persian, .UmmAlQura, time.Date{ year: 1403i32, month: 1u8, day: 1u8 })
    if shifted_e != ok || shifted.year != 1445i32 || shifted.month != 9u8 || shifted.day != 10u8 { os.exit(644) }
    ret ok
}
