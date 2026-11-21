// e.fmt.mat5 against R.matlab::readMat and writeMat. tests/oracle/matlab.json and the .mat files under tests/oracle/data come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R matlab`; the case layout is at the top of scripts/r_oracle/groups/matlab.R.

use e.fmt.mat5 as mat
use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// how many places two parsed variables differ
fn diff(p: *const mat.Var, q: *const mat.Var) -> usize {
    var d = 0usize
    if p.class != q.class || p.complex != q.complex || p.nd != q.nd || p.count != q.count || p.nf != q.nf || p.kids.len != q.kids.len || p.re.len != q.re.len || p.im.len != q.im.len { ret 1usize }
    var i = 0usize
    while i < p.nd {
        if p.dims[i] != q.dims[i] { d += 1usize }
        i += 1usize
    }
    i = 0usize
    while i < p.re.len {
        if p.re[i] != q.re[i] { d += 1usize }
        i += 1usize
    }
    i = 0usize
    while i < p.im.len {
        if p.im[i] != q.im[i] { d += 1usize }
        i += 1usize
    }
    i = 0usize
    while i < p.kids.len {
        d += diff(&p.kids[i], &q.kids[i])
        i += 1usize
    }
    ret d
}

fn metric(name: str, v: *const mat.Var, aux: usize) -> f64 {
    let cls = usize(v.class)
    let nested = cls == 1usize || cls == 2usize
    if str.eq(name, "count") {
        if nested { ret f64(v.kids.len) }
        if cls == 4usize { ret f64(v.dims[0usize]) }
        ret f64(v.count)
    }
    if str.eq(name, "ndim") {
        if cls == 2usize { ret f64(v.nd + 1usize) }
        ret f64(v.nd)
    }
    if str.eq(name, "dim") {
        if cls == 2usize {
            if aux == 0usize { ret f64(v.nf) }
            ret f64(v.dims[aux - 1usize])
        }
        ret f64(v.dims[aux])
    }
    var rows = 0usize
    var cols = 1usize
    if cls == 4usize && v.nd == 2usize {
        rows = v.dims[0usize]
        cols = v.dims[1usize]
    }
    var s = 0.0f64
    var i = 0usize
    while i < v.re.len {
        var w = f64(i + 1usize)
        if cls == 4usize && rows > 0usize { w = f64((i % rows) * cols + i / rows + 1usize) }
        if str.eq(name, "sum") { s += v.re[i] }
        if str.eq(name, "wsum") { s += v.re[i] * w }
        if v.complex && str.eq(name, "isum") { s += v.im[i] }
        if v.complex && str.eq(name, "wisum") { s += v.im[i] * w }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/matlab_")
    let _ = str.push_usize(&bb, usize(x[0usize]))
    let _ = str.push(&bb, ".mat")
    let path = str.done(&bb)
    let (bytes, re) = fs.read_file(a, path, 4194304usize)
    if re != ok { os.exit(6) }
    let (m, pe) = mat.parse(a, bytes)
    if pe != ok { os.exit(7) }
    if str.eq(c.name, "nvars") { ret f64(m.nvars) }
    if str.eq(c.name, "rewrite") || str.eq(c.name, "selfrt") {
        let (o, we) = mat.write(a, m.vars)
        if we != ok { os.exit(8) }
        if str.eq(c.name, "selfrt") {
            let (m2, pe2) = mat.parse(a, o)
            if pe2 != ok { os.exit(9) }
            var d = 0usize
            if m2.nvars != m.nvars { d += 1usize }
            var k = 0usize
            while k < m.nvars && k < m2.nvars {
                d += diff(&m.vars[k], &m2.vars[k])
                k += 1usize
            }
            ret f64(d)
        }
        var d = 0usize
        if o.len != bytes.len { d += 1000000usize }
        var k = 128usize
        while k < o.len && k < bytes.len {
            if o[k] != bytes[k] && d == 0usize { d = k }
            k += 1usize
        }
        ret f64(d)
    }
    var cur = &m.vars[usize(x[1usize])]
    if str.eq(c.name, "name") {
        var s = 0.0f64
        var i = 0usize
        while i < cur.name.len {
            s += f64(cur.name[i])
            i += 1usize
        }
        ret s
    }
    var lvl = 2usize
    while lvl < 4usize && x[lvl] >= 0.0f64 {
        cur = &cur.kids[usize(x[lvl])]
        lvl += 1usize
    }
    var aux = 0usize
    if x[4usize] >= 0.0f64 { aux = usize(x[4usize]) }
    ret metric(c.name, cur, aux)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/matlab.json")
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
