// R gbm's R layer over the engine in gbmfit: gbm() and gbm.fit() with their data preparation (the weights rescaled to mean one, the coxph rows put in decreasing time within the
// training and the held-out part, the multinomial rows with a first example of every class in front and the response spread over the classes), train.fraction, cross-validation
// (the folds drawn with sample(), one seed per fold, the held-out error summed over the folds), predict at any number of trees, gbm.perf for "test" and "cv", relative.influence and gbm.more.
//
// Not here: the loess smoother of gbm.perf(method = "OOB"), offsets, categorical predictors.

use e.math
use e.mem
use e.algo.rand.r as rng
use e.algo.stat.gbmfit as gb

error BadInput

type Input = struct {
    dist: usize, n: usize, p: usize, ntrees: usize, shrinkage: f64, depth: usize, minobs: usize, bag: f64, trainfrac: f64,
    par: f64, maxrank: usize, cv: usize, ncores1: bool, stratify: bool,
    x: []const f64, y: []const f64, status: []const f64, w: []const f64, group: []const f64, mono: []const f64
}

type Fitted = struct {
    sp: gb.Spec, m: gb.Model, n: usize, nclass: usize, ntrain: usize, dist: usize, trainfrac: f64,
    fit: []f64, perm: []usize, cv_error: []f64, cv_fitted: []f64, has_cv: bool
}

