// `e.text.unicode`: categories, combining classes, simple case mappings, full case
// folding, whitespace, alphabetic and numeric against Python's unicodedata 15.0.0
// (reference.py beside this fixture generates the module's tables and these
// expectations), and grapheme clusters over combining marks, CR LF, regional
// indicator pairs, a ZWJ family, decomposed Hangul and a variation selector. Every
// check has its own exit code.
use e.os
use e.mem
use e.str
use e.text.unicode as unicode

fn main(a: *mem.Arena, args: []str) -> err {
    if !str.eq(unicode.version(), "15.0.0") { os.exit(1) }
    if unicode.category(65u32) != .Lu { os.exit(10) }
    if unicode.category(97u32) != .Ll { os.exit(11) }
    if unicode.category(453u32) != .Lt { os.exit(12) }
    if unicode.category(688u32) != .Lm { os.exit(13) }
    if unicode.category(20013u32) != .Lo { os.exit(14) }
    if unicode.category(768u32) != .Mn { os.exit(15) }
    if unicode.category(2307u32) != .Mc { os.exit(16) }
    if unicode.category(8413u32) != .Me { os.exit(17) }
    if unicode.category(55u32) != .Nd { os.exit(18) }
    if unicode.category(8544u32) != .Nl { os.exit(19) }
    if unicode.category(189u32) != .No { os.exit(20) }
    if unicode.category(95u32) != .Pc { os.exit(21) }
    if unicode.category(45u32) != .Pd { os.exit(22) }
    if unicode.category(40u32) != .Ps { os.exit(23) }
    if unicode.category(41u32) != .Pe { os.exit(24) }
    if unicode.category(171u32) != .Pi { os.exit(25) }
    if unicode.category(187u32) != .Pf { os.exit(26) }
    if unicode.category(33u32) != .Po { os.exit(27) }
    if unicode.category(43u32) != .Sm { os.exit(28) }
    if unicode.category(36u32) != .Sc { os.exit(29) }
    if unicode.category(94u32) != .Sk { os.exit(30) }
    if unicode.category(169u32) != .So { os.exit(31) }
    if unicode.category(32u32) != .Zs { os.exit(32) }
    if unicode.category(8232u32) != .Zl { os.exit(33) }
    if unicode.category(8233u32) != .Zp { os.exit(34) }
    if unicode.category(7u32) != .Cc { os.exit(35) }
    if unicode.category(173u32) != .Cf { os.exit(36) }
    if unicode.category(55296u32) != .Cs { os.exit(37) }
    if unicode.category(57344u32) != .Co { os.exit(38) }
    if unicode.category(888u32) != .Cn { os.exit(39) }
    if unicode.category(1114111u32) != .Cn { os.exit(40) }
    if unicode.category(128512u32) != .So { os.exit(41) }
    if unicode.category(65536u32) != .Lo { os.exit(42) }
    if unicode.category(917999u32) != .Mn { os.exit(43) }
    if unicode.combining_class(768u32) != 230u8 { os.exit(44) }
    if unicode.combining_class(769u32) != 230u8 { os.exit(45) }
    if unicode.combining_class(789u32) != 232u8 { os.exit(46) }
    if unicode.combining_class(795u32) != 216u8 { os.exit(47) }
    if unicode.combining_class(12441u32) != 8u8 { os.exit(48) }
    if unicode.combining_class(65u32) != 0u8 { os.exit(49) }
    if unicode.combining_class(7630u32) != 214u8 { os.exit(50) }
    if unicode.combining_class(837u32) != 240u8 { os.exit(51) }
    if unicode.to_lower_simple(65u32) != 97u32 || unicode.to_upper_simple(65u32) != 65u32 { os.exit(52) }
    if unicode.to_lower_simple(97u32) != 97u32 || unicode.to_upper_simple(97u32) != 65u32 { os.exit(53) }
    if unicode.to_lower_simple(201u32) != 233u32 || unicode.to_upper_simple(201u32) != 201u32 { os.exit(54) }
    if unicode.to_lower_simple(7838u32) != 223u32 || unicode.to_upper_simple(7838u32) != 7838u32 { os.exit(55) }
    if unicode.to_lower_simple(931u32) != 963u32 || unicode.to_upper_simple(931u32) != 931u32 { os.exit(56) }
    if unicode.to_lower_simple(66560u32) != 66600u32 || unicode.to_upper_simple(66560u32) != 66560u32 { os.exit(57) }
    if unicode.to_lower_simple(453u32) != 454u32 || unicode.to_upper_simple(453u32) != 452u32 { os.exit(58) }
    if unicode.to_lower_simple(304u32) != 304u32 || unicode.to_upper_simple(304u32) != 304u32 { os.exit(59) }
    if unicode.to_lower_simple(20013u32) != 20013u32 || unicode.to_upper_simple(20013u32) != 20013u32 { os.exit(60) }
    let (fold_61, fe61) = unicode.casefold(a, "Stra\xc3\x9fe")
    if fe61 != ok || !str.eq(fold_61, "strasse") { os.exit(61) }
    let (fold_62, fe62) = unicode.casefold(a, "\xce\xa3\xce\x8a\xce\xa3\xce\xa5\xce\xa6\xce\x9f\xce\xa3")
    if fe62 != ok || !str.eq(fold_62, "\xcf\x83\xce\xaf\xcf\x83\xcf\x85\xcf\x86\xce\xbf\xcf\x83") { os.exit(62) }
    let (fold_63, fe63) = unicode.casefold(a, "\xc7\x85emal")
    if fe63 != ok || !str.eq(fold_63, "\xc7\x86emal") { os.exit(63) }
    let (fold_64, fe64) = unicode.casefold(a, "\xc4\xb0")
    if fe64 != ok || !str.eq(fold_64, "i\xcc\x87") { os.exit(64) }
    let (fold_65, fe65) = unicode.casefold(a, "plain ascii")
    if fe65 != ok || !str.eq(fold_65, "plain ascii") { os.exit(65) }
    let (fold_66, fe66) = unicode.casefold(a, "\xef\xac\x83")
    if fe66 != ok || !str.eq(fold_66, "ffi") { os.exit(66) }
    if unicode.is_whitespace(32u32) != true { os.exit(67) }
    if unicode.is_whitespace(9u32) != true { os.exit(68) }
    if unicode.is_whitespace(160u32) != true { os.exit(69) }
    if unicode.is_whitespace(12288u32) != true { os.exit(70) }
    if unicode.is_whitespace(65u32) != false { os.exit(71) }
    if unicode.is_whitespace(8203u32) != false { os.exit(72) }
    if unicode.is_alphabetic(65u32) != true || unicode.is_numeric(65u32) != false { os.exit(73) }
    if unicode.is_alphabetic(20013u32) != true || unicode.is_numeric(20013u32) != false { os.exit(74) }
    if unicode.is_alphabetic(8544u32) != true || unicode.is_numeric(8544u32) != true { os.exit(75) }
    if unicode.is_alphabetic(55u32) != false || unicode.is_numeric(55u32) != true { os.exit(76) }
    if unicode.is_alphabetic(189u32) != false || unicode.is_numeric(189u32) != true { os.exit(77) }
    if unicode.is_alphabetic(43u32) != false || unicode.is_numeric(43u32) != false { os.exit(78) }
    var it_79 = unicode.graphemes("e\xcc\x81a")
    let (g_79, more_79) = unicode.graphemes_next(&it_79)
    if !more_79 || !str.eq(g_79, "e\xcc\x81") { os.exit(79) }
    let (g_80, more_80) = unicode.graphemes_next(&it_79)
    if !more_80 || !str.eq(g_80, "a") { os.exit(80) }
    let (end_81, more_end_81) = unicode.graphemes_next(&it_79)
    if more_end_81 { os.exit(81) }
    var it_82 = unicode.graphemes("\x0d\x0ax")
    let (g_82, more_82) = unicode.graphemes_next(&it_82)
    if !more_82 || !str.eq(g_82, "\x0d\x0a") { os.exit(82) }
    let (g_83, more_83) = unicode.graphemes_next(&it_82)
    if !more_83 || !str.eq(g_83, "x") { os.exit(83) }
    let (end_84, more_end_84) = unicode.graphemes_next(&it_82)
    if more_end_84 { os.exit(84) }
    var it_85 = unicode.graphemes("\xf0\x9f\x87\xba\xf0\x9f\x87\xb8\xf0\x9f\x87\xac\xf0\x9f\x87\xa7")
    let (g_85, more_85) = unicode.graphemes_next(&it_85)
    if !more_85 || !str.eq(g_85, "\xf0\x9f\x87\xba\xf0\x9f\x87\xb8") { os.exit(85) }
    let (g_86, more_86) = unicode.graphemes_next(&it_85)
    if !more_86 || !str.eq(g_86, "\xf0\x9f\x87\xac\xf0\x9f\x87\xa7") { os.exit(86) }
    let (end_87, more_end_87) = unicode.graphemes_next(&it_85)
    if more_end_87 { os.exit(87) }
    var it_88 = unicode.graphemes("\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7!")
    let (g_88, more_88) = unicode.graphemes_next(&it_88)
    if !more_88 || !str.eq(g_88, "\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7") { os.exit(88) }
    let (g_89, more_89) = unicode.graphemes_next(&it_88)
    if !more_89 || !str.eq(g_89, "!") { os.exit(89) }
    let (end_90, more_end_90) = unicode.graphemes_next(&it_88)
    if more_end_90 { os.exit(90) }
    var it_91 = unicode.graphemes("\xe1\x84\x80\xe1\x85\xa1\xe1\x86\xa8\xea\xb0\x81")
    let (g_91, more_91) = unicode.graphemes_next(&it_91)
    if !more_91 || !str.eq(g_91, "\xe1\x84\x80\xe1\x85\xa1\xe1\x86\xa8") { os.exit(91) }
    let (g_92, more_92) = unicode.graphemes_next(&it_91)
    if !more_92 || !str.eq(g_92, "\xea\xb0\x81") { os.exit(92) }
    let (end_93, more_end_93) = unicode.graphemes_next(&it_91)
    if more_end_93 { os.exit(93) }
    var it_94 = unicode.graphemes("a\xef\xb8\x8fb")
    let (g_94, more_94) = unicode.graphemes_next(&it_94)
    if !more_94 || !str.eq(g_94, "a\xef\xb8\x8f") { os.exit(94) }
    let (g_95, more_95) = unicode.graphemes_next(&it_94)
    if !more_95 || !str.eq(g_95, "b") { os.exit(95) }
    let (end_96, more_end_96) = unicode.graphemes_next(&it_94)
    if more_end_96 { os.exit(96) }
    var it_97 = unicode.graphemes("")
    let (end_97, more_end_97) = unicode.graphemes_next(&it_97)
    if more_end_97 { os.exit(97) }
    ret ok
}
