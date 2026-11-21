// e.fmt.dta against haven, second set: formats 113 to 119 written by haven (tagged missing values, tagged value
// labels, UTF-8, strLs) and formats 104 to 116 built from the format description in both byte orders (every
// storage type and missing code). tests/oracle/haven_dta2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R haven_dta2`; the layout is at the top of
// scripts/r_oracle/groups/haven_dta2.R and the files come from scripts/make_haven_dta2.R.

use e.fmt.dta as dta
use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn strsum(s: str) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < s.len {
        t += f64(i + 1usize) * f64(s[i])
        i += 1usize
    }
    ret t
}

fn path_of(f: i64) -> str {
    if f == 1i64 { ret "tests/data/haven/w8.dta" }
    if f == 2i64 { ret "tests/data/haven/w10.dta" }
    if f == 3i64 { ret "tests/data/haven/w12.dta" }
    if f == 4i64 { ret "tests/data/haven/w13.dta" }
    if f == 5i64 { ret "tests/data/haven/w14.dta" }
    if f == 6i64 { ret "tests/data/haven/w15.dta" }
    if f == 7i64 { ret "tests/data/haven/h104L.dta" }
    if f == 8i64 { ret "tests/data/haven/h104M.dta" }
    if f == 9i64 { ret "tests/data/haven/h105L.dta" }
    if f == 10i64 { ret "tests/data/haven/h105M.dta" }
    if f == 11i64 { ret "tests/data/haven/h108L.dta" }
    if f == 12i64 { ret "tests/data/haven/h108M.dta" }
    if f == 13i64 { ret "tests/data/haven/h110L.dta" }
    if f == 14i64 { ret "tests/data/haven/h110M.dta" }
    if f == 15i64 { ret "tests/data/haven/h111L.dta" }
    if f == 16i64 { ret "tests/data/haven/h111M.dta" }
    if f == 17i64 { ret "tests/data/haven/h112L.dta" }
    if f == 18i64 { ret "tests/data/haven/h112M.dta" }
    if f == 19i64 { ret "tests/data/haven/h113L.dta" }
    if f == 20i64 { ret "tests/data/haven/h113M.dta" }
    if f == 21i64 { ret "tests/data/haven/h114L.dta" }
    if f == 22i64 { ret "tests/data/haven/h114M.dta" }
    if f == 23i64 { ret "tests/data/haven/h115L.dta" }
    if f == 24i64 { ret "tests/data/haven/h115M.dta" }
    if f == 25i64 { ret "tests/data/haven/h116L.dta" }
    if f == 27i64 { ret "tests/data/haven/d8.dta" }
    if f == 28i64 { ret "tests/data/haven/d14.dta" }
    if f == 29i64 { ret "tests/data/haven/d15.dta" }
    ret "tests/data/haven/h116M.dta"
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let (bytes, re) = fs.read_file(a, path_of(i64(x[0usize])), 4194304usize)
    if re != ok { os.exit(4) }
    let (d, e) = dta.read(a, bytes)
    if e != ok { os.exit(5) }
    let col = i64(x[1usize])
    let stat = u8(x[2usize])
    if col < 0i64 {
        if stat == 0u8 { ret f64(d.nvars) }
        if stat == 1u8 { ret f64(d.nobs) }
        ret strsum(d.label)
    }
    let cc = usize(col)
    if stat == 0u8 { ret strsum(d.names[cc]) }
    if stat == 1u8 { ret strsum(d.varlabels[cc]) }
    if stat == 11u8 { ret strsum(d.formats[cc]) }
    var s = 0.0f64
    var w = 0.0f64
    var na = 0.0f64
    var r = 0usize
    while r < d.nobs {
        let at = r * d.nvars + cc
        if stat == 5u8 { s += f64(r + 1usize) * strsum(d.text[at]) }
        if stat == 12u8 { s += f64(d.text[at].len) }
        if stat == 9u8 { s += f64(r + 1usize) * f64(d.tags[at]) }
        if stat >= 2u8 && stat <= 4u8 {
            let val = dta.value(&d, r, cc)
            if val == val {
                s += val
                w += f64(r + 1usize) * val
            } else {
                na += 1.0f64
            }
        }
        r += 1usize
    }
    if stat == 3u8 { ret w }
    if stat == 4u8 { ret na }
    if stat <= 5u8 || stat == 9u8 || stat == 12u8 { ret s }
    // value labels of the column's table
    var k = 0usize
    var found = false
    while k < d.lbl_names.len && !found {
        if d.vlnames[cc].len > 0usize && str.eq(d.lbl_names[k], d.vlnames[cc]) { found = true } else { k += 1usize }
    }
    if !found { ret 0.0f64 }
    if stat == 6u8 { ret f64(d.lbl_count[k]) }
    var t = 0.0f64
    var j = 0usize
    while j < d.lbl_count[k] {
        let at = d.lbl_first[k] + j
        let code = d.lbl_codes[at]
        if stat == 7u8 && code == code { t += code }
        if stat == 8u8 { t += f64(j + 1usize) * strsum(d.lbl_texts[at]) }
        if stat == 10u8 { t += f64(j + 1usize) * f64(d.lbl_tags[at]) }
        j += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/haven_dta2.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
