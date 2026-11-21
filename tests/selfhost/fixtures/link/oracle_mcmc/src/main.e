// e.algo.stat.mcmcpkg against mcmc 0.9-8 under set.seed. tests/oracle/mcmc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmc`; the layout is at the top of scripts/r_oracle/groups/mcmc.R.

use e.algo.rand.r as rng
use e.algo.stat.mcmcpkg as mc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// position-weighted sum of the non-NaN entries
fn wsum(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] == x[i] { s += f64(i + 1usize) * x[i] }
        i += 1usize
    }
    ret s
}

fn nans(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] != x[i] { s += 1.0f64 }
        i += 1usize
    }
    ret s
}

fn is_name(c: *const oracle.Case, n: str) -> bool {
    ret str.eq(c.name, n)
}

// metrop and morph.metrop cases
fn chain(a: *mem.Arena, c: *const oracle.Case, morphed: bool) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = i64(z[0usize])
    let id = usize(z[1usize])
    let d = usize(z[2usize])
    let nb = usize(z[3usize])
    let bl = usize(z[4usize])
    let ns = usize(z[5usize])
    let nb2 = usize(z[6usize])
    var p = 7usize
    var mo = mc.Morph { use_b: false, b: 1.0f64, use_expo: false, r: 0.0f64, p: 3.0f64, center: z[0usize..0usize] }
    if morphed {
        mo.use_b = z[7usize] > 0.5f64
        mo.b = z[8usize]
        mo.use_expo = z[9usize] > 0.5f64
        mo.r = z[10usize]
        mo.p = z[11usize]
        p = 12usize
    }
    let init = z[p..p + d]
    p += d
    if morphed {
        mo.center = z[p..p + d]
        p += d
    }
    let sl = usize(z[p])
    let sc = z[p + 1usize..p + 1usize + sl]
    p += 1usize + sl
    let kind = usize(z[p])
    let ol = usize(z[p + 1usize])
    var enc: [16]f64 = zero
    var ne = 0usize
    if kind > 0usize {
        enc[0usize] = f64(kind)
        var q = 0usize
        while q < ol {
            enc[1usize + q] = z[p + 2usize + q]
            q += 1usize
        }
        ne = 1usize + ol
    }
    let outs = enc[0usize..ne]
    let nout = mc.out_dim(outs, d, morphed)
    let tot = nb + nb2
    let (batch, e1) = mem.alloc[f64](a, tot * nout)
    let (accb, e2) = mem.alloc[f64](a, tot)
    let (fin, e3) = mem.alloc[f64](a, d)
    let (finm, e4) = mem.alloc[f64](a, d)
    let (accall, e5) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    var nlast = nb
    var first = 0usize
    if morphed {
        if mc.morph_metrop(a, &g, id, &mo, init, false, nb, bl, ns, sc, outs, batch, accb, accall, fin, finm) != ok { ret nan }
        if nb2 > 0usize {
            first = nb
            nlast = nb2
            let (cur, e6) = mem.alloc[f64](a, d)
            if e6 != ok { ret nan }
            var q = 0usize
            while q < d {
                cur[q] = finm[q]
                q += 1usize
            }
            if mc.morph_metrop(a, &g, id, &mo, cur, true, nb2, bl, ns, sc, outs, batch[nb * nout..tot * nout], accb[nb..tot], accall, fin, finm) != ok { ret nan }
        }
    } else {
        if mc.metrop(a, &g, id, init, nb, bl, ns, sc, outs, batch, accb, accall, fin) != ok { ret nan }
        if nb2 > 0usize {
            first = nb
            nlast = nb2
            let (cur, e6) = mem.alloc[f64](a, d)
            if e6 != ok { ret nan }
            var q = 0usize
            while q < d {
                cur[q] = fin[q]
                q += 1usize
            }
            if mc.metrop(a, &g, id, cur, nb2, bl, ns, sc, outs, batch[nb * nout..tot * nout], accb[nb..tot], accall, fin) != ok { ret nan }
        }
    }
    if is_name(c, "next") || is_name(c, "mnext") { ret rng.unif(&g) }
    if is_name(c, "batch") || is_name(c, "mbatch") { ret wsum(batch[first * nout..tot * nout]) }
    if is_name(c, "acc") || is_name(c, "macc") { ret wsum(accb[first..tot]) }
    if is_name(c, "accall") || is_name(c, "maccall") { ret accall[0usize] }
    if is_name(c, "mfinm") { ret wsum(finm) }
    ret wsum(fin)
}

