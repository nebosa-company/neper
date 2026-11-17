// e.algo.stat.clusterpkg (pam, clara, daisy, silhouette) against cluster 2.1.8.2. tests/oracle/clusterpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clusterpkg`; the argument layout of each case is at the top of
// scripts/r_oracle/groups/clusterpkg.R. Every answer is one number, mostly a position-weighted checksum of a result vector.

use e.algo.rand.r as rng
use e.algo.stat.clusterpkg as cp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn say(a: *mem.Arena, v: f64) -> err {
    let (initial, builder_error) = str.builder(a, 40usize)
    if builder_error != ok { ret builder_error }
    var b = initial
    let _ = str.push_f64(&b, v)
    ret io.print(str.done(&b))
}

fn sum_u(v: []const usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(v[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn sum_f(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

// the data of a case: n by p column-major starting at args[off], -999999 meaning NA
fn take_matrix(a: *mem.Arena, x: []const f64, off: usize, count: usize) -> []f64 {
    let (m, e) = mem.alloc[f64](a, count)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < count {
        m[i] = x[off + i]
        if m[i] < 0.0f64 - 999000.0f64 { m[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    ret m
}

fn pam_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let k = usize(x[2usize])
    let pamonce = usize(x[3usize])
    let metric = usize(x[4usize])
    let seed = x[5usize]
    let ng = usize(x[6usize])
    let (given, e0) = mem.alloc[usize](a, k + ng)
    if e0 != ok { os.exit(5) }
    var i = 0usize
    while i < ng {
        given[i] = usize(x[7usize + i])
        i += 1usize
    }
    var has_given = ng > 0usize
    let data = take_matrix(a, x, 7usize + ng, n * p)
    let (jtmd, e1) = mem.alloc[i64](a, p)
    if e1 != ok { os.exit(5) }
    let (valmd, e2) = mem.alloc[f64](a, p)
    if e2 != ok { os.exit(5) }
    let _ = cp.na_prepare(data, n, p, jtmd, valmd)
    let (dys, e3) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
    if e3 != ok { os.exit(5) }
    if cp.dysta(data, n, p, dys, metric, jtmd, valmd) != 0usize { os.exit(6) }
    if seed >= 0.0f64 {
        var rg: rng.Rng = zero
        rng.seed(&rg, i64(seed))
        let (draw, e4) = rng.sample_int(a, &rg, i64(n), i64(k), false)
        if e4 != ok { os.exit(7) }
        i = 0usize
        while i < k {
            given[i] = usize(draw[i])
            i += 1usize
        }
        has_given = true
    }
    let (fit, e5) = cp.pam(a, dys, n, k, given, has_given, true, pamonce, true)
    if e5 != ok { os.exit(8) }
    let w = c.name
    if str.eq(w, "pam_build") { ret fit.obj_build }
    if str.eq(w, "pam_swap") { ret fit.obj_swap }
    if str.eq(w, "pam_med") { ret sum_u(fit.med) }
    if str.eq(w, "pam_clu") { ret sum_u(fit.clu) }
    if str.eq(w, "pam_isol") { ret sum_u(fit.isol) }
    if str.eq(w, "pam_clusinf") { ret sum_f(fit.clusinf) }
    if str.eq(w, "pam_ttsil") { ret fit.ttsil }
    if str.eq(w, "pam_avsil") { ret sum_f(fit.avsil) }
    if str.eq(w, "pam_sil") { ret sum_f(fit.silinfo[2usize * n..3usize * n]) }
    if str.eq(w, "pam_silnb") { ret sum_f(fit.silinfo[n..2usize * n]) }
    os.exit(9)
    ret 0.0f64
}

fn clara_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let k = usize(x[2usize])
    let samples = usize(x[3usize])
    let sampsize = usize(x[4usize])
    let metric = usize(x[5usize])
    let rng_r = x[6usize] != 0.0f64
    let seed = i64(x[7usize])
    let pam_like = x[8usize] != 0.0f64
    let correct = x[9usize] != 0.0f64
    let stand = x[10usize] != 0.0f64
    let data = take_matrix(a, x, 11usize, n * p)
    if stand { cp.stand_data(data, n, p) }
    let (jtmd, e1) = mem.alloc[i64](a, p)
    if e1 != ok { os.exit(5) }
    let (valmd, e2) = mem.alloc[f64](a, p)
    if e2 != ok { os.exit(5) }
    let has_na = cp.na_prepare(data, n, p, jtmd, valmd)
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let (fit, e3) = cp.clara(a, data, n, p, k, samples, sampsize, has_na, valmd, jtmd, metric, rng_r, &rg, pam_like, correct)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    if fit.jstop != 0usize { os.exit(7) }
    let w = c.name
    if str.eq(w, "clara_obj") { ret fit.obj }
    if str.eq(w, "clara_clu") { ret sum_u(fit.clu) }
    if str.eq(w, "clara_med") { ret sum_u(fit.med) }
    if str.eq(w, "clara_sample") { ret sum_u(fit.sample) }
    if str.eq(w, "clara_size") { ret sum_u(fit.size) }
    if str.eq(w, "clara_maxdis") { ret sum_f(fit.maxdis) }
    if str.eq(w, "clara_avdis") { ret sum_f(fit.avdis) }
    if str.eq(w, "clara_ratdis") { ret sum_f(fit.ratdis) }
    if str.eq(w, "clara_ttsil") { ret fit.ttsil }
    if str.eq(w, "clara_avsil") { ret sum_f(fit.avsil) }
    if str.eq(w, "clara_sil") { ret sum_f(fit.silinf[2usize * sampsize..3usize * sampsize]) }
    if str.eq(w, "clara_silnb") { ret sum_f(fit.silinf[sampsize..2usize * sampsize]) }
    os.exit(9)
    ret 0.0f64
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.starts_with(c.name, "pam_") { ret pam_case(a, c) }
    if str.starts_with(c.name, "clara_") { ret clara_case(a, c) }
    os.exit(4)
    ret 0.0f64
}

fn report(a: *mem.Arena, c: *const oracle.Case, got: f64) {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret }
    var b = initial
    let _ = str.push(&b, c.name)
    var h = 0usize
    while h < c.args.len && h < 11usize {
        let _ = str.push(&b, " ")
        let _ = str.push_f64(&b, c.args[h])
        h += 1usize
    }
    let _ = str.push(&b, ": got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    let _ = io.print(str.done(&b))
    let _ = io.print("\n")
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clusterpkg.json")
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
            if failures <= 12usize { report(a, c, got) }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
