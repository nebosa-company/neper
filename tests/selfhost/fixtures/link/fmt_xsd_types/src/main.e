// e.fmt.xsd.valid against libxml2's schema validator through lxml (L081, D2271 part 1; scripts/
// xsd_datatype_reference.py writes this file): for each of the 39 built-in types, boundary and seeded-
// mutation candidates (padding, inserted, deleted and replaced characters, non-ASCII name characters)
// with the verdict libxml2 gives for `<e>text</e>` under `<xs:element name="e" type="xs:T"/>`. A mismatch
// prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.fmt.xsd

fn report(table: str, index: usize) -> err {
    var digits: [20]u8 = zero
    var count = 0usize
    var n = index
    if n == 0usize {
        digits[0usize] = 0u8
        count = 1usize
    }
    while n > 0usize {
        digits[count] = u8(n % 10usize)
        n /= 10usize
        count += 1usize
    }
    let glyphs = "0123456789"
    try io.print("xsd mismatch in ")
    try io.print(table)
    try io.print(" at ")
    var i = count
    while i > 0usize {
        i -= 1usize
        try io.print(glyphs[usize(digits[i])..usize(digits[i]) + 1usize])
    }
    try io.print("\n")
    os.exit(1)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let t_string = [130]str{ "", "a", " a ", "a\tb", "a\nb", "x y", "日本語", "é", "😀", "b y", "\n", " a\n", "\t", "  a ", "\na\t ", "\n y", " \n", " 日本語", " a", " ", " 😀b", "\n\tx y \n", "b\ty\n", "\n\n", "\n\t\ta\nb\n", "\na\t\n", "語", " \n\n \n\n", "b", "本語", "é\t", "\tx y\n", "\nb", "\t日本語b", " \n ", " \nb", "  ", "a ", " \t\t ", "\t\t\n\n", " a\tba", "ab\nb", " xby", "xay", "ab", "😀a", "a\t", "\n a\t  ", "ba ", "a\n b", "bab ", "\t ", "\ta ", "日\n本語", "\n  ", "\téa ", "a\t\tb", "b日本a語", "  \n", "  日本語 ", "\tbx y", "\ta\t", " \t", "éb", " a\n\nb ", "\na", "ba\nb", "\na\n", "\t\n", "\n ", " \n  ", "\n\tb", "a \nb", "\n\t ", "a\nb\t\n", " a \t", " a\nb", "\naa", "\na\nb", "\t  ", "a\n\tb", "\nb ", "\ta", "   a a ", "日b本b\n", "\n a ", "\n日語a", "  a \n", " \t \n\n", "\t\t  y", " 日本語a\t\n", "\ta\n\n", "\té", "\né\n", "a\n", "\n \n", " a\tb\n", " b", " b\t ", " x y\n", " 😀", "日本a", " \ta \n ", "ba😀 ", " ab\n ", " xay", "aba", " aa\tb\n", " b \t", " a\n b ", "\n\t\n  ", "日\t\t語", "\nx y\n", "\t a ", "\tx  y ", " \nb ", "\ta\n\tb ", "\na\t\n ", "a a ", "\n a \n", "aa\t\t", " \ta\tb", "x y\n", "ba", "\né ", "\t\t y\n", "  a\nb", "  b ", "a\na \n", " éb " }
    let w_string = [130]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    var i_string = 0usize
    while i_string < 130 {
        if xsd.valid(.String, t_string[i_string]) != w_string[i_string] { try report("string", i_string) }
        i_string += 1usize
    }
    let t_normalizedString = [130]str{ "", "a", " a ", "a\tb", "a\nb", "x y", "日本語", "é", "😀", " ", " a\na", "x  ", "x y ", "éa", "a\n", "\t ", "\n本語", "\t\na\t\nb \n", "日本語 b", "\n", "a\tbb", " \n", "\t\t ", "日b", "日本 \t", "\na\t", "\n\n\t\n", "b\n", "\n  ", " 日本語\n", "\tb本語", "日\n\t語", "é ", "a\n\ta", "xa y", "\t日本語 ", "  ", "a\t", "\ta \n", "\nx   ", "\tb語", "a ", "\ta\n\n", "a\n  y", "\té \n", "\t\n", "xy", "\t😀b\t", "    ", " bxay ", "ab", "\n ", "x \tb", "   ", "\nb", "\t", "日本\t語", "\ta\tb ", " xy ", "b y", "日b本語", "\ta ", "\na\tb\n ", "日本", "\ta😀\n", "本語", "\tb\nb ", "\t\t  ", "\t本語", "  \n\nb", "\ta \nb", "\na\n ", "\n\n ", "aa\nb", "b a", " ba ", " \n ", "   \n", "\tx by\n\t", "b", " \t日本語 \n", "\ta\n", "\t😀b\n", "\t\nb", "\n\n", "\n😀\n", "\n \n a \n", " \tb", " \nb", "\ta", " a", "\n \n", " \ta\n ", "\tab", "  a\t ", "\nab ", "\naa ", "a\n\n", "\t\ta\t", "x y\n", "   y\n", "\taé ", "\ta\t\n", "bb", "abb", " \n a \n", "  aa ", "\n a ", "a\n\tab", "  \n", " b\n", "x b", " \nb ", "\na\n", "\na\tab\n", "\n a  ", "\tx y\n", "\ta\tb b ", "\nb a\nb", "\nb\t", "\tx y", " a\ta\n", " \t\ta\nb\n", " \t", "\t 日本 語\n\n", "\n y", "\ta\nb ", "a\na", "\n\ta\tb  ", "\tx \ny " }
    let w_normalizedString = [130]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    var i_normalizedString = 0usize
    while i_normalizedString < 130 {
        if xsd.valid(.NormalizedString, t_normalizedString[i_normalizedString]) != w_normalizedString[i_normalizedString] { try report("normalizedString", i_normalizedString) }
        i_normalizedString += 1usize
    }
    let t_token = [130]str{ "", "a", " a ", "a\tb", "a\nb", "x y", "日本語", "é", "😀", " aa", "a ", "\t\nx y\n", "a\n", "\n本語", "\t\né \n", " \nb", "\n ", " \n", " \tb", "x ", " a\nb", " \ta ", "\té", " \na\nb", "\na\n ", "\ta ", "日b語", "a\t\t", "b", "\na\t", "  \na ", "\nab ", "a\nb ", "\n\n", "\t\t😀\n", "\t  \n", "xy", "\tb", " \t日本語a", "\ta\tb ", "\ta", "\n", "日\n本語", "\né\n", "\t\na\t\n\n", "xbb", "\na本b", "bab", " ", " \n\n", "\t\ta\nb\n", "\t\ta  ", " by\n", "\n  ", "\n\n\n", "\ta\n", "\nab", "\na\nb ", " \t", "\n\na\nb ", " \tab\n", " 😀\n", "\tb ", "x\n", "\nbb\n", "\ta\n\n ", "\n\t\nb", "\na ", "\t\n \ta ", "a\ta", "ab", "日本語\n", "a\n\t\t", "\t\t   ", "\t\n", "\t\tb ", "x", " a\nb\n", "\t a語\n", "\n a ", "\t", "\n\na  ", "\t\n\t", "  \n", "\tab  ", "é\n", "  \t", "\na\n \n", "aa \t", "\n ab\n ", " \t😀b\n", "  \n ", "  b", "a\n ", "\tba ", "a\t", "\nb\n", " x y\n\n", "  é", "\n\té\nb", "x a", "ab\tb", "x\ny", "\n本語\t", "ba b", "\nbb", "\n\nx y\n\n", "a\t ", " \t a\t \n", "a  ", "\n\na\t\n ", "\n\n😀", "\n\né", " éb", "\n\t\t本語\n", "\ty", "\t a\t ", "日\n\t語", "a\tb\t", " a\tb\n", " 😀", "aa\ta", "\n a\tb ", "\ta b", " \na", " a\tb", "\nx a ", "\tx y", "aé", "  " }
    let w_token = [130]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    var i_token = 0usize
    while i_token < 130 {
        if xsd.valid(.Token, t_token[i_token]) != w_token[i_token] { try report("token", i_token) }
        i_token += 1usize
    }
    let t_language = [130]str{ "en", "en-US", "de-CH-1996", "i-klingon", "x-private", "abcdefgh", "abcdefghi", "en-", "-en", "en--US", "1a", "a1", "en-123456789", "en-12345678", "abcd9fgh", " \n9a1", "1", " -private ", " i-klingon\n", "abcdefbh", "enA", "en11", " \nen-US \n", "\t1n-12345678\n", "ab cdefghi", "abbcaefgA", "", "bcdefgh1", "\n1a\n ", " de-C-1996\n", "e9-A-US", " n ", "\nx-private\n", " en--US", "en---US", "9", " en", " en-129345678 ", " be-CH-1996", "\ta ", "\t1a\n", "91aB\n", "ben-234568", "en-S", "en-1234A5-78", "n-", "\nea-1234567", "1-Bn", "A1", "en112356789", "aB-bcefgh", " a ", "\tn ", "bcdefghi", "i-klinn", "\nde-CH-1996 1", " ab1defghi", "\t i-klingon- ", "  en--U ", "\n1  ", "a1cdefghi", " d-e-CH-199A ", "1A", "-A", "\nbBcdefghi", "\nen-1345678 ", "\t x-private\n ", "en-1345679B", "\tabcd efghi", "de-CH-1  6", "\tabcdefghi ", "A", "9n-", "1n-USA", "\n1a\n", "-B", "en--US ", " A n", "ade-CH-1996", "i--klin-obn", "aenA", "en-1356789", "en--123467A9", "\nx-private ", "n12345678", "\ni-klingon ", "  A1\n", "-e-CHb19b96", "-e9", "enb-aUS ", "ean-USB", "\t-B\n", "ean", "en-1234568", "-en-123A456789 ", "\te9a-US\n", "abceghi", "e-n-US", "\n-en\n", "e-n-a", "\t\nen-\n\n", "\na\n", "Aen-", "en--12A56789", "\tBa\n", "-bnA-", "\ten12345678\n", "aB", "A 1n-", "-1en ", "\t\ne9n-", "-b1", "\ten---9S ", "\nena ", "abcdefg1h", "en-1S", "abcAdef9gh", "n", "en-23456789", "abcd-fgh", "Bi-klinon", "enbUS", "en-134-6789", "ai-klingon\n", " abcdefgh", "d-CH-B1996", "en-1234567b8", "e9n-123456789", "de-CH-19a96", "i-kingon" }
    let w_language = [130]bool{ true, true, true, true, true, true, false, false, false, false, false, false, false, true, false, false, false, false, true, true, true, false, true, false, false, false, false, false, false, true, false, true, true, false, false, false, true, false, true, true, false, false, true, true, true, false, true, false, false, false, true, true, true, true, true, false, false, false, false, false, false, true, false, false, false, true, true, true, false, false, false, true, false, false, false, false, false, false, true, false, true, true, false, true, false, true, false, false, false, true, true, false, true, true, false, false, true, true, false, true, false, true, false, false, true, false, false, true, false, false, false, false, false, true, false, true, false, true, true, true, true, true, true, true, true, true, false, false, true, true }
    var i_language = 0usize
    while i_language < 130 {
        if xsd.valid(.Language, t_language[i_language]) != w_language[i_language] { try report("language", i_language) }
        i_language += 1usize
    }
    let t_Name = [117]str{ "a", ":a", "a:b", "_x", "a-b", "a.b", "1a", "-a", ".a", "a b", "é", "é1", "日本", "a·", "·a", "à", "̀a", ":", "a:", "::", "a×", "a÷", ": ×", "", "日a", "- ", "a.", "\t_x\n", "\ta", "\ta . ", "\tà̀", " é", "\n日é", "\ta:b\n", "\n1", " a::", ":b", "a._.b·", "\na日 ", " ", "\né1", "\tà\n", "\n1a", "\ta\n", "ab", "1", "::\n", "÷", "\n_x ", "a÷日", "a-", "\n:b ", "_a:", "\na-b_\n", "-̀", "̀日", "\té1", ".", "1é", "\n\n", "  ", " ̀a ", "  : -", "aa", "\t", "\t̀\n", "·", "-", " é1\n", " \té11\n", " ..a", "\né", "\na _x  ", " a", "\t .", ":-b", ":ab-b", "\n_x", "̀", "a ", "日a×", "a本", "éa", " -a ", "\ta÷ \n", " \t_a\n", "aé1\n", "· ", "\n.̀", "\ta ", " é_\n", "·:_", "é ", "\t:", ".·", "\na·.b\n", "\n: :", "a日é", "\n\tba-b\n ", "a--÷", "本", "\t1a ·", " a:\n", "\n\ta:\n\n", "\n", "日\t", "b日本", " .-", "a1", ":1", "\n -a ", "\n\n:\n\n", " ·", "\ta \n", "a÷·", ". :", "1b." }
    let w_Name = [117]bool{ true, true, true, true, true, true, false, false, false, false, true, true, true, true, false, true, false, true, true, true, false, false, false, false, true, false, true, true, true, false, true, true, true, true, false, true, true, true, true, false, true, true, false, true, true, false, true, false, true, false, true, true, true, true, false, false, true, false, false, false, false, false, false, true, false, false, false, false, true, true, false, true, false, true, false, true, true, true, false, true, false, true, true, false, false, true, true, false, false, true, true, false, true, true, false, true, false, true, true, false, true, false, true, true, false, true, true, false, true, true, false, true, false, true, false, false, false }
    var i_Name = 0usize
    while i_Name < 117 {
        if xsd.valid(.Name, t_Name[i_Name]) != w_Name[i_Name] { try report("Name", i_Name) }
        i_Name += 1usize
    }
    let t_NCName = [115]str{ "a", ":a", "a:b", "_x", "a-b", "a.b", "1a", "-a", ".a", "a b", "é", "é1", "日本", "a·", "·a", "à", "̀a", ":", "a:", "::", "a×", "a÷", "̀", ".a ", "\ta", "\na\n", ".:b", " 1a-.b ", " .bb", "\t:·\n", "ab", "ab-", "éà", "\n日本\n", "\n:  ", "\t\n", ".:", "\tx̀ ", "\n", ":·", " ·a\n:", "  ", "\n::", "ab ", ":×", ":a.", "b:", "·-a", "\t", "", ".", "._x", ".ab ", "x", " ̀a\n:", "a-bé", "\n\t·a ", " é\n", "1", "\n 日·a ", "·̀", "b×", "\n.\n", " -\n", "\n-1a\n", "\n1b", "\t·a", "\n b ", "ba", " a b\n", "·:a", "-", "a_b", "\n·", "\né\n", " à 1", "\n -a ", " 1a", " \t \n", "\té\n", "·é1", "\t -à", "\na.b\n", "-a b ", "\tax", "b1", ":é", " ", "  ̀:\n", "日.-", "_ :a", ":1:a", "\nb ", "._ ", "\ǹa\n", "\t ", "à÷", "日", "\n  a\n\n ", "a日.1", " .1a", " \na_ ", " ·a", "é̀", "-é ", "\na日\n", "\n·--", "日-", " -", " éa", "_̀", "éb", ". ", "1·a ", ".·" }
    let w_NCName = [115]bool{ true, false, false, true, true, true, false, false, false, false, true, true, true, true, false, true, false, false, false, false, false, false, false, false, true, true, false, false, false, false, true, true, true, true, false, false, false, true, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, true, false, true, false, true, false, true, false, false, false, false, false, false, false, true, true, false, false, false, true, false, true, false, false, false, false, true, false, false, true, false, true, true, false, false, false, true, false, false, true, false, false, false, false, true, true, true, false, true, false, true, false, true, false, true, false, true, true, true, false, false, false }
    var i_NCName = 0usize
    while i_NCName < 115 {
        if xsd.valid(.NCName, t_NCName[i_NCName]) != w_NCName[i_NCName] { try report("NCName", i_NCName) }
        i_NCName += 1usize
    }
    let t_NMTOKEN = [114]str{ "a", ":a", "a:b", "_x", "a-b", "a.b", "1a", "-a", ".a", "a b", "é", "é1", "日本", "a·", "·a", "à", "̀a", ":", "a:", "::", "a×", "a÷", " b..b", "..a", " a·", "\t a·b ", " :", "\ta  ", "\n_x ", "", "\t:\n", "\t\ta\n", " 日本", ":日:1", " :: ", "a·:  b", "  ·\n", "\n:: ", "·1a", " ._a", "  :_", " \n-a\n ", "-a:", ":日̀a", "a:_\n", "×é", "\t.é\n", "x1", "1", "\na·\n", "-\ta×\n\n", "\t_", "-\n日本", "\t̀", "·", "a.", "\na.日", " é1 ", " ̀\n", "a-a", "1aé", "\n:日\n", ":·", "b ·", ".日a", " a", "\t ", " a:", "日:a本", "1a1", "\n.:b", "\n·\n-", "a日日", ":1a", "ab b", "·_", "\n", "̀xé-", "\t-日本\n", "\na\n", " _: :", " 1", ".-b日", "\t1é", "a日b", "_à", " a·\n", "\n\na÷", "\ta·", " éé", " aé .", "\t\n", "日:本", " à ", "\n日本 ", "a÷a", "_ ·", " ·-ba ", "-̀a", "\t  ·a \n", "bb ", "b", "a.a", "a1.", "\tab", "\na_.b", ".a b", ":̀aa日", ".", " ::\n", " 日本 ", "\tx\n", ":.", "- 1b" }
    let w_NMTOKEN = [114]bool{ true, true, true, true, true, true, true, true, true, false, true, true, true, true, true, true, true, true, true, true, false, false, true, true, true, true, true, true, true, false, true, true, true, true, true, false, true, true, true, true, true, true, true, true, true, false, true, true, true, true, false, true, false, true, true, true, true, true, true, true, true, true, true, false, true, true, false, true, true, true, true, false, true, true, false, true, false, true, true, true, false, true, true, true, true, true, true, false, true, true, false, false, true, true, true, false, false, true, true, true, true, true, true, true, true, true, false, true, true, true, true, true, true, false }
    var i_NMTOKEN = 0usize
    while i_NMTOKEN < 114 {
        if xsd.valid(.NMToken, t_NMTOKEN[i_NMTOKEN]) != w_NMTOKEN[i_NMTOKEN] { try report("NMTOKEN", i_NMTOKEN) }
        i_NMTOKEN += 1usize
    }
    let t_ID = [115]str{ "a", ":a", "a:b", "_x", "a-b", "a.b", "1a", "-a", ".a", "a b", "é", "é1", "日本", "a·", "·a", "à", "̀a", ":", "a:", "::", "a×", "a÷", "\t-̀ba ", "a··b", "", " \n", "b-a", "\ta", "\n", "\n日本", "a b1", " .-a\n", ".b", "\ta-b ", "-", " 1a\n日", "a.a", "ba", "·.b", " ·", "_a:", " :\n", "\ta·", "-1", "·ba", "̀_", "̀", " \t\n:a\n ", "日", "a.b ", "a:\n", "b", " a÷ ", "\t:·", "\t a1b\n ", ".:a", "\n.a·", "日̀", " \n- b \n", "\ta ", "\tb\n", "a::\n", "\tax\n", "\n··", " .a ", "aba", "\t-a ", "::1", " ̀a b", " ._ ", " aé\n", " ··a", "\t", " \na:éb\n", "\n÷", "\tb:a\n", "\ta b ", " :é", "a日", "a-", ":-a", "\t\n", "_", "\n:日 ", " a-b ", "\t1a", "a·é", "-a×", " a \n", "a×a", "\né\n", "---", "aé", "̀̀a", "1 aa", " \t.a \n", "\tà ", "\ǹb", "1 ", "\t\n_x  ", "\na: ", "日本 ", "1éb", ":̀", "a.é", "x", ".", "\t·1a\n", " à ", "\na×\n", "_::", "\n_:\n", "_:b", "ab", "\nx:\n" }
    let w_ID = [115]bool{ true, false, false, true, true, true, false, false, false, false, true, true, true, true, false, true, false, false, false, false, false, false, false, true, false, false, true, true, false, true, false, false, false, true, false, false, true, true, false, false, false, false, true, false, false, false, false, false, true, true, false, true, false, false, true, false, false, true, false, true, true, false, true, false, false, true, false, false, false, false, true, false, false, false, false, false, false, false, true, true, false, false, true, false, true, false, true, false, true, false, true, false, true, false, false, false, true, false, false, true, false, true, false, false, true, true, false, false, true, false, false, false, false, true, false }
    var i_ID = 0usize
    while i_ID < 115 {
        if xsd.valid(.ID, t_ID[i_ID]) != w_ID[i_ID] { try report("ID", i_ID) }
        i_ID += 1usize
    }
    let t_IDREF = [113]str{ "a", ":a", "a:b", "_x", "a-b", "a.b", "1a", "-a", ".a", "a b", "é", "é1", "日本", "a·", "·a", "à", "̀a", ":", "a:", "::", "a×", "a÷", "̀aa", "·", "\t   ", "\n日本", " a-b_- ", "_", "·.", " ", "", "-", " 日本-", "_a·", ":_", "a÷b", "\t·1", ".·.b", "a a", "a×b", "a.:", "日:", "_ ", "\ta日\n", "̀", "a÷日", " 日 ", "a1:b", "\n:: ", "\n:", "-:", ".-b", " ·a ", "\t\n", " :", "a ", "1 ", "\t\t\n-a \n", "·1", "̀àa日", "- ", "̀·", "\t·a\n", " a日_\n", "__", "b", "\t.:b ", " -", "\na\n", "::a:", "̀1", "̀a.b", "_ ̀", ".\ta×", "日", "1", ".", "\t a\n", "_1 ", "\t:日 ", "\t··", "\n\t\n\n", "a·b", "é.1", " a. ", "\n_", "̀· ", "._-", " 日a", "a.日b̀", " ·.b\n", ":_a", "̀-", "\n\n", "ab", "àb1", "a. ", "\ta:\n", "a日·", "a· ", " \t\t日本  ", "b:", "本", " \n", "a×1a", "\n\ǹ̀a  ", "1.a", " a:", "a·a", "a:.b", "a·÷", "é÷", ":1a" }
    let w_IDREF = [113]bool{ true, false, false, true, true, true, false, false, false, false, true, true, true, true, false, true, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, true, true, false, false, false, false, false, false, false, false, true, true, false, false, true, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, true, true, true, false, false, true, false, false, false, false, false, true, false, false, true, true, false, false, false, true, true, true, true, false, false, true, true, false, false, false, false, true, true, true, false, true, true, true, false, true, false, false, false, false, false, true, false, false, false, false }
    var i_IDREF = 0usize
    while i_IDREF < 113 {
        if xsd.valid(.IDREF, t_IDREF[i_IDREF]) != w_IDREF[i_IDREF] { try report("IDREF", i_IDREF) }
        i_IDREF += 1usize
    }
    let t_QName = [89]str{ "a", "_x", "a-b", "a.b", "1a", "-a", ".a", "a b", "é", "é1", "日本", "a·", "·a", "à", "̀a", "a×", "a÷", "xml:lang", "\n a×", "_", "", "\ta.b ", " ", ".", "\n\t.a \n", "xml:ang", "\n.a", "a -", "1日", "a-", "-à", "\t à-", "abbc", "b·", "é.1 ", "\n 日a  ", "-éa b", "éé1", "1", "é_", "\né.·", "\tb1\n", "\ta.\n", "\nxb ", " \t̀a ", "x1", "\t日本 ", "..a\n", "·÷  ", "\t a\n", "  ", " -·", "̀-a", "-a- ", "\nb", "a.", "\t a.b\n", "1-", " b", " 1 ", "\t\na· ", "·1 b", "\t1a  ", "\ta×", "aa", "\txml:lang ", "-", "-a1·\n", "ba b", " \na\n", " a ", "xab", "·", "_a÷", "̀", "x-a", "\ta", "é̀", "\txml:lang_ ", "a日", "._ 1b", " ̀", "\n_x-", "xlélang", "\n1x\n", " aa\n", "\t-a\n", "\t1a ", " -" }
    let w_QName = [89]bool{ true, true, true, true, false, false, false, false, true, true, true, true, false, true, false, false, false, true, false, true, false, true, false, false, false, true, false, false, false, true, false, true, true, true, true, true, false, true, false, true, true, true, true, true, false, true, true, false, false, true, false, false, false, false, true, true, true, false, true, false, true, false, false, false, true, true, false, false, false, true, true, true, false, false, false, true, true, true, true, true, false, false, true, true, false, true, false, false, false }
    var i_QName = 0usize
    while i_QName < 89 {
        if xsd.valid(.QName, t_QName[i_QName]) != w_QName[i_QName] { try report("QName", i_QName) }
        i_QName += 1usize
    }
    let t_boolean = [130]str{ "true", "false", "1", "0", "TRUE", "True", "yes", "", "2", "-1", " true ", "true false", "01", "tru", "\ttrue false\n", "yts1", "\ntrue falste\n", "2e", " tue false", "faulse", "ru", "RE", "e s", "r\t01", "\t true ", " 01\n", "1r1r", "  ", "farse", " trrue ", "\t -1\n", "true ase", "1eue", "rut0", "tre s", " TRUu", " reurue ", "02", "TUeE", "\n 0 ", "\t\ttrus false\n", " 1", "\ttre", "\t0 ", "rys", "\tru1", "u", "t\t ", "\nuTRUE\n", "\n011e ", "\n\n2 \n", "uRUE", "rrrue", " -1 ", "tTReUE", "tr0ue", "0r0u1", "etre false", "\nr", "\ne", "\t1", "\ne\n", " true false ", "t1s", "trseu", " 0ruet ", "\tfatls ", "0t1", " 0t01", "t 10 ", " \n", " e s", "\ttrue false ", "\n\t ", "ye", "1ru", "1t", "tu", "etru", "true fa1lse", " Truu ", "\t\nyes\n ", "Ts", "\nturue fal e ", "\n2 ", " ", "\t0\n", "\n\nfase\n ", " u1\n\n", "\tyes", "0 ", "\nu\n", " yes\n", "\nfae\n", "\n", "yrr s", "ye ", "\tTR UE ", "  u", "  true ", "  trues ", "1 ", "\n0 ", " 1\n", "trueftl e", "tu false", "true 0alsse", "tTRU", "e1", "\t \n", " -1", "\n true  ", "\nru", " \n\n ", "e", "0 1", "\n01", " teu", "t", "\t01 ", "\n1", "\tfalre ", "\n 1\n", "\nTRUE\n", "0tr", " rte ", "\t\nfasse  ", "\ttrure fase ", "r01", "sy01" }
    let w_boolean = [130]bool{ true, true, true, true, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, true, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, true, false, false, false, false, false, false, false, false, true, false, true, true, true, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, true, false, true, false, false, false, false, false, false, false }
    var i_boolean = 0usize
    while i_boolean < 130 {
        if xsd.valid(.Boolean, t_boolean[i_boolean]) != w_boolean[i_boolean] { try report("boolean", i_boolean) }
        i_boolean += 1usize
    }
    let t_decimal = [90]str{ "0", "-0", "+0", "1.", ".1", "1.5", "-1.5", "+1.5", "1e5", "1.5.2", "00012", "1,5", "١٢", "1.e", "9001", "e0002E12", "\t3\n", "9a", "Na3NF", "\t+8", "\ta+0\n", "I\t0012", "1N.", "\t69e5", " 1.5.2 ", "81.", "١", "-1.E5", "\n61,5\n", "1", "a-12", "..10", "I1.5", " ١N", "١92", "\t3", " +0", " 1.52 ", "e5", "+1.5 ", "7", "٢.", " +a5", "\t-1.7 ", "9٢5", "+1.", "9N١٢", "\n .1\n\n", "\n00-012 ", "2", "+1.65", "Ne5", " ٢\n", "\t1.+5.N", "3٢", "+1.E", "+2", "١٢8", "-1.56", "0-", "36", "IN5", "0022", "E0", "04", "-1+5", "\t8.", "  9", " 1.7", "1a.", "1I.5.2", "\n-0 ", ".5", "21.5", "151.2", "00082", "\t١٢F7", "+15.3", "90", "e5-", "80", "\n91.5.2\n", " 1.82", "N١\n", "0012", "1,", " 48-\n", "9\n \n ", " 0 \n", "1.5.+2" }
    let w_decimal = [90]bool{ true, true, true, true, true, true, true, true, false, false, true, false, false, false, true, false, true, false, false, true, false, false, false, false, false, true, false, false, false, true, false, false, false, false, false, true, true, true, false, true, true, false, false, true, false, true, false, true, false, true, true, false, false, false, false, false, true, false, true, false, true, false, true, false, true, false, true, true, true, false, false, true, true, true, true, true, false, true, true, false, true, false, true, false, true, false, false, true, true, false }
    var i_decimal = 0usize
    while i_decimal < 90 {
        if xsd.valid(.Decimal, t_decimal[i_decimal]) != w_decimal[i_decimal] { try report("decimal", i_decimal) }
        i_decimal += 1usize
    }
    let t_integer = [123]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "1e3", "--1", "+-1", "1 2", "07", "3-0", "1e23", "-- ", "F0+", " \n0\n\na", " ", " 13 \n", "\n1e30\n", "\t+\n", "\n  ", "006", "a", " -", "23", "\n\t1e0\n", "\t6E ", " 9\n", "0e1", "a1\n", "8-1", " +e5 ", "a01", "\t6 ", "e", "\t137", "\t 1e3 \n", "097", "+10", "\tE0", "1e", "1.0a", "\n-0 ", ".", "\n--1", "N-", "\t10 ", "+2-1", "-F1F", "F0", "0a", "\t--1\n", "0E6", "6-0-", "1 a2", "3.9", "F+77", "\n-7 ", "a --1 ", "+0.", " +0 ", "e3", "N -61\n", "0+01", "\t+", "05", "\t\t--1\n\n", "-20a", " - ", "1--1", ".0", "\na", "6a", "\t00 7\n", "\n", "7F3", "1 0", "-N9", "608 ", "\n007 ", "\t0 ", "\t--0\n", "\n10 ", " e- \n", " F07\n", "-+7", "a--6", "2 +0\na", "-27-", "E", "1-", "1", "\t", "71", "13", " \n.0\n", " \n", "\n\t-1\n\n", "1NEe3", "\t-", "\n057", " -6", "0N07", " N", " \n+1\n", " 3-007", "8", "4", "\n+-1", "..0", "\t1.63 ", " 0\n+", "172", " +-", "-1", "e\n-", " 0N7 ", " 307", "  I", "\n--1 0" }
    let w_integer = [123]bool{ true, true, true, false, false, false, false, true, true, false, false, false, false, true, false, false, false, false, false, false, true, false, false, false, true, false, false, true, false, false, true, false, false, false, false, false, true, false, true, false, true, true, false, false, false, true, false, false, false, true, false, false, false, false, false, false, false, false, false, false, true, false, false, true, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, true, false, false, false, false, false, false, false, false, true, false, true, true, false, false, true, false, false, true, true, false, false, true, false, true, true, false, false, false, false, true, false, true, false, false, true, false, false }
    var i_integer = 0usize
    while i_integer < 123 {
        if xsd.valid(.Integer, t_integer[i_integer]) != w_integer[i_integer] { try report("integer", i_integer) }
        i_integer += 1usize
    }
    let t_nonPositiveInteger = [101]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "1e3", "--1", "+-1", "1 2", "-1", "1", "+1", "-00", "+00", "00", "a+", "\n00\n", "\t", "N01", "  ", "\n07\n", "\t\n+-1\n", "\nN", "\n007 ", "\t+ ", "\ta-F0", "9-", "-E", "+\t-N007\n", " + ", "F1", "F", "51", " 1 ", "\n07", "4+", "a-1\n", "51+", " +1 ", "\t1-8 ", " I\n", "1. 00", "\ne3", "\n+6", "\n ", "N0", "12", "4", "E\n+", "\t\n", "1.06", "\t90\n", "4+0", "6", "9F-0", "1 67-2", "+-52", " -07E", "\t+61", "-107", " 004", "N1", " \n", "-6 -", "+ ", "900", "\n-3-1 ", " --1\n", "1 8", "\t +0 ", "\n00e1 ", "1 5", "+-", "0IF", "61+ 2", "1e\n", "1.a", " -- ", "+04", "1a", "-09", "\n", "1e  ", " 00", "-807", " +30", " 1.0+", "\n-007\n", "\n-00F", " 2", " -00", "7", "a 2", "I", "\n00 ", "1 ", "\t-.\n" }
    let w_nonPositiveInteger = [101]bool{ true, true, true, false, false, false, false, false, true, false, false, false, false, true, false, false, true, true, true, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, true, false, false, true, true, false, false, true, false, false, true, false, false, false, true, false, false }
    var i_nonPositiveInteger = 0usize
    while i_nonPositiveInteger < 101 {
        if xsd.valid(.NonPositiveInteger, t_nonPositiveInteger[i_nonPositiveInteger]) != w_nonPositiveInteger[i_nonPositiveInteger] { try report("nonPositiveInteger", i_nonPositiveInteger) }
        i_nonPositiveInteger += 1usize
    }
    let t_negativeInteger = [115]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "1e3", "--1", "+-1", "1 2", "-1", "1", "+1", "-00", "+00", "00", "\n\t0\n", "+9-1", ".0", " 1.", " ", "\n\n1 72  ", "8-00 ", "\t1 2\n", "\n9\n", "-6-F", "8+0", "+4", "\t3-1", "14-0", "--", " 1N2 ", "9+1", "1.e0", "+6+", " 0 ", "3", "3\n1e3", "\t+ ", " -a0 ", "41 +2", "02", "\n0\n", "\n\n", "91e3", "a", "E0", "\t\t.00 \n", "+39", "Ee", "70", "-0107", " 1 2 ", "  -002\n\n", "\t+", "16E2", "1. 2", "\t\n-", " .0 ", "\n1a.7\n", "\n 8", "-38007", "1 452", "\t1\n", "\t3-00\n", "\n5 ", "  +-+ ", "+1e3", "+N-0", "\t0 ", "640", "e4", "\n017", "91.", " e83", "\t1 2", "\t\t\n1.0\n\n\n", "\t8+00 ", "I\t00I", "++ ", "N-", "-e1", "+0I", "00+", "+Ne", "\n 70 ", "-006", "050e7", "8", "1e.0", "9-81", "\t", "1E", " +0", "+390", "+-", "13", "0077", "e", "+-F4", "\n0-00\n", "\n.0 ", " -1 ", " +005", "1 2F", "-a1", "\n\n\n\n", " e1", "07", ".507", " -1", " 1e3E" }
    let w_negativeInteger = [115]bool{ false, false, false, false, false, false, false, false, true, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, true, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, true, false }
    var i_negativeInteger = 0usize
    while i_negativeInteger < 115 {
        if xsd.valid(.NegativeInteger, t_negativeInteger[i_negativeInteger]) != w_negativeInteger[i_negativeInteger] { try report("negativeInteger", i_negativeInteger) }
        i_negativeInteger += 1usize
    }
    let t_nonNegativeInteger = [107]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "1e3", "--1", "+-1", "1 2", "-1", "1", "+1", "-00", "+00", "00", "\t-4\ne", "7\t10 ", "\n\n16 2", "12.0", "  ", "\n+010\n", " \n-0 ", " N", "e.", "I+-1", "1.6", "+1e", "\n1.e", "\t1 e", "-0.07", "1 62", "\t+1 ", "\na-5", "7", " -04\n", "1N.07", "e00", "\n\t1F0\n ", "-51", "\n", "\n -1\n ", "+0+\n", " \n0 ", "+0 ", "  2\n", "\n \n", "e3", "3", "\t +000\n", "9-307", "\n\n \n", "9+1", "-45", "8007", "\n-3", "80", "\n-007\n", "+6", "0057", "\n5.", "074", " ", "  2", "1 e3.", "0.", " - ", "50", "\n13.0 ", "3.", "\n-00E", "eF1a", ".61", "I", "\n-", "\n-1", "N7", "\n07\n", "03", "-a1", "\n-00+\n", "\n-1 ", "\nF 2 ", "e", "\t41\n", "31 a7", "\n1 2\n", "8", "1.0a2", "F0", "I+", "-9+", "-007 ", "81", "-E", "\t--1\n", "9--9", "+1e3", "F+1", " \n", "6-", " 07", "\n+-1 ", "4I 27" }
    let w_nonNegativeInteger = [107]bool{ true, true, true, false, false, false, false, true, false, false, false, false, false, false, true, true, true, true, true, false, false, false, false, false, true, true, false, false, false, false, false, false, false, false, false, true, false, true, false, false, false, false, false, false, false, false, true, true, true, false, false, true, true, false, false, false, false, true, false, true, false, true, true, false, true, false, true, false, false, false, true, false, false, false, false, false, false, false, false, false, true, true, false, false, false, false, false, true, false, false, true, false, false, false, false, false, true, false, false, false, false, false, false, false, true, false, false }
    var i_nonNegativeInteger = 0usize
    while i_nonNegativeInteger < 107 {
        if xsd.valid(.NonNegativeInteger, t_nonNegativeInteger[i_nonNegativeInteger]) != w_nonNegativeInteger[i_nonNegativeInteger] { try report("nonNegativeInteger", i_nonNegativeInteger) }
        i_nonNegativeInteger += 1usize
    }
    let t_positiveInteger = [111]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "1e3", "--1", "+-1", "1 2", "-1", "1", "+1", "-00", "+00", "00", "61", "a1", "F-0", "\t+", "9+1", " 0\n", "\n\n190  ", "70F", "-7-4", "15", " 00", "I\n", "5640", " 3 1", "3e3", "\n 40 \n", "8\n", " \t-\n 6", "21", "+-1E", "8--1", "+1-", ". F", "-0N", "\n+17", "\t007 ", "I97", "9I", "e3", "5+00", "\n\t1  ", " -007", "N1 2 ", "\n1 7", "F-", "-.", "F", " ", " -4I ", "9", "1e83", "e", "\t+F2\n", "+-5", "-25", "1-", "-.0", "N", "3-1", "\n+\n", "\t411 ", "-N", "\n-5", "\t1 ", "N+0", "\t+ ", "-2307", "N\t+0", "\n-51\n", "1.", "+71", " \t9+1", "\n--91", " 4 ", "+a1", "\n-007F", ".+", "9-I0", "\t--1 ", "-09", "\n\n 2\n\n", " -00 ", "000", "F1", "13", "+4", "F4+", "-e", "\ne3", "\n1e3 ", "\n+", "\n18e3", "01+", "172", " 1 2", "5-", "+08", "1\n", "\n007 ", "\t\t+ ", "\t007\n", "e+-1" }
    let w_positiveInteger = [111]bool{ false, false, false, false, false, false, false, true, false, false, false, false, false, false, true, true, false, false, false, true, false, false, false, false, false, true, false, false, true, false, false, true, false, false, true, true, false, true, false, false, false, false, false, true, true, false, false, false, false, true, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, true, false, false, true, false, false, false, false, false, false, true, false, false, true, false, false, false, false, false, false, true, false, false, false, true, true, false, false, false, false, false, false, false, true, false, false, true, true, true, false, true, false }
    var i_positiveInteger = 0usize
    while i_positiveInteger < 111 {
        if xsd.valid(.PositiveInteger, t_positiveInteger[i_positiveInteger]) != w_positiveInteger[i_positiveInteger] { try report("positiveInteger", i_positiveInteger) }
        i_positiveInteger += 1usize
    }
    let t_long = [130]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "123456789012345678901234567890", "1e3", "--1", "+-1", "1 2", "9223372036854775807", "9223372036854775808", "-9223372036854775808", "-9223372036854775809", "09223372036854775807", "+9223372036854775807", "-0009223372036854775808", "\t \n\n", "\n923.372036854775807 ", "\t-\n", "2233720368577580a8", "\t1. 2", "+922337203684775807", " +E", "-000922337202685775848", "88e", "\n\n", "407", "\nE 4 ", " \t1 ", "  7", "\t", "-9223N720368547758008", "-9223372036854775N808", "F6", "\t+0 ", "92230372036854775808", "\n4\n", "\n\t+922332036854775807 ", "\n6-1", "a-1.", "-922a372036854775809", "-07", " 07\n", "0607", "-9233720368354775809", "\n+6\n", "   ", "a0", " -007e", "-.0e", " 2233720368514775808", " 12345678901234567890123456+7890", ".0", "\n9223372036854-75807", "-92233703685477808", "--.1", "\n1 2 ", "\n8", "\n-000922N372036854775808", "\t1", "\n\n\t+0 \n", "123456789I012345678901234567890", "2", "1.90", "F", "1e3\ne", "1.07", "--11", "005.", "0-.", "-000922337N036854775808", "\n-000922337203665477588", "300", "7 1.0", "E9223372036854775807", "922337203685477507", "\te\n", "92233-720360854775807", "-\n\n", "\n ", ". 0", "\n-09225372036854775808\n", "96.0", "++I", "922337203685477N5808", "0I", "\n-1 2\n", "\n9227372036854775807\n", " +4", "+21aE", " 0087", "037", "7e-1", "\t11I3\n", "92233720+68547758708", "12345678901234537890134567490", "-00 9223372036854775808", "\n007N", "922337203618547+5807", "F 2", "90", "\t\t9223372036854775807\n\n", "3", " + ", "\n9223372036385477508 ", "9-007 ", "e", "9223720368547F5807", "F307", "\n0 0", "00", "\t-000922337203685775808\n", "09223372036854758207", "\n00+e\n", "9223372036854a785807", " 1 2\n", "9923372036954775807", "12345678901234567890123456790", "09223372.-36854775807", "+-01", ".", "09223372036354775807", "\n+", "\n--1", "9223372036854 75807" }
    let w_long = [130]bool{ true, true, true, false, false, false, false, true, true, false, false, false, false, false, true, false, true, false, true, true, true, false, false, false, false, false, true, false, true, false, false, true, false, true, true, false, false, false, false, true, false, true, true, false, false, false, true, true, true, false, true, false, false, false, false, true, false, false, false, true, false, false, true, false, true, true, false, true, false, false, false, false, false, false, false, false, true, true, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, true, false, true, true, false, false, false, false, false, false, false, false, true, true, true, false, true, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, true, false, false, false }
    var i_long = 0usize
    while i_long < 130 {
        if xsd.valid(.Long, t_long[i_long]) != w_long[i_long] { try report("long", i_long) }
        i_long += 1usize
    }
    let t_int = [130]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "123456789012345678901234567890", "1e3", "--1", "+-1", "1 2", "2147483647", "2147483648", "-2147483648", "-2147483649", "0002147483647", "+2147483647", "\n 1.08", "90.", " 007", "\t\n21474183648  ", "-N214748368", "\t5.0 4", "+01", "\t1 ", "\t  ", "\t123456789012345678901234567890", "\t7\n", "\n", "\t294743647 ", "214743648", "12345678901234567801234567890", "\n0F", " 00", "\t002147483647 ", " -\n", "4+", "10", "\t610", "-9", "4007", "\t\n123456789012345678901234567890\n", " -2147483649", "12345I6789012345678901234567890", "2147483e48", "1", " -2147483649\n", "\t1F3456789012345678901234567890", "\ne60", "F0 ", "\n\t123456709012345678901234567890 ", "\n00", " -2147483648", "\n007\n", " \t0002147483647\n", "\n+ 2147483647 ", "\t2", "\n2147483647\n", "\t2147483648 ", "8-", "6147483647", "N-10", " \t+N", "F", "5", "00e", "1E3", "00021474836478", "\n + e", "\t-11", "--9", "N2945678902345678901234567890", "-07", "1e73", "21474836", "  + \n", "E", "\n ", "\t\n1.40\n", "\t 2147E83648 ", "21464839648", "1e+e", "\n\tI ", "\n2147483647 ", "1.+", "\te3 ", " 32147483249\n", " 1.0\n", "\t1 2 ", "123456789012e45678901834567890", "0067", " -247483649\n", "\n-2147483649 ", "1.I0\n", "\n- ", "e-0", "\t0\n", "95\t\n", "\n\n-\n", "\t6", "\t\n\n", "--a4", "81", "0I7", "-147483649", " -3\n", "\t+2147483647 ", "21487483I648", " \n0002147483647 ", "\n\t\n ", "+2107483647", "074", "1.F", "00", "\n\n-214 483648\n", "+ ", "2\t\n", " -00E ", "12345678901234567890234767890", "0\n", "\t", "217483647", "94", "\n123456789012345678901234567890 ", "-70", "122", "1234567189012345678901234567890" }
    let w_int = [130]bool{ true, true, true, false, false, false, false, true, true, false, false, false, false, false, true, false, true, false, true, true, false, false, true, false, false, false, true, true, false, false, true, false, true, true, false, false, true, true, false, false, true, true, true, true, false, false, false, false, true, false, false, false, false, false, true, true, true, true, false, true, true, false, false, false, false, false, false, true, false, false, false, false, true, false, false, true, false, true, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, true, true, false, false, false, false, true, true, false, true, false, false, true, false, true, true, true, false, true, false, true, true, false, true, false, false, true, false, false, true, false, true, true, false, true, true, false }
    var i_int = 0usize
    while i_int < 130 {
        if xsd.valid(.Int, t_int[i_int]) != w_int[i_int] { try report("int", i_int) }
        i_int += 1usize
    }
    let t_short = [130]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "123456789012345678901234567890", "1e3", "--1", "+-1", "1 2", "32767", "32768", "-32768", "-32769", "0032767", "3267", " 32768\n", "+9-1", "\t-32768\n", "\t0", "a6", "+2-N17", "I -+32769\n", "\n2768-", " \n", "-07", "\t-.\n", "-.", "-37669", "\t2", "\t1 12\n-", "\t123456789012345678901235678I90 ", "1e37", "\n32767", "-32749", "-327628", ".0", " E-\n", "06", "-0.7", "-1", "5", "07", "\n2\n", "\n+0 ", " ", "\n-", "+1", " -4", ".e3", "a+0", " \n12345679012345678901234567890 ", "\t- ", "\n.0", "+60", "3", "\t\n13 ", "1-.2", "1.", "-50", "-8", "-0-", "42", "N-1", " --1\n", ".+e1", "3I37", "-3768", "\n0", "113", "10", "00-", "\t32764-", "4", "7-F", " 0 ", "F+", " .\n", "1234567890234506789051234567890", "3268", "0-", "  ", " .017", "\n32768", "\n\n0 ", ".", "03", "3276F", "+0 ", "-327I8", "\n5-007\n", " 12345678901234567890124567890\n", "\n15\n", "1..", "a8-82768", "1204567389012345678901234567890", "123456789012345 678901234567890", "123456789012345678901234667890", "\t12345678901234578901234567890", " -- ", " 4+0 ", "12F13", "126456789012345678901234563890", "\t02032767\n", "-90", "\t+-13 ", "12345678901234F567890124567890", "007e", "\nN", " 8", "-327694", "0207", ".-32769", "7", "E0", "\t0e07", "2767", "003767", "\t-3E769", " 2767", "\n\n ", "1.0N", "3278", "\n+\n", "-32869", "81.0" }
    let w_short = [130]bool{ true, true, true, false, false, false, false, true, true, false, false, false, false, false, true, false, true, false, true, true, false, false, true, true, false, false, false, false, false, true, false, false, false, true, false, false, false, true, true, false, false, false, true, false, true, true, true, true, true, false, false, true, true, false, false, false, false, false, true, true, true, false, false, true, true, false, true, false, false, false, false, true, true, true, true, false, false, true, false, true, false, false, false, true, false, false, false, false, true, false, true, false, true, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, true, false, true, false, true, false, false, true, true, false, true, false, false, true, false, false, false }
    var i_short = 0usize
    while i_short < 130 {
        if xsd.valid(.Short, t_short[i_short]) != w_short[i_short] { try report("short", i_short) }
        i_short += 1usize
    }
    let t_byte = [130]str{ "0", "-0", "+0", "1.0", "", "+", "-", "007", "-007", "123456789012345678901234567890", "1e3", "--1", "+-1", "1 2", "127", "128", "-128", "-129", "000127", "+127", "\t 2\n", "+1287", "  1.0 \n", "08", "++210", "07079", "0F0627", "\n-0 ", "I-", "---1", " 00E ", "92", "00127", " +122\n", "-00", "1", "\t+0", " +0 ", "4 2", "\n00012", "1234567890123456768901234567890", "\n+-\n", "\t 0N07\n", "EI007", "\n0707 ", " -24\n", " 5 ", "\t0000127\n", "\t-8-15", "\t127\n", "1.2", "  ", "-179", "4", "N", "+1.0\n", "+17", "\t--9\n", "\n+e3", "F001273", "9", "123456789012345678960123456E890", "+--61", "7-0127", "\n\n \n", "-790", " \t-5\n ", "78", " +28", "\n0 07 ", "+-007 ", "\t 1427\n\n", "e", "1e", "1234567890123456790134567890", "028 ", "I0-129", "55", ".0", "12", "-00E7", "\t152", "--", "62", "0001a27", "\t128\n7", ".", "\n+1274\n", " 9 N", "-1-8", "77+", "\n-129", "\t\t127\nF", "+ 127", "+12", "3-6", "1+0", "13", "\t1 2", "\n0001e7 ", "\t-180 ", "1e-", "-7", "+-N1", "\n3 ", "\n123456789012345678901345I7890\n", "\n ", "-a29", "\t-129 ", "\n123456a7890N12345678901234567890", " +0", "0I", "\t 50", "+F127", "\n", "\t-129", "19F2", "1e4", "127E", "--5529", "6\t007 ", "E01", " \t0 ", " 1e3\n", "  a2\n", " +-1\n", " 9--1", "\t \n", ".10", "+05" }
    let w_byte = [130]bool{ true, true, true, false, false, false, false, true, true, false, false, false, false, false, true, false, true, false, true, true, true, false, false, true, false, false, false, true, false, false, false, true, true, true, true, true, true, true, false, true, false, false, false, false, false, true, true, true, false, true, false, false, false, true, false, false, true, false, false, false, true, false, false, false, false, false, true, true, true, false, false, false, false, false, false, true, false, true, false, true, false, false, false, true, false, false, false, false, false, false, false, false, false, false, true, false, false, true, false, false, false, false, true, false, true, false, false, false, false, false, true, false, true, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, true }
    var i_byte = 0usize
    while i_byte < 130 {
        if xsd.valid(.Byte, t_byte[i_byte]) != w_byte[i_byte] { try report("byte", i_byte) }
        i_byte += 1usize
    }
    let t_unsignedLong = [93]str{ "0", "1.0", "", "007", "123456789012345678901234567890", "1e3", "1 2", "18446744073709551615", "18446744073709551616", "00018446744073709551615", " \t\t123456789012345678901234567890\n ", " ", " 0", "\n\n0\n", "\t18446744073709551615 ", "184467440737095516E6", "\t.", "8.-1", " 2", "0-", "1-0", "0001844167440737095571615", " 1e3 ", "\t00018446744073709551615 ", "\n184467440379551616\n", "\t1I3e", "\n", "1844674073e0955115", " 8 ", "184644073709551616", "0001844674407370955161", " \t00018446744073709551615", "1844674073709551615", " e3", "7+18446744093709551615", "184476744073709551N15", "000184 -6744073709551615", " \n", "\t18446744073709551616", "e ", "\t1N3\n", "\t\n1844674407370551615\n ", " 12345678I002345678901234567890 ", "\ta1e3 ", "\n   ", "1844644073709551615", "\n3.0", "F \n", "184467440737-0955116", "1", "\t8+", "00184466744073709551615", " 15e53 ", "00018446744073709. 51615", "NI5", "001844E74073709551615", " 7-1", "1234567895123456789012345.7890", "\t0001446744073709551615 ", "N7", "00", "18446744073I70955161", "9.70", "1844E744907379551615", "\t1 2", " 7 ", "\t ", "e3", "\t 000181446744073709551615\n ", "6 ", "184467440637955616", " I007 ", "00018E467440a73709551615", "3 -5 ", " E2", " \t1\n", "1.", "0001844744073709551615", "\n000184467447370955161F5 ", " 0\n", "3\t \n\n", "1.70", "12345678I9012345678901234567890", "0001446744073709551615", "I", "1.9", "18446a7440737039551615", "7.0", "e1--1", "5.0", "\n 18446744073709551616\n", "\n1234567890012345678901234567890 ", "e-" }
    let w_unsignedLong = [93]bool{ true, false, false, true, false, false, false, true, false, true, false, false, true, true, true, false, false, false, true, false, false, false, false, true, true, false, false, false, true, true, true, true, true, false, false, false, false, false, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false, false, false, false, false, false, true, false, true, false, false, false, false, true, false, false, false, true, true, false, false, false, false, true, false, true, false, true, true, false, false, true, false, false, false, false, false, false, false, false, false }
    var i_unsignedLong = 0usize
    while i_unsignedLong < 93 {
        if xsd.valid(.UnsignedLong, t_unsignedLong[i_unsignedLong]) != w_unsignedLong[i_unsignedLong] { try report("unsignedLong", i_unsignedLong) }
        i_unsignedLong += 1usize
    }
    let t_unsignedInt = [82]str{ "0", "1.0", "", "007", "123456789012345678901234567890", "1e3", "1 2", "4294967295", "4294967296", "42949867295", "\nN", "123456789012N345678901234567890", "2-1", "\n1", "\n1  ", "\t4294967296", "42994967295", "\n077-\n", "49496296", "8-", "42949.7296", "9+-1", "7.", "FN", "\n4+E\n", "\n0", "\tE", "4294967297", "1\t+-1.", "\n007\n", "\n2+4294967295 ", "\t053\n", "1 N", "12345679012345678901234567890", "6", "0\t1234567890132345678901234567890 ", "1+", "42949267296", "1.. ", " 0 72", "a+1\n", "4 2", "12345678901234a678901234567890", "1", "60", "51.0\n", "F8", "7- ", "\nN1", "3123456789012345678901234567890", "a-1", "\n ", "\na-1N", " \n9\n", "1429496+7296", "\n 4294967295  ", " Ie3", "1.3", "  ", "\n429467296\n", "F2-1a", "4007", "\t\n", " 1.0  ", "1.", "12 3456789012345678901234567890", "\t ", "8", "65", "4N9496726", "I070", "9 ", "1-N", "13.0", "1\t- ", "0+a", " \n", "123456789012345678901234577e890", "00a7", "\t1234567890123456789012345678N90\n", "4294967267", "9-0 " }
    let w_unsignedInt = [82]bool{ true, false, false, true, false, false, false, true, false, false, false, false, false, true, true, false, false, false, true, false, false, false, false, false, false, true, false, false, false, true, false, true, false, false, true, false, false, false, false, false, false, false, false, true, true, false, false, false, false, false, false, false, false, true, false, true, false, false, false, true, false, true, false, false, false, false, false, true, true, false, false, true, false, false, false, false, false, false, false, false, true, false }
    var i_unsignedInt = 0usize
    while i_unsignedInt < 82 {
        if xsd.valid(.UnsignedInt, t_unsignedInt[i_unsignedInt]) != w_unsignedInt[i_unsignedInt] { try report("unsignedInt", i_unsignedInt) }
        i_unsignedInt += 1usize
    }
    let t_unsignedShort = [94]str{ "0", "1.0", "", "007", "123456789012345678901234567890", "1e3", "1 2", "65535", "65536", "\n\n", "3-N1", "eI", "6553", "\n0037 ", "\t1234567890123456789012345678e9", " 12345678912F45678901234567890\n", " 65536 ", "6536", "6E536", "e3", "12", "a", "6", ".- ", "I +--1 ", "\t\na \n", "8 ", "\t e0  ", " 1 8", "\n12345678901234567901234567890\n", "N0", "8+", "991", "EE", "\n1E2 ", "4-0", "N", "\ne-0", "5535", "\t65536", "4-02", "124567801245678901234567890", "653", "12a345678901234567890123+4567890", " 8655366 ", "\te", "\n", "55.6", "\t 2 ", "655a5", "1.-6", " 007\n", "\t1 N2\n", "\n20\n", "1", "3-1", " \t81e3  ", "\n8", "66535", "12345678901234e5678901234597890", "655 5", "E-1", "4 -0", "13", "  ", " 65535", "9.800", "\t 65535\n ", "\n1 2\n", " 123456789012345789012034567890", " 2", "6F535", "\n536\n", "e\n", " 1", "\t12345678901234567890123.567+890", "\t\n", ".", "\n\t65535\n ", " 6559536\n", ".08", "e", "6-1", "81e3F\n", "2", "\n 2\n", " ", " 6555 ", ".65536", "\n1.0\n", "68F+35", "\n 1e3", ".3", "1245678912345678901234567890" }
    let w_unsignedShort = [94]bool{ true, false, false, true, false, false, false, true, false, false, false, false, true, true, false, false, false, true, false, false, true, false, true, false, false, false, true, false, false, false, false, false, true, false, false, false, false, false, true, false, false, false, true, false, false, false, false, false, true, false, false, true, false, true, true, false, false, true, false, false, false, false, false, true, false, true, false, true, false, false, true, false, true, false, true, false, false, false, true, false, false, false, false, false, true, true, false, true, false, false, false, false, false, false }
    var i_unsignedShort = 0usize
    while i_unsignedShort < 94 {
        if xsd.valid(.UnsignedShort, t_unsignedShort[i_unsignedShort]) != w_unsignedShort[i_unsignedShort] { try report("unsignedShort", i_unsignedShort) }
        i_unsignedShort += 1usize
    }
    let t_unsignedByte = [92]str{ "0", "1.0", "", "007", "123456789012345678901234567890", "1e3", "1 2", "255", "256", "671", "65", " a 2 ", "1e3 ", " I\n", "33", "\t\t1\n", "\n2I6a", "6", "1a2", "\t\t256 ", "\n257\n", "\t1 2", "e007", "109", "1", "2e525", "\n1a\n", "1e33", "\n255\n", "1 ", "\t2", "\n056", "855", "4", "\n\n", "12 45678901234567890123467890", "\t\n", "14", "1234567890123467890123457890", "7", "0E", "123456786012345678901234567890", "\n1ae3", "\t \n", "235+", "F", "\t3", "1 I", "  407", " I55\n", "0I", "1 N2", "\n12345678901234567890123456890 ", "9F6", "a0", "0I07", " 256", "F0", "FF8-", " ", "5-0", "1.4F-", "80F", "1F8", "\t12346789012345678901234567890 ", "\n1\n", "\t2355", "e", "61.", " 12 ", " 255", "\n256\n", " 2255", "3-1", "a", ". 2", " 51I", "\t9-1", "123456789012F45678901235567890", "0 -", " 4", "\t\n12345678901234567801234567890  ", "60037", "\t55\n", "5", " \n0\n ", "\n e\n ", "\t2856 ", "\n", "\n2756\n", " 5", "\t0e" }
    let w_unsignedByte = [92]bool{ true, false, false, true, false, false, false, true, false, false, true, false, false, false, true, true, false, true, false, false, false, false, false, true, true, false, false, false, true, true, true, true, false, true, false, false, false, true, false, true, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, true, true, false, false, false, false, false, false, false, false, false, true, false, false, true, true, true, false, false, false, false, true, false }
    var i_unsignedByte = 0usize
    while i_unsignedByte < 92 {
        if xsd.valid(.UnsignedByte, t_unsignedByte[i_unsignedByte]) != w_unsignedByte[i_unsignedByte] { try report("unsignedByte", i_unsignedByte) }
        i_unsignedByte += 1usize
    }
    let t_float = [118]str{ "0", "1", "INF", "-INF", "+INF", "NaN", "nan", "inf", "INFINITY", "1e5", "1E5", "1e+5", "1e-5", "e5", ".5e5", "5.e5", ".e5", "1.5", "+1.5", "1e5.5", "1ee5", "0x10", "1e999", "-1e999", "1e-999", "+", "", "1 e5", "1_0", "\t1e5", " -e999 ", "+N.5", "+a", "1eF", ".e50", "11eE5", "IN", "naan", "\t1eI5", "iN", "\t..e5", "F0", "\n.e5", ".5ea", ".5", "1.", "if", "\n0x10\n", "-1e-999", "IF7NF2", "I.F", "7.e5", "85", "\n+ ", " aee5", ".59I", "\t1e-992\n", "-I93NF", "1an", "12e+5", " +2F", "in1", "\n4-I9NF ", "\n1ee-5\n", "019e-5999", "e475", "\n", "\t\n5.e5 ", "\n5.", "\n\n1.5\n", "1.e5", " \n\t1_0\n  ", "Na-", "16ee5", "I06x10", "\n1.E5\n", "\t1_41 ", " 5..5\n", "\n.e5 ", "5.5", "\tININ8TY ", "\t1 ", "\t.5e5", "N", "na0", " 1e-5", "9an", ".a", " Na6N ", "\n1e5\n", " \n-1e999", "F", "1883", "E00", "0x0", "1115", "Fe5", "\te1e-5 \n", "5e5", "81e-E5", "1e02", "1e-939", "1e1", "1.58", "E1_0", "\n1I0", "20", " \n", "0aN", "++0NF", "\t1_0\n", "1eE0999", ".INFINIY", "\n1", "1e-5\n", "In", "\n5.e5", "1e8e5" }
    let w_float = [118]bool{ true, true, true, true, false, true, false, false, false, true, true, true, true, false, true, true, false, true, true, false, false, false, true, true, true, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, false, false, true, false, false, true, true, false, false, false, true, false, false, true, false, false, false, false, true, false, false, true, true, true, true, false, false, false, false, true, false, false, false, true, false, true, true, false, false, true, false, false, false, true, true, false, true, false, false, true, false, false, true, false, true, true, true, true, false, false, true, false, false, false, false, false, false, true, true, false, true, false }
    var i_float = 0usize
    while i_float < 118 {
        if xsd.valid(.Float, t_float[i_float]) != w_float[i_float] { try report("float", i_float) }
        i_float += 1usize
    }
    let t_double = [116]str{ "0", "1", "INF", "-INF", "+INF", "NaN", "nan", "inf", "INFINITY", "1e5", "1E5", "1e+5", "1e-5", "e5", ".5e5", "5.e5", ".e5", "1.5", "+1.5", "1e5.5", "1ee5", "0x10", "1e999", "-1e999", "1e-999", "+", "", "1 e5", "1_0", "\te5\n", "\n17.5\n", "F7e99", "\t\te5\n", "\t1E0", " 1E5 ", "e999", "\t1e+5 ", "inf ", "2 ", "7E-5", "\n-ee990 ", "\t1 e5", "1e+55", "+.e5", "\te-99N9", "1+5", " 0010", "53e8", "\n.ee5\n", "1e7.5", "+IF7", "1e-1N", "\t\n", "ae+5", "-\n\n", " +.a5", " .5e5\n", "1F", "i2nf", " 1e+5\n", "9 e5 ", "\t15", "I", "8", "\t1ee03", "nn", " 1  ", "na", "12", "e15", "1e++", "7", "1ee999", "4", "\n 1e-5\n", "a.5", "INFINIT", "-1e996", "n6n", "05x17", "IN0FINITY", " +1.5 ", " .65", " nf", "1e999 ", "N \n", "\t.e5\n", " 13\n", "\n1-999\n", "1ea5", "110", " nan\n", "\t1e95.5\n", "0-INF", "\n5e5 ", "N-N", " ", " 5e5I ", "+INF+", "1e-e9", "-1e999\n", "1e9949", "\t1e-51\n", "1ee5 ", "161", ".535", " 5e5\n", "E6", "an", "1 e-999", "+8NF", " +7NF ", "N7", "5I+NF", " 355\n", "15.5" }
    let w_double = [116]bool{ true, true, true, true, false, true, false, false, false, true, true, true, true, false, true, true, false, true, true, false, false, false, true, true, true, false, false, false, false, false, true, false, false, true, true, false, true, false, true, true, false, false, true, false, false, false, true, true, false, false, false, false, false, false, false, false, true, false, false, true, false, true, false, true, false, false, true, false, true, false, false, true, false, true, true, false, false, true, false, false, false, true, true, false, true, false, false, true, false, false, true, false, false, false, true, false, false, false, false, false, true, true, true, false, true, true, true, false, false, false, false, false, false, false, true, true }
    var i_double = 0usize
    while i_double < 116 {
        if xsd.valid(.Double, t_double[i_double]) != w_double[i_double] { try report("double", i_double) }
        i_double += 1usize
    }
    let t_duration = [88]str{ "P1Y", "P1M", "P1D", "PT1H", "PT1M", "PT1S", "P", "PT", "-P1Y", "+P1Y", "P1Y2M3DT4H5M6S", "P1Y2M3DT4H5M6.7S", "P1.5Y", "P1.5D", "PT1.5H", "PT1.5S", "P1D1Y", "P1M1Y", "PT1S1M", "P1YT", "P0Y", "P0D", "P-1Y", "PT0S", "P1Y2M3DT", "P1", "PY", "P1Y 2M", "p1y", "P1W", "P0001Y", "P1Y1M43DT4H5M6S", "01.2M3T", "-PD", "-P0Y", "PY2Y3DT4H5M6S", "P1Y2M3D5T4HM6.7S", "P6T1M", "P1Y2M3.DT4H5M6.7DS", "+PY3-", "+PY", "PHY", "+P1", ".PTYM", "71y", "pS", "ST1S", "1y", "3H", "509", "1.5D", "Dy", "P01Y", "P4", "PW", "P0M1Y", "40D", "P1M1S", "P16W", "+15", "P1S", "S-61Y.", "3", "01YM", "P4T2.5H", "P1Y2M3DT4H5Y6.7S", "P0001YH", "P--S1M", "P11M64", "T0S6", "PT1.5SH7", "P15D", "P16 2M.", "P-1M1Y", "P6Y", "1Y", "1.5DD8", "P1T2T", "P1Y2M3DT4H5MSS.7S", "P1Y2", "515", "P1YPM3DT", "PDT1S1.", "P00035-Y", "-T12S1M", "TPT1S19M", "MT1M", "PT18M" }
    let w_duration = [88]bool{ true, true, true, true, true, true, false, false, true, false, true, true, false, false, false, true, false, false, false, false, true, true, false, true, false, false, false, false, false, false, true, true, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, true }
    var i_duration = 0usize
    while i_duration < 88 {
        if xsd.valid(.Duration, t_duration[i_duration]) != w_duration[i_duration] { try report("duration", i_duration) }
        i_duration += 1usize
    }
    let t_dateTime = [93]str{ "2000-01-01T00:00:00", "2000-01-01T00:00:00Z", "2000-01-01T00:00:00.5", "2000-01-01T00:00:00.", "2000-01-01T24:00:00", "2000-01-01T24:00:00.0", "2000-01-01T24:00:01", "2000-01-01T23:59:59", "2000-01-01T23:60:00", "2000-01-01T23:59:60", "2000-02-29T00:00:00", "1900-02-29T00:00:00", "2100-02-29T00:00:00", "2000-02-30T00:00:00", "2001-04-31T00:00:00", "2000-13-01T00:00:00", "2000-00-01T00:00:00", "2000-01-00T00:00:00", "0000-01-01T00:00:00", "-0001-01-01T00:00:00", "0001-01-01T00:00:00", "00001-01-01T00:00:00", "12345-01-01T00:00:00", "012345-01-01T00:00:00", "999-01-01T00:00:00", "2000-1-01T00:00:00", "2000-01-1T00:00:00", "2000-01-01t00:00:00", "2000-01-01 00:00:00", "2000-01-01T0:00:00", "2000-01-01T00:00", "2000-01-01T00:00:00+14:00", "2000-01-01T00:00:00+14:01", "2000-01-01T00:00:00-14:00", "2000-01-01T00:00:00+15:00", "2000-01-01T00:00:00+13:59", "2000-01-01T00:00:00+0100", "2000-01-01T00:00:00+01", "2000-01-01T00:00:00+01:60", "2000-01-01T00:00:00z", "2000-01-01T00:00:00ZZ", "2000-01-01T00:00:00.123456789012Z", "0001-01-01T0:0T:00", "60Z00-01901T00:00:00", "2000-601-0 1T00:00:00+15:00", "2000-10T00:0-0:00", "2000-13-01T00:060:00", "0001-01301T00:00:00", "2000-01-01T00:00:0+01", "2000-01Z-01T00:00:00ZZ", "2000-00-01T00:600:0", "2000-01-01t00:030", "2000-07-01T0:00:00", "999-091-01T00:90:00", "2000-01-01T+245:00:01", "-00010-2-29T0:00:00", "210-2-29T00:00:00", "2000-04-31T00:00:00", "2000-01-01T00:00:0Z", "2000-0101T24:00:0", "2000-02-30T00:000:0", "200-01-01T00:00:-0+14:01", "-0001-01-01T00:00:00.", "2345-01-01T600:00:00T", "2000-01-01T800:00", "2000-01-01T0:00:00+0100", "2000-0 7-01T23:60:00", "999-1-01T00:00200", "200-01-01T23:589:59", "000-01-01T2:00:00", "2000-01-01T.:0:00.0", "20007-01-01224:00:00", "2007-01-01T00:00:00+0100", "2000-01-0140 :00:00+0100", "+2 00-01-00T600:00:00", "2000-02-3030:00:00", "001-01-0T00:00:00", "-0001-01-01T00::0:.0", "1900-02-2T19T00:00:00", "10360-01-01T00:00:00+01", "2100-02-9T00:00:00", "20007-01-01 00:00:00", "8000-01-01T00:00:00ZZ", "2000-01-01T 23:59:601", "000T-01-01T00:50:00", "2000-01-01T00:-00:00+4:01", "2001-04-1T00:00:010", "2000-020-29T00:0000", "00001-01-01T00:00:0", "2000-00-0100:00:00", "2100-02-29T00-:00:0", "200001-01T009:00:00+01:40", "200104-310-:00:00" }
    let w_dateTime = [93]bool{ true, true, true, false, true, true, false, true, false, false, true, false, false, false, false, false, false, false, false, true, true, false, true, false, false, false, false, false, false, false, false, true, false, true, false, true, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var i_dateTime = 0usize
    while i_dateTime < 93 {
        if xsd.valid(.DateTime, t_dateTime[i_dateTime]) != w_dateTime[i_dateTime] { try report("dateTime", i_dateTime) }
        i_dateTime += 1usize
    }
    let t_time = [81]str{ "00:00:00", "23:59:59", "24:00:00", "24:00:01", "24:01:00", "12:00:00.5", "12:00:00.", "12:60:00", "12:00:60", "1:00:00", "12:0:00", "12:00:0", "12:00", "12:00:00Z", "12:00:00+14:00", "12:00:00+14:01", "12:00:00-05:30", "12:00:00+5:30", "25:00:00", "12:00:00.0000Z", "24:00:00.000", "32:006:0.5", "2:04:00+14:00", "2:00:0", "240:70", "242:00:00.0", "16:00:0", "24:0100", "24T:0100", "12:00:00+:30", "25:007:00", "24: 00:00.00", "12:00:0+5:30", "23:5-:859", "23:59+2", "-12:-0:00.", "12:0700Z", ":2:60:5Z", "24:02:0", "23:29:5", "4:-0:00", "12:02:00+14:01", "254:1:00", "1:5000:00", "12:0000+6:3-", "1:00:07", "-0:00:01", "92:900", "1.0-0:0", "00:00:02", "12:00:00605:3", "12:.0:00+5:30", "12:0:00.", "16:00:040.", "12:00.:00+:30", "02:00:00", "92:000:00+14:01", "12:0000+14:00", "23:59:45Z9", "200:00", "26:00:00", "12:00:0-05:30", "07:00:00", "10:0000.0000Z", "012:00:0014:0", "15:6:200", "1200:00.5", "100:60", "12:0000.0000Z", "12:60+00.", "12:60:0", "12:00100+14:00", "12:00:  0-05:30", "1 :00:00+14:-1", "12:00:0-0.", "12:00:00.0.00Z", "24:00:8+", "12:Z0:00-", "+2:00T0:00.5", "12:00:Z", "22400:01" }
    let w_time = [81]bool{ true, true, true, false, false, true, false, false, false, false, false, false, false, true, true, false, true, false, false, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, true, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var i_time = 0usize
    while i_time < 81 {
        if xsd.valid(.Time, t_time[i_time]) != w_time[i_time] { try report("time", i_time) }
        i_time += 1usize
    }
    let t_date = [82]str{ "2000-01-01", "2000-02-29", "1900-02-29", "2000-02-30", "2000-01-01Z", "2000-01-01+01:00", "2000-01-01T00:00:00", "-2000-01-01", "0000-01-01", "2000-01", "2000-13-01", "2000-12-32", "20000101", "2000/01/01", "12345-12-31", "0123-01-01", "2000-1-1", "2000-01-01+14:00", "2000-01-01+14:30", "2000-01-011", "200001-01T00:00:00", "2000-0 -01+01:00", "2000-01001+14:00", "200:0-12-32", "2000-13-0", "Z2000-01-01", "-2:000-01-01", "0123-03-01", "000-81", "200-13-01", "1900--02-29", "000-01-01+01:00", "20T0001", "2000 1-01Z", "29T00-0:-29", "990-02-290", "2000-1:3-02", "200./01/01", "2000501", "0123-021-01", "2000-02-40", "2000-0-01", "200/01/01", "1900-0-2Z", "9123-01-Z1", "2000010", "2.000-12-T2", "29000-01", "2000-12-3", "200-01-06+Z1:00", "00/00/01", "5000-1-1", "25000-02-29", "-208001-01", "190002-29", "2000-01-01+14130", "2000-801--0", "2000-01-01Z5", "2000-01-01+14:005", "12345-12-631", "2000-01-06+1400", "200:0-01-01+01:00", "2000-02-40-", "-200-01-01", "0000-0-01:", "172345-12-31", "200-01-01", "2000-01.01", "200001-01T0Z0:00:0", "23000/01/01", "0000-1-01", "2000-01-01+14:100", "1900029", "190+0-02-29", "2002/017/01", "2000-01-07+14:30", "200001", "2000501-01T00:00:00", "2000-012", "-22000-01-01", "2000 -01-01+01:00", "2000-091-1" }
    let w_date = [82]bool{ true, true, false, false, true, true, false, true, false, false, false, false, false, false, true, true, false, true, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false }
    var i_date = 0usize
    while i_date < 82 {
        if xsd.valid(.Date, t_date[i_date]) != w_date[i_date] { try report("date", i_date) }
        i_date += 1usize
    }
    let t_gYearMonth = [76]str{ "2000-01", "2000-12", "2000-13", "2000-00", "2000-1", "2000", "-2000-05", "0000-01", "12345-01", "2000-01Z", "2000-01+05:00", "2000-01-01", "999-01", "2000-01+15:00", "1235-01", "2000-0T+05:Z00", "72345-01", "-200--05", "20-01", "0T00+0-01", "200001", "20001", ".2-0", "999-1", "0002-01", "200.-0+1", "1234501", "2002-003", "+Z00-01", "2000-0++05:00", "2000-0-01", "12345-.0.1", "20.00-01+15:00", "9:9901", "123-401", "9000-06+15:00", "200-+01Z", "-207-05", "2:001-01+05:T0", "2000-05", "2000-01+05-00", ".2000-01-", "2000-01+0:00", "280-01Z", "1.23T45-0", "2000-01-0-15", "00000", "2000-01-21", "21000-T0", "2000 01", "200-01", "000-1-3", "200013", "2000-0101", "500-812", "00+-0-1", "000-01+15:00", "2040-1T", "9:9-01", "200--0-01", "2000-01+05:0028", "200-01+15:00", "2002-1", "2000-200", "999--01", "060-01", "T200000", "2000 1", "12345-0Z01", "-20800-05", "200", "2010-9", "0000101", "200-12", "2:070", "200001+05:00" }
    let w_gYearMonth = [76]bool{ true, true, false, false, false, false, true, false, true, true, true, false, false, false, true, false, true, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false }
    var i_gYearMonth = 0usize
    while i_gYearMonth < 76 {
        if xsd.valid(.GYearMonth, t_gYearMonth[i_gYearMonth]) != w_gYearMonth[i_gYearMonth] { try report("gYearMonth", i_gYearMonth) }
        i_gYearMonth += 1usize
    }
    let t_gYear = [75]str{ "2000", "-2000", "0000", "0001", "999", "12345", "012345", "2000Z", "2000+05:00", "2000-01", "20000", "-0001", "2000+14:00", "2000+14:01", "abcd", "", "1234+5", "320600", "100001", "00:1", "012645", "2+000+142+00", "-20Z0", "00:01", "412345", "25000-4:00", "20001", "00601", "1245", "-56000", "T8cd", "a2Tc", "44bd", "12+5395", "20800", "200030", "0245", "2000+143:51", "0345", "0 01", "2000+14:100", "997", "008", "2106", "8-20001", "-000-", "2000+05:0", "00-80", "9 1 2345", "200-01", "123+45", "01T345", "2-000614:00", "9", "2700-0Z", "abcd-", "200T-01", "20T00-1", "::2345", "-0501", "20700Z", "9.9", "20:00Z", "-0002", "2000+1401", "000-0-", "1-345", "00060", "50:70", "0403", "0122345", "0200", "2030", "2800-01", "200:" }
    let w_gYear = [75]bool{ true, true, false, true, false, true, false, true, true, false, true, true, true, false, false, false, false, true, true, false, false, false, false, false, true, false, true, false, true, true, false, false, false, false, true, true, true, false, true, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, false, false, true, false, false, false, false, false, true, false, true, true, false, false }
    var i_gYear = 0usize
    while i_gYear < 75 {
        if xsd.valid(.GYear, t_gYear[i_gYear]) != w_gYear[i_gYear] { try report("gYear", i_gYear) }
        i_gYear += 1usize
    }
    let t_gMonthDay = [72]str{ "--01-01", "--12-31", "--02-29", "--02-30", "--04-31", "--13-01", "--00-01", "--01-00", "--1-01", "-01-01", "--01-01Z", "--01-01+05:00", "--0101", "01-01", "--01-1", "--01-32", "--Z13-0-+1", "-1-02-3-0", "--01-01+05:0", "--04-30", "--010", "7-800-01", "014-1", "9--017-00", "010-0", "--02-249", "602-29", "-101-00", "--0101+805:00", "--54-3", "-0101", "--12-031", "--04-Z1", "01- 0T", "--04Z-31", "-00--01", "--01-0-", "4-0:1-01Z", "--00-30", "01:01+", "--72-31", "--913-0", "--2929", "--0130", "--0T-30", "901-01", "--8-4-31", "-101-0Z", "-+2-2+", "--01-01+05:0703", "015201.", "--1701", "-01--1", "-01-0-1", "--01-600", "--0-30", "-00-014", "-T-1-01", "--01-701Z", "--13-04", "--01-171+05:00", "--0-29", "--0-0", "--02-Z:", "--01-372", "--02-9", "-01-3", "--2-31", "-01-010", "-501-1", "--010.", ".--.7-01Z" }
    let w_gMonthDay = [72]bool{ true, true, true, false, false, false, false, false, false, false, true, true, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var i_gMonthDay = 0usize
    while i_gMonthDay < 72 {
        if xsd.valid(.GMonthDay, t_gMonthDay[i_gMonthDay]) != w_gMonthDay[i_gMonthDay] { try report("gMonthDay", i_gMonthDay) }
        i_gMonthDay += 1usize
    }
    let t_gDay = [71]str{ "---01", "---31", "---32", "---00", "---1", "--01", "---01Z", "---01+05:00", "---001", "01", "---1Z", "-:Z-1Z", "--.81", "-3-91", "Z01T", "---Z3", "-6-1", "---1+5:03", "2-5--3", "---01+04:00", "-", "--1-1", "---15", "--1", "5--T:31", "-Z--12Z", "Z--00", "--50Z", "--- 70", "-:-1", "2---0T1+05:00", "---1TZ", "--3-1", "811", ".---01Z", "--70", "601", "013", "--8-1Z", "0", "-.-301", "---0.01", "-51", "- -1+", "-6--5-32", "6--32", "-7-", "-8-32", "--0.1", "-- -701", "-01Z", "--31", "--01Z", "", "--00-", "--1Z", "-7--001", "- .011", "-1-32", "--81", "0---Z", "--32", "---0-1Z", "07", "--3", "---01+075:00", "--93-3", "111", "---0", "T--01", "---1+05:00" }
    let w_gDay = [71]bool{ true, true, false, false, false, false, true, true, false, false, false, false, false, false, false, false, false, false, false, true, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var i_gDay = 0usize
    while i_gDay < 71 {
        if xsd.valid(.GDay, t_gDay[i_gDay]) != w_gDay[i_gDay] { try report("gDay", i_gDay) }
        i_gDay += 1usize
    }
    let t_gMonth = [78]str{ "--01", "--12", "--13", "--00", "--1", "-01", "--01Z", "--01+05:00", "--01--", "--12--", "01", "--001", "-001", "7-0", "--03", "T--1", "--:12", "4--01-", "-15", "--01+0:00", "11", "051", ".-18+", "--9601", "--1-", "-101Z", "-174", "1-", "---01+505:00-", "031", "--051+05:00", "--122", "---01+01:00", "0-06Z", "--0--Z", ":--913", "--T01+05:00", "021", "301", "-+-12-", "-050", "01+:", "-02", "-T071", "--2--", "5--01Z", "880", "-42--", "-0--", "-+9T1", "--", "--0Z", "--712", "- - 13", "--912", "--9001", "6-01Z", "--07", "9-+12--", "--1.", "--61+", "-018-", "0-01", "-3-12-", "--001T", "9401", "--05:901", "-1--", "--1.2", "0-3", "0", "Z-01", "--3683", "-6", "-1", "T-00", "1", "-118" }
    let w_gMonth = [78]bool{ true, true, false, false, false, false, true, true, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var i_gMonth = 0usize
    while i_gMonth < 78 {
        if xsd.valid(.GMonth, t_gMonth[i_gMonth]) != w_gMonth[i_gMonth] { try report("gMonth", i_gMonth) }
        i_gMonth += 1usize
    }
    let t_hexBinary = [130]str{ "", "00", "ff", "FF", "aB", "abc", "g0", "0 0", " 00 ", "0x00", "00ff00ff", "0g", "0", "00\n", "\t0fD", "x00", "00f00ff", "\t  00ff00ff ", "\t 00 \n", "\n\ndF ", "20A", "\n ", "agB", "wf/f", "0w 0", "FFg", "00ff00Bf", "  ", "a", " 0a0E ", "B00 ", "3D", "b6c", "\t0g", "\nffB\n", "+", "00A\n", "Dab", "0 50+", " 00ff00ff\n", "0ff00ff", " 8", "C", "0\n\n", "C00", "0a", "=aB", "A\n", "800\n", "0b/", "700ff00ff", "\t\n", "\n0g ", "\t ", "A", "0x09", "FF6", "05C", "0\n", "g", "ge", "gaf0", "0x/f0", "\nE 0g\n", "0x00EC", "D700  ", " F\n", "04", " \t5\n\n", "F+B", "\tA 00 + ", "\t\naB", "aEc", "\nA0 ", " 800 ", "\n0", "0700", "\t0x00", "\t0g\n", "05 0", "\n\t", "6g", "5", "0\n9", "2g", "29", "50", "a\n", "B\tff\n", "03x00", "\n\t0 ", "00f200Qf", "\n00\n", "\t", "e", "A00", "D0", "6", "=\n", "\nwf5\n", "60", " a0 ", " 40 ", "fbf", "30wg", "\n4\n", "B", "Fc", " ", "c0A", "\n7 ", "\n800 ", " g ", "Fabc\n", "6\n", "+0", "ab5c", "acdc", "\n00 ", " \n", "5\n", "A0\ng", " FF\n", "gF", "F", " 0 0 ", "x", " FF", "A=", "003ff00f" }
    let w_hexBinary = [130]bool{ true, true, true, true, true, false, false, false, true, false, true, false, false, true, false, false, false, true, true, true, false, true, false, false, false, false, true, true, false, true, false, true, false, false, false, false, false, false, false, true, false, false, false, false, false, true, false, false, false, false, false, true, false, true, false, false, false, false, false, false, false, false, false, false, false, true, false, true, false, false, false, true, false, true, false, false, true, false, false, false, true, false, false, false, false, true, true, false, false, false, false, false, true, true, false, false, true, false, false, false, true, true, true, false, false, false, false, true, true, false, false, false, false, true, false, false, true, true, true, true, false, false, true, false, false, false, false, true, false, true }
    var i_hexBinary = 0usize
    while i_hexBinary < 130 {
        if xsd.valid(.HexBinary, t_hexBinary[i_hexBinary]) != w_hexBinary[i_hexBinary] { try report("hexBinary", i_hexBinary) }
        i_hexBinary += 1usize
    }
    let t_base64Binary = [127]str{ "", "QQ==", "QQ=", "QQ", "QUI=", "QUJD", "QUJDRA==", "QUJDRA=", "QUJDRA", "QR==", "QQ=a", "=QQ=", "QQ===", "Q Q = =", "QUJD\nRA==", "QUJ=", "QUK=", "AAAA", "AA==", "AB==", "AAB=", "AAC=", "++//", "QU JD", "QUJD ", "QUJ D", "*AAA", "A===", "AAEC=e", "BUJD ", "QUJ wD\n", "d=5=", "QJD", "  ", "5", " QUJD ", " D", "\n9QR=d\n", "eK=", "\n AC=\n", "=5Q==", "\nAB=+ ", "\t\tQUJgRA==\n", "\nA===\n", "*AA", "\n\n2Q=\n ", "\n8++// ", "QUJ5DA=/", "QUJD6A==", "\nAB= ", " QQ=a", "\nQQ==\n", "QUbJD ", "\tQQ2", "\nAAB=B", "\nUJDR", "+3=", "QUDRA=", "\nA2AB\n ", "A ==", "Q=A", "\n\nAB=  ", "3 Q = =", "Q=a", "\t =QQ=\n ", "AAC1=", "QB", "QQ4=aQ", "w\nUJ=\n", "=QU JD ", "\t\nBU JD\n", " QUJ D ", "\nQ=\n", "Q1AUJD ", "\n CA===  ", "\tQU JD ", " BQUJRA", " AAA8", "Q Q b =", "QfJD", "DB=", "3UJ ", "g===", "*eAA", "AC=", " AB==", "QR=3", "QUJDdRA==", "Qb==", "=8QQ=", "QaK=", "=A=", "\tQ Q  =\n", "QU/DRA=\n", "QDQ=a", "QFQ==", "\n*AAA\n", "\tQUJD\nRA==\n", "=QQ1", "Q5/=a", "UJ=", " QQ==", "QBQ==", "\n Q= ", "QUAJ D", "QUJ0", "QUJD\nRA=", "\nQbJD", "\tQU 3JD\ne", "Q2JDRA", "A=Q5Qe", "QR=", "w1Uf=", "\nQUI=", "aQ==", "\nQUI=w\n", "QQ=a=C", "4I", "QBQ", " QFUJD/A ", "\tQUJe\n", "\nQA\n", "Q==2", "\nQUJD2F ", "Qd D", "AA=C=", "ABw=C" }
    let w_base64Binary = [127]bool{ true, true, false, false, true, true, true, false, false, false, false, false, false, true, true, false, false, true, true, false, false, false, true, true, true, true, false, false, false, true, false, false, false, true, false, true, false, false, false, false, false, false, true, false, false, false, false, false, true, false, false, true, false, false, false, true, false, false, true, false, false, false, true, false, false, false, false, false, false, false, true, true, false, false, false, true, false, true, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, true, false, false, false, true, false, true, false, false, false, false, false, true, true, false, false, false, false, false, true, false, false, false, false, false, false }
    var i_base64Binary = 0usize
    while i_base64Binary < 127 {
        if xsd.valid(.Base64Binary, t_base64Binary[i_base64Binary]) != w_base64Binary[i_base64Binary] { try report("base64Binary", i_base64Binary) }
        i_base64Binary += 1usize
    }
    let spec_types = [88]xsd.Type{ .UnsignedByte, .UnsignedByte, .UnsignedByte, .UnsignedLong, .UnsignedLong, .UnsignedInt, .UnsignedInt, .UnsignedShort, .UnsignedShort, .Integer, .Integer, .Decimal, .Decimal, .Decimal, .NonNegativeInteger, .NonNegativeInteger, .PositiveInteger, .PositiveInteger, .PositiveInteger, .NegativeInteger, .NegativeInteger, .NegativeInteger, .NonPositiveInteger, .NonPositiveInteger, .NonPositiveInteger, .NonPositiveInteger, .Float, .Float, .Double, .Double, .Float, .Double, .Float, .Float, .Duration, .Duration, .Duration, .Duration, .Duration, .Duration, .Date, .Date, .Time, .Time, .DateTime, .DateTime, .GYear, .GYearMonth, .GMonthDay, .GDay, .GMonth, .DateTime, .DateTime, .DateTime, .DateTime, .DateTime, .Name, .Name, .Name, .Name, .Name, .Name, .Name, .NMToken, .NMToken, .NMToken, .NMToken, .NCName, .NCName, .NCName, .ID, .IDREF, .QName, .QName, .QName, .QName, .QName, .QName, .AnyURI, .AnyURI, .AnyURI, .AnyURI, .AnyURI, .AnyURI, .AnyURI, .Base64Binary, .Base64Binary, .Base64Binary }
    let spec_texts = [88]str{ "+255", "-0", "+256", "+0", "+18446744073709551615", "-0", " +7 ", "+1", "-1", "1234567890123456789012345678901234567890", "-1234567890123456789012345678901234567890", "12345678901234567890.123456789012345678", " - ", "+", "99999999999999999999999999999999999999999999999999999999", "-99999999999999999999999999999999999999999999999999999999", "123456789012345678901234567890", "0", "-0", "-99999999999999999999999999999999999999999999999999999999", "-0", "99999999999999999999999999999", "-99999999999999999999999999999999999999999999999999999999", "0", "+0", "1", "1e", "1e+", "1e-", ".5e", " INF ", "\nNaN\n", " -INF", "+INF", "PT.5S", "PT1.S", " PT1S ", "\tP1Y\n", "P99999999999Y", "PT0.5S", " 2000-01-01 ", "\t2000-02-29\n", " 12:00:00 ", "\t24:00:00\n", " 2000-01-01T00:00:00 ", "\n2000-01-01T00:00:00-14:00\n", " 2000 ", "\n2000-01+05:00\n", " --01-01Z ", " ---01 ", "\t--01\n", "-0001-02-29T00:00:00", "-0002-02-29T00:00:00", "-0004-02-29T00:00:00", "-0005-02-29T00:00:00", "0000-01-01T00:00:00", "a‌", "𐀀", "󯿿", "󰀀", "a ", "‌", "a·", "‌", "a b", "", "𐀀", "a‍", "a:b", "̀", "𝟎", "x‌", "a:b", "a:b:c", ":a", "a:", "x:‌", " a:b ", "", "a b", "http://[::1/", ":", "a%zz", "日本", " \t x \n", "--__", "QUJD", "QUJ-" }
    let spec_want = [88]bool{ true, true, false, true, true, true, true, true, false, true, true, true, false, false, true, false, true, false, false, true, false, false, true, true, true, false, false, false, false, false, true, true, true, false, false, false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false, false, true, false, true, true, true, false, false, true, true, true, false, false, true, true, false, false, true, true, true, false, false, false, true, true, true, true, true, true, true, true, true, false, true, false }
    var spec_i = 0usize
    while spec_i < 88 {
        if xsd.valid(spec_types[spec_i], spec_texts[spec_i]) != spec_want[spec_i] { try report("spec", spec_i) }
        spec_i += 1usize
    }
    var named = 0usize
    let (n_string, f_string) = xsd.type_named("string")
    if !f_string || n_string != .String { try report("type-named", named) }
    named += 1usize
    let (n_normalizedString, f_normalizedString) = xsd.type_named("normalizedString")
    if !f_normalizedString || n_normalizedString != .NormalizedString { try report("type-named", named) }
    named += 1usize
    let (n_token, f_token) = xsd.type_named("token")
    if !f_token || n_token != .Token { try report("type-named", named) }
    named += 1usize
    let (n_language, f_language) = xsd.type_named("language")
    if !f_language || n_language != .Language { try report("type-named", named) }
    named += 1usize
    let (n_Name, f_Name) = xsd.type_named("Name")
    if !f_Name || n_Name != .Name { try report("type-named", named) }
    named += 1usize
    let (n_NCName, f_NCName) = xsd.type_named("NCName")
    if !f_NCName || n_NCName != .NCName { try report("type-named", named) }
    named += 1usize
    let (n_NMTOKEN, f_NMTOKEN) = xsd.type_named("NMTOKEN")
    if !f_NMTOKEN || n_NMTOKEN != .NMToken { try report("type-named", named) }
    named += 1usize
    let (n_ID, f_ID) = xsd.type_named("ID")
    if !f_ID || n_ID != .ID { try report("type-named", named) }
    named += 1usize
    let (n_IDREF, f_IDREF) = xsd.type_named("IDREF")
    if !f_IDREF || n_IDREF != .IDREF { try report("type-named", named) }
    named += 1usize
    let (n_anyURI, f_anyURI) = xsd.type_named("anyURI")
    if !f_anyURI || n_anyURI != .AnyURI { try report("type-named", named) }
    named += 1usize
    let (n_QName, f_QName) = xsd.type_named("QName")
    if !f_QName || n_QName != .QName { try report("type-named", named) }
    named += 1usize
    let (n_boolean, f_boolean) = xsd.type_named("boolean")
    if !f_boolean || n_boolean != .Boolean { try report("type-named", named) }
    named += 1usize
    let (n_decimal, f_decimal) = xsd.type_named("decimal")
    if !f_decimal || n_decimal != .Decimal { try report("type-named", named) }
    named += 1usize
    let (n_integer, f_integer) = xsd.type_named("integer")
    if !f_integer || n_integer != .Integer { try report("type-named", named) }
    named += 1usize
    let (n_nonPositiveInteger, f_nonPositiveInteger) = xsd.type_named("nonPositiveInteger")
    if !f_nonPositiveInteger || n_nonPositiveInteger != .NonPositiveInteger { try report("type-named", named) }
    named += 1usize
    let (n_negativeInteger, f_negativeInteger) = xsd.type_named("negativeInteger")
    if !f_negativeInteger || n_negativeInteger != .NegativeInteger { try report("type-named", named) }
    named += 1usize
    let (n_nonNegativeInteger, f_nonNegativeInteger) = xsd.type_named("nonNegativeInteger")
    if !f_nonNegativeInteger || n_nonNegativeInteger != .NonNegativeInteger { try report("type-named", named) }
    named += 1usize
    let (n_positiveInteger, f_positiveInteger) = xsd.type_named("positiveInteger")
    if !f_positiveInteger || n_positiveInteger != .PositiveInteger { try report("type-named", named) }
    named += 1usize
    let (n_long, f_long) = xsd.type_named("long")
    if !f_long || n_long != .Long { try report("type-named", named) }
    named += 1usize
    let (n_int, f_int) = xsd.type_named("int")
    if !f_int || n_int != .Int { try report("type-named", named) }
    named += 1usize
    let (n_short, f_short) = xsd.type_named("short")
    if !f_short || n_short != .Short { try report("type-named", named) }
    named += 1usize
    let (n_byte, f_byte) = xsd.type_named("byte")
    if !f_byte || n_byte != .Byte { try report("type-named", named) }
    named += 1usize
    let (n_unsignedLong, f_unsignedLong) = xsd.type_named("unsignedLong")
    if !f_unsignedLong || n_unsignedLong != .UnsignedLong { try report("type-named", named) }
    named += 1usize
    let (n_unsignedInt, f_unsignedInt) = xsd.type_named("unsignedInt")
    if !f_unsignedInt || n_unsignedInt != .UnsignedInt { try report("type-named", named) }
    named += 1usize
    let (n_unsignedShort, f_unsignedShort) = xsd.type_named("unsignedShort")
    if !f_unsignedShort || n_unsignedShort != .UnsignedShort { try report("type-named", named) }
    named += 1usize
    let (n_unsignedByte, f_unsignedByte) = xsd.type_named("unsignedByte")
    if !f_unsignedByte || n_unsignedByte != .UnsignedByte { try report("type-named", named) }
    named += 1usize
    let (n_float, f_float) = xsd.type_named("float")
    if !f_float || n_float != .Float { try report("type-named", named) }
    named += 1usize
    let (n_double, f_double) = xsd.type_named("double")
    if !f_double || n_double != .Double { try report("type-named", named) }
    named += 1usize
    let (n_duration, f_duration) = xsd.type_named("duration")
    if !f_duration || n_duration != .Duration { try report("type-named", named) }
    named += 1usize
    let (n_dateTime, f_dateTime) = xsd.type_named("dateTime")
    if !f_dateTime || n_dateTime != .DateTime { try report("type-named", named) }
    named += 1usize
    let (n_time, f_time) = xsd.type_named("time")
    if !f_time || n_time != .Time { try report("type-named", named) }
    named += 1usize
    let (n_date, f_date) = xsd.type_named("date")
    if !f_date || n_date != .Date { try report("type-named", named) }
    named += 1usize
    let (n_gYearMonth, f_gYearMonth) = xsd.type_named("gYearMonth")
    if !f_gYearMonth || n_gYearMonth != .GYearMonth { try report("type-named", named) }
    named += 1usize
    let (n_gYear, f_gYear) = xsd.type_named("gYear")
    if !f_gYear || n_gYear != .GYear { try report("type-named", named) }
    named += 1usize
    let (n_gMonthDay, f_gMonthDay) = xsd.type_named("gMonthDay")
    if !f_gMonthDay || n_gMonthDay != .GMonthDay { try report("type-named", named) }
    named += 1usize
    let (n_gDay, f_gDay) = xsd.type_named("gDay")
    if !f_gDay || n_gDay != .GDay { try report("type-named", named) }
    named += 1usize
    let (n_gMonth, f_gMonth) = xsd.type_named("gMonth")
    if !f_gMonth || n_gMonth != .GMonth { try report("type-named", named) }
    named += 1usize
    let (n_hexBinary, f_hexBinary) = xsd.type_named("hexBinary")
    if !f_hexBinary || n_hexBinary != .HexBinary { try report("type-named", named) }
    named += 1usize
    let (n_base64Binary, f_base64Binary) = xsd.type_named("base64Binary")
    if !f_base64Binary || n_base64Binary != .Base64Binary { try report("type-named", named) }
    named += 1usize
    let (_, found_0) = xsd.type_named("")
    if found_0 { try report("type-named-unknown", 0usize) }
    let (_, found_1) = xsd.type_named("String")
    if found_1 { try report("type-named-unknown", 1usize) }
    let (_, found_2) = xsd.type_named("INT")
    if found_2 { try report("type-named-unknown", 2usize) }
    let (_, found_3) = xsd.type_named("xs:int")
    if found_3 { try report("type-named-unknown", 3usize) }
    let (_, found_4) = xsd.type_named("int ")
    if found_4 { try report("type-named-unknown", 4usize) }
    let (_, found_5) = xsd.type_named("anySimpleType")
    if found_5 { try report("type-named-unknown", 5usize) }
    let (_, found_6) = xsd.type_named("dateTimeStamp")
    if found_6 { try report("type-named-unknown", 6usize) }
    let (_, found_7) = xsd.type_named("Boolean")
    if found_7 { try report("type-named-unknown", 7usize) }
    let (_, found_8) = xsd.type_named("integers")
    if found_8 { try report("type-named-unknown", 8usize) }
    if xsd.whitespace(.String) != xsd.Whitespace.Preserve || xsd.whitespace(.NormalizedString) != xsd.Whitespace.Replace || xsd.whitespace(.Token) != xsd.Whitespace.Collapse || xsd.whitespace(.Int) != xsd.Whitespace.Collapse || xsd.whitespace(.Base64Binary) != xsd.Whitespace.Collapse { try report("whitespace", 0usize) }
    try io.print("fmt xsd types ok\n")
    ret ok
}
