// e.fmt.sas7bdat against haven: read_sas on four real .sas7bdat files (iris, datetime, hadley, tagged-na): names, labels,
// formats, numbers, strings, dates and tagged missing values. tests/oracle/haven_sas.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R haven_sas`; the stat numbers are listed at the top
// of scripts/r_oracle/groups/haven_sas.R.

use e.fmt.sas7bdat as xport
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
    var path = "tests/data/haven/iris.sas7bdat"
    var fi = i64(x[0usize])
    if fi == 2i64 { path = "tests/data/haven/datetime.sas7bdat" }
    if fi == 3i64 { path = "tests/data/haven/hadley.sas7bdat" }
    if fi == 4i64 { path = "tests/data/haven/tagged-na.sas7bdat" }
    if fi == 5i64 { path = "tests/data/haven/rle64.sas7bdat" }
    if fi == 6i64 { path = "tests/data/haven/rle32.sas7bdat" }
    if fi == 7i64 { path = "tests/data/haven/raw64.sas7bdat" }
    if fi == 8i64 { path = "tests/data/haven/rdc32.sas7bdat" }
    if fi == 9i64 { path = "tests/data/haven/rdc64.sas7bdat" }
    if fi == 10i64 { path = "tests/data/haven/rle32be.sas7bdat" }
    if fi == 11i64 { path = "tests/data/haven/rdc64be.sas7bdat" }
    if fi == 12i64 { path = "tests/data/haven/raw64be.sas7bdat" }
    let (bytes, re) = fs.read_file(a, path, 8388608usize)
    if re != ok { os.exit(4) }
    let (d, e) = xport.read(a, bytes)
    if e != ok {
        let _ = io.print(path)
        if e == xport.BadFile { os.exit(5) }
        os.exit(6)
    }
    let col = i64(x[1usize])
    let stat = u8(x[2usize])
    if col < 0i64 {
        if stat == 0u8 { ret f64(d.nvars) }
        ret f64(d.nobs)
    }
    let cc = usize(col)
    if stat >= 9u8 {
        var cpath = ""
        if fi == 3i64 { cpath = "tests/data/haven/formats.sas7bcat" }
        if fi == 4i64 { cpath = "tests/data/haven/tagged-na.sas7bcat" }
        if cpath.len == 0usize { ret 0.0f64 }
        let (cb, cre) = fs.read_file(a, cpath, 8388608usize)
        if cre != ok { os.exit(7) }
        let (cat, cle) = xport.read_catalog(a, cb)
        if cle != ok { os.exit(8) }
        var n = 0.0f64
        var sum = 0.0f64
        var nm = 0.0f64
        var tg = 0.0f64
        var si = 0usize
        while si < cat.nsets {
            if str.eq(cat.names[si], d.formats[cc]) {
                var ek = 0usize
                while ek < cat.count[si] {
                    let ei = cat.first[si] + ek
                    n += 1.0f64
                    if cat.is_text[si] != 0u8 { sum += n * strsum(cat.text[ei]) } else if cat.num[ei] == cat.num[ei] { sum += cat.num[ei] }
                    nm += n * strsum(cat.label[ei])
                    tg += n * f64(cat.tags[ei])
                    ek += 1usize
                }
            }
            si += 1usize
        }
        if stat == 9u8 { ret n }
        if stat == 10u8 { ret sum }
        if stat == 11u8 { ret nm }
        ret tg
    }
    if stat == 0u8 { ret strsum(d.names[cc]) }
    if stat == 1u8 { ret strsum(d.labels[cc]) }
    if stat == 6u8 { ret strsum(d.formats[cc]) }
    var s = 0.0f64
    var w = 0.0f64
    var na = 0.0f64
    var r = 0usize
    while r < d.nobs {
        if stat == 5u8 { s += f64(r + 1usize) * strsum(d.text[r * d.nvars + cc]) }
        if stat == 8u8 { s += f64(d.text[r * d.nvars + cc].len) }
        if stat == 7u8 { s += f64(r + 1usize) * f64(d.tags[r * d.nvars + cc]) }
        if stat >= 2u8 && stat <= 4u8 {
            let val = xport.value(&d, r, cc)
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
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/haven_sas.json")
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
