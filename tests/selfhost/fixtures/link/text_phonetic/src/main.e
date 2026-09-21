// `e.text.phonetic`: Soundex, the original Metaphone and NYSIIS agree with
// jellyfish on fifty-odd names (checked one by one in Python before they
// were written here), the empty name codes to nothing, and short output
// answers `TooSmall`. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.phonetic

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn check(name: str, soundex: str, metaphone: str, nysiis: str) {
    var out: [32]u8 = zero
    var scratch: [32]u8 = zero
    let (s, s_error) = phonetic.soundex(name, out[..])
    if s_error != ok || !same(s, soundex) { os.exit(1i32) }
    let (m, m_error) = phonetic.metaphone(name, out[..])
    if m_error != ok || !same(m, metaphone) { os.exit(2i32) }
    let (n, n_error) = phonetic.nysiis(name, out[..], scratch[..])
    if n_error != ok || !same(n, nysiis) { os.exit(3i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    check("Robert", "R163", "RBRT", "RABAD")
    check("Rupert", "R163", "RPRT", "RAPAD")
    check("Rubin", "R150", "RBN", "RABAN")
    check("Ashcraft", "A261", "AXKRFT", "ASCRAFT")
    check("Tymczak", "T522", "TMKSK", "TYNCSAC")
    check("Pfister", "P236", "PFSTR", "FASTAR")
    check("Honeyman", "H555", "HNMN", "HANAYNAN")
    check("Lee", "L000", "L", "LY")
    check("Washington", "W252", "WXNKTN", "WASANGTAN")
    check("Jackson", "J250", "JKSN", "JACSAN")
    check("Knight", "K523", "NT", "NAGT")
    check("Mitchell", "M324", "MXL", "MATCAL")
    check("Bryan", "B650", "BRYN", "BRYAN")
    check("Schmidt", "S530", "SXMTT", "SNAD")
    check("Thompson", "T512", "0MPSN", "TANPSAN")
    check("Phillips", "P412", "FLPS", "FALAP")
    check("MacDonald", "M235", "MKTNLT", "MCDANALD")
    check("Wright", "W623", "RT", "WRAGT")
    check("Xavier", "X160", "SFR", "XAVAR")
    check("Zach", "Z200", "SX", "ZAC")
    check("Knuth", "K530", "N0", "NAT")
    check("Thumb", "T510", "0M", "TANB")
    check("Science", "S520", "SSNS", "SCANC")
    check("Bough", "B200", "BKH", "BAG")
    check("Christopher", "C623", "XRSTFR", "CRASTAFAR")
    check("Aardvark", "A631", "RTFRK", "ARDVARC")
    check("Ghost", "G230", "KHST", "GAST")
    check("Judge", "J320", "JJ", "JADG")
    check("Otto", "O300", "OT", "OT")
    check("Cough", "C200", "KKH", "CAG")
    check("Wheat", "W300", "WT", "WAT")
    check("Shoe", "S000", "X", "S")
    check("Ciao", "C000", "X", "C")
    check("Gnome", "G550", "NM", "GNAN")
    check("Sign", "S250", "S", "SAGN")
    check("Highway", "H200", "HW", "HAGWY")
    check("Machine", "M250", "MXN", "MCAN")
    check("Whistle", "W234", "WSTL", "WASTL")
    check("Pneumonia", "P555", "NMN", "PNANAN")
    check("Aegis", "A220", "EJS", "AG")
    check("Accept", "A213", "AKSPT", "ACAPT")
    check("Bridget", "B632", "BRJT", "BRADGAT")
    check("Xerxes", "X622", "SRKSS", "XARX")
    check("Xiomara", "X560", "XMR", "XANAR")
    check("Nation", "N350", "NXN", "NATAN")
    check("Catch", "C320", "KX", "CATC")
    check("Stewart", "S363", "STWRT", "STAEAD")
    check("Richardson", "R263", "RXRTSN", "RACARDSAN")
    check("Hughes", "H220", "HKHS", "HAG")
    check("Schwartz", "S632", "SXWRTS", "SWART")
    check("Ewing", "E520", "EWNK", "EANG")
    check("Kneel", "K540", "NL", "NAL")
    check("Dewey", "D000", "TW", "DAEY")
    check("Powers", "P620", "PWRS", "PAOAR")
    check("robert", "R163", "RBRT", "RABAD")

    // 4: the empty name and short storage.
    var out: [8]u8 = zero
    var scratch: [8]u8 = zero
    let (empty, empty_error) = phonetic.soundex("", out[..])
    if empty_error != ok || empty.len != 0usize { os.exit(4i32) }
    let (empty_n, empty_n_error) = phonetic.nysiis("", out[..], scratch[..])
    if empty_n_error != ok || empty_n.len != 0usize { os.exit(4i32) }
    let (empty_m, empty_m_error) = phonetic.metaphone("", out[..])
    if empty_m_error != ok || empty_m.len != 0usize { os.exit(4i32) }
    let (_, s_room) = phonetic.soundex("Robert", out[..3usize])
    if s_room != phonetic.TooSmall { os.exit(4i32) }
    let (_, m_room) = phonetic.metaphone("Robert", out[..6usize])
    if m_room != phonetic.TooSmall { os.exit(4i32) }
    let (_, n_room) = phonetic.nysiis("Robert", out[..], scratch[..6usize])
    if n_room != phonetic.TooSmall { os.exit(4i32) }

    try io.print("text phonetic ok\n")
    ret ok
}
