// `e.net.idna`: every RFC 3492 7.1 sample encodes to the RFC's Punycode and decodes back
// (codes 1-19 encode, 101-119 decode), `to_ascii` agrees with the Python `idna` package
// (uts46, non-transitional: ß stays ß) on the plan's domains and `to_unicode` reverses it,
// every RFC 5892 contextual rule has a positive and negative case, PVALID and RFC 5893
// Bidi refusals cannot enter through either U-labels or A-labels, and the hyphen, length,
// buffer and bad-digit errors answer by name. The Unicode 15.0 tables come from
// reference.py beside this fixture.

use e.io
use e.mem
use e.net.idna
use e.os

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn same_points(a: []const u32, b: []const u32) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn sample(points: []const u32, expected: []const u8, code: i32) {
    var out: [128]u8 = zero
    let (n, encode_error) = idna.punycode_encode(points, out[..])
    if encode_error != ok || !same(out[..n], expected) { os.exit(code) }
    var back: [64]u32 = zero
    let (m, decode_error) = idna.punycode_decode(expected, back[..])
    if decode_error != ok || !same_points(back[..m], points) { os.exit(code + 100i32) }
}

// `to_ascii` of `domain` is `a_label`, and `to_unicode` of that is `u_label`.
fn domain(input: []const u8, a_label: []const u8, u_label: []const u8, code: i32) {
    var out: [256]u8 = zero
    var scratch: [512]u32 = zero
    let (n, ascii_error) = idna.to_ascii(input, out[..], scratch[..])
    if ascii_error != ok || !same(out[..n], a_label) { os.exit(code) }
    var uni: [256]u8 = zero
    let (m, unicode_error) = idna.to_unicode(out[..n], uni[..])
    if unicode_error != ok || !same(uni[..m], u_label) { os.exit(code + 10i32) }
}

fn failing(input: []const u8, expected: err, code: i32) {
    var out: [256]u8 = zero
    var scratch: [512]u32 = zero
    let (n, ascii_error) = idna.to_ascii(input, out[..], scratch[..])
    if ascii_error != expected { os.exit(code) }
}

