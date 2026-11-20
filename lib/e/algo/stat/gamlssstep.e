// R gamlss stepGAIC for main-effect terms: add and drop searches of one parameter's terms with the penalty k, each candidate refitted from scratch by
// e.algo.stat.gamlssfit as update() does. The model path and the final term list are the result.

use e.algo.stat.gamlssfit as gf
use e.math
use e.mem

type Step = struct {
    nterms: usize,
    terms: []usize,
    npath: usize,
    change: []i64,
    gaic: []f64,
    df: []f64,
    dev: []f64,
}

// extractAIC(fit, k = k) of the model whose parameter `what` has the intercept and the candidate columns terms[0..nt]: (df, GAIC), NaN when the fit fails
fn gaic_of(a: *mem.Arena, fam: usize, algo: usize, y: []const f64, w: []const f64, fixed: []const f64, fncol: []const usize, link: []const usize, what: usize, cand: []const f64, terms: []const usize, nt: usize, k: f64) -> (f64, f64, f64) {
    let n = y.len
    let mark = mem.mark(a)
    var ncol: [3]usize = zero
    var j = 0usize
    var tot = 0usize
    while j < 3usize {
        ncol[j] = fncol[j]
        if j == what { ncol[j] = 1usize + nt }
        tot += ncol[j]
        j += 1usize
    }
    let (xs, e1) = mem.alloc[f64](a, n * tot + 1usize)
    let (off, e2) = mem.alloc[f64](a, 4usize * n)
    let (st, e3) = mem.alloc[f64](a, 4usize * n)
    let (hs, e4) = mem.alloc[usize](a, 3usize)
    let (stp, e5) = mem.alloc[f64](a, 3usize)
    let nan = 0.0f64 / 0.0f64
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok {
        mem.reset(a, mark)
        ret (nan, nan, nan)
    }
    var i = 0usize
    while i < 4usize * n {
        off[i] = 0.0f64
        st[i] = 0.0f64
        i += 1usize
    }
    j = 0usize
    while j < 3usize {
        hs[j] = 0usize
        stp[j] = 1.0f64
        j += 1usize
    }
    var at = 0usize
    var src = 0usize
    j = 0usize
    while j < 3usize {
        if j == what {
            i = 0usize
            while i < n {
                xs[at + i] = 1.0f64
                i += 1usize
            }
            at += n
            var t = 0usize
            while t < nt {
                i = 0usize
                while i < n {
                    xs[at + i] = cand[terms[t] * n + i]
                    i += 1usize
                }
                at += n
                t += 1usize
            }
        } else {
            i = 0usize
            while i < n * fncol[j] {
                xs[at + i] = fixed[src + i]
                i += 1usize
            }
            at += n * fncol[j]
        }
        src += n * fncol[j]
        j += 1usize
    }
    let (o, fe) = gf.fit_model(a, fam, algo, y, w, xs, ncol[0usize..3usize], link, off, st, hs, stp, 0.001f64, 20usize, 0.001f64, 50usize, true, 1usize, 20usize)
    if fe != ok {
        mem.reset(a, mark)
        ret (nan, nan, nan)
    }
    let df = o.df
    let dv = o.gdev
    mem.reset(a, mark)
    ret (df, dv + k * df, dv)
}

