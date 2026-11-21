// e.fmt.xport against haven: read_xpt on tests/data/haven/x5.xpt (version 5) and x8.xpt (version 8): IBM
// floats, tagged missing values, strings, formats, labels and dates. tests/oracle/haven_xpt.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R haven_xpt`; the stat numbers are listed at the top
// of scripts/r_oracle/groups/haven_xpt.R.

use e.fmt.xport as xport
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
    var path = "tests/data/haven/x5.xpt"
    if i64(x[0usize]) == 2i64 { path = "tests/data/haven/x8.xpt" }
    let (bytes, re) = fs.read_file(a, path, 4194304usize)
    if re != ok { os.exit(4) }
    let (d, e) = xport.read(a, bytes)
    if e != ok { os.exit(5) }
    let col = i64(x[1usize])
    let stat = u8(x[2usize])
    if col < 0i64 {
        if stat == 0u8 { ret f64(d.nvars) }
        ret f64(d.nobs)
    }
    let cc = usize(col)
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/haven_xpt.json")
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