fn unicode_failing(input: []const u8, code: i32) {
    var out: [256]u8 = zero
    let (_, unicode_error) = idna.to_unicode(input, out[..])
    if unicode_error != idna.Invalid { os.exit(code) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1-19 / 101-119: the RFC 3492 sample strings.
    let pa = [17]u32{ 1604u32, 1610u32, 1607u32, 1605u32, 1575u32, 1576u32, 1578u32, 1603u32, 1604u32, 1605u32, 1608u32, 1588u32, 1593u32, 1585u32, 1576u32, 1610u32, 1567u32 }
    sample(pa[..], "egbpdaj6bu4bxfgehfvwxn", 1i32)
    let pb = [9]u32{ 20182u32, 20204u32, 20026u32, 20160u32, 20040u32, 19981u32, 35828u32, 20013u32, 25991u32 }
    sample(pb[..], "ihqwcrb4cv8a8dqg056pqjye", 2i32)
    let pc = [9]u32{ 20182u32, 20497u32, 29234u32, 20160u32, 40637u32, 19981u32, 35498u32, 20013u32, 25991u32 }
    sample(pc[..], "ihqwctvzc91f659drss3x8bo0yb", 3i32)
    let pd = [22]u32{ 80u32, 114u32, 111u32, 269u32, 112u32, 114u32, 111u32, 115u32, 116u32, 283u32, 110u32, 101u32, 109u32, 108u32, 117u32, 118u32, 237u32, 269u32, 101u32, 115u32, 107u32, 121u32 }
    sample(pd[..], "Proprostnemluvesky-uyb24dma41a", 4i32)
    let pe = [22]u32{ 1500u32, 1502u32, 1492u32, 1492u32, 1501u32, 1508u32, 1513u32, 1493u32, 1496u32, 1500u32, 1488u32, 1502u32, 1491u32, 1489u32, 1512u32, 1497u32, 1501u32, 1506u32, 1489u32, 1512u32, 1497u32, 1514u32 }
    sample(pe[..], "4dbcagdahymbxekheh6e0a7fei0b", 5i32)
    let pf = [30]u32{ 2351u32, 2361u32, 2354u32, 2379u32, 2327u32, 2361u32, 2367u32, 2344u32, 2381u32, 2342u32, 2368u32, 2325u32, 2381u32, 2351u32, 2379u32, 2306u32, 2344u32, 2361u32, 2368u32, 2306u32, 2348u32, 2379u32, 2354u32, 2360u32, 2325u32, 2340u32, 2375u32, 2361u32, 2376u32, 2306u32 }
    sample(pf[..], "i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd", 6i32)
    let pg = [18]u32{ 12394u32, 12380u32, 12415u32, 12435u32, 12394u32, 26085u32, 26412u32, 35486u32, 12434u32, 35441u32, 12375u32, 12390u32, 12367u32, 12428u32, 12394u32, 12356u32, 12398u32, 12363u32 }
    sample(pg[..], "n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa", 7i32)
    let ph = [24]u32{ 49464u32, 44228u32, 51032u32, 47784u32, 46304u32, 49324u32, 46988u32, 46308u32, 51060u32, 54620u32, 44397u32, 50612u32, 47484u32, 51060u32, 54644u32, 54620u32, 45796u32, 47732u32, 50620u32, 47560u32, 45208u32, 51339u32, 51012u32, 44620u32 }
    sample(ph[..], "989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c", 8i32)
    let pi = [28]u32{ 1087u32, 1086u32, 1095u32, 1077u32, 1084u32, 1091u32, 1078u32, 1077u32, 1086u32, 1085u32, 1080u32, 1085u32, 1077u32, 1075u32, 1086u32, 1074u32, 1086u32, 1088u32, 1103u32, 1090u32, 1087u32, 1086u32, 1088u32, 1091u32, 1089u32, 1089u32, 1082u32, 1080u32 }
    sample(pi[..], "b1abfaaepdrnnbgefbadotcwatmq2g4l", 9i32)
    let pj = [40]u32{ 80u32, 111u32, 114u32, 113u32, 117u32, 233u32, 110u32, 111u32, 112u32, 117u32, 101u32, 100u32, 101u32, 110u32, 115u32, 105u32, 109u32, 112u32, 108u32, 101u32, 109u32, 101u32, 110u32, 116u32, 101u32, 104u32, 97u32, 98u32, 108u32, 97u32, 114u32, 101u32, 110u32, 69u32, 115u32, 112u32, 97u32, 241u32, 111u32, 108u32 }
    sample(pj[..], "PorqunopuedensimplementehablarenEspaol-fmd56a", 10i32)
    let pk = [31]u32{ 84u32, 7841u32, 105u32, 115u32, 97u32, 111u32, 104u32, 7885u32, 107u32, 104u32, 244u32, 110u32, 103u32, 116u32, 104u32, 7875u32, 99u32, 104u32, 7881u32, 110u32, 243u32, 105u32, 116u32, 105u32, 7871u32, 110u32, 103u32, 86u32, 105u32, 7879u32, 116u32 }
    sample(pk[..], "TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g", 11i32)
    let pl = [8]u32{ 51u32, 24180u32, 66u32, 32068u32, 37329u32, 20843u32, 20808u32, 29983u32 }
    sample(pl[..], "3B-ww4c5e180e575a65lsy2b", 12i32)
    let pm = [24]u32{ 23433u32, 23460u32, 22856u32, 32654u32, 24693u32, 45u32, 119u32, 105u32, 116u32, 104u32, 45u32, 83u32, 85u32, 80u32, 69u32, 82u32, 45u32, 77u32, 79u32, 78u32, 75u32, 69u32, 89u32, 83u32 }
    sample(pm[..], "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n", 13i32)
    let pn = [25]u32{ 72u32, 101u32, 108u32, 108u32, 111u32, 45u32, 65u32, 110u32, 111u32, 116u32, 104u32, 101u32, 114u32, 45u32, 87u32, 97u32, 121u32, 45u32, 12381u32, 12428u32, 12382u32, 12428u32, 12398u32, 22580u32, 25152u32 }
    sample(pn[..], "Hello-Another-Way--fc4qua05auwb3674vfr0b", 14i32)
    let po = [8]u32{ 12402u32, 12392u32, 12388u32, 23627u32, 26681u32, 12398u32, 19979u32, 50u32 }
    sample(po[..], "2-u9tlzr9756bt3uc0v", 15i32)
    let pp = [13]u32{ 77u32, 97u32, 106u32, 105u32, 12391u32, 75u32, 111u32, 105u32, 12377u32, 12427u32, 53u32, 31186u32, 21069u32 }
    sample(pp[..], "MajiKoi5-783gue6qz075azm5e", 16i32)
    let pq = [9]u32{ 12497u32, 12501u32, 12451u32, 12540u32, 100u32, 101u32, 12523u32, 12531u32, 12496u32 }
    sample(pq[..], "de-jg4avhby1noc0d", 17i32)
    let pr = [7]u32{ 12381u32, 12398u32, 12473u32, 12500u32, 12540u32, 12489u32, 12391u32 }
    sample(pr[..], "d9juau41awczczp", 18i32)
    let ps = [11]u32{ 45u32, 62u32, 32u32, 36u32, 49u32, 46u32, 48u32, 48u32, 32u32, 60u32, 45u32 }
    sample(ps[..], "-> $1.00 <--", 19i32)

    // 20: the RFC prints sample I with an uppercase D; a decoder reads digits either case.
    var back: [64]u32 = zero
    let (mixed_n, mixed_error) = idna.punycode_decode("b1abfaaepdrnnbgefbaDotcwatmq2g4l", back[..])
    if mixed_error != ok || !same_points(back[..mixed_n], pi[..]) { os.exit(20i32) }

    // 21-26 (+10 for the way back): to_ascii against the idna package, to_unicode reverses.
    domain("b\xc3\xbccher.example", "xn--bcher-kva.example", "b\xc3\xbccher.example", 21i32)
    domain("m\xc3\xbcnchen.de", "xn--mnchen-3ya.de", "m\xc3\xbcnchen.de", 22i32)
    domain("\xe4\xbe\x8b\xe3\x81\x88.\xe3\x83\x86\xe3\x82\xb9\xe3\x83\x88", "xn--r8jz45g.xn--zckzah", "\xe4\xbe\x8b\xe3\x81\x88.\xe3\x83\x86\xe3\x82\xb9\xe3\x83\x88", 23i32)
    // Non-transitional: ß is not mapped to ss (idna.encode answers the same).
    domain("stra\xc3\x9fe.de", "xn--strae-oqa.de", "stra\xc3\x9fe.de", 24i32)
    domain("B\xc3\xbccher.Example", "xn--bcher-kva.example", "b\xc3\xbccher.example", 25i32)
    domain("Example.COM", "example.com", "example.com", 26i32)
    // 27: the ideographic full stop separates labels; 28: an A-label passes through.
    domain("\xe4\xbe\x8b\xe3\x81\x88\xe3\x80\x82\xe3\x83\x86\xe3\x82\xb9\xe3\x83\x88", "xn--r8jz45g.xn--zckzah", "\xe4\xbe\x8b\xe3\x81\x88.\xe3\x83\x86\xe3\x82\xb9\xe3\x83\x88", 27i32)
    domain("xn--bcher-kva.example", "xn--bcher-kva.example", "b\xc3\xbccher.example", 28i32)
    domain("XN--BCHER-KVA.Example", "xn--bcher-kva.example", "b\xc3\xbccher.example", 29i32)

    // 40-44: the hyphen and length rules.
    failing("a..b", idna.Invalid, 40i32)
    failing("-abc.example", idna.Invalid, 41i32)
    failing("abc-.example", idna.Invalid, 42i32)
    failing("ab--cd.example", idna.Invalid, 43i32)
    var long: [72]u8 = zero
    var i = 0usize
    while i < 64usize {
        long[i] = 97u8
        i += 1usize
    }
    let tail = ".example"
    while i < 72usize {
        long[i] = tail[i - 64usize]
        i += 1usize
    }
    failing(long[..], idna.TooLong, 44i32)
    // 46-47: a short output and a short scratch answer TooSmall.
    var small: [8]u8 = zero
    var scratch: [512]u32 = zero
    let (small_n, small_error) = idna.to_ascii("b\xc3\xbccher.example", small[..], scratch[..])
    if small_error != idna.TooSmall { os.exit(46i32) }
    var out: [256]u8 = zero
    let (scratch_n, scratch_error) = idna.to_ascii("b\xc3\xbccher.example", out[..], scratch[..8usize])
    if scratch_error != idna.TooSmall { os.exit(47i32) }
    // 48: 64 a's is TooLong even with room; 49: malformed UTF-8 is Invalid.
    let (long_n, long_error) = idna.to_ascii(long[..64usize], out[..], scratch[..])
    if long_error != idna.TooLong { os.exit(48i32) }
    failing("b\xffcher.example", idna.Invalid, 49i32)

    // 50-52: a bad digit, an overflowing digit run and a bad label decode as Invalid.
    let (bad_n, bad_error) = idna.punycode_decode("bcher-k!a", back[..])
    if bad_error != idna.Invalid { os.exit(50i32) }
    let (over_n, over_error) = idna.to_unicode("xn--999999999.example", out[..])
    if over_error != idna.Invalid { os.exit(51i32) }
    let (bad_label_n, bad_label_error) = idna.to_unicode("xn--bcher-k!a.example", out[..])
    if bad_label_error != idna.Invalid { os.exit(52i32) }

    // 53-54: the predicates.
    if !idna.is_ascii_label("abc-1") || idna.is_ascii_label("b\xc3\xbccher") { os.exit(53i32) }
    if !idna.label_valid("xn--bcher-kva") || idna.label_valid("ab--cd") || idna.label_valid("") || idna.label_valid("a_b") { os.exit(54i32) }

    // 60-69: every RFC 5892 contextual rule, including both CONTEXTJ paths.
    domain("l\xc2\xb7l", "xn--ll-0ea", "l\xc2\xb7l", 60i32)
    domain("\xcd\xb5\xce\xb1", "xn--wva4j", "\xcd\xb5\xce\xb1", 61i32)
    domain("\xd7\x90\xd7\xb3", "xn--4db4e", "\xd7\x90\xd7\xb3", 62i32)
    domain("\xe3\x82\xab\xe3\x83\xbb\xe3\x83\x8a", "xn--lck2c6g", "\xe3\x82\xab\xe3\x83\xbb\xe3\x83\x8a", 63i32)
    domain("\xd8\xa7\xd9\xa1\xd9\xa2", "xn--mgb0jd", "\xd8\xa7\xd9\xa1\xd9\xa2", 64i32)
    domain("\xd8\xa7\xdb\xb1\xdb\xb2", "xn--mgb81bd", "\xd8\xa7\xdb\xb1\xdb\xb2", 65i32)
    domain("\xe0\xa4\x95\xe0\xa5\x8d\xe2\x80\x8d", "xn--11b6iy14e", "\xe0\xa4\x95\xe0\xa5\x8d\xe2\x80\x8d", 66i32)
    domain("\xe0\xa4\x95\xe0\xa5\x8d\xe2\x80\x8c", "xn--11b6iv14e", "\xe0\xa4\x95\xe0\xa5\x8d\xe2\x80\x8c", 67i32)
    domain("\xd9\x86\xe2\x80\x8c\xd9\x86", "xn--ihba709q", "\xd9\x86\xe2\x80\x8c\xd9\x86", 68i32)
    domain("\xd8\xa7\xd9\x84\xd8\xb9\xd8\xb1\xd8\xa8\xd9\x8a\xd8\xa9", "xn--mgbcd4a2b0d2b", "\xd8\xa7\xd9\x84\xd8\xb9\xd8\xb1\xd8\xa8\xd9\x8a\xd8\xa9", 69i32)

    // 80-92: bad contexts, disallowed/unassigned scalars and RFC 5893 failures.
    failing("a\xc2\xb7b", idna.Invalid, 80i32)
    failing("\xcd\xb5a", idna.Invalid, 81i32)
    failing("a\xd7\xb3", idna.Invalid, 82i32)
    failing("a\xe3\x83\xbbb", idna.Invalid, 83i32)
    failing("\xd9\xa1\xdb\xb2", idna.Invalid, 84i32)
    failing("a\xe2\x80\x8cb", idna.Invalid, 85i32)
    failing("a\xe2\x80\x8db", idna.Invalid, 98i32)
    failing("abc\xf0\x9f\x98\x80", idna.Invalid, 86i32)
    failing("\xef\xac\x81", idna.Invalid, 87i32)
    failing("\xcc\x81a", idna.Invalid, 88i32)
    failing("\xd9\x80", idna.Invalid, 89i32)
    failing("\xd8\xa7a", idna.Invalid, 90i32)
    failing("\xd8\xa71\xd9\xa1", idna.Invalid, 91i32)
    failing("\xcd\xb8", idna.Invalid, 92i32)

    // A-labels cannot bypass U-label validity checks on decode or pass-through.
    unicode_failing("xn--abc-th33b", 93i32)
    unicode_failing("xn--ab-0ea", 94i32)
    unicode_failing("xn--a-ymc", 95i32)
    unicode_failing("xn--jm6c", 96i32)
    failing("xn--abc-th33b", idna.Invalid, 97i32)
    unicode_failing("xn--ab-m1t", 99i32)

    try io.print("net idna ok\n")
    ret ok
}