// stepGAIC(object, scope = list(lower, upper), direction, k): fixed holds the three parameters' design columns one after the other (fncol columns each, the entry of
// `what` is ignored), cand the q candidate columns, init the starting terms, lower and upper flag each candidate; direction 0 both, 1 backward, 2 forward
fn step_gaic(a: *mem.Arena, fam: usize, algo: usize, y: []const f64, w: []const f64, fixed: []const f64, fncol: []const usize, link: []const usize, what: usize, cand: []const f64, q: usize, init: []const usize, ninit: usize, lower: []const usize, upper: []const usize, direction: usize, k: f64, maxsteps: usize) -> (Step, err) {
    var out: Step = zero
    let (terms, e1) = mem.alloc[usize](a, q + 2usize)
    let (trial, e2) = mem.alloc[usize](a, q + 2usize)
    let (change, e3) = mem.alloc[i64](a, maxsteps + 2usize)
    let (gaic, e4) = mem.alloc[f64](a, maxsteps + 2usize)
    let (dfs, e5) = mem.alloc[f64](a, maxsteps + 2usize)
    let (devs, e6) = mem.alloc[f64](a, maxsteps + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (out, mem.Full) }
    var nt = ninit
    var i = 0usize
    while i < ninit {
        terms[i] = init[i]
        i += 1usize
    }
    let backward = direction == 0usize || direction == 1usize
    let forward = direction == 0usize || direction == 2usize
    let (df0, g0, d0) = gaic_of(a, fam, algo, y, w, fixed, fncol, link, what, cand, terms, nt, k)
    var np = 1usize
    change[0usize] = 0i64
    gaic[0usize] = g0
    dfs[0usize] = df0
    devs[0usize] = d0
    var cur = g0
    var steps = maxsteps
    var go = true
    while steps > 0usize && go {
        steps -= 1usize
        let before = cur
        // the candidates: row 0 is <none>, then the drops in term order, then the additions in scope order
        var best = 0i64
        var bestg = cur
        var have_best = false
        var ndrop = 0usize
        if backward {
            var t = 0usize
            while t < nt {
                if lower[terms[t]] == 0usize {
                    var m = 0usize
                    var u = 0usize
                    while u < nt {
                        if u != t {
                            trial[m] = terms[u]
                            m += 1usize
                        }
                        u += 1usize
                    }
                    let (df, g, dv) = gaic_of(a, fam, algo, y, w, fixed, fncol, link, what, cand, trial, m, k)
                    ndrop += 1usize
                    // an AIC row only competes when its df differs from the current model's
                    if df == df && df != dfs[np - 1usize] && g == g && (!have_best || g < bestg) && g < cur {
                        best = 0i64 - i64(terms[t] + 1usize)
                        bestg = g
                        have_best = true
                    }
                }
                t += 1usize
            }
        }
        if forward {
            var c = 0usize
            while c < q {
                var present = false
                var u = 0usize
                while u < nt {
                    if terms[u] == c { present = true }
                    u += 1usize
                }
                if upper[c] == 1usize && !present {
                    var m = 0usize
                    u = 0usize
                    while u < nt {
                        trial[m] = terms[u]
                        m += 1usize
                        u += 1usize
                    }
                    trial[m] = c
                    m += 1usize
                    let (df, g, dv) = gaic_of(a, fam, algo, y, w, fixed, fncol, link, what, cand, trial, m, k)
                    if df == df && df != dfs[np - 1usize] && g == g && (!have_best || g < bestg) && g < cur {
                        best = i64(c + 1usize)
                        bestg = g
                        have_best = true
                    }
                }
                c += 1usize
            }
        }
        if !have_best {
            go = false
        } else {
            // apply the best change and refit
            if best < 0i64 {
                let drop_term = usize(0i64 - best) - 1usize
                var m = 0usize
                var u = 0usize
                while u < nt {
                    if terms[u] != drop_term {
                        terms[m] = terms[u]
                        m += 1usize
                    }
                    u += 1usize
                }
                nt = m
            } else {
                terms[nt] = usize(best) - 1usize
                nt += 1usize
            }
            let (df, g, dv) = gaic_of(a, fam, algo, y, w, fixed, fncol, link, what, cand, terms, nt, k)
            if g >= before + 0.0000001f64 {
                go = false
            } else {
                change[np] = best
                gaic[np] = g
                dfs[np] = df
                devs[np] = dv
                np += 1usize
                cur = g
            }
        }
    }
    out = Step { nterms: nt, terms: terms, npath: np, change: change, gaic: gaic, df: dfs, dev: devs }
    ret (out, ok)
}
