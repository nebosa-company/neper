// e.algo.stat.glmnet: cox, multinomial, cv, relax and predict against glmnet. tests/oracle/glmnet_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R glmnet_ext`; the case layout is at the top of scripts/r_oracle/groups/glmnet_ext.R.

use e.algo.stat.glmnet as gl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 {
    ret 0.0f64 / 0.0f64
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
    let _ = str.push(&b, ") q ")
    let _ = str.push_f64(&b, c.args[c.args.len - 2usize])
    let _ = str.push(&b, ",")
    let _ = str.push_f64(&b, c.args[c.args.len - 1usize])
    let _ = str.push(&b, " got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, " want ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
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
    var dl = 0usize
    if str.eq(c.name, "cox") || str.eq(c.name, "coxlen") || str.eq(c.name, "coxlam") { dl = 2usize * n }
    var nk = 1usize
    var cmult = false
    if str.eq(c.name, "mult") || str.eq(c.name, "multlen") || str.eq(c.name, "multlam") {
        dl = n + 2usize
        nk = usize(x[d0 + n])
        cmult = true
    }
    var glmfam = 2usize
    var glmq = false
    if str.eq(c.name, "binlen") || str.eq(c.name, "binlam") { glmfam = 0usize }
    if str.eq(c.name, "poislen") || str.eq(c.name, "poislam") { glmfam = 1usize }
    if glmfam < 2usize {
        dl = n
        glmq = true
    }
    var kind = 0usize
    if str.eq(c.name, "cvmult") {
        kind = 1usize
        dl = 2usize * n + 5usize
        nk = usize(x[d0 + n])
    }
    if str.eq(c.name, "cvcox") {
        kind = 2usize
        dl = 3usize * n + 3usize
    }
    if str.eq(c.name, "excg") || str.eq(c.name, "excb") {
        kind = 3usize
        dl = n + p
    }
    if str.eq(c.name, "binb") || str.eq(c.name, "poisb") {
        kind = 4usize
        dl = n
    }
    var rfam = 9usize
    if str.eq(c.name, "rlxg") { rfam = 2usize }
    if str.eq(c.name, "rlxb") { rfam = 0usize }
    if str.eq(c.name, "rlxp") { rfam = 1usize }
    if str.eq(c.name, "rlxc") { rfam = 3usize }
    if rfam < 9usize {
        kind = 5usize
        dl = n
        if rfam == 3usize { dl = 2usize * n }
    }
    if str.eq(c.name, "prd") {
        kind = 6usize
        nk = usize(x[d0 + 2usize])
        dl = 3usize + nk * (p + 1usize)
    }
    if str.eq(c.name, "lseq") {
        kind = 7usize
        dl = n
    }
    var cfam = 9usize
    if str.eq(c.name, "cfg") { cfam = 2usize }
    if str.eq(c.name, "cfb") { cfam = 0usize }
    if str.eq(c.name, "cfp") { cfam = 1usize }
    if cfam < 9usize {
        kind = 8usize
        dl = n
    }
    var cvfam = 3usize
    if str.eq(c.name, "cvgA") { cvfam = 2usize }
    if str.eq(c.name, "cvbA") { cvfam = 0usize }
    if str.eq(c.name, "cvpA") { cvfam = 1usize }
    if cvfam < 3usize { dl = 2usize * n + 2usize }
    let tm = x[d0..d0 + n]
    let st = x[d0 + n..d0 + 2usize * n]
    let xo = d0 + dl
    let xm = x[xo..xo + n * p]
    let wo = xo + n * p
    let wts = x[wo..wo + n * hw]
    let bo = wo + n * hw
    let lo = x[bo..bo + p * hb]
    let up = x[bo + p * hb..bo + 2usize * p * hb]
    let oo = bo + 2usize * p * hb
    let off = x[oo..oo + n * ho * nk]
    let qo = oo + n * ho * nk
    if str.eq(c.name, "cox") {
        let (cf, e1) = mem.alloc[f64](a, nl * p)
        let (dv, e2) = mem.alloc[f64](a, nl)
        if e1 != ok || e2 != ok { ret nan() }
        if gl.cox(a, xm, tm, st, wts, off, lo, up, n, p, alpha, std, vf, lam, cf, dv) != ok { ret nan() }
        ret cf[usize(x[qo]) * p + usize(x[qo + 1usize]) - 1usize]
    }
    if str.eq(c.name, "coxlen") {
        ret f64(gl.cox_path_len(a, xm, tm, st, wts, off, lo, up, n, p, alpha, std, vf, 100usize))
    }
    if str.eq(c.name, "coxlam") {
        let (lo2, e1) = mem.alloc[f64](a, 100usize)
        if e1 != ok { ret nan() }
        if gl.cox_lambda_path(a, xm, tm, st, wts, off, n, p, alpha, std, vf, 100usize, lo2) != ok { ret nan() }
        ret lo2[usize(x[qo])]
    }
    if kind == 1usize {
        // cvmult: data = (class[n] 0-based, K, grouped, foldid[n] 0-based, nfolds, measure, auto); query = (k, which: 0 cvm, 1 cvsd, 2 lambda.min, 3 lambda.1se, 4 the number of lambdas)
        let (lab, e0) = mem.alloc[usize](a, n)
        let (fid, e1) = mem.alloc[usize](a, n)
        let (lam5, e2) = mem.alloc[f64](a, 100usize)
        if e0 != ok || e1 != ok || e2 != ok { ret nan() }
        var q = 0usize
        while q < n {
            lab[q] = usize(tm[q])
            fid[q] = usize(x[d0 + n + 2usize + q])
            q += 1usize
        }
        let grp = x[d0 + n + 1usize] != 0.0f64
        let nfo = usize(x[d0 + 2usize * n + 2usize])
        let ms = usize(x[d0 + 2usize * n + 3usize])
        let au = x[d0 + 2usize * n + 4usize] != 0.0f64
        var lamv = lam
        var nlen = nl
        if au {
            if gl.multinomial_lambda_path(a, xm, lab, wts, off, n, p, nk, alpha, std, grp, vf, 100usize, lam5) != ok { ret nan() }
            nlen = gl.multinomial_path_len(a, xm, lab, wts, off, lo, up, n, p, nk, alpha, std, grp, vf, 100usize)
            lamv = lam5[0usize..nlen]
        }
        if usize(x[qo + 1usize]) == 4usize { ret f64(nlen) }
        let (cm, e3) = mem.alloc[f64](a, nlen)
        let (cs, e4) = mem.alloc[f64](a, nlen)
        if e3 != ok || e4 != ok { ret nan() }
        if gl.cv_multinomial(a, ms, xm, lab, n, p, nk, alpha, std, grp, vf, lamv, fid, nfo, au, cm, cs) != ok { ret nan() }
        let wh = usize(x[qo + 1usize])
        if wh >= 2usize {
            let (sel, e5) = mem.alloc[f64](a, 2usize)
            if e5 != ok { ret nan() }
            gl.cv_select(lamv, cm, cs, sel)
            ret sel[wh - 2usize]
        }
        if usize(x[qo]) >= nlen { ret nan() }
        if wh == 0usize { ret cm[usize(x[qo])] }
        ret cs[usize(x[qo])]
    }
    if kind == 2usize {
        // cvcox: data = (time[n], status[n], foldid[n] 0-based, nfolds, measure 0 deviance 1 C, auto); same query as cvmult
        let (fid, e1) = mem.alloc[usize](a, n)
        let (lam5, e2) = mem.alloc[f64](a, 100usize)
        if e1 != ok || e2 != ok { ret nan() }
        var q = 0usize
        while q < n {
            fid[q] = usize(x[d0 + 2usize * n + q])
            q += 1usize
        }
        let nfo = usize(x[d0 + 3usize * n])
        let ms = usize(x[d0 + 3usize * n + 1usize])
        let au = x[d0 + 3usize * n + 2usize] != 0.0f64
        var lamv = lam
        var nlen = nl
        if au {
            if gl.cox_lambda_path(a, xm, tm, st, wts, off, n, p, alpha, std, vf, 100usize, lam5) != ok { ret nan() }
            nlen = gl.cox_path_len(a, xm, tm, st, wts, off, lo, up, n, p, alpha, std, vf, 100usize)
            lamv = lam5[0usize..nlen]
        }
        if usize(x[qo + 1usize]) == 4usize { ret f64(nlen) }
        let (cm, e3) = mem.alloc[f64](a, nlen)
        let (cs, e4) = mem.alloc[f64](a, nlen)
        if e3 != ok || e4 != ok { ret nan() }
        if gl.cv_cox(a, ms, xm, tm, st, wts, n, p, alpha, std, vf, lamv, fid, nfo, au, cm, cs) != ok { ret nan() }
        let wh = usize(x[qo + 1usize])
        if wh >= 2usize {
            let (sel, e5) = mem.alloc[f64](a, 2usize)
            if e5 != ok { ret nan() }
            if ms == 1usize { gl.cv_select_max(lamv, cm, cs, sel) } else { gl.cv_select(lamv, cm, cs, sel) }
            ret sel[wh - 2usize]
        }
        if usize(x[qo]) >= nlen { ret nan() }
        if wh == 0usize { ret cm[usize(x[qo])] }
        ret cs[usize(x[qo])]
    }
    if kind == 5usize {
        // rlx*: data = y[n] (Cox: time[n], status[n]); the lasso path at lam, its relaxed refits and gamma blend; query = (k, j, gamma)
        let (cf, e1) = mem.alloc[f64](a, nl * (p + 1usize))
        let (rc, e2) = mem.alloc[f64](a, nl * (p + 1usize))
        let (bl, e3) = mem.alloc[f64](a, nl * (p + 1usize))
        let (cx, e4) = mem.alloc[f64](a, nl * p)
        let (dv, e5) = mem.alloc[f64](a, nl)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan() }
        let none: []const f64 = zero
        let nodv: []f64 = zero
        var fe = ok
        if rfam == 2usize { fe = gl.gaussian(a, xm, tm, wts, lo, up, n, p, alpha, std, vf, lam, cf) }
        if rfam == 0usize || rfam == 1usize { fe = gl.glm_path_dev(a, rfam, xm, tm, wts, off, lo, up, n, p, alpha, std, vf, lam, cf, nodv) }
        if rfam == 3usize {
            fe = gl.cox(a, xm, tm, st, wts, off, lo, up, n, p, alpha, std, vf, lam, cx, dv)
            var k0 = 0usize
            while k0 < nl {
                cf[k0 * (p + 1usize)] = 0.0f64
                var j0 = 0usize
                while j0 < p {
                    cf[k0 * (p + 1usize) + 1usize + j0] = cx[k0 * p + j0]
                    j0 += 1usize
                }
                k0 += 1usize
            }
        }
        if fe != ok { ret nan() }
        if gl.relax_path(a, rfam, xm, tm, st, wts, off, n, p, cf, nl, rc) != ok { ret nan() }
        gl.relax_blend(cf, rc, x[qo + 2usize], bl)
        ret bl[usize(x[qo]) * (p + 1usize) + usize(x[qo + 1usize])]
    }
    if kind == 6usize {
        // prd: data = (family 2 gaussian 0 binomial 1 poisson 3 cox 4 multinomial, type 0 link 1 response 2 class 3 nonzero count 4 nonzero index, nc, rows[nc (p + 1)]); newx is X, the offset (n * nc when ho) follows; query = (i, class)
        let fm = usize(x[d0])
        let kd = usize(x[d0 + 1usize])
        let rows = x[d0 + 3usize..d0 + 3usize + nk * (p + 1usize)]
        let (out, e1) = mem.alloc[f64](a, n * nk)
        let (lk, e2) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok { ret nan() }
        let qi = usize(x[qo])
        let qc = usize(x[qo + 1usize])
        if kd == 3usize { ret f64(gl.nonzero_count(rows[qc * (p + 1usize)..(qc + 1usize) * (p + 1usize)], p)) }
        if kd == 4usize { ret f64(gl.nonzero_at(rows[qc * (p + 1usize)..(qc + 1usize) * (p + 1usize)], p, qi) + 1usize) }
        if fm == 4usize {
            gl.predict_multinomial(xm, n, p, nk, rows, off, kd, out)
            if kd == 2usize { ret out[qi] + 1.0f64 }
            ret out[qc * n + qi]
        }
        gl.predict_link(xm, n, p, rows, off, lk)
        if kd == 0usize { ret lk[qi] }
        if kd == 1usize {
            var rf = fm
            if fm == 3usize { rf = 1usize }
            gl.predict_response(rf, lk, out)
            ret out[qi]
        }
        gl.predict_class(lk, out)
        ret out[qi]
    }
    if kind == 7usize {
        // lseq: data = y[n]; query = (k, nlambda, lambda.min.ratio): the k-th lambda of glmnet(nlambda =, lambda.min.ratio =), from the first lambda of the default gaussian path
        let (l0, e1) = mem.alloc[f64](a, 100usize)
        let (l1, e2) = mem.alloc[f64](a, usize(x[qo + 1usize]))
        if e1 != ok || e2 != ok { ret nan() }
        if gl.lambda_path(a, xm, tm, n, p, alpha, std, vf, 100usize, l0) != ok { ret nan() }
        gl.lambda_seq(l0[0usize], x[qo + 2usize], usize(x[qo + 1usize]), l1)
        ret l1[usize(x[qo])]
    }
    if kind == 8usize {
        // cfg / cfb / cfp: data = y[n]; query = (k, j); the plain gaussian, binomial or poisson path, for comparison with glmnet at its default thresh
        let (sm, e4) = mem.alloc[f64](a, nl * (p + 1usize))
        if e4 != ok { ret nan() }
        let none: []const f64 = zero
        let nodv: []f64 = zero
        var fe = ok
        if cfam == 2usize { fe = gl.gaussian(a, xm, tm, none, none, none, n, p, alpha, std, vf, lam, sm) } else { fe = gl.glm_path_dev(a, cfam, xm, tm, none, none, none, none, n, p, alpha, std, vf, lam, sm, nodv) }
        if fe != ok { ret nan() }
        ret sm[usize(x[qo]) * (p + 1usize) + usize(x[qo + 1usize])]
    }
    if kind == 3usize {
        // excg / excb: data = (y[n], exclude[p]); query = (k, j) with j 0 the intercept; the fit is made on the kept variables and spread back
        let (xk, e1) = mem.alloc[f64](a, n * p)
        let (vk, e2) = mem.alloc[f64](a, p)
        let (kept, e3) = mem.alloc[usize](a, p)
        let (sm, e4) = mem.alloc[f64](a, nl * (p + 1usize))
        let (fu, e5) = mem.alloc[f64](a, nl * (p + 1usize))
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan() }
        let nkp = gl.keep_columns(xm, vf, n, p, x[d0 + n..d0 + n + p], xk, vk, kept)
        let none: []const f64 = zero
        let sc = gl.exclude_scale(vf, p, x[d0 + n..d0 + n + p], nkp)
        let (lamc, e6) = mem.alloc[f64](a, nl)
        if e6 != ok { ret nan() }
        var ql = 0usize
        while ql < nl {
            lamc[ql] = lam[ql] * sc
            ql += 1usize
        }
        var fe = ok
        if str.eq(c.name, "excg") { fe = gl.gaussian(a, xk[0usize..n * nkp], tm, none, none, none, n, nkp, alpha, std, vk[0usize..nkp], lamc, sm) } else { fe = gl.binomial(a, xk[0usize..n * nkp], tm, none, none, n, nkp, alpha, std, vk[0usize..nkp], lamc, sm) }
        if fe != ok { ret nan() }
        gl.scatter_coef(sm, kept, nkp, p, nl, fu)
        ret fu[usize(x[qo]) * (p + 1usize) + usize(x[qo + 1usize])]
    }
    if kind == 4usize {
        // binb / poisb: data = (y[n]); the bounds ride in lo and up; query = (k, j)
        let (sm, e4) = mem.alloc[f64](a, nl * (p + 1usize))
        let (dv, e5) = mem.alloc[f64](a, 1usize)
        if e4 != ok || e5 != ok { ret nan() }
        var fam = 0usize
        if str.eq(c.name, "poisb") { fam = 1usize }
        let nodv: []f64 = zero
        if gl.glm_path_dev(a, fam, xm, tm, wts, off, lo, up, n, p, alpha, std, vf, lam, sm, nodv) != ok { ret nan() }
        ret sm[usize(x[qo]) * (p + 1usize) + usize(x[qo + 1usize])]
    }
    if cvfam < 3usize {
        // cv with the default lambda: data = (y[n], foldid[n] 0-based, nfolds, measure); query = (k, which: 0 cvm, 1 cvsd, 2 lambda.min, 3 lambda.1se, 4 the number of lambdas)
        let (lam4, e1) = mem.alloc[f64](a, 100usize)
        let (fid, e2) = mem.alloc[usize](a, n)
        if e1 != ok || e2 != ok { ret nan() }
        var q = 0usize
        while q < n {
            fid[q] = usize(x[d0 + n + q])
            q += 1usize
        }
        let none: []const f64 = zero
        var nlen = 0usize
        if cvfam == 2usize {
            if gl.lambda_path(a, xm, tm, n, p, alpha, std, vf, 100usize, lam4) != ok { ret nan() }
            nlen = gl.path_len(a, xm, tm, n, p, alpha, std, vf, 100usize)
        } else {
            if gl.glm_lambda_path(a, cvfam, xm, tm, none, none, n, p, alpha, std, vf, 100usize, lam4) != ok { ret nan() }
            nlen = gl.glm_path_len(a, cvfam, xm, tm, none, none, n, p, alpha, std, vf, 100usize)
        }
        if usize(x[qo + 1usize]) == 4usize { ret f64(nlen) }
        let (cm, e3) = mem.alloc[f64](a, nlen)
        let (cs, e4) = mem.alloc[f64](a, nlen)
        if e3 != ok || e4 != ok { ret nan() }
        let nfo = usize(x[d0 + 2usize * n])
        let ms = usize(x[d0 + 2usize * n + 1usize])
        var ce = ok
        if cvfam == 2usize { ce = gl.cv_gaussian(a, xm, tm, n, p, alpha, std, vf, lam4[0usize..nlen], fid, nfo, true, cm, cs) }
        if cvfam == 0usize { ce = gl.cv_binomial(a, ms, xm, tm, n, p, alpha, std, vf, lam4[0usize..nlen], fid, nfo, true, cm, cs) }
        if cvfam == 1usize { ce = gl.cv_poisson(a, ms, xm, tm, n, p, alpha, std, vf, lam4[0usize..nlen], fid, nfo, true, cm, cs) }
        if ce != ok { ret nan() }
        let wh = usize(x[qo + 1usize])
        if wh >= 2usize {
            let (sel, e5) = mem.alloc[f64](a, 2usize)
            if e5 != ok { ret nan() }
            gl.cv_select(lam4[0usize..nlen], cm, cs, sel)
            ret sel[wh - 2usize]
        }
        if usize(x[qo]) >= nlen { ret nan() }
        if wh == 0usize { ret cm[usize(x[qo])] }
        ret cs[usize(x[qo])]
    }
    if glmq {
        if str.eq(c.name, "binlen") || str.eq(c.name, "poislen") { ret f64(gl.glm_path_len(a, glmfam, xm, tm, wts, off, n, p, alpha, std, vf, 100usize)) }
        let (lo3, e1) = mem.alloc[f64](a, 100usize)
        if e1 != ok { ret nan() }
        if gl.glm_lambda_path(a, glmfam, xm, tm, wts, off, n, p, alpha, std, vf, 100usize, lo3) != ok { ret nan() }
        ret lo3[usize(x[qo])]
    }
    if cmult && str.eq(c.name, "multlen") {
        let (lab, e0) = mem.alloc[usize](a, n)
        if e0 != ok { ret nan() }
        var i = 0usize
        while i < n {
            lab[i] = usize(tm[i])
            i += 1usize
        }
        ret f64(gl.multinomial_path_len(a, xm, lab, wts, off, lo, up, n, p, nk, alpha, std, x[d0 + n + 1usize] != 0.0f64, vf, 100usize))
    }
    if cmult && str.eq(c.name, "multlam") {
        let (lab, e0) = mem.alloc[usize](a, n)
        let (lo3, e1) = mem.alloc[f64](a, 100usize)
        if e0 != ok || e1 != ok { ret nan() }
        var i = 0usize
        while i < n {
            lab[i] = usize(tm[i])
            i += 1usize
        }
        if gl.multinomial_lambda_path(a, xm, lab, wts, off, n, p, nk, alpha, std, x[d0 + n + 1usize] != 0.0f64, vf, 100usize, lo3) != ok { ret nan() }
        ret lo3[usize(x[qo])]
    }
    if cmult {
        let (lab, e0) = mem.alloc[usize](a, n)
        let (cf, e1) = mem.alloc[f64](a, nl * nk * (p + 1usize))
        let (dv, e2) = mem.alloc[f64](a, nl)
        if e0 != ok || e1 != ok || e2 != ok { ret nan() }
        var i = 0usize
        while i < n {
            lab[i] = usize(tm[i])
            i += 1usize
        }
        if gl.multinomial(a, xm, lab, wts, off, lo, up, n, p, nk, alpha, std, x[d0 + n + 1usize] != 0.0f64, vf, lam, cf, dv) != ok { ret nan() }
        ret cf[(usize(x[qo]) * nk + usize(x[qo + 1usize])) * (p + 1usize) + usize(x[qo + 2usize])]
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
