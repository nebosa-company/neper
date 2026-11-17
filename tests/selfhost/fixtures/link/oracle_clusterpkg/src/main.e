// e.algo.stat.clusterpkg (pam, clara, daisy, silhouette) and e.algo.stat.clustertree (agnes, diana, mona) against cluster 2.1.8.2. tests/oracle/clusterpkg.json
// and clustertree.json come from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clusterpkg clustertree`; the argument layout of each case is at the top
// of scripts/r_oracle/groups/clusterpkg.R and clustertree.R. Every answer is one number, mostly a position-weighted checksum of a result vector.

use e.algo.rand.r as rng
use e.algo.stat.clusterfuzzy as fz
use e.algo.stat.clusterhull as hl
use e.algo.stat.clusterpkg as cp
use e.algo.stat.clustertree as ct
use e.algo.stat.hclust as hc
use e.math
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

fn sum_i(v: []const i64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(v[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

// agnes (method 1..7) and diana (method 0): args (n, p, metric, stand, method, npar, par..., kcut, x column-major)
fn twins_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let metric = usize(x[2usize])
    let stand = x[3usize] != 0.0f64
    let method = usize(x[4usize])
    let np = usize(x[5usize])
    let kcut = usize(x[6usize + np])
    let data = take_matrix(a, x, 7usize + np, n * p)
    if stand { cp.stand_data(data, n, p) }
    let (jtmd, e1) = mem.alloc[i64](a, p)
    if e1 != ok { os.exit(5) }
    let (valmd, e2) = mem.alloc[f64](a, p)
    if e2 != ok { os.exit(5) }
    let _ = cp.na_prepare(data, n, p, jtmd, valmd)
    let (dys, e3) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
    if e3 != ok { os.exit(5) }
    if cp.dysta(data, n, p, dys, metric, jtmd, valmd) != 0usize { os.exit(6) }
    var fit: ct.TwinsFit = zero
    if str.starts_with(c.name, "agnes_") {
        let (alpha, e4) = mem.alloc[f64](a, 4usize)
        if e4 != ok { os.exit(5) }
        if !ct.par_method(method, x[6usize..6usize + np], np, alpha) { os.exit(6) }
        let (f1, e5) = ct.agnes(a, dys, n, method, alpha)
        if e5 != ok { ret 0.0f64 / 0.0f64 }
        fit = f1
    } else {
        let (f2, e6) = ct.diana(a, dys, n)
        if e6 != ok { ret 0.0f64 / 0.0f64 }
        fit = f2
    }
    let w = c.name
    if str.ends_with(w, "_height") { ret sum_f(fit.height) }
    if str.ends_with(w, "_order") { ret sum_u(fit.order) }
    if str.ends_with(w, "_merge") {
        var s = 0.0f64
        var i = 0usize
        while i < n - 1usize {
            s += f64(fit.merge_a[i]) * f64(i + 1usize) + f64(fit.merge_b[i]) * f64(n - 1usize + i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.ends_with(w, "_coef") { ret fit.coef }
    if str.ends_with(w, "_coefhclust") {
        let (ch, e0) = ct.coef_hclust(a, &fit)
        if e0 != ok { os.exit(5) }
        ret ch
    }
    if str.ends_with(w, "_coefhier") {
        let (cf, e7) = ct.coef_hier(a, fit.height)
        if e7 != ok { os.exit(5) }
        ret cf
    }
    if str.ends_with(w, "_cutree") {
        let (tree, e8) = ct.to_tree(a, &fit)
        if e8 != ok { os.exit(5) }
        let (lab, e9) = mem.alloc[usize](a, n)
        if e9 != ok { os.exit(5) }
        if hc.cutree(a, &tree, n, kcut, lab) != ok { os.exit(5) }
        ret sum_u(lab)
    }
    os.exit(9)
    ret 0.0f64
}

// mona: args (n, p, x column-major with 0, 1, NA = 2)
fn mona_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let (m, e1) = mem.alloc[i64](a, n * p)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n * p {
        m[i] = i64(x[2usize + i])
        i += 1usize
    }
    let (fit, e2) = ct.mona(a, m, n, p)
    if e2 != ok { os.exit(5) }
    if fit.jerr != 0usize { os.exit(6) }
    let w = c.name
    if str.eq(w, "mona_order") { ret sum_u(fit.order) }
    if str.eq(w, "mona_variable") { ret sum_u(fit.variable) }
    if str.eq(w, "mona_step") { ret sum_u(fit.step) }
    if str.eq(w, "mona_data") { ret sum_i(fit.data) }
    os.exit(9)
    ret 0.0f64
}

// daisy: args (n, p, metric, stand, types(p), weights(p), x column-major codes, NA = -999999)
fn daisy_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let metric = usize(x[2usize])
    let stand = x[3usize] != 0.0f64
    let (types, e1) = mem.alloc[usize](a, p)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < p {
        types[i] = usize(x[4usize + i])
        i += 1usize
    }
    let data = take_matrix(a, x, 4usize + 2usize * p, n * p)
    let (d, e2) = mem.alloc[f64](a, n * n)
    if e2 != ok { os.exit(5) }
    if cp.daisy(a, data, n, p, types, x[4usize + p..4usize + 2usize * p], metric, stand, d) != ok { os.exit(6) }
    var s = 0.0f64
    var pos = 1usize
    var col = 0usize
    while col < n {
        var row = col + 1usize
        while row < n {
            s += d[row * n + col] * f64(pos)
            pos += 1usize
            row += 1usize
        }
        col += 1usize
    }
    ret s
}

// silhouette: args (n, k, ismat, cluster(n), x(n by 2 column-major))
fn sil_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let k = usize(x[1usize])
    let ismat = x[2usize] != 0.0f64
    let (cl, e1) = mem.alloc[usize](a, n)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        cl[i] = usize(x[3usize + i])
        i += 1usize
    }
    let off = 3usize + n
    let (d, e2) = mem.alloc[f64](a, n * n)
    if e2 != ok { os.exit(5) }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[off + i] - x[off + j]
            let dy = x[off + n + i] - x[off + n + j]
            d[i * n + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    var dv = d
    if !ismat {
        let (v, e3) = mem.alloc[f64](a, n * (n - 1usize) / 2usize)
        if e3 != ok { os.exit(5) }
        var at = 0usize
        var col = 0usize
        while col < n {
            var row = col + 1usize
            while row < n {
                v[at] = d[row * n + col]
                at += 1usize
                row += 1usize
            }
            col += 1usize
        }
        dv = v
    }
    let (si, e4) = mem.alloc[f64](a, n)
    if e4 != ok { os.exit(5) }
    let (nb, e5) = mem.alloc[usize](a, n)
    if e5 != ok { os.exit(5) }
    if cp.sildist(a, dv, n, cl, k, ismat, si, nb) != ok { os.exit(6) }
    if str.eq(c.name, "sil_width") { ret sum_f(si) }
    ret sum_u(nb)
}

// fanny: args (n, p, k, metric, stand, memb.exp, tol, maxit, hasini, diss, x column-major, ini column-major when hasini)
fn fanny_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let k = usize(x[2usize])
    let metric = usize(x[3usize])
    let stand = x[4usize] != 0.0f64
    let r = x[5usize]
    let tol = x[6usize]
    let maxit = usize(x[7usize])
    let hasini = x[8usize] != 0.0f64
    let diss = x[9usize] != 0.0f64
    let data = take_matrix(a, x, 10usize, n * p)
    if stand && !diss { cp.stand_data(data, n, p) }
    let (jtmd, e1) = mem.alloc[i64](a, p)
    if e1 != ok { os.exit(5) }
    let (valmd, e2) = mem.alloc[f64](a, p)
    if e2 != ok { os.exit(5) }
    let _ = cp.na_prepare(data, n, p, jtmd, valmd)
    var ini: []const f64 = x[10usize + n * p..]
    var dss: []f64 = zero
    if diss {
        let (v, e3) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
        if e3 != ok { os.exit(5) }
        if fz.dysta3(data, n, p, v, 1usize, jtmd, valmd) != 0usize { os.exit(6) }
        dss = v
    }
    let (fit, e4) = fz.fanny(a, dss, diss, data, n, p, k, jtmd, valmd, metric, r, tol, maxit, ini, hasini, true)
    if e4 != ok { os.exit(7) }
    let w = c.name
    if str.eq(w, "fanny_memb") { ret sum_f(fit.memb) }
    if str.eq(w, "fanny_dunn") { ret fit.dunn }
    if str.eq(w, "fanny_norm") { ret fit.normalized }
    if str.eq(w, "fanny_obj") { ret fit.obj }
    if str.eq(w, "fanny_kcrisp") { ret f64(fit.k_crisp) }
    if str.eq(w, "fanny_clu") { ret sum_u(fit.clu) }
    if str.eq(w, "fanny_iter") { ret f64(fit.iter) }
    if str.eq(w, "fanny_ttsil") { ret fit.ttsil }
    if str.eq(w, "fanny_avsil") { ret sum_f(fit.avsil) }
    if str.eq(w, "fanny_sil") { ret sum_f(fit.silinf[2usize * n..3usize * n]) }
    if str.eq(w, "fanny_silnb") { ret sum_f(fit.silinf[n..2usize * n]) }
    os.exit(9)
    ret 0.0f64
}

// ellipsoidhull: args (n, p, tol, maxit, x column-major)
fn hull_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let (fit, e1) = hl.ellipsoidhull(a, x[4usize..], n, p, x[2usize], usize(x[3usize]))
    if e1 != ok { os.exit(5) }
    let w = c.name
    if str.eq(w, "hull_loc") { ret sum_f(fit.loc) }
    if str.eq(w, "hull_cov") { ret sum_f(fit.cov) }
    if str.eq(w, "hull_d2") { ret fit.d2 }
    if str.eq(w, "hull_eps") { ret fit.eps }
    if str.eq(w, "hull_it") { ret f64(fit.it) }
    if str.eq(w, "hull_conv") {
        if fit.conv { ret 1.0f64 }
        ret 0.0f64
    }
    let (lv, e2) = hl.log_volume(a, fit.cov, fit.d2, p)
    if e2 != ok { os.exit(5) }
    ret lv
}

