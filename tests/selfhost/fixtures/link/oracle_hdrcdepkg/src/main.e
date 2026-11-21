// e.algo.stat.hdrcdepkg against hdrcde 3.5.0. tests/oracle/hdrcdepkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hdrcdepkg`; the case layouts are at the top of scripts/r_oracle/groups/hdrcdepkg.R.

use e.algo.rand.r as rr
use e.algo.stat.hdrcdepkg as hd
use e.algo.stat.rdensity as rd
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// the value one hdr case asks for, given the density (xs, ys), the sample the heights are read at and the two probabilities
fn hdr_value(a: *mem.Arena, what: usize, ri: usize, k: usize, p1: f64, p2: f64, xs: []const f64, ys: []const f64, samp: []const f64) -> f64 {
    var alo = 1.0f64 - p1
    var ahi = 1.0f64 - p2
    if ahi < alo {
        alo = 1.0f64 - p2
        ahi = 1.0f64 - p1
    }
    var alpha = alo
    if ri == 1usize { alpha = ahi }
    let (fx, e1) = mem.alloc[f64](a, samp.len + 1usize)
    let (ends, e2) = mem.alloc[f64](a, 200usize)
    let (modes, e3) = mem.alloc[f64](a, xs.len + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(11) }
    if what <= 2usize {
        let fa = hd.falpha_of(samp, xs, ys, alpha, fx)
        if what == 0usize { ret fa }
        let cnt = hd.hdr_ends(xs, ys, fa, ends)
        if what == 1usize { ret f64(cnt) }
        if k < cnt { ret ends[k] }
        ret 0.0f64 - 1.0f64
    }
    var all = false
    if what >= 5usize { all = true }
    let m = hd.hdr_modes(xs, ys, all, modes)
    if what == 3usize || what == 5usize { ret f64(m) }
    if k < m { ret modes[k] }
    ret 0.0f64 - 1.0f64
}

fn seq_arr(a: *mem.Arena, from: f64, to: f64, n: usize) -> []f64 {
    let s = hd.newf(a, n)
    if s.len == 0usize { os.exit(12) }
    var i = 0usize
    while i < n {
        s[i] = hd.seqat(from, to, i, n)
        i += 1usize
    }
    ret s
}

fn min_of(x: []const f64) -> f64 {
    var m = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < m { m = x[i] }
        i += 1usize
    }
    ret m
}

fn max_of(x: []const f64) -> f64 {
    var m = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] > m { m = x[i] }
        i += 1usize
    }
    ret m
}

// the default cde(x, y): margins 15 and 100, rule-of-thumb bandwidths; z has 1500 values
type Cde = struct { z: []f64, ym: []f64, xm: []f64 }

fn default_cde(a: *mem.Arena, x: []const f64, y: []const f64) -> Cde {
    let (aa, bb) = hd.cdeband_rules0(x, y)
    let ym = seq_arr(a, min_of(y) - 4.0f64 * bb, max_of(y) + 4.0f64 * bb, 100usize)
    let xm = seq_arr(a, min_of(x), max_of(x), 15usize)
    let z = hd.newf(a, 1500usize)
    if z.len == 0usize { os.exit(13) }
    if hd.cde_z(a, x, y, aa, bb, xm, ym, z) != ok { os.exit(14) }
    ret Cde { z: z, ym: ym, xm: xm }
}

