// e.algo.stat.veganpkg against vegan diversity, rarefy, estimateR and vegdist. tests/oracle/vegan.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vegan`; the layout is at the top of scripts/r_oracle/groups/vegan.R.

use e.algo.stat.veganpkg as vg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nr = usize(z[0usize])
    let nc = usize(z[1usize])
    let m = z[3usize..3usize + nr * nc]
    let (out, e1) = mem.alloc[f64](a, 6usize)
    if e1 != ok { ret nan }
    var s = 0.0f64
    var slot = 7usize
    if str.eq(c.name, "shannon") { slot = 0usize }
    if str.eq(c.name, "simpson") { slot = 1usize }
    if str.eq(c.name, "invsimpson") { slot = 2usize }
    if str.eq(c.name, "pielou") { slot = 3usize }
    if str.eq(c.name, "richness") { slot = 4usize }
    if str.eq(c.name, "chao1") { slot = 5usize }
    var r = 0usize
    if slot < 6usize {
        while r < nr {
            vg.diversity(m, nr, nc, r, out)
            s += out[slot] * f64(r + 1usize)
            r += 1usize
        }
        ret s
    }
    if str.eq(c.name, "rarefy") {
        while r < nr {
            s += vg.rarefy(m, nc, r, z[2usize]) * f64(r + 1usize)
            r += 1usize
        }
        ret s
    }
    var method = 0usize
    if str.eq(c.name, "d_1") { method = 1usize }
    if str.eq(c.name, "d_2") { method = 2usize }
    if str.eq(c.name, "d_3") { method = 3usize }
    if str.eq(c.name, "d_4") { method = 4usize }
    if str.eq(c.name, "d_5") { method = 5usize }
    if str.eq(c.name, "d_6") { method = 6usize }
    if str.eq(c.name, "d_7") { method = 7usize }
    if str.eq(c.name, "d_8") { method = 8usize }
    if str.eq(c.name, "d_9") { method = 9usize }
    // R lists the lower triangle by columns
    var pos = 1usize
    var cb = 0usize
    while cb < nr {
        var ra = cb + 1usize
        while ra < nr {
            s += vg.vegdist(m, nr, nc, ra, cb, method) * f64(pos)
            pos += 1usize
            ra += 1usize
        }
        cb += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vegan.json")
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
