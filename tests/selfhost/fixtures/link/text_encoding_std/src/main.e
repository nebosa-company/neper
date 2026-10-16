// `e.text.charset`, `e.text.charset_cjk` and `e.fmt.html.encoding`: the Encoding Standard's labels, single-byte and
// multi-byte decoders on a character or two of each, and the HTML encoding sniffing (BOM, transport label, meta prescan).

use e.fmt.html.encoding as sniff
use e.mem
use e.os
use e.str
use e.text.charset as charset
use e.text.charset_cjk as cjk

fn decoded(a: *mem.Arena, name: str, bytes: str) -> str {
    let (t, e) = cjk.decode(a, name, bytes)
    if e != ok { ret "!" }
    ret t
}

fn label_is(label: str, want: str) -> bool {
    let (name, good) = charset.label_to_name(label)
    ret good && str.eq(name, want)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Labels.
    if !label_is(" Latin1 ", "windows-1252") || !label_is("UTF8", "UTF-8") || !label_is("iso-8859-1", "windows-1252") { os.exit(1i32) }
    if !label_is("sjis", "Shift_JIS") { os.exit(30i32) }
    if !label_is("gb2312", "GBK") { os.exit(31i32) }
    if !label_is("KOI8-R", "KOI8-R") { os.exit(32i32) }
    if !label_is("utf-16", "UTF-16LE") { os.exit(33i32) }
    let (unknown, known) = charset.label_to_name("no-such-encoding")
    if known { os.exit(3i32) }
    // Single-byte encodings.
    if !str.eq(decoded(a, "windows-1252", "\x80\xe9a"), "\xe2\x82\xac\xc3\xa9a") { os.exit(4i32) }
    if !str.eq(decoded(a, "ISO-8859-2", "\xb1"), "\xc4\x85") { os.exit(5i32) }
    if !str.eq(decoded(a, "KOI8-R", "\xc1"), "\xd0\xb0") { os.exit(6i32) }
    // Multi-byte encodings.
    if !str.eq(decoded(a, "Shift_JIS", "\x82\xa0\xb1"), "\xe3\x81\x82\xef\xbd\xb1") { os.exit(7i32) }
    if !str.eq(decoded(a, "EUC-JP", "\xa4\xa2\x8e\xb1"), "\xe3\x81\x82\xef\xbd\xb1") { os.exit(8i32) }
    if !str.eq(decoded(a, "Big5", "\xa4\x40"), "\xe4\xb8\x80") { os.exit(9i32) }
    if !str.eq(decoded(a, "GBK", "\xb0\xa1"), "\xe5\x95\x8a") { os.exit(10i32) }
    if !str.eq(decoded(a, "gb18030", "\x81\x30\x81\x30"), "\xc2\x80") { os.exit(11i32) }
    if !str.eq(decoded(a, "EUC-KR", "\xb0\xa1"), "\xea\xb0\x80") { os.exit(12i32) }
    if !str.eq(decoded(a, "ISO-2022-JP", "\x1b$B$\x22\x1b(Bx"), "\xe3\x81\x82x") { os.exit(13i32) }
    // A malformed sequence is one replacement character; an ASCII byte after a lone lead byte survives.
    if !str.eq(decoded(a, "Shift_JIS", "\x82A"), "\xef\xbf\xbdA") { os.exit(14i32) }
    // UTF-16 through the BOM.
    let (t16, e16) = cjk.decode_sniffing_bom(a, "windows-1252", "\xff\xfeh\x00i\x00")
    if e16 != ok || !str.eq(t16, "hi") { os.exit(15i32) }
    // HTML encoding sniffing.
    if !str.eq(sniff.determine("<meta charset=\"iso-8859-2\">", ""), "ISO-8859-2") { os.exit(16i32) }
    if !str.eq(sniff.determine("<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=koi8-r\">", ""), "KOI8-R") { os.exit(17i32) }
    if !str.eq(sniff.determine("<meta charset=utf-8>", "windows-1251"), "windows-1251") { os.exit(18i32) }
    if !str.eq(sniff.determine("<p>plain</p>", ""), "windows-1252") { os.exit(19i32) }
    if !str.eq(sniff.determine("\xef\xbb\xbf<meta charset=koi8-r>", ""), "UTF-8") { os.exit(20i32) }
    if !str.eq(sniff.determine("<!-- <meta charset=koi8-r> --><p>", ""), "windows-1252") { os.exit(21i32) }
    if !str.eq(sniff.determine("<meta charset=utf-16le>", ""), "UTF-8") { os.exit(22i32) }
    if !str.eq(sniff.determine("<meta http-equiv=refresh content=\"0; charset=koi8-r\">", ""), "windows-1252") { os.exit(23i32) }
    let (doc, used, de) = sniff.decode_document(a, "<meta charset=windows-1251><p>\xcf\xf0\xe8\xe2\xe5\xf2", "")
    if de != ok || !str.eq(used, "windows-1251") || !str.eq(doc, "<meta charset=windows-1251><p>\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82") { os.exit(24i32) }
    ret ok
}
