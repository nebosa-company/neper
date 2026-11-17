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
