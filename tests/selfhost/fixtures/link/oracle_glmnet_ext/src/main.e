// e.algo.stat.glmnet: cox, multinomial, mgaussian, cv, relax and predict against glmnet. tests/oracle/glmnet_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R glmnet_ext`; the case layout is at the top of scripts/r_oracle/groups/glmnet_ext.R.
// Most cases answer a checksum, the sum over every coefficient (or every cvm) of weight(i) times its value, so one case checks a whole fit.

use e.algo.stat.glmnet as gl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 {
    ret 0.0f64 / 0.0f64
}

fn weight(i: usize) -> f64 {
    ret 1.0f64 + f64((i * 7usize) % 13usize) / 13.0f64
}

fn checksum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += weight(i) * v[i]
        i += 1usize
    }
    ret s
}

// the case name, its first four numbers (n, p, alpha, std) and the two answers
fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, be) = str.builder(a, 160usize)
    if be != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, " (")
    var at = 0usize
    while at < 4usize && at < c.args.len {
        if at > 0usize { let _ = str.push(&b, ", ") }
        let _ = str.push_f64(&b, c.args[at])
        at += 1usize
    }
    let _ = str.push(&b, ") fam ")
    var fq = 0.0f64
    if c.args.len > 8usize { fq = c.args[8usize + usize(c.args[4usize]) + usize(c.args[1usize])] }
    let _ = str.push_f64(&b, fq)
    let _ = str.push(&b, " q ")
    let _ = str.push_f64(&b, c.args[c.args.len - 2usize])
    let _ = str.push(&b, ",")
    let _ = str.push_f64(&b, c.args[c.args.len - 1usize])
    let _ = str.push(&b, " got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, " want ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

// The coefficients of one fit as gl.* reports them for every lambda: nl rows of (nc blocks of the intercept and p slopes), on all p variables (excluded ones zero). fam 0 binomial, 1 poisson, 2 gaussian, 3 Cox, 4 multinomial, 5 mgaussian; ya the response (the time for Cox, the labels for
// the multinomial, the n by nc matrix for mgaussian), stat the Cox status, strata and start the Cox extras (empty for none), excl a 0/1 mask over the variables (empty for none). relax answers the gamma blend of the relaxed refits.
fn fit_rows(a: *mem.Arena, gf: bool, fam: usize, relaxf: bool, gamma: f64, efron: bool, grouped: bool, nc: usize, xm: []const f64, ya: []const f64, stat: []const f64, strata: []const f64, start: []const f64, wts: []const f64, off: []const f64, lo: []const f64, up: []const f64, excl: []const f64, n: usize, p: usize, alpha: f64, std: bool, lam: []const f64, vf: []const f64, out: []f64) -> err {
    let nl = lam.len
    var ncs = 1usize
    if fam == 4usize || fam == 5usize { ncs = nc }
    let (xk, e1) = mem.alloc[f64](a, n * p)
    let (vk, e2) = mem.alloc[f64](a, p)
    let (kept, e3) = mem.alloc[usize](a, p)
    let (sm, e4) = mem.alloc[f64](a, nl * ncs * (p + 1usize))
    let (rc, e5) = mem.alloc[f64](a, nl * ncs * (p + 1usize))
    let (lamc, e6) = mem.alloc[f64](a, nl)
    let (lok, e7) = mem.alloc[f64](a, p)
    let (uok, e8) = mem.alloc[f64](a, p)
    let (lab, e9) = mem.alloc[usize](a, n)
    let (cx, e10) = mem.alloc[f64](a, nl * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret e1 }
    let nkp = gl.keep_columns(xm, vf, n, p, excl, xk, vk, kept)
    var sc = 1.0f64
    if excl.len == p { sc = gl.exclude_scale(vf, p, excl, nkp) }
    var k = 0usize
    while k < nl {
        lamc[k] = lam[k] * sc
        k += 1usize
    }
    var q = 0usize
    while q < nkp {
        if lo.len == p {
            lok[q] = lo[kept[q]]
            uok[q] = up[kept[q]]
        }
        q += 1usize
    }
    var lz = lok[0usize..0usize]
    var uz = uok[0usize..0usize]
    if lo.len == p {
        lz = lok[0usize..nkp]
        uz = uok[0usize..nkp]
    }
    let none: []const f64 = zero
    let nodv: []f64 = zero
    var i = 0usize
    while i < n {
        if fam == 4usize { lab[i] = usize(ya[i]) }
        i += 1usize
    }
    var fe = ok
    let xs = xk[0usize..n * nkp]
    let vs = vk[0usize..nkp]
    if fam == 2usize {
        let (ye, e11) = mem.alloc[f64](a, n)
        if e11 != ok { ret e11 }
        i = 0usize
        while i < n {
            ye[i] = ya[i]
            if off.len == n { ye[i] = ya[i] - off[i] }
            i += 1usize
        }
        fe = gl.gaussian(a, xs, ye, wts, lz, uz, n, nkp, alpha, std, vs, lamc, sm)
    }
    if fam == 0usize || fam == 1usize { fe = gl.glm_path_dev(a, fam, xs, ya[0usize..n], wts, off, lz, uz, n, nkp, alpha, std, vs, lamc, sm, nodv) }
    if fam == 3usize {
        fe = gl.cox_ext(a, xs, ya[0usize..n], start, strata, efron, stat, wts, off, lz, uz, n, nkp, alpha, std, vs, lamc, cx, nodv)
        k = 0usize
        while k < nl {
            sm[k * (nkp + 1usize)] = 0.0f64
            var j = 0usize
            while j < nkp {
                sm[k * (nkp + 1usize) + 1usize + j] = cx[k * nkp + j]
                j += 1usize
            }
            k += 1usize
        }
    }
    if fam == 4usize && gf {
        let (dvg, eg1) = mem.alloc[f64](a, nl)
        let (alg, eg2) = mem.alloc[f64](a, nl)
        if eg1 != ok || eg2 != ok { ret eg1 }
        let nfit = gl.glm_multinomial(a, xs, lab, wts, off, lz, uz, n, nkp, nc, alpha, std, grouped, vs, lamc, 100usize, 1.0e-7f64, sm, dvg, alg)
        if nfit != nl { ret eg1 }
        // R centres the intercepts over the classes
        var kg = 0usize
        while kg < nl {
            var mi = 0.0f64
            var cg = 0usize
            while cg < nc {
                mi += sm[(kg * nc + cg) * (nkp + 1usize)]
                cg += 1usize
            }
            cg = 0usize
            while cg < nc {
                sm[(kg * nc + cg) * (nkp + 1usize)] -= mi / f64(nc)
                cg += 1usize
            }
            kg += 1usize
        }
    } else if fam == 4usize {
        fe = gl.multinomial(a, xs, lab, wts, off, lz, uz, n, nkp, nc, alpha, std, grouped, vs, lamc, sm, nodv)
    }
    if fam == 5usize { fe = gl.mgaussian_b(a, xs, ya, wts, lz, uz, n, nkp, nc, alpha, std, vs, lamc, sm) }
    if fe != ok { ret fe }
    if relaxf {
        var re = ok
        if fam <= 3usize { re = gl.relax_path(a, fam, xs, ya[0usize..n], stat, wts, off, n, nkp, sm, nl, rc) }
        if fam == 4usize { re = gl.relax_multi(a, 4usize, xs, lab, none, wts, off, n, nkp, nc, sm, nl, rc) }
        if fam == 5usize { re = gl.relax_multi(a, 5usize, xs, lab, ya, wts, off, n, nkp, nc, sm, nl, rc) }
        if re != ok { ret re }
        gl.relax_blend(sm[0usize..nl * ncs * (nkp + 1usize)], rc[0usize..nl * ncs * (nkp + 1usize)], gamma, sm[0usize..nl * ncs * (nkp + 1usize)])
    }
    gl.scatter_coef(sm, kept, nkp, p, nl * ncs, out)
    ret ok
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let alpha = x[2usize]
    let std = x[3usize] != 0.0f64
    let nl = usize(x[4usize])
    let hw = usize(x[5usize])
    let hb = usize(x[6usize])
    let ho = usize(x[7usize])
    let lam = x[8usize..8usize + nl]
    let vf = x[8usize + nl..8usize + nl + p]
    let d0 = 8usize + nl + p
    let gf = str.eq(c.name, "gfit") || str.eq(c.name, "glam")
    let isfit = str.eq(c.name, "fit") || str.eq(c.name, "lam") || str.eq(c.name, "cv") || gf
    if isfit {
        // data = (fam, relax, gamma, efron, grouped, nc, hasExcl, hasStrata, hasStart), the response (Cox: time, status, strata when hasStrata, start when hasStart; mgaussian: n by nc), exclude[p] when hasExcl
        let fam = usize(x[d0])
        let relaxf = x[d0 + 1usize] != 0.0f64
        let gamma = x[d0 + 2usize]
        let efron = x[d0 + 3usize] != 0.0f64
        let grouped = x[d0 + 4usize] != 0.0f64
        let nc = usize(x[d0 + 5usize])
        let hx = usize(x[d0 + 6usize])
        let hs = usize(x[d0 + 7usize])
        let ht = usize(x[d0 + 8usize])
        let yo = d0 + 9usize
        var yl = n
        if fam == 3usize { yl = 2usize * n + hs * n + ht * n }
        if fam == 5usize { yl = n * nc }
        let ya = x[yo..yo + yl]
        var stat = ya[0usize..0usize]
        var strata = ya[0usize..0usize]
        var start = ya[0usize..0usize]
        if fam == 3usize {
            stat = ya[n..2usize * n]
            if hs == 1usize { strata = ya[2usize * n..3usize * n] }
            if ht == 1usize { start = ya[2usize * n + hs * n..3usize * n + hs * n] }
        }
        let eo = yo + yl
        let excl = x[eo..eo + p * hx]
        let xo = eo + p * hx
        let xm = x[xo..xo + n * p]
        let wo = xo + n * p
        let wts = x[wo..wo + n * hw]
        let bo = wo + n * hw
        let lo = x[bo..bo + p * hb]
        let up = x[bo + p * hb..bo + 2usize * p * hb]
        let oo = bo + 2usize * p * hb
        var oc = 1usize
        if fam == 4usize { oc = nc }
        let off = x[oo..oo + n * ho * oc]
        let qo = oo + n * ho * oc
        var ncs = 1usize
        if fam == 4usize || fam == 5usize { ncs = nc }
        let mt = ya[0usize..n]
        if str.eq(c.name, "fit") || str.eq(c.name, "gfit") {
            let (out, e1) = mem.alloc[f64](a, nl * ncs * (p + 1usize))
            if e1 != ok { ret nan() }
            if fit_rows(a, gf, fam, relaxf, gamma, efron, grouped, nc, xm, ya, stat, strata, start, wts, off, lo, up, excl, n, p, alpha, std, lam, vf, out) != ok { ret nan() }
            ret checksum(out)
        }
        if str.eq(c.name, "glam") && fam == 4usize {
            // glam: glmnet's own multinomial path (the ported algorithm at the default thresh): query 0 the checksum of its lambdas, 1 their number
            let (lab2, ea) = mem.alloc[usize](a, n)
            let (cg, eb) = mem.alloc[f64](a, 100usize * nc * (p + 1usize))
            let (dg, ec) = mem.alloc[f64](a, 100usize)
            let (alg, ed) = mem.alloc[f64](a, 100usize)
            if ea != ok || eb != ok || ec != ok || ed != ok { ret nan() }
            var ii = 0usize
            while ii < n {
                lab2[ii] = usize(ya[ii])
                ii += 1usize
            }
            let noln: []const f64 = zero
            let nfit = gl.glm_multinomial(a, xm, lab2, wts, off, lo, up, n, p, nc, alpha, std, grouped, vf, noln, 100usize, 1.0e-7f64, cg, dg, alg)
            if usize(x[qo]) == 1usize { ret f64(nfit) }
            ret checksum(alg[0usize..nfit])
        }
        // lam: the automatic sequence (query 0: its checksum, 1: its length), cv: see below; excluded variables are dropped and the sequence divided by exclude_scale
        let (xk, e0a) = mem.alloc[f64](a, n * p)
        let (vk, e0b) = mem.alloc[f64](a, p)
        let (kept, e0c) = mem.alloc[usize](a, p)
        if e0a != ok || e0b != ok || e0c != ok { ret nan() }
        let nkp = gl.keep_columns(xm, vf, n, p, excl, xk, vk, kept)
        let xl = xk[0usize..n * nkp]
        let vl = vk[0usize..nkp]
        let pl = nkp
        var scl = 1.0f64
        if excl.len == p { scl = gl.exclude_scale(vf, p, excl, nkp) }
        let (lm, e2) = mem.alloc[f64](a, 100usize)
        if e2 != ok { ret nan() }
        let none: []const f64 = zero
        var nlen = 0usize
        var lerr = ok
        if fam == 2usize {
            let (ye, e3) = mem.alloc[f64](a, n)
            if e3 != ok { ret nan() }
            var i = 0usize
            while i < n {
                ye[i] = ya[i]
                if off.len == n { ye[i] = ya[i] - off[i] }
                i += 1usize
            }
            lerr = gl.lambda_path_w(a, xl, ye, wts, n, pl, alpha, std, vl, 100usize, lm)
            nlen = gl.path_len_w(a, xl, ye, wts, n, pl, alpha, std, vl, 100usize)
        }
        if fam == 0usize || fam == 1usize {
            lerr = gl.glm_lambda_path(a, fam, xl, mt, wts, off, n, pl, alpha, std, vl, 100usize, lm)
            nlen = gl.glm_path_len(a, fam, xl, mt, wts, off, n, pl, alpha, std, vl, 100usize)
        }
        if fam == 3usize {
            lerr = gl.cox_lambda_path_ext(a, xl, mt, start, strata, efron, stat, wts, off, n, pl, alpha, std, vl, 100usize, lm)
            nlen = gl.cox_path_len_ext(a, xl, mt, start, strata, efron, stat, wts, off, lo, up, n, pl, alpha, std, vl, 100usize)
        }
        let (lab, e4) = mem.alloc[usize](a, n)
        if e4 != ok { ret nan() }
        if fam == 4usize {
            var i = 0usize
            while i < n {
                lab[i] = usize(ya[i])
                i += 1usize
            }
            lerr = gl.multinomial_lambda_path(a, xl, lab, wts, off, n, pl, nc, alpha, std, grouped, vl, 100usize, lm)
            nlen = gl.multinomial_path_len(a, xl, lab, wts, off, lo, up, n, pl, nc, alpha, std, grouped, vl, 100usize)
        }
        var qq = 0usize
        while qq < 100usize {
            lm[qq] = lm[qq] / scl
            qq += 1usize
        }
        if lerr != ok { ret nan() }
        if str.eq(c.name, "lam") {
            if usize(x[qo]) == 1usize { ret f64(nlen) }
            ret checksum(lm[0usize..nlen])
        }
        // cv: query = (which, kfrom, nfolds, measure, auto, gammas?, foldid[n]); which 0 the weighted mean cvm over k = kfrom .. (the end, less the last lambda when auto), 1 the same for cvsd, 2 lambda.min, 3 lambda.1se, 4 the number of lambdas, 5 gamma.min, 6 the relaxed lambda.min
        let which = usize(x[qo])
        let kfrom = usize(x[qo + 1usize])
        let nfo = usize(x[qo + 2usize])
        let ms = usize(x[qo + 3usize])
        let au = x[qo + 4usize] != 0.0f64
        let (fid, e5) = mem.alloc[usize](a, n)
        if e5 != ok { ret nan() }
        var q = 0usize
        while q < n {
            fid[q] = usize(x[qo + 5usize + q])
            q += 1usize
        }
        var lamv = lam
        var nl2 = nl
        if au {
            lamv = lm[0usize..nlen]
            nl2 = nlen
        }
        if which == 4usize { ret f64(nlen) }
        let (gm, e6) = mem.alloc[f64](a, 5usize)
        if e6 != ok { ret nan() }
        var ng = 1usize
        gm[0usize] = 1.0f64
        if relaxf {
            ng = 5usize
            gm[0usize] = 0.0f64
            gm[1usize] = 0.25f64
            gm[2usize] = 0.5f64
            gm[3usize] = 0.75f64
            gm[4usize] = 1.0f64
        }
        let (cm, e7) = mem.alloc[f64](a, ng * nl2)
        let (cs, e8) = mem.alloc[f64](a, ng * nl2)
        if e7 != ok || e8 != ok { ret nan() }
        var ce = ok
        var mcode = ms
        if fam == 3usize && ms == 1usize { mcode = 5usize }
        if fam <= 3usize { ce = gl.cv_engine(a, fam, mcode, xm, mt, stat, wts, off, n, p, alpha, std, vf, lamv, fid, nfo, au, relaxf, gm[0usize..ng], cm, cs) }
        if fam == 4usize { ce = gl.cv_multinomial(a, ms, xm, lab, wts, off, n, p, nc, alpha, std, grouped, vf, lamv, fid, nfo, au, relaxf, gm[0usize..ng], cm, cs) }
        if ce != ok { ret nan() }
        var gsel = ng - 1usize
        if relaxf && which <= 1usize { gsel = usize(x[qo + 5usize + n]) }
        let maxi = (fam == 3usize && ms == 1usize) || (fam == 0usize && ms == 4usize)
        if which >= 2usize {
            let (sel, e9) = mem.alloc[f64](a, 2usize)
            if e9 != ok { ret nan() }
            if relaxf && which == 5usize {
                gl.cv_select_relax(lamv, gm[0usize..ng], cm, maxi, sel)
                ret sel[1usize]
            }
            if relaxf && which == 6usize {
                gl.cv_select_relax(lamv, gm[0usize..ng], cm, maxi, sel)
                ret sel[0usize]
            }
            if maxi { gl.cv_select_max(lamv, cm[gsel * nl2..(gsel + 1usize) * nl2], cs[gsel * nl2..(gsel + 1usize) * nl2], sel) } else { gl.cv_select(lamv, cm[gsel * nl2..(gsel + 1usize) * nl2], cs[gsel * nl2..(gsel + 1usize) * nl2], sel) }
            if which == 3usize { ret sel[1usize] }
            ret sel[0usize]
        }
        var kend = nl2
        if au { kend = nl2 - 1usize }
        if kfrom >= kend { ret nan() }
        var sw = 0.0f64
        var sv = 0.0f64
        var kk = kfrom
        while kk < kend {
            var v = cm[gsel * nl2 + kk]
            if which == 1usize { v = cs[gsel * nl2 + kk] }
            sw += weight(kk)
            sv += weight(kk) * v
            kk += 1usize
        }
        ret sv / sw
    }
    if str.eq(c.name, "lseq") {
        // lseq: data = y[n]; query = (nlambda, lambda.min.ratio): the checksum of glmnet(nlambda =, lambda.min.ratio =)'s lambdas up to the number R reports (the last query value)
        let y = x[d0..d0 + n]
        let xm = x[d0 + n..d0 + n + n * p]
        let qo = d0 + n + n * p
        let (l0, e1) = mem.alloc[f64](a, 100usize)
        let (l1, e2) = mem.alloc[f64](a, usize(x[qo]))
        if e1 != ok || e2 != ok { ret nan() }
        if gl.lambda_path(a, xm, y, n, p, alpha, std, vf, 100usize, l0) != ok { ret nan() }
        gl.lambda_seq(l0[0usize], x[qo + 1usize], usize(x[qo]), l1)
        ret checksum(l1[0usize..usize(x[qo + 2usize])])
    }
    if str.eq(c.name, "prd") {
        // prd: data = (family 2 gaussian 0 binomial 1 poisson 3 cox 4 multinomial, nc, rows[nc (p + 1)]), newx (n rows), the offset (n * nc when ho); query = (type 0 link 1 response 2 class 3 nonzero), the answer the checksum over every prediction (class and nonzero as numbers)
        let fm = usize(x[d0])
        let nk = usize(x[d0 + 1usize])
        let rows = x[d0 + 2usize..d0 + 2usize + nk * (p + 1usize)]
        let xo = d0 + 2usize + nk * (p + 1usize)
        let xm = x[xo..xo + n * p]
        let off = x[xo + n * p..xo + n * p + n * ho * nk]
        let kd = usize(x[xo + n * p + n * ho * nk])
        let (out, e1) = mem.alloc[f64](a, n * nk)
        let (lk, e2) = mem.alloc[f64](a, n)
        let (acc, e3) = mem.alloc[f64](a, n * nk + 2usize * p * nk + nk)
        if e1 != ok || e2 != ok || e3 != ok { ret nan() }
        var na = 0usize
        if kd == 3usize {
            var cc = 0usize
            while cc < nk {
                let r = rows[cc * (p + 1usize)..(cc + 1usize) * (p + 1usize)]
                let cnt = gl.nonzero_count(r, p)
                acc[na] = f64(cnt)
                na += 1usize
                var t = 0usize
                while t < cnt {
                    acc[na] = f64(gl.nonzero_at(r, p, t) + 1usize)
                    na += 1usize
                    t += 1usize
                }
                cc += 1usize
            }
            ret checksum(acc[0usize..na])
        }
        if fm == 4usize {
            gl.predict_multinomial(xm, n, p, nk, rows, off, kd, out)
            var cnt = n * nk
            if kd == 2usize { cnt = n }
            var t = 0usize
            while t < cnt {
                var v = out[t]
                if kd == 2usize { v = v + 1.0f64 }
                acc[t] = v
                t += 1usize
            }
            ret checksum(acc[0usize..cnt])
        }
        gl.predict_link(xm, n, p, rows, off, lk)
        if kd == 0usize { ret checksum(lk) }
        if kd == 1usize {
            var rf = fm
            if fm == 3usize { rf = 1usize }
            gl.predict_response(rf, lk, out)
            ret checksum(out[0usize..n])
        }
        gl.predict_class(lk, out)
        ret checksum(out[0usize..n])
    }
    ret nan()
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/glmnet_ext.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
