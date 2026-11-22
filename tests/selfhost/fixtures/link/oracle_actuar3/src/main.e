// e.algo.stat.actuar against actuar, third group: hierarchical credibility and barycenter regression credibility. tests/oracle/actuar3.json comes from scripts/r_oracle/groups/actuar3.R.


use e.algo.stat.actuar as ac
use e.io
use e.math
use e.mem
use e.os
use e.algo.rand.r as rr
use e.str
use e.test.oracle as oracle
fn answer(ar: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "hier") {
        let hl = usize(x[0usize])
        let hn = usize(x[1usize])
        let ht = usize(x[2usize])
        let (pl, pe2) = mem.alloc[usize](ar, hl)
        let (nnv, pe3) = mem.alloc[usize](ar, hl)
        let (ho, pe4) = mem.alloc[f64](ar, 64usize + 4usize * hn + 4usize * hn * ht)
        if pe2 != ok || pe3 != ok || pe4 != ok { os.exit(11) }
        var hi = 0usize
        var psum = 0usize
        while hi < hl {
            pl[hi] = usize(x[4usize + hi])
            psum += pl[hi]
            hi += 1usize
        }
        let (par, pe) = mem.alloc[usize](ar, psum)
        if pe != ok { os.exit(11) }
        hi = 0usize
        while hi < psum {
            par[hi] = usize(x[4usize + hl + hi])
            hi += 1usize
        }
        let nb0 = 4usize + hl + psum
        hi = 0usize
        while hi < hl {
            nnv[hi] = usize(x[nb0 + hi])
            hi += 1usize
        }
        let rb = nb0 + hl
        if ac.cm_hierarchical(ar, hl, hn, ht, usize(x[3usize]), x[rb..rb + hn * ht], x[rb + hn * ht..rb + 2usize * hn * ht], par, pl, nnv, ho) != ok { os.exit(12) }
        ret ho[usize(x[rb + 2usize * hn * ht])]
    }
    if str.eq(c.name, "hb") {
        let bn = usize(x[0usize])
        let bt = usize(x[1usize])
        let bp = usize(x[2usize])
        let (bo, be) = mem.alloc[f64](ar, 2usize * bp + 1usize + 3usize * bp * bn + 4usize)
        if be != ok { os.exit(41) }
        let rb = 4usize
        if ac.hache_bary(ar, x[rb..rb + bn * bt], x[rb + bn * bt..rb + 2usize * bn * bt], x[rb + 2usize * bn * bt..rb + 2usize * bn * bt + bt * bp], bn, bt, bp, usize(x[3usize]), bo) != ok { os.exit(42) }
        ret bo[usize(x[rb + 2usize * bn * bt + bt * bp])]
    }
    ret 0.0f64 / 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/actuar3.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
