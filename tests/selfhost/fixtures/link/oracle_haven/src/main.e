// e.fmt.dta against haven: read_dta on the Stata 117 and 118 files of tests/data/haven (names, labels,
// values, missing codes and value labels). tests/oracle/haven.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R haven`; the layout is at the top of
// scripts/r_oracle/groups/haven.R.

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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let v = i64(x[0usize])
    var path = "tests/data/haven/t13.dta"
    if v == 14i64 { path = "tests/data/haven/t14.dta" }
    if v == 15i64 { path = "tests/data/haven/t15.dta" }
    let (bytes, re) = fs.read_file(a, path, 1048576usize)
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
    if stat >= 2u8 && stat <= 4u8 {
        var s = 0.0f64
        var w = 0.0f64
        var na = 0.0f64
        var r = 0usize
        while r < d.nobs {
            let val = d.num[r * d.nvars + cc]
            if val == val {
                s += val
                w += f64(r + 1usize) * val
            } else {
                na += 1.0f64
            }
            r += 1usize
        }
        if stat == 2u8 { ret s }
        if stat == 3u8 { ret w }
        ret na
    }
    if stat == 5u8 {
        var w = 0.0f64
        var r = 0usize
        while r < d.nobs {
            w += f64(r + 1usize) * strsum(d.text[r * d.nvars + cc])
            r += 1usize
        }
        ret w
    }
    // value labels of the column's table
    var k = 0usize
    var found = false
    while k < d.lbl_names.len && !found {
        if d.vlnames[cc].len > 0usize && str.eq(d.lbl_names[k], d.vlnames[cc]) { found = true } else { k += 1usize }
    }
    if !found { ret 0.0f64 }
    if stat == 6u8 { ret f64(d.lbl_count[k]) }
    var s = 0.0f64
    var j = 0usize
    while j < d.lbl_count[k] {
        if stat == 7u8 { s += f64(d.lbl_codes[d.lbl_first[k] + j]) } else { s += f64(j + 1usize) * strsum(d.lbl_texts[d.lbl_first[k] + j]) }
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/haven.json")
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