// the response and weights of an already ordered training set, boosted: gbm.fit
fn fit_rows(a: *mem.Arena, rg: *rng.Rng, cf: *const Input, x: []const f64, y: []const f64, status: []const f64, wraw: []const f64, n: usize, ntrain: usize) -> (Fitted, err) {
    var bad = 0usize
    var fd: Fitted = zero
    if f64(ntrain) * cf.bag <= 2.0f64 * f64(cf.minobs) + 1.0f64 { ret (fd, BadInput) }
    if cf.depth < 1usize || cf.depth > 49usize { ret (fd, BadInput) }
    let w0 = gb.af(a, n, &bad)
    var i = 0usize
    var sw = 0.0f64
    if wraw.len == n {
        sw = gb.rsum(wraw, n)
        while i < n {
            w0[i] = wraw[i] * f64(n) / sw
            i += 1usize
        }
    } else {
        while i < n {
            w0[i] = 1.0f64
            i += 1usize
        }
    }
    let perm = gb.au(a, n, &bad)
    i = 0usize
    while i < n {
        perm[i] = i
        i += 1usize
    }
    var nclass = 1usize
    var xs = gb.af(a, n * cf.p, &bad)
    var ys = gb.af(a, n, &bad)
    var ms = gb.af(a, n, &bad)
    var ws = gb.af(a, n, &bad)
    let key = gb.af(a, n, &bad)
    let tmp = gb.au(a, n, &bad)
    if bad != 0usize { ret (fd, gb.NoMemory) }
    if cf.dist == 8usize {
        // coxph: decreasing time within the training rows and within the rest
        i = 0usize
        while i < n {
            key[i] = 0.0f64 - y[i]
            i += 1usize
        }
        msort_range(key, perm, tmp, 0usize, ntrain)
        msort_range(key, perm, tmp, ntrain, n)
    }
    if cf.dist == 9usize {
        var kmax = 0usize
        i = 0usize
        while i < n {
            if usize(y[i]) + 1usize > kmax { kmax = usize(y[i]) + 1usize }
            i += 1usize
        }
        nclass = kmax
        if nclass > ntrain { ret (fd, BadInput) }
        // the first row of every class goes in front, the rest follow in order
        let used = gb.au(a, n, &bad)
        if bad != 0usize { ret (fd, gb.NoMemory) }
        var k = 0usize
        var at = 0usize
        while k < nclass {
            i = 0usize
            while i < n {
                if usize(y[i]) == k {
                    perm[at] = i
                    used[i] = 1usize
                    at += 1usize
                    break
                }
                i += 1usize
            }
            k += 1usize
        }
        i = 0usize
        while i < n {
            if used[i] == 0usize {
                perm[at] = i
                at += 1usize
            }
            i += 1usize
        }
    }
    var j = 0usize
    while j < cf.p {
        i = 0usize
        while i < n {
            xs[j * n + i] = x[j * n + perm[i]]
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        ys[i] = y[perm[i]]
        ws[i] = w0[perm[i]]
        if status.len == n { ms[i] = status[perm[i]] }
        i += 1usize
    }
    var yy = ys
    var ww = ws
    if cf.dist == 9usize {
        yy = gb.af(a, n * nclass, &bad)
        ww = gb.af(a, n * nclass, &bad)
        if bad != 0usize { ret (fd, gb.NoMemory) }
        var k = 0usize
        while k < nclass {
            i = 0usize
            while i < n {
                if usize(ys[i]) == k {
                    yy[k * n + i] = 1.0f64
                } else {
                    yy[k * n + i] = 0.0f64
                }
                ww[k * n + i] = ws[i]
                i += 1usize
            }
            k += 1usize
        }
    }
    var mono = gb.af(a, cf.p, &bad)
    if cf.mono.len == cf.p {
        j = 0usize
        while j < cf.p {
            mono[j] = cf.mono[j]
            j += 1usize
        }
    }
    var alpha = 0.0f64
    var nu = 0.0f64
    if cf.dist == 5usize { alpha = cf.par }
    if cf.dist == 7usize { nu = cf.par }
    let sp = gb.Spec{ dist: cf.dist, n: n, p: cf.p, ntrain: ntrain, nclass: nclass, ntrees: cf.ntrees, shrinkage: cf.shrinkage, depth: cf.depth, minobs: cf.minobs, bag: cf.bag,
        alpha: alpha, nu: nu, maxrank: cf.maxrank, ngroups: 0usize, x: xs, y: yy, w: ww, misc: ms, mono: mono }
    let (m, fe) = gb.fit(a, &sp, rg, fd.fit)
    if fe != ok { ret (fd, fe) }
    fd.sp = sp
    fd.m = m
    fd.n = n
    fd.nclass = nclass
    fd.ntrain = ntrain
    fd.dist = cf.dist
    fd.trainfrac = cf.trainfrac
    fd.perm = perm
    fd.has_cv = false
    let fo = gb.af(a, n * nclass, &bad)
    if bad != 0usize { ret (fd, gb.NoMemory) }
    i = 0usize
    while i < n * nclass {
        fo[i] = m.f[i]
        i += 1usize
    }
    if cf.dist == 8usize {
        i = 0usize
        while i < n {
            fo[perm[i]] = m.f[i]
            i += 1usize
        }
    }
    fd.fit = fo
    ret (fd, ok)
}

// a stable sort of idx[lo..hi] by key[idx[i]]
fn msort_range(key: []const f64, idx: []usize, tmp: []usize, lo: usize, hi: usize) {
    if hi <= lo { ret }
    gb.msort(key, idx[lo..hi], tmp, hi - lo)
}

// getCVgroup: the fold of every training row, drawn with sample(rep(1:folds, length = n))
fn cv_groups(a: *mem.Arena, rg: *rng.Rng, cf: *const Input, y: []const f64, ntrain: usize, group: []usize) -> err {
    let folds = cf.cv
    if cf.dist == 9usize || (cf.dist == 1usize && cf.stratify) {
        // stratified: within every class sample(rep(1:folds, length = class size))
        var kmax = 0usize
        var i = 0usize
        while i < ntrain {
            if usize(y[i]) + 1usize > kmax { kmax = usize(y[i]) + 1usize }
            i += 1usize
        }
        var k = 0usize
        while k < kmax {
            var cnt = 0usize
            i = 0usize
            while i < ntrain {
                if usize(y[i]) == k { cnt += 1usize }
                i += 1usize
            }
            if cnt == 0usize {
                k += 1usize
                continue
            }
            let (pm, pe) = rng.sample_int(a, rg, i64(cnt), i64(cnt), false)
            if pe != ok { ret pe }
            var at = 0usize
            i = 0usize
            while i < ntrain {
                if usize(y[i]) == k {
                    group[i] = (usize(pm[at]) - 1usize) % folds + 1usize
                    at += 1usize
                }
                i += 1usize
            }
            k += 1usize
        }
        ret ok
    }
    let (pm, pe) = rng.sample_int(a, rg, i64(ntrain), i64(ntrain), false)
    if pe != ok { ret pe }
    var i = 0usize
    while i < ntrain {
        group[i] = (usize(pm[i]) - 1usize) % folds + 1usize
        i += 1usize
    }
    ret ok
}

// gbm(): train.fraction and cross-validation around fit_rows. With n.cores = 1 every fold reseeds the one generator (so the final fit continues from the last fold's stream); otherwise the folds run on their own generators
fn gbm(a: *mem.Arena, rg: *rng.Rng, cf: *const Input) -> (Fitted, err) {
    let n = cf.n
    var bad = 0usize
    let ntrain = usize(math.floor[f64](cf.trainfrac * f64(n)))
    var cvfit: []f64 = zero
    var cverr: []f64 = zero
    var has = false
    if cf.cv > 1usize {
        has = true
        let folds = cf.cv
        let group = gb.au(a, ntrain, &bad)
        let seeds = gb.af(a, folds, &bad)
        let sizes = gb.af(a, folds, &bad)
        cverr = gb.af(a, cf.ntrees, &bad)
        cvfit = gb.af(a, ntrain, &bad)
        let ord = gb.au(a, ntrain, &bad)
        let key = gb.af(a, ntrain, &bad)
        let xs = gb.af(a, ntrain * cf.p, &bad)
        let ys = gb.af(a, ntrain, &bad)
        let ss = gb.af(a, ntrain, &bad)
        let wsub = gb.af(a, ntrain, &bad)
        let xp = gb.af(a, ntrain * cf.p, &bad)
        let pr = gb.af(a, ntrain, &bad)
        if bad != 0usize { ret (zero_fit(), gb.NoMemory) }
        let ce = cv_groups(a, rg, cf, cf.y, ntrain, group)
        if ce != ok { ret (zero_fit(), ce) }
        var k = 0usize
        while k < folds {
            seeds[k] = rng.runif(rg, 0.0f64 - 2147483647.0f64, 2147483648.0f64)
            k += 1usize
        }
        var i = 0usize
        while i < ntrain {
            sizes[group[i] - 1usize] += 1.0f64
            i += 1usize
        }
        let (models, me) = mem.alloc[Fitted](a, folds)
        if me != ok { ret (zero_fit(), me) }
        var other: rng.Rng = zero
        k = 0usize
        while k < folds {
            // the fold's rows: those outside the fold first, the fold's own last, each in order
            let kk = k + 1usize
            var at = 0usize
            i = 0usize
            while i < ntrain {
                if group[i] != kk {
                    ord[at] = i
                    at += 1usize
                }
                i += 1usize
            }
            let nin = at
            i = 0usize
            while i < ntrain {
                if group[i] == kk {
                    ord[at] = i
                    at += 1usize
                }
                i += 1usize
            }
            var j = 0usize
            while j < cf.p {
                i = 0usize
                while i < ntrain {
                    xs[j * ntrain + i] = cf.x[j * n + ord[i]]
                    i += 1usize
                }
                j += 1usize
            }
            i = 0usize
            while i < ntrain {
                ys[i] = cf.y[ord[i]]
                if cf.status.len == n { ss[i] = cf.status[ord[i]] }
                if cf.w.len == n { wsub[i] = cf.w[ord[i]] }
                i += 1usize
            }
            var ws2: []f64 = zero
            if cf.w.len == n { ws2 = wsub }
            var ss2: []f64 = zero
            if cf.status.len == n { ss2 = ss }
            let seed = i64(seeds[k])
            var fe = ok
            var fdk: Fitted = zero
            if cf.ncores1 {
                rng.seed(rg, seed)
                let (r1, e1) = fit_rows(a, rg, cf, xs, ys, ss2, ws2, ntrain, nin)
                fdk = r1
                fe = e1
            } else {
                rng.seed(&other, seed)
                let (r1, e1) = fit_rows(a, &other, cf, xs, ys, ss2, ws2, ntrain, nin)
                fdk = r1
                fe = e1
            }
            if fe != ok { ret (zero_fit(), fe) }
            models[k] = fdk
            k += 1usize
        }
        var t = 0usize
        while t < cf.ntrees {
            k = 0usize
            while k < folds {
                key[k] = models[k].m.valid_err[t] * sizes[k]
                k += 1usize
            }
            cverr[t] = gb.rsum(key, folds) / f64(ntrain)
            t += 1usize
        }
        let nbest = which_min(cverr, cf.ntrees)
        if models[0].nclass == 1usize {
            k = 0usize
            while k < folds {
                let kk = k + 1usize
                var cnt = 0usize
                i = 0usize
                while i < ntrain {
                    if group[i] == kk {
                        ord[cnt] = i
                        cnt += 1usize
                    }
                    i += 1usize
                }
                var j = 0usize
                while j < cf.p {
                    i = 0usize
                    while i < cnt {
                        xp[j * cnt + i] = cf.x[j * n + ord[i]]
                        i += 1usize
                    }
                    j += 1usize
                }
                gb.predict_link(&models[k].m, xp, cnt, nbest, pr)
                i = 0usize
                while i < cnt {
                    cvfit[ord[i]] = pr[i]
                    i += 1usize
                }
                k += 1usize
            }
        }
    }
    let (fd, fe) = fit_rows(a, rg, cf, cf.x, cf.y, cf.status, cf.w, n, ntrain)
    if fe != ok { ret (fd, fe) }
    var out = fd
    out.cv_error = cverr
    out.cv_fitted = cvfit
    out.has_cv = has
    ret (out, ok)
}

fn zero_fit() -> Fitted {
    var z: Fitted = zero
    ret z
}

// predict.gbm on the link scale with the first use_trees trees
fn predict(f: *const Fitted, xnew: []const f64, nn: usize, use_trees: usize, out: []f64) {
    gb.predict_link(&f.m, xnew, nn, use_trees, out)
}

// predict.gbm(type = "response"): the link-scale values passed through the loss's inverse link (class probabilities for multinomial, row by row)
fn to_response(dist: usize, nclass: usize, nn: usize, out: []f64) {
    var i = 0usize
    if dist == 1usize {
        while i < nn * nclass {
            out[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - out[i]))
            i += 1usize
        }
    }
    if dist == 2usize {
        while i < nn * nclass {
            out[i] = math.exp[f64](out[i])
            i += 1usize
        }
    }
    if dist == 3usize {
        while i < nn * nclass {
            out[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - 2.0f64 * out[i]))
            i += 1usize
        }
    }
    if dist == 9usize {
        var r = 0usize
        while r < nn {
            var s = 0.0f64
            var k = 0usize
            while k < nclass {
                out[k * nn + r] = math.exp[f64](out[k * nn + r])
                s += out[k * nn + r]
                k += 1usize
            }
            k = 0usize
            while k < nclass {
                out[k * nn + r] = out[k * nn + r] / s
                k += 1usize
            }
            r += 1usize
        }
    }
}