fn run_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let g = c.args
    let kind = usize(g[0usize])
    if kind == 1usize || kind == 2usize || kind == 6usize {
        var bw = 0.0f64
        var lam = 1.0f64
        var seed = 0i64
        var n = 0usize
        var at = 0usize
        if kind == 1usize {
            bw = g[6usize]
            n = usize(g[7usize])
            at = 8usize
        }
        if kind == 2usize {
            bw = g[6usize]
            lam = g[7usize]
            n = usize(g[8usize])
            at = 9usize
        }
        if kind == 6usize {
            lam = g[6usize]
            seed = i64(g[7usize])
            n = usize(g[8usize])
            at = 9usize
        }
        let x = g[at..at + n]
        let (xo, e1) = mem.alloc[f64](a, 1100usize)
        let (yo, e2) = mem.alloc[f64](a, 1100usize)
        if e1 != ok || e2 != ok { os.exit(15) }
        var m = 0usize
        if kind == 1usize {
            let (s, e3) = mem.alloc[f64](a, n + 1usize)
            let (sc, e4) = mem.alloc[f64](a, 2560usize)
            if e3 != ok || e4 != ok { os.exit(16) }
            var i = 0usize
            while i < n {
                s[i] = x[i]
                i += 1usize
            }
            hd.sort_f64(s[0usize..n])
            hd.den_grid(x, s[0usize..n], bw, xo, yo, sc)
            m = 512usize
        } else {
            if kind == 6usize {
                let (tx, e5) = mem.alloc[f64](a, n + 1usize)
                if e5 != ok { os.exit(17) }
                var i = 0usize
                while i < n {
                    if lam == 1.0f64 { tx[i] = x[i] } else { tx[i] = hd.boxcox(x[i], lam) }
                    i += 1usize
                }
                let (b, be) = hd.hdrbw(a, tx[0usize..n], (g[4usize] + g[5usize]) / 2.0f64, seed, 1000000usize)
                if be != ok { os.exit(18) }
                bw = b
            }
            let (cnt, te) = hd.tdensity(a, x, bw, lam, xo, yo)
            if te != ok { os.exit(19) }
            m = cnt
        }
        ret hdr_value(a, usize(g[1usize]), usize(g[2usize]), usize(g[3usize]), g[4usize], g[5usize], xo[0usize..m], yo[0usize..m], x)
    }
    if kind == 3usize {
        let seed = i64(g[6usize])
        let nn = usize(g[7usize])
        let m = usize(g[8usize])
        let xs = g[9usize..9usize + m]
        let ys = g[9usize + m..9usize + 2usize * m]
        var r: rr.Rng = zero
        rr.seed(&r, seed)
        let (samp, se) = mem.alloc[f64](a, nn + 1usize)
        if se != ok { os.exit(20) }
        if hd.sample_prob(a, &r, xs, ys, nn, samp[0usize..nn]) != ok { os.exit(21) }
        ret hdr_value(a, usize(g[1usize]), usize(g[2usize]), usize(g[3usize]), g[4usize], g[5usize], xs, ys, samp[0usize..nn])
    }
    if kind == 5usize {
        let n = usize(g[3usize])
        let (b, be) = hd.hdrbw(a, g[4usize..4usize + n], g[2usize], i64(g[1usize]), 1000000usize)
        if be != ok { os.exit(22) }
        ret b
    }
    if kind == 7usize || kind == 10usize {
        let n = usize(g[2usize])
        let x = g[3usize..3usize + n]
        let y = g[3usize + n..3usize + 2usize * n]
        let (aa, bb) = hd.cdeband_rules0(x, y)
        if kind == 7usize {
            if g[1usize] == 0.0f64 { ret aa }
            ret bb
        }
        if g[1usize] == 1.0f64 { ret bb }
        let ym = seq_arr(a, min_of(y), max_of(y), 25usize)
        let (ra, re) = hd.cdeband_regress(a, x, y, ym)
        if re != ok { os.exit(23) }
        ret ra
    }
    if kind == 8usize {
        let ix = usize(g[1usize])
        let iy = usize(g[2usize])
        let nx = usize(g[3usize])
        let ny = usize(g[4usize])
        let n = usize(g[5usize])
        let x = g[8usize..8usize + n]
        let y = g[8usize + n..8usize + 2usize * n]
        let xm = g[8usize + 2usize * n..8usize + 2usize * n + nx]
        let ym = g[8usize + 2usize * n + nx..8usize + 2usize * n + nx + ny]
        let z = hd.newf(a, nx * ny)
        if z.len == 0usize { os.exit(24) }
        if hd.cde_z(a, x, y, g[6usize], g[7usize], xm, ym, z) != ok { os.exit(25) }
        ret z[ix * ny + iy]
    }
    if kind == 9usize {
        let n = usize(g[3usize])
        let cd = default_cde(a, g[4usize..4usize + n], g[4usize + n..4usize + 2usize * n])
        ret cd.z[usize(g[1usize]) * 100usize + usize(g[2usize])]
    }
    if kind == 11usize {
        let row = usize(g[1usize])
        let what = usize(g[2usize])
        let ri = usize(g[3usize])
        let k = usize(g[4usize])
        let seed = i64(g[5usize])
        let n = usize(g[6usize])
        let cd = default_cde(a, g[7usize..7usize + n], g[7usize + n..7usize + 2usize * n])
        let z = cd.z
        let ym = cd.ym
        var r: rr.Rng = zero
        rr.seed(&r, seed)
        let (samp, se) = mem.alloc[f64](a, 1001usize)
        if se != ok { os.exit(26) }
        var i = 0usize
        while i <= row {
            var sumz = 0.0f64
            var j = 0usize
            while j < 100usize {
                sumz += z[i * 100usize + j]
                j += 1usize
            }
            if sumz > 0.0f64 {
                if hd.sample_prob(a, &r, ym, z[i * 100usize..i * 100usize + 100usize], 1000usize, samp[0usize..1000usize]) != ok { os.exit(27) }
            }
            i += 1usize
        }
        var w = 0usize
        if what == 1usize { w = 1usize }
        if what == 2usize { w = 2usize }
        ret hdr_value(a, w, ri, k, 0.5f64, 0.95f64, ym, z[row * 100usize..row * 100usize + 100usize], samp[0usize..1000usize])
    }
    if kind == 13usize || kind == 14usize {
        let n = usize(g[3usize])
        let x = g[4usize..4usize + n]
        let y = g[4usize + n..4usize + 2usize * n]
        let ym = seq_arr(a, min_of(y), max_of(y), 25usize)
        var r: rr.Rng = zero
        rr.seed(&r, i64(g[2usize]))
        var ba = 0.0f64
        var bb = 0.0f64
        var be: err = ok
        if kind == 13usize {
            let (p, q, e) = hd.cde_bandwidths_m1(a, &r, x, y, ym)
            ba = p
            bb = q
            be = e
        } else {
            let (p, q, e) = hd.cde_bandwidths_m4(a, &r, x, y, ym)
            ba = p
            bb = q
            be = e
        }
        if be != ok { os.exit(29) }
        if g[1usize] == 0.0f64 { ret ba }
        ret bb
    }
    if kind == 12usize || kind == 15usize {
        let what = usize(g[1usize])
        let p = usize(g[2usize])
        let i = usize(g[3usize])
        let deg = usize(g[4usize])
        let np = usize(g[5usize])
        let start_q = g[6usize] == 1.0f64
        let nxf = usize(g[7usize])
        var aa = g[8usize]
        var bb = g[9usize]
        let n = usize(g[10usize])
        let x = g[11usize..11usize + n]
        let y = g[11usize + n..11usize + 2usize * n]
        if kind == 15usize {
            let ym = seq_arr(a, min_of(y), max_of(y), 25usize)
            var r: rr.Rng = zero
            rr.seed(&r, i64(g[8usize]))
            let (ha, hb, he) = hd.cde_bandwidths_m1(a, &r, x, y, ym)
            if he != ok { os.exit(30) }
            aa = ha
            bb = hb
        }
        let xmin = min_of(x)
        let xmax = max_of(x)
        let ymin = min_of(y)
        let ymax = max_of(y)
        if what == 2usize { ret 1.0f64 / (10.0f64 * ((xmax - xmin) * (ymax - ymin))) }
        let x0 = hd.seqat(xmin, xmax, i, nxf)
        var y0 = hd.seqat(ymin, ymax, p, np)
        if start_q {
            let (s, se) = mem.alloc[f64](a, n + 1usize)
            if se != ok { os.exit(28) }
            var q = 0usize
            while q < n {
                s[q] = y[q]
                q += 1usize
            }
            hd.sort_f64(s[0usize..n])
            y0 = rd.quant7(s[0usize..n], f64(p) * (1.0f64 / f64(np - 1usize)))
        }
        let fit = hd.modal_fit(x, y, x0, y0, aa, bb, deg, 30usize)
        if what == 0usize { ret fit }
        ret hd.kde2d_point(x, y, x0, fit, aa, bb)
    }
    ret nan()
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hdrcdepkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = run_case(a, c)
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
