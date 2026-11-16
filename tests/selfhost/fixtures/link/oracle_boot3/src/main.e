// e.algo.stat.boot studentized intervals and abc.ci against boot. tests/oracle/boot3.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R boot3`; the layout is at the top of scripts/r_oracle/groups/boot3.R.

use e.algo.rand.r as rng
use e.algo.stat.boot as bt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "abc_lo") || str.eq(c.name, "abc_hi") {
        let n = usize(z[2usize])
        let (lo, hi, e) = bt.abc_ci(a, z[3usize..3usize + n], u8(z[0usize]), z[1usize])
        if e != ok { ret nan }
        if str.eq(c.name, "abc_lo") { ret lo }
        ret hi
    }
    if str.eq(c.name, "anti_t0") || str.eq(c.name, "anti_t") || str.eq(c.name, "anti_tsum") || str.eq(c.name, "anti_idx") {
        let seed = i64(z[0usize])
        let st = u8(z[1usize])
        let r = usize(z[2usize])
        let n = usize(z[3usize])
        var g: rng.Rng = zero
        rng.seed(&g, seed)
        let (b, be) = bt.boot_antithetic(a, &g, z[4usize..4usize + n], st, r, z[4usize + n..4usize + 2usize * n])
        if be != ok { ret nan }
        if str.eq(c.name, "anti_t0") { ret b.t0 }
        if str.eq(c.name, "anti_t") { ret b.t[usize(z[4usize + 2usize * n])] }
        if str.eq(c.name, "anti_idx") { ret f64(b.idx[usize(z[4usize + 2usize * n])]) }
        var s = 0.0f64
        var i = 0usize
        while i < r {
            s += b.t[i]
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "model_t0") || str.eq(c.name, "model_t") || str.eq(c.name, "model_tsum") {
        let seed = i64(z[0usize])
        let st = u8(z[1usize])
        let r = usize(z[2usize])
        let n = usize(z[3usize])
        let mf = usize(z[4usize + 3usize * n])
        let gb = 5usize + 3usize * n + 2usize * mf
        let mg = usize(z[gb])
        var g: rng.Rng = zero
        rng.seed(&g, seed)
        let (b, be) = bt.censboot_model(a, &g, z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], z[4usize + 2usize * n..4usize + 3usize * n], z[5usize + 3usize * n..5usize + 3usize * n + mf], z[5usize + 3usize * n + mf..gb], z[gb + 1usize..gb + 1usize + mg], z[gb + 1usize + mg..gb + 1usize + 2usize * mg], st, r)
        if be != ok { ret nan }
        if str.eq(c.name, "model_t0") { ret b.t0 }
        if str.eq(c.name, "model_t") { ret b.t[usize(z[gb + 1usize + 2usize * mg])] }
        var s = 0.0f64
        var i = 0usize
        while i < r {
            s += b.t[i]
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "condcox_t0") || str.eq(c.name, "condcox_t") || str.eq(c.name, "condcox_tsum") {
        let seed = i64(z[0usize])
        let st = u8(z[1usize])
        let r = usize(z[2usize])
        let n = usize(z[3usize])
        let mf = usize(z[4usize + 3usize * n])
        let gb = 5usize + 3usize * n + 2usize * mf
        let mg = usize(z[gb])
        var g: rng.Rng = zero
        rng.seed(&g, seed)
        let (b, be) = bt.censboot_condcox(a, &g, z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], z[4usize + 2usize * n..4usize + 3usize * n], z[5usize + 3usize * n..5usize + 3usize * n + mf], z[5usize + 3usize * n + mf..gb], z[gb + 1usize..gb + 1usize + mg], z[gb + 1usize + mg..gb + 1usize + 2usize * mg], st, r)
        if be != ok { ret nan }
        if str.eq(c.name, "condcox_t0") { ret b.t0 }
        if str.eq(c.name, "condcox_t") { ret b.t[usize(z[gb + 1usize + 2usize * mg])] }
        var s = 0.0f64
        var i = 0usize
        while i < r {
            s += b.t[i]
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "ei_inf_s") || str.eq(c.name, "ei_inf_1") || str.eq(c.name, "ei_jw_s") || str.eq(c.name, "ei_jw_1") || str.eq(c.name, "ei_ji_s") || str.eq(c.name, "ei_ji_1") {
        let kd = u8(z[0usize])
        let n = usize(z[1usize])
        let (lo, le) = mem.alloc[f64](a, n)
        if le != ok { ret nan }
        var ee = ok
        if c.name[3usize] == 105u8 { ee = bt.empinf_inf(a, z[2usize..2usize + n], kd, 0.001f64, lo) }
        if c.name[3usize] == 106u8 && c.name[4usize] == 119u8 { ee = bt.empinf_jack(a, z[2usize..2usize + n], kd, true, lo) }
        if c.name[3usize] == 106u8 && c.name[4usize] == 105u8 { ee = bt.empinf_jack(a, z[2usize..2usize + n], kd, false, lo) }
        if ee != ok { ret nan }
        if c.name[c.name.len - 1usize] == 49u8 { ret lo[0usize] }
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += lo[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "ei_pw_s") || str.eq(c.name, "ei_pw_1") || str.eq(c.name, "ei_pi_s") || str.eq(c.name, "ei_pi_1") || str.eq(c.name, "ei_reg_s") || str.eq(c.name, "ei_reg_1") {
        let kd = u8(z[0usize])
        let n = usize(z[1usize])
        let (lo, le) = mem.alloc[f64](a, n)
        if le != ok { ret nan }
        var ee = ok
        if c.name[3usize] == 112u8 { ee = bt.empinf_pos(a, z[2usize..2usize + n], kd, c.name[4usize] == 119u8, lo) }
        if c.name[3usize] == 114u8 {
            var g: rng.Rng = zero
            rng.seed(&g, i64(z[2usize + n]))
            let (bo, be) = bt.boot(a, &g, z[2usize..2usize + n], kd, usize(z[3usize + n]))
            if be != ok { ret nan }
            ee = bt.empinf_reg(a, &bo, lo)
        }
        if ee != ok { ret nan }
        if c.name[c.name.len - 1usize] == 49u8 { ret lo[0usize] }
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += lo[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "cond_t0") || str.eq(c.name, "cond_t") || str.eq(c.name, "cond_tsum") {
        let seed = i64(z[0usize])
        let st = u8(z[1usize])
        let r = usize(z[2usize])
        let n = usize(z[3usize])
        var g: rng.Rng = zero
        rng.seed(&g, seed)
        let (b, be) = bt.censboot_cond(a, &g, z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], st, r)
        if be != ok { ret nan }
        if str.eq(c.name, "cond_t0") { ret b.t0 }
        if str.eq(c.name, "cond_t") { ret b.t[usize(z[4usize + 2usize * n])] }
        var s = 0.0f64
        var i = 0usize
        while i < r {
            s += b.t[i]
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "weird_t0") || str.eq(c.name, "weird_t") || str.eq(c.name, "weird_tsum") {
        let seed = i64(z[0usize])
        let st = u8(z[1usize])
        let r = usize(z[2usize])
        let n = usize(z[3usize])
        var g: rng.Rng = zero
        rng.seed(&g, seed)
        let (b, be) = bt.censboot_weird(a, &g, z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], st, r)
        if be != ok { ret nan }
        if str.eq(c.name, "weird_t0") { ret b.t0 }
        if str.eq(c.name, "weird_t") { ret b.t[usize(z[4usize + 2usize * n])] }
        var s = 0.0f64
        var i = 0usize
        while i < r {
            s += b.t[i]
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "cens_t0") || str.eq(c.name, "cens_t") || str.eq(c.name, "cens_tsum") {
        let seed = i64(z[0usize])
        let st = u8(z[1usize])
        let r = usize(z[2usize])
        let n = usize(z[3usize])
        var g: rng.Rng = zero
        rng.seed(&g, seed)
        let (b, be) = bt.censboot_ordinary(a, &g, z[4usize..4usize + n], st, r)
        if be != ok { ret nan }
        if str.eq(c.name, "cens_t0") { ret b.t0 }
        if str.eq(c.name, "cens_t") { ret b.t[usize(z[4usize + n])] }
        var s = 0.0f64
        var i = 0usize
        while i < r {
            s += b.t[i]
            i += 1usize
        }
        ret s
    }
    let seed = i64(z[0usize])
    let r = usize(z[1usize])
    let conf = z[2usize]
    let n = usize(z[3usize])
    let x = z[4usize..4usize + n]
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (b, be) = bt.boot(a, &g, x, 0u8, r)
    if be != ok { ret nan }
    let (lo, hi, e) = bt.stud_mean_ci(a, &b, x, conf)
    if e != ok { ret nan }
    if str.eq(c.name, "stud_lo") { ret lo }
    ret hi
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/boot3.json")
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