// which.min over a prefix of the sequence, 1-based, the first of the smallest
fn which_min(v: []const f64, m: usize) -> usize {
    var best = 0usize
    var bv = 0.0f64 / 0.0f64
    var t = 0usize
    while t < m {
        if v[t] == v[t] && (bv != bv || v[t] < bv) {
            bv = v[t]
            best = t + 1usize
        }
        t += 1usize
    }
    ret best
}

// gbm.perf(method = "test") and (method = "cv"): the number of trees that minimises the held-out and the cross-validated error
fn best_iter_test(f: *const Fitted) -> usize { ret which_min(f.m.valid_err, f.m.ntrees) }
fn best_iter_cv(f: *const Fitted) -> usize { ret which_min(f.cv_error, f.m.ntrees) }

// the tree count predict() and relative.influence() take when none is given: the held-out minimum, else the cross-validated one, else every tree
fn default_trees(f: *const Fitted) -> usize {
    if f.trainfrac < 1.0f64 { ret best_iter_test(f) }
    if f.has_cv { ret best_iter_cv(f) }
    ret f.m.ntrees
}

// relative.influence(f, n.trees): the summed improvements, unscaled
fn relative_influence(a: *mem.Arena, f: *const Fitted, use_trees: usize, out: []f64) -> err {
    var bad = 0usize
    let scr = gb.af(a, f.m.stride + use_trees * f.nclass + 1usize, &bad)
    if bad != 0usize { ret gb.NoMemory }
    gb.rel_inf(&f.m, use_trees, out, scr)
    ret ok
}

