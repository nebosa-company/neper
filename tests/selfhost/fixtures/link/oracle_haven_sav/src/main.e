// e.fmt.sav against haven: read_sav on tests/data/haven/s1.sav, s2.sav and s3.zsav (plain, bytecode and zlib
// compressed; long strings, user-missing values, value labels, dates). tests/oracle/haven_sav.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R haven_sav`; the stat numbers are listed at
// the top of scripts/r_oracle/groups/haven_sav.R.

use e.fmt.sav as sav
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
    let f = i64(x[0usize])
    var path = "tests/data/haven/s1.sav"
    if f == 2i64 { path = "tests/data/haven/s2.sav" }
    if f == 3i64 { path = "tests/data/haven/s3.zsav" }
    let (bytes, re) = fs.read_file(a, path, 4194304usize)
    if re != ok { os.exit(4) }
    let (d, e) = sav.read(a, bytes)
    if e != ok { os.exit(5) }
    let col = i64(x[1usize])
    let stat = u8(x[2usize])
    if col < 0i64 {
        if stat == 0u8 { ret f64(d.nvars) }
        ret f64(d.nobs)
    }
    let cc = usize(col)
    let text = d.is_text[cc] != 0u8
    if stat == 0u8 { ret strsum(d.names[cc]) }
    if stat == 1u8 { ret strsum(d.varlabels[cc]) }
    if stat == 9u8 { ret strsum(d.formats[cc]) }
    if stat == 10u8 { ret f64(d.display_width[cc]) }
    // haven's na_values are the single-valued entries: every one, or the third of a range plus value
    var first = 0usize
    var last = usize(d.miss_count[cc])
    if d.miss_range[cc] != 0u8 {
        first = 2usize
        if last < 3usize { last = 2usize }
    }
    if stat == 11u8 { ret f64(last - first) }
    if stat == 12u8 {
        var s = 0.0f64
        var j = first
        while j < last {
            if text { s += f64(j + 1usize) * strsum(d.miss_text[cc * 3usize + j]) } else { s += d.miss_num[cc * 3usize + j] }
            j += 1usize
        }
        ret s
    }
    if stat == 13u8 { ret d.miss_num[cc * 3usize] }
    if stat == 14u8 { ret d.miss_num[cc * 3usize + 1usize] }
    if stat == 15u8 && text {
        var n = 0.0f64
        var r = 0usize
        while r < d.nobs {
            if sav.text_user_missing(&d, cc, d.text[r * d.nvars + cc]) { n += 1.0f64 }
            r += 1usize
        }
        ret n
    }
    if stat == 2u8 || stat == 3u8 || stat == 4u8 || stat == 15u8 {
        var s = 0.0f64
        var w = 0.0f64
        var na = 0.0f64
        var r = 0usize
        while r < d.nobs {
            let val = sav.value(&d, r, cc)
            var missing = val != val
            if stat == 15u8 && !missing && sav.num_user_missing(&d, cc, d.num[r * d.nvars + cc]) { missing = true }
            if missing {
                na += 1.0f64
            } else {
                s += val
                w += f64(r + 1usize) * val
            }
            r += 1usize
        }
        if stat == 2u8 { ret s }
        if stat == 3u8 { ret w }
        ret na
    }
    if stat == 5u8 || stat == 16u8 {
        var w = 0.0f64
        var r = 0usize
        while r < d.nobs {
            if stat == 5u8 { w += f64(r + 1usize) * strsum(d.text[r * d.nvars + cc]) } else { w += f64(d.text[r * d.nvars + cc].len) }
            r += 1usize
        }
        ret w
    }
    let k = d.label_set[cc]
    if k < 0i64 { ret 0.0f64 }
    let set = usize(k)
    if stat == 6u8 { ret f64(d.set_count[set]) }
    var s = 0.0f64
    var j = 0usize
    while j < d.set_count[set] {
        let en = d.set_first[set] + j
        if stat == 7u8 {
            if text { s += f64(j + 1usize) * strsum(d.entry_text[en]) } else { s += d.entry_num[en] }
        } else {
            s += f64(j + 1usize) * strsum(d.entry_label[en])
        }
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/haven_sav.json")
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
