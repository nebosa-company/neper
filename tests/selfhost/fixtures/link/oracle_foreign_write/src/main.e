// e.fmt.writeforeign against foreign::write.foreign (SPSS and Stata). tests/oracle/foreign_write.json, the frames (wf_<i>.spec) and R's own output files under
// tests/oracle/data come from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R foreign_write`; the layouts are at the top of scripts/r_oracle/groups/foreign_write.R.

use e.fmt.writeforeign as wf
use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn line_end(t: str, at: usize) -> usize {
    var e = at
    while e < t.len && t[e] != 10u8 { e += 1usize }
    ret e
}

fn trim_cr(t: str, s: usize, e: usize) -> usize {
    if e > s && t[e - 1usize] == 13u8 { ret e - 1usize }
    ret e
}

// the number of tab-separated fields of t[s..e], an empty line having none
fn count_fields(t: str, s: usize, e: usize) -> usize {
    if e == s { ret 0usize }
    var n = 1usize
    var i = s
    while i < e {
        if t[i] == 9u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn field(t: str, s: usize, e: usize, k: usize) -> str {
    var from = s
    var idx = 0usize
    var i = s
    while i <= e {
        if i == e || t[i] == 9u8 {
            if idx == k { ret t[from..i] }
            idx += 1usize
            from = i + 1usize
        }
        i += 1usize
    }
    ret t[s..s]
}

fn number(s: str) -> f64 {
    if str.eq(s, "NA") { ret 0.0f64 / 0.0f64 }
    let (x, pe) = str.parse_f64(s)
    if pe != ok { os.exit(11) }
    ret x
}

fn load(a: *mem.Arena, i: usize, names: *[]str, f: *wf.Frame) {
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/wf_")
    let _ = str.push_i64(&bb, i64(i))
    let _ = str.push(&bb, ".spec")
    let (t, re) = fs.read_file(a, str.done(&bb), 4194304usize)
    if re != ok { os.exit(6) }
    // the lines
    let (starts, es1) = mem.alloc[usize](a, 4096usize)
    if es1 != ok { os.exit(7) }
    let (ends, es2) = mem.alloc[usize](a, 4096usize)
    if es2 != ok { os.exit(7) }
    var n = 0usize
    var p = 0usize
    while p < t.len {
        let le = line_end(t, p)
        starts[n] = p
        ends[n] = trim_cr(t, p, le)
        n += 1usize
        p = le + 1usize
    }
    let hdr = t[starts[0usize]..ends[0usize]]
    // the header is blank-separated, not tab-separated
    var sp = 0usize
    while sp < hdr.len && hdr[sp] != 32u8 { sp += 1usize }
    let ncols = usize(number(hdr[0usize..sp]))
    let nrows = usize(number(hdr[(sp + 1usize)..hdr.len]))
    let (nm, e1) = mem.alloc[str](a, ncols + 1usize)
    if e1 != ok { os.exit(7) }
    let (kind, e2) = mem.alloc[u8](a, ncols + 1usize)
    if e2 != ok { os.exit(7) }
    let (nlev, e3) = mem.alloc[usize](a, ncols + 1usize)
    if e3 != ok { os.exit(7) }
    let (vals, e4) = mem.alloc[f64](a, ncols * nrows + 1usize)
    if e4 != ok { os.exit(7) }
    let (txt, e5) = mem.alloc[str](a, ncols * nrows + 1usize)
    if e5 != ok { os.exit(7) }
    var total_levels = 0usize
    var j = 0usize
    while j < ncols {
        let ls = 1usize + 4usize * j + 2usize
        total_levels += count_fields(t, starts[ls], ends[ls])
        j += 1usize
    }
    let (levels, e6) = mem.alloc[str](a, total_levels + 1usize)
    if e6 != ok { os.exit(7) }
    var li = 0usize
    j = 0usize
    while j < ncols {
        let base = 1usize + 4usize * j
        nm[j] = t[starts[base]..ends[base]]
        kind[j] = u8(number(t[starts[base + 1usize]..ends[base + 1usize]]))
        let nl = count_fields(t, starts[base + 2usize], ends[base + 2usize])
        nlev[j] = nl
        var l = 0usize
        while l < nl {
            levels[li] = field(t, starts[base + 2usize], ends[base + 2usize], l)
            li += 1usize
            l += 1usize
        }
        var r = 0usize
        while r < nrows {
            let fv = field(t, starts[base + 3usize], ends[base + 3usize], r)
            if kind[j] == 2u8 {
                if str.eq(fv, "<NA>") {
                    vals[j * nrows + r] = 0.0f64 / 0.0f64
                } else {
                    vals[j * nrows + r] = 0.0f64
                    txt[j * nrows + r] = fv
                }
            } else {
                vals[j * nrows + r] = number(fv)
            }
            r += 1usize
        }
        j += 1usize
    }
    *names = nm[0usize..ncols]
    f.ncols = ncols
    f.nrows = nrows
    f.kind = kind[0usize..ncols]
    f.nlev = nlev[0usize..ncols]
    f.levels = levels[0usize..total_levels]
    f.values = vals[0usize..(ncols * nrows)]
    f.txt = txt[0usize..(ncols * nrows)]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let idx = usize(x[0usize])
    let pkg = usize(x[1usize])
    let part = usize(x[2usize])
    var names: []str = zero
    var f: wf.Frame = zero
    load(a, idx, &names, &f)
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/wf_")
    let _ = str.push_i64(&bb, i64(idx))
    if pkg == 0usize { let _ = str.push(&bb, "_spss.csv") } else { let _ = str.push(&bb, "_stata.csv") }
    let dfile = str.done(&bb)
    var data: str = ""
    var code: str = ""
    var we: err = ok
    if pkg == 0usize {
        let (d, cd, ee) = wf.spss(a, &f, names, dfile)
        data = d
        code = cd
        we = ee
    } else {
        let (d, cd, ee) = wf.stata(a, &f, names, dfile)
        data = d
        code = cd
        we = ee
    }
    if we != ok { os.exit(8) }
    var out = data
    if part == 1usize { out = code }
    if str.eq(c.name, "len") { ret f64(out.len) }
    var h = 0.0f64
    var i = 0usize
    while i < out.len {
        h += f64(out[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret h
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/foreign_write.json")
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