// gbm.more: nnew more trees continuing from the fit and from the generator's stream
fn more(a: *mem.Arena, rg: *rng.Rng, f: *const Fitted, nnew: usize) -> (Fitted, err) {
    var sp2 = f.sp
    sp2.ntrees = nnew
    let (m2, e2) = gb.fit(a, &sp2, rg, f.m.f)
    if e2 != ok { ret (zero_fit(), e2) }
    var bad = 0usize
    let nc = f.nclass
    let tot = (f.m.ntrees + nnew) * nc
    let old = f.m.ntrees * nc
    let st = f.m.stride
    var m = f.m
    m.ntrees = f.m.ntrees + nnew
    m.train_err = gb.af(a, m.ntrees, &bad)
    m.valid_err = gb.af(a, m.ntrees, &bad)
    m.oobag = gb.af(a, m.ntrees, &bad)
    m.nnodes = gb.au(a, tot, &bad)
    m.tvar = gb.ai(a, tot * st, &bad)
    m.tcode = gb.af(a, tot * st, &bad)
    m.tleft = gb.ai(a, tot * st, &bad)
    m.tright = gb.ai(a, tot * st, &bad)
    m.tmiss = gb.ai(a, tot * st, &bad)
    m.terr = gb.af(a, tot * st, &bad)
    m.twt = gb.af(a, tot * st, &bad)
    m.tpred = gb.af(a, tot * st, &bad)
    if bad != 0usize { ret (zero_fit(), gb.NoMemory) }
    var i = 0usize
    while i < f.m.ntrees {
        m.train_err[i] = f.m.train_err[i]
        m.valid_err[i] = f.m.valid_err[i]
        m.oobag[i] = f.m.oobag[i]
        i += 1usize
    }
    i = 0usize
    while i < nnew {
        m.train_err[f.m.ntrees + i] = m2.train_err[i]
        m.valid_err[f.m.ntrees + i] = m2.valid_err[i]
        m.oobag[f.m.ntrees + i] = m2.oobag[i]
        i += 1usize
    }
    i = 0usize
    while i < tot {
        if i < old {
            m.nnodes[i] = f.m.nnodes[i]
        } else {
            m.nnodes[i] = m2.nnodes[i - old]
        }
        var q = 0usize
        while q < st {
            if i < old {
                m.tvar[i * st + q] = f.m.tvar[i * st + q]
                m.tcode[i * st + q] = f.m.tcode[i * st + q]
                m.tleft[i * st + q] = f.m.tleft[i * st + q]
                m.tright[i * st + q] = f.m.tright[i * st + q]
                m.tmiss[i * st + q] = f.m.tmiss[i * st + q]
                m.terr[i * st + q] = f.m.terr[i * st + q]
                m.twt[i * st + q] = f.m.twt[i * st + q]
                m.tpred[i * st + q] = f.m.tpred[i * st + q]
            } else {
                let j = (i - old) * st + q
                m.tvar[i * st + q] = m2.tvar[j]
                m.tcode[i * st + q] = m2.tcode[j]
                m.tleft[i * st + q] = m2.tleft[j]
                m.tright[i * st + q] = m2.tright[j]
                m.tmiss[i * st + q] = m2.tmiss[j]
                m.terr[i * st + q] = m2.terr[j]
                m.twt[i * st + q] = m2.twt[j]
                m.tpred[i * st + q] = m2.tpred[j]
            }
            q += 1usize
        }
        i += 1usize
    }
    m.f = m2.f
    var out = *f
    out.m = m
    out.sp = sp2
    let fo = gb.af(a, f.n * nc, &bad)
    if bad != 0usize { ret (zero_fit(), gb.NoMemory) }
    i = 0usize
    while i < f.n * nc {
        fo[i] = m.f[i]
        i += 1usize
    }
    if f.dist == 8usize {
        i = 0usize
        while i < f.n {
            fo[f.perm[i]] = m.f[i]
            i += 1usize
        }
    }
    out.fit = fo
    ret (out, ok)
}
