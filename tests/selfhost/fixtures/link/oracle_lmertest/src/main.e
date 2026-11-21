// e.algo.stat.lmerpkg (lmerTest side) against lmerTest and pbkrtest on one-random-intercept models. tests/oracle/lmertest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lmertest`; the argument layout is at the top of scripts/r_oracle/groups/lmertest.R.

use e.algo.stat.lmerpkg as lm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let ng = usize(z[2usize])
    let reml = z[3usize] != 0.0f64
    let op = usize(z[4usize])
    let sub = usize(z[5usize])
    let kr = z[6usize] != 0.0f64
    let theta = z[7usize]
    let sigma = z[8usize]
    let nt = usize(z[9usize])
    let r = usize(z[10usize])
    let (g, ge) = mem.alloc[usize](a, n)
    let (asgn, ae) = mem.alloc[usize](a, p)
    let (xmap, me) = mem.alloc[usize](a, p)
    let (order, oe) = mem.alloc[usize](a, nt + 1usize)
    if ge != ok || ae != ok || me != ok || oe != ok { ret nan }
    let ox = 12usize
    let og = ox + n * p
    let oy = og + n
    let oa = oy + n
    let orx = oa + p
    let oxm = orx + n * r
    let oo = oxm + p
    let oc = oo + nt
    let oex = oc + nt * nt
    var i = 0usize
    while i < n {
        g[i] = usize(z[og + i])
        i += 1usize
    }
    i = 0usize
    while i < p {
        asgn[i] = usize(z[oa + i])
        xmap[i] = usize(z[oxm + i])
        i += 1usize
    }
    i = 0usize
    while i < nt {
        order[i] = usize(z[oo + i])
        i += 1usize
    }
    let x = z[ox..ox + n * p]
    let y = z[oy..oy + n]
    let tm = lm.Terms{ nterm: nt, asgn: asgn, order: order, contain: z[oc..oc + nt * nt], r: r, rdx: z[orx..orx + n * r], xmap: xmap }
    let ex = z[oex..z.len]
    if op == 1usize {
        // summary coefficient table: column sub, rows folded by row number
        let (lv, le) = mem.alloc[f64](a, p)
        let (co, ce) = mem.alloc[f64](a, 5usize)
        if le != ok || ce != ok { ret nan }
        var tot = 0.0f64
        var j = 0usize
        while j < p {
            var q = 0usize
            while q < p {
                lv[q] = 0.0f64
                q += 1usize
            }
            lv[j] = 1.0f64
            if lm.lmer_contest(a, x, y, g, n, p, ng, reml, theta, sigma, lv, kr, co) != ok { ret nan }
            tot += co[sub] * f64(j + 1usize)
            j += 1usize
        }
        ret tot
    }
    if op == 2usize {
        let (ao, ee) = mem.alloc[f64](a, 6usize * nt)
        if ee != ok { ret nan }
        if lm.lmer_anova(a, x, y, g, n, p, ng, reml, theta, sigma, &tm, usize(ex[0usize]), kr, ao) != ok { ret nan }
        var tot = 0.0f64
        var k = 0usize
        while k < nt {
            tot += ao[6usize * k + sub] * f64(k + 1usize)
            k += 1usize
        }
        ret tot
    }
    if op == 3usize {
        let term = usize(ex[0usize])
        let (cols, ce) = mem.alloc[usize](a, p)
        if ce != ok { ret nan }
        var nc = 0usize
        i = 0usize
        while i < p {
            if asgn[i] == term + 1usize {
                cols[nc] = i
                nc += 1usize
            }
            i += 1usize
        }
        let kk = nc + 1usize
        let np = kk * (kk - 1usize) / 2usize
        let (dout, de) = mem.alloc[f64](a, 7usize * np)
        if de != ok { ret nan }
        if lm.lmer_diffls(a, x, y, g, n, p, ng, reml, theta, sigma, cols[0usize..nc], kk, 0.95f64, kr, dout) != ok { ret nan }
        var tot = 0.0f64
        var m = 0usize
        while m < np {
            tot += dout[7usize * m + sub] * f64(m + 1usize)
            m += 1usize
        }
        ret tot
    }
    if op == 4usize {
        let (ro, re) = mem.alloc[f64](a, 9usize)
        if re != ok { ret nan }
        if lm.lmer_ranova(a, x, y, g, n, p, ng, reml, theta, sigma, ro) != ok { ret nan }
        ret ro[sub]
    }
    if op == 5usize {
        let (so, se) = mem.alloc[f64](a, 4usize + 5usize * nt)
        if se != ok { ret nan }
        if lm.lmer_step(a, x, y, g, n, p, ng, reml, &tm, ex[0usize], ex[1usize], so) != ok { ret nan }
        if sub == 0usize { ret so[0usize] }
        if sub == 1usize { ret so[1usize] }
        if sub == 7usize { ret so[2usize + 5usize * nt] }
        if sub == 8usize { ret so[3usize + 5usize * nt] }
        let nel = usize(so[1usize])
        var tot = 0.0f64
        if sub <= 3usize {
            var m = 0usize
            while m < nel {
                var v = so[2usize + m]
                if sub == 3usize { v = so[2usize + nt + m] }
                tot += v * f64(m + 1usize)
                m += 1usize
            }
            ret tot
        }
        // the final table: F (sub 4), DenDF (5) and p (6) of the surviving terms, folded by position among them
        var pos = 0usize
        var k = 0usize
        while k < nt {
            let v = so[2usize + 2usize * nt + 3usize * k + sub - 4usize]
            if so[2usize + 2usize * nt + 3usize * k] == so[2usize + 2usize * nt + 3usize * k] {
                pos += 1usize
                tot += v * f64(pos)
            }
            k += 1usize
        }
        ret tot
    }
    if op == 6usize {
        let (co, ce) = mem.alloc[f64](a, 5usize)
        if ce != ok { ret nan }
        if lm.lmer_contest(a, x, y, g, n, p, ng, reml, theta, sigma, ex[0usize..p], kr, co) != ok { ret nan }
        ret co[sub]
    }
    let (jo, je) = mem.alloc[f64](a, 6usize)
    if je != ok { ret nan }
    let q = usize(ex[0usize])
    if lm.lmer_contest_joint(a, x, y, g, n, p, ng, reml, theta, sigma, ex[1usize..1usize + q * p], q, kr, jo) != ok { ret nan }
    ret jo[sub]
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, "op ")
    let _ = str.push_f64(&b, c.args[4usize])
    let _ = str.push(&b, " sub ")
    let _ = str.push_f64(&b, c.args[5usize])
    let _ = str.push(&b, " ddf ")
    let _ = str.push_f64(&b, c.args[6usize])
    let _ = str.push(&b, " n ")
    let _ = str.push_f64(&b, c.args[0usize])
    let _ = str.push(&b, " p ")
    let _ = str.push_f64(&b, c.args[1usize])
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lmertest.json")
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
            if failures <= 24usize {
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