// clusGap with pam: args (n, p, K.max, B, d.power, pca, seed, x column-major)
fn gap_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let kmax = usize(x[2usize])
    var rg: rng.Rng = zero
    rng.seed(&rg, i64(x[6usize]))
    let (fit, e1) = hl.clus_gap(a, x[7usize..], n, p, kmax, usize(x[3usize]), x[4usize], x[5usize] != 0.0f64, &rg)
    if e1 != ok { os.exit(5) }
    let w = c.name
    if str.eq(w, "gap_logw") { ret sum_f(fit.tab[0usize..kmax]) }
    if str.eq(w, "gap_elogw") { ret sum_f(fit.tab[kmax..2usize * kmax]) }
    if str.eq(w, "gap_gap") { ret sum_f(fit.tab[2usize * kmax..3usize * kmax]) }
    if str.eq(w, "gap_se") { ret sum_f(fit.tab[3usize * kmax..4usize * kmax]) }
    var which = 0usize
    if str.eq(w, "gap_maxse1") { which = 1usize }
    if str.eq(w, "gap_maxse2") { which = 2usize }
    if str.eq(w, "gap_maxse3") { which = 3usize }
    if str.eq(w, "gap_maxse4") { which = 4usize }
    if str.eq(w, "gap_maxse5") { which = 5usize }
    if which == 0usize { os.exit(9) }
    ret f64(hl.max_se(fit.tab[2usize * kmax..3usize * kmax], fit.tab[3usize * kmax..4usize * kmax], which, 1.0f64))
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.starts_with(c.name, "hull_") { ret hull_case(a, c) }
    if str.starts_with(c.name, "gap_") { ret gap_case(a, c) }
    if str.starts_with(c.name, "fanny_") { ret fanny_case(a, c) }
    if str.starts_with(c.name, "agnes_") || str.starts_with(c.name, "diana_") { ret twins_case(a, c) }
    if str.starts_with(c.name, "mona_") { ret mona_case(a, c) }
    if str.starts_with(c.name, "daisy_") { ret daisy_case(a, c) }
    if str.starts_with(c.name, "sil_") { ret sil_case(a, c) }
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

fn run(a: *mem.Arena, path: str) -> usize {
    let (golden, load_error) = oracle.load(a, path)
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
    ret failures
}

fn main(a: *mem.Arena, args: []str) -> err {
    var failures = run(a, "tests/oracle/clusterpkg.json")
    failures += run(a, "tests/oracle/clustertree.json")
    failures += run(a, "tests/oracle/clusterfuzzy.json")
    failures += run(a, "tests/oracle/clusterhull.json")
    if failures > 0usize { os.exit(1) }
    ret ok
}