fn temper_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = i64(z[0usize])
    let par = z[2usize] > 0.5f64
    let nc = usize(z[3usize])
    let nx = usize(z[4usize])
    let nb = usize(z[5usize])
    let nb2 = usize(z[9usize])
    var p = 11usize
    let beta = z[p..p + nc]
    p += nc
    let cc = z[p..p + nc]
    p += nc
    let neigh = z[p..p + nc * nc]
    p += nc * nc
    var nst = nx + 1usize
    if par { nst = nc * nx }
    let init = z[p..p + nst]
    p += nst
    let scl = z[p..z.len]
    var t = mc.Temper { id: usize(z[1usize]), ncomp: nc, nx: nx, parallel: par, beta: beta, cc: cc, neigh: neigh, scale: scl, scale_list: z[10usize] > 0.5f64, outid: usize(z[8usize]), nbatch: nb, blen: usize(z[6usize]), nspac: usize(z[7usize]) }
    let nout = mc.temper_nout(&t)
    let tot = nb + nb2
    let (w, e1) = mem.alloc[f64](a, tot * nout + tot * nc + nc + nc * nc + 2usize * nst)
    if e1 != ok { ret nan }
    var q = 0usize
    var res = mc.TemperOut { batch: w[q..q + nb * nout], ibatch: w[q..q], acceptx: w[q..q], accepti: w[q..q], fin: w[q..q] }
    q += nb * nout
    res.ibatch = w[q..q + nb * nc]
    q += nb * nc
    res.acceptx = w[q..q + nc]
    q += nc
    res.accepti = w[q..q + nc * nc]
    q += nc * nc
    res.fin = w[q..q + nst]
    q += nst
    let cur = w[q..q + nst]
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    if mc.temper(a, &g, &t, init, &res) != ok { ret nan }
    if nb2 > 0usize {
        var i = 0usize
        while i < nst {
            cur[i] = res.fin[i]
            i += 1usize
        }
        t.nbatch = nb2
        let (w2, e2) = mem.alloc[f64](a, nb2 * nout + nb2 * nc)
        if e2 != ok { ret nan }
        res.batch = w2[0usize..nb2 * nout]
        res.ibatch = w2[nb2 * nout..nb2 * nout + nb2 * nc]
        if mc.temper(a, &g, &t, cur, &res) != ok { ret nan }
    }
    if is_name(c, "tnext") { ret rng.unif(&g) }
    if is_name(c, "tb") { ret wsum(res.batch) }
    if is_name(c, "ti") { ret wsum(res.ibatch) }
    if is_name(c, "tax") { ret wsum(res.acceptx) }
    if is_name(c, "tai") { ret wsum(res.accepti) }
    if is_name(c, "tnan") { ret nans(res.acceptx) + nans(res.accepti) }
    ret wsum(res.fin)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "iseq") {
        let cn = usize(z[0usize])
        let (io2, ie) = mem.alloc[f64](a, 5usize + 3usize * cn)
        if ie != ok { ret nan }
        if mc.initseq(a, z[1usize..1usize + cn], io2) != ok { ret nan }
        let j = usize(z[1usize + cn])
        let m = usize(io2[1usize])
        var jmap = 0usize
        if j == 1usize { jmap = 2usize }
        if j == 2usize { jmap = 3usize }
        if j == 3usize { jmap = 4usize }
        if j <= 3usize { ret io2[jmap] }
        if j == 4usize { ret f64(m) }
        var sm = 0.0f64
        var t = 0usize
        while t < m {
            sm += io2[5usize + (j - 5usize) * m + t]
            t += 1usize
        }
        ret sm
    }
    if str.eq(c.name, "olbm") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let (v, ev) = mem.alloc[f64](a, p * p)
        if ev != ok { ret nan }
        if mc.olbm(a, z[6usize..6usize + n * p], n, p, usize(z[2usize]), z[3usize] > 0.5f64, v) != ok { ret nan }
        ret v[usize(z[4usize]) + p * usize(z[5usize])]
    }
    if str.eq(c.name, "mtr") || str.eq(c.name, "minv") || str.eq(c.name, "mjac") {
        let d = usize(z[5usize])
        let mo = mc.Morph { use_b: z[0usize] > 0.5f64, b: z[1usize], use_expo: z[2usize] > 0.5f64, r: z[3usize], p: z[4usize], center: z[6usize..6usize + d] }
        let x = z[6usize + d..6usize + 2usize * d]
        let (o, eo) = mem.alloc[f64](a, d)
        if eo != ok { ret nan }
        if str.eq(c.name, "mjac") { ret mc.morph_logjac(&mo, x) }
        if str.eq(c.name, "mtr") { mc.morph_transform(&mo, x, o) } else { mc.morph_inverse(&mo, x, o) }
        ret wsum(o)
    }
    if str.eq(c.name, "tb") || str.eq(c.name, "ti") || str.eq(c.name, "tax") || str.eq(c.name, "tai") || str.eq(c.name, "tnan") || str.eq(c.name, "tf") || str.eq(c.name, "tnext") { ret temper_case(a, c) }
    let morphed = str.eq(c.name, "mbatch") || str.eq(c.name, "macc") || str.eq(c.name, "maccall") || str.eq(c.name, "mfin") || str.eq(c.name, "mfinm") || str.eq(c.name, "mnext")
    ret chain(a, c, morphed)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmc.json")
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
