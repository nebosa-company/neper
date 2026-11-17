// e.algo.stat.signaldsp against signal. tests/oracle/signaldsp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R signaldsp`; the layout of each case is in scripts/r_oracle/groups/signaldsp.R.

use e.algo.stat.signaldsp as sd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn alloc_f(a: *mem.Arena, n: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { os.exit(5) }
    ret v
}

fn answer_two(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "win") {
        let n = usize(x[1usize])
        let o = alloc_f(a, n)
        if sd.window(a, usize(x[0usize]), n, x[2usize], o) != ok { os.exit(7) }
        ret wsum(o)
    }
    if str.eq(k, "fzr") || str.eq(k, "fzi") {
        let mode = usize(x[0usize])
        let nb = usize(x[1usize])
        let na = usize(x[2usize])
        let n = usize(x[3usize])
        let b = x[4usize..4usize + nb]
        let aa = x[4usize + nb..4usize + nb + na]
        let w = x[4usize + nb + na..4usize + nb + na + 5usize]
        var cnt = n
        if mode >= 2usize { cnt = 5usize }
        let hr = alloc_f(a, cnt)
        let hi = alloc_f(a, cnt)
        if mode == 0usize { sd.freqz_grid(b, aa, n, false, hr, hi) }
        if mode == 1usize { sd.freqz_grid(b, aa, n, true, hr, hi) }
        if mode == 2usize { sd.freqz_points(b, aa, w, hr, hi) }
        if mode == 3usize { sd.freqs_points(b, aa, w, hr, hi) }
        if str.eq(k, "fzr") { ret wsum(hr) }
        ret wsum(hi)
    }
    if str.eq(k, "gd") {
        let nb = usize(x[0usize])
        let na = usize(x[1usize])
        let n = usize(x[2usize])
        var len = n
        if x[3usize] < 0.5f64 { len = n }
        let g = alloc_f(a, 2usize * n)
        if sd.grpdelay(a, x[4usize..4usize + nb], x[4usize + nb..4usize + nb + na], n, x[3usize] > 0.5f64, g) != ok { os.exit(7) }
        var cnt = n
        if x[3usize] > 0.5f64 { cnt = n }
        ret wsum(g[0usize..cnt])
    }
    if str.eq(k, "imz") || str.eq(k, "imzn") {
        let nb = usize(x[0usize])
        let na = usize(x[1usize])
        var n = usize(x[2usize])
        let b = x[3usize..3usize + nb]
        let aa = x[3usize + nb..3usize + nb + na]
        if n == 0usize { n = sd.impz_length(a, b, aa) }
        if str.eq(k, "imzn") { ret f64(n) }
        let o = alloc_f(a, n)
        sd.impz(b, aa, n, o)
        ret wsum(o)
    }
    if str.eq(k, "sgr") || str.eq(k, "sgi") || str.eq(k, "sgf") || str.eq(k, "sgt") || str.eq(k, "sgd") {
        let len = usize(x[0usize])
        let n = usize(x[1usize])
        let ws = usize(x[3usize])
        let win = alloc_f(a, ws)
        var kind = 0usize
        if x[2usize] > 0.5f64 { kind = 1usize }
        if sd.window(a, kind, ws, 0.0f64, win) != ok { os.exit(7) }
        let sre = alloc_f(a, len * n)
        let sim = alloc_f(a, len * n)
        let f = alloc_f(a, n)
        let t = alloc_f(a, len)
        let (count, retn, e) = sd.specgram(a, x[6usize..6usize + len], n, x[5usize], win, usize(x[4usize]), sre, sim, f, t)
        if e != ok { os.exit(8) }
        if str.eq(k, "sgr") { ret wsum(sre[0usize..count * retn]) }
        if str.eq(k, "sgi") { ret wsum(sim[0usize..count * retn]) }
        if str.eq(k, "sgf") { ret wsum(f[0usize..retn]) }
        if str.eq(k, "sgt") { ret wsum(t[0usize..count]) }
        ret f64(retn * 1000usize + count)
    }
    if str.eq(k, "unw") {
        let len = usize(x[1usize])
        let o = alloc_f(a, len)
        sd.unwrap_tol(x[2usize..2usize + len], x[0usize], o)
        ret wsum(o)
    }
    if str.eq(k, "lva") || str.eq(k, "lvv") || str.eq(k, "lvr") {
        let p = usize(x[0usize])
        let len = usize(x[1usize])
        let acf = x[2usize..2usize + len]
        var pp = p
        if pp >= len { pp = len - 1usize }
        let aa = alloc_f(a, pp + 1usize)
        let rf = alloc_f(a, pp)
        let v = sd.levinson(acf, pp, aa, rf)
        if str.eq(k, "lvv") { ret v }
        if str.eq(k, "lvr") { ret wsum(rf) }
        // a = c(1, a)
        var s = 1.0f64
        var i = 0usize
        while i < pp {
            s += aa[i] * f64(i + 2usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(k, "fli") {
        let nb = usize(x[0usize])
        let na = usize(x[1usize])
        let len = usize(x[2usize])
        let nix = usize(x[3usize])
        let niy = usize(x[4usize])
        let b = x[5usize..5usize + nb]
        let aa = x[5usize + nb..5usize + nb + na]
        let xs = x[5usize + nb + na..5usize + nb + na + len]
        let ix = x[5usize + nb + na + len..5usize + nb + na + len + nix]
        let iy = x[5usize + nb + na + len + nix..5usize + nb + na + len + nix + niy]
        let rev = alloc_f(a, niy + 1usize)
        var i = 0usize
        while i < niy {
            rev[i] = iy[niy - 1usize - i]
            i += 1usize
        }
        let o = alloc_f(a, len)
        sd.filter_init(b, aa, xs, ix, rev[0usize..niy], o)
        ret wsum(o)
    }
    if str.eq(k, "cnv") {
        let nb = usize(x[0usize])
        let len = usize(x[1usize])
        let o = alloc_f(a, nb + len - 1usize)
        sd.conv(x[2usize..2usize + nb], x[2usize + nb..2usize + nb + len], o)
        ret wsum(o)
    }
    if str.eq(k, "fft") {
        let nb = usize(x[0usize])
        let len = usize(x[1usize])
        let o = alloc_f(a, len)
        sd.fftfilt(x[2usize..2usize + nb], x[2usize + nb..2usize + nb + len], o)
        ret wsum(o)
    }
    ret answer_three(a, c)
}

fn zero_nan(v: []f64) {
    var i = 0usize
    while i < v.len {
        if v[i] != v[i] { v[i] = 0.0f64 }
        i += 1usize
    }
}

fn answer_three(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "rmz") {
        let n = usize(x[0usize])
        let nf = usize(x[3usize])
        let o = alloc_f(a, n + 1usize)
        if sd.remez(a, n, x[4usize..4usize + 2usize * nf], x[4usize + 2usize * nf..4usize + 4usize * nf], x[4usize + 4usize * nf..4usize + 5usize * nf], usize(x[1usize]), usize(x[2usize]), o) != ok { os.exit(7) }
        ret wsum(o)
    }
    if str.eq(k, "f1") || str.eq(k, "f1n") {
        let n = usize(x[0usize])
        let nw = usize(x[5usize])
        let win = alloc_f(a, n + 1usize)
        if sd.window(a, usize(x[2usize]), n + 1usize, x[3usize], win) != ok { os.exit(7) }
        let o = alloc_f(a, n + 2usize)
        let (len, e) = sd.fir1(a, n, x[6usize..6usize + nw], usize(x[1usize]), win, x[4usize] > 0.5f64, o)
        if e != ok { os.exit(8) }
        if str.eq(k, "f1n") { ret f64(len) }
        ret wsum(o[0usize..len])
    }
    if str.eq(k, "f2") {
        let n = usize(x[0usize])
        let nf = usize(x[5usize])
        let win = alloc_f(a, n + 1usize)
        if sd.window(a, usize(x[3usize]), n + 1usize, x[4usize], win) != ok { os.exit(7) }
        let o = alloc_f(a, n + 1usize)
        if sd.fir2(a, n, x[6usize..6usize + nf], x[6usize + nf..6usize + 2usize * nf], usize(x[1usize]), x[2usize], win, o) != ok { os.exit(8) }
        ret wsum(o)
    }
    if str.eq(k, "rs") || str.eq(k, "rsn") {
        let p = usize(x[0usize])
        let q = usize(x[1usize])
        let d = usize(x[2usize])
        let len = usize(x[3usize])
        let cnt = sd.resample_length(len, p, q)
        if str.eq(k, "rsn") { ret f64(cnt) }
        let o = alloc_f(a, cnt)
        if sd.resample(a, x[4usize..4usize + len], p, q, d, o) != ok { os.exit(8) }
        ret wsum(o)
    }
    if str.eq(k, "dcm") {
        let q = usize(x[1usize])
        let len = usize(x[3usize])
        let o = alloc_f(a, (len + q - 1usize) / q)
        if sd.decimate(a, x[4usize..4usize + len], q, usize(x[2usize]), usize(x[0usize]), o) != ok { os.exit(8) }
        ret wsum(o)
    }
    if str.eq(k, "ipo") {
        let q = usize(x[0usize])
        let len = usize(x[3usize])
        let o = alloc_f(a, len * q)
        if sd.interp(a, x[4usize..4usize + len], q, usize(x[1usize]), x[2usize], o) != ok { os.exit(8) }
        ret wsum(o)
    }
    if str.eq(k, "i1") {
        let nx = usize(x[1usize])
        let nxi = usize(x[2usize])
        let o = alloc_f(a, nxi)
        if sd.interp1(a, x[3usize..3usize + nx], x[3usize + nx..3usize + 2usize * nx], x[3usize + 2usize * nx..3usize + 2usize * nx + nxi], usize(x[0usize]), o) != ok { os.exit(8) }
        zero_nan(o)
        ret wsum(o)
    }
    if str.eq(k, "sgm") {
        let n = usize(x[1usize])
        let o = alloc_f(a, n * n)
        if sd.sgolay(a, usize(x[0usize]), n, usize(x[2usize]), x[3usize], o) != ok { os.exit(8) }
        ret wsum(o)
    }
    if str.eq(k, "sfl") || str.eq(k, "sfd") {
        var p = 3usize
        var n = 5usize
        var m = 0usize
        var ts = 1.0f64
        var len = usize(x[0usize])
        var at = 1usize
        if str.eq(k, "sfl") {
            p = usize(x[0usize])
            n = usize(x[1usize])
            m = usize(x[2usize])
            ts = x[3usize]
            len = usize(x[4usize])
            at = 5usize
        }
        let o = alloc_f(a, len)
        if sd.sgolayfilt(a, x[at..at + len], p, n, m, ts, o) != ok { os.exit(8) }
        ret wsum(o)
    }
    if str.eq(k, "bon") || str.eq(k, "boc") || str.eq(k, "bot") || str.eq(k, "con") || str.eq(k, "cot") || str.eq(k, "eon") || str.eq(k, "eot") {
        let nw = usize(x[0usize])
        let wp = x[1usize..1usize + nw]
        let ws = x[1usize + nw..1usize + 2usize * nw]
        let rp = x[1usize + 2usize * nw]
        let rs = x[2usize + 2usize * nw]
        let wc = alloc_f(a, 2usize)
        var n = 0usize
        var ty = 0usize
        if str.eq(k, "bon") || str.eq(k, "boc") || str.eq(k, "bot") {
            let (n1, t1) = sd.buttord(wp, ws, rp, rs, wc)
            n = n1
            ty = t1
            if str.eq(k, "boc") { ret wsum(wc[0usize..nw]) }
        } else if str.eq(k, "con") || str.eq(k, "cot") {
            let (n2, t2) = sd.cheb1ord(wp, ws, rp, rs)
            n = n2
            ty = t2
        } else {
            let (n3, t3) = sd.ellipord(wp, ws, rp, rs)
            ty = t3
            if str.eq(k, "eon") { ret n3 }
        }
        if str.eq(k, "bot") || str.eq(k, "cot") || str.eq(k, "eot") { ret f64(ty) }
        ret f64(n)
    }
    if str.eq(k, "kon") || str.eq(k, "kob") || str.eq(k, "kow") || str.eq(k, "kot") {
        let nf = usize(x[1usize])
        let nm = nf / 2usize + 1usize
        let w = alloc_f(a, 4usize)
        let (n, ty, beta) = sd.kaiserord(x[2usize..2usize + nf], x[2usize + nf..2usize + nf + nm], x[2usize + nf + nm], x[0usize], w)
        if str.eq(k, "kon") { ret f64(n) }
        if str.eq(k, "kob") { ret beta }
        if str.eq(k, "kot") { ret f64(ty) }
        ret wsum(w[0usize..nf / 2usize])
    }
    if str.eq(k, "chp") {
        let len = usize(x[5usize])
        let o = alloc_f(a, len)
        sd.chirp(x[6usize..6usize + len], x[1usize], x[2usize], x[3usize], usize(x[0usize]), x[4usize], o)
        ret wsum(o)
    }
    if str.eq(k, "spc") {
        let len = usize(x[0usize])
        let o = alloc_f(a, len)
        sd.spencer(x[1usize..1usize + len], o)
        zero_nan(o)
        ret wsum(o)
    }
    if str.eq(k, "rtr") || str.eq(k, "rti") {
        let nc = usize(x[0usize])
        let re = alloc_f(a, nc)
        let im = alloc_f(a, nc)
        let deg = sd.roots(a, x[1usize..1usize + nc], re, im)
        if deg < 0i64 { os.exit(8) }
        if str.eq(k, "rtr") { ret wsum(re[0usize..usize(deg)]) }
        ret wsum(im[0usize..usize(deg)])
    }
    if str.eq(k, "zb") || str.eq(k, "za") {
        let nz = usize(x[0usize])
        let np = usize(x[1usize])
        let g = x[2usize]
        let zr = alloc_f(a, 2usize * nz)
        let zi = alloc_f(a, 2usize * nz)
        let pr = alloc_f(a, 2usize * np)
        let pim = alloc_f(a, 2usize * np)
        var i = 0usize
        while i < nz {
            zr[i] = x[3usize + i]
            zr[nz + i] = x[3usize + i]
            zi[i] = x[3usize + nz + i]
            zi[nz + i] = 0.0f64 - x[3usize + nz + i]
            i += 1usize
        }
        i = 0usize
        while i < np {
            pr[i] = x[3usize + 2usize * nz + i]
            pr[np + i] = x[3usize + 2usize * nz + i]
            pim[i] = x[3usize + 2usize * nz + np + i]
            pim[np + i] = 0.0f64 - x[3usize + 2usize * nz + np + i]
            i += 1usize
        }
        let b = alloc_f(a, 2usize * nz + 1usize)
        let aa = alloc_f(a, 2usize * np + 1usize)
        sd.zpg_to_arma(zr, zi, pr, pim, g, b, aa)
        if str.eq(k, "zb") { ret wsum(b) }
        ret wsum(aa)
    }
    os.exit(9)
    ret 0.0f64
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "db") || str.eq(k, "da") {
        let n = usize(x[2usize])
        let nw = usize(x[5usize])
        var len = n + 1usize
        if nw == 2usize { len = 2usize * n + 1usize }
        let (b, e1) = mem.alloc[f64](a, len)
        if e1 != ok { os.exit(5) }
        let (aa, e2) = mem.alloc[f64](a, len)
        if e2 != ok { os.exit(6) }
        if sd.design(usize(x[0usize]), n, x[3usize], x[4usize], x[6usize..6usize + nw], usize(x[1usize]), true, b, aa) != ok { os.exit(7) }
        if str.eq(k, "db") { ret wsum(b) }
        ret wsum(aa)
    }
    ret answer_two(a, c)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/signaldsp.json")
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
