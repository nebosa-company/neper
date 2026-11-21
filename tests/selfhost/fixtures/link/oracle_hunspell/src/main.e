// e.text.hunspell against R's hunspell package over its bundled en_US and en_GB dictionaries.
// tests/oracle/hunspell.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hunspell`;
// the four dictionary files are the ones the package ships. A case is (dictionary: 0 en_US, 1 en_GB),
// the word or text in "in", and for "check" a number (1 correct, 0 not), otherwise the answer text
// with one result per line.

use e.text.hunspell as hs
use e.io
use e.fs
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn load_dict(a: *mem.Arena, stem: str) -> hs.Dict {
    let (aff, ae) = fs.read_file(a, str_cat(a, stem, ".aff"), 16777216usize)
    if ae != ok { os.exit(2) }
    let (dic, de) = fs.read_file(a, str_cat(a, stem, ".dic"), 16777216usize)
    if de != ok { os.exit(3) }
    let (d, le) = hs.load(a, aff, dic)
    if le != ok { os.exit(4) }
    ret d
}

fn str_cat(a: *mem.Arena, x: str, y: str) -> str {
    let (r, e) = str.concat(a, x, y)
    if e != ok { os.exit(5) }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hunspell.json")
    if load_error != ok { os.exit(6) }
    if golden.cases.len == 0usize { os.exit(7) }
    var us = load_dict(a, "tests/oracle/hunspell/en_US")
    var gb = load_dict(a, "tests/oracle/hunspell/en_GB")
    var added = load_dict(a, "tests/oracle/hunspell/en_US")
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var d = &us
        if c.args[0usize] == 1.0f64 { d = &gb }
        if c.args[0usize] == 2.0f64 { d = &added }
        if str.eq(c.name, "added") {
            hs.add_words(a, &added, c.inputs)
            at += 1usize
            continue
        }
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
            } else if str.eq(c.name, "find_f") {
                got = hs.find_format(a, d, word, u8(c.args[1usize]))
            } else if str.eq(c.name, "parse_f") {
                got = hs.parse_tokens(a, d, word, u8(c.args[1usize]))
            } else {
                got = hs.find(a, d, word)
            }
            good = oracle.agrees_text(got, c)
        }
        if !good {
            failures += 1usize
            if failures <= 25usize {
                let _ = io.print(c.name)
                let _ = io.print(" [")
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
