// e.text.hunspell against R's hunspell package over three hand-written dictionaries (long, numeric
// and UTF-8 flags, OCONV, MAP, KEY, anchored REP, BREAK, IGNORE, KEEPCASE, FORBIDDENWORD,
// NOSUGGEST, NEEDAFFIX, WARN, COMPOUNDRULE with ? and *). tests/oracle/hunspell_custom.json and the
// dictionary files come from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hunspell_custom`.
// A case is (dictionary number) with the word or text in "in"; "check" answers 1 or 0, the others
// answer text with one result per line.

use e.text.hunspell as hs
use e.io
use e.fs
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn str_cat(a: *mem.Arena, x: str, y: str) -> str {
    let (r, e) = str.concat(a, x, y)
    if e != ok { os.exit(5) }
    ret r
}

fn load_dict(a: *mem.Arena, number: usize) -> hs.Dict {
    var stem = "tests/oracle/hunspell/custom0"
    if number == 1usize { stem = "tests/oracle/hunspell/custom1" }
    if number == 2usize { stem = "tests/oracle/hunspell/custom2" }
    if number == 3usize { stem = "tests/oracle/hunspell/custom3" }
    if number == 4usize { stem = "tests/oracle/hunspell/custom4" }
    if number == 5usize { stem = "tests/oracle/hunspell/custom5" }
    let (aff, ae) = fs.read_file(a, str_cat(a, stem, ".aff"), 16777216usize)
    if ae != ok { os.exit(2) }
    let (dic, de) = fs.read_file(a, str_cat(a, stem, ".dic"), 16777216usize)
    if de != ok { os.exit(3) }
    let (d, le) = hs.load(a, aff, dic)
    if le != ok { os.exit(4) }
    ret d
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hunspell_custom.json")
    if load_error != ok { os.exit(6) }
    if golden.cases.len == 0usize { os.exit(7) }
    var dicts: [6]hs.Dict = zero
    var count = 0usize
    while count < 6usize {
        dicts[count] = load_dict(a, count)
        count += 1usize
    }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let d = &dicts[usize(c.args[0usize])]
        let word = c.inputs[0usize]
        var good = false
        var got = ""
        var number = 0.0f64
        if str.eq(c.name, "check") {
            if hs.spell(a, d, word) { number = 1.0f64 }
            good = oracle.agrees(number, c)
        } else {
            if str.eq(c.name, "analyze") {
                got = hs.analyze(a, d, word)
            } else if str.eq(c.name, "stem") {
                got = hs.stem(a, d, word)
            } else if str.eq(c.name, "suggest") {
                got = hs.suggest(a, d, word)
            } else {
                got = hs.find(a, d, word)
            }
            good = oracle.agrees_text(got, c)
        }
        if !good {
            failures += 1usize
            if failures <= 25usize {
                let _ = io.print(c.name)
                let _ = io.print(" d")
                let digits = "0123"
                let dn = usize(c.args[0usize])
                let _ = io.print(digits[dn..dn + 1usize])
                let _ = io.print("[")
                let _ = io.print(word)
                let _ = io.print("] got (")
                let _ = io.print(got)
                let _ = io.print(") want (")
                let _ = io.print(c.text)
                let _ = io.print(")\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
