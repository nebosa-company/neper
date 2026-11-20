// R earth: predict(type = "terms"), evimp, and the text of format.earth and print.earth for models made by e.algo.stat.earthfit.

use e.algo.stat.earthfit as ef
use e.math
use e.mem

// ---- predict(type = "terms")

// the additive part of a single response model: columns are the predictors that appear in an additive term, rows the m cases; returns (matrix m by ncols, ncols)
// and fills pred_of with the predictor numbers (0-based) of the columns
fn predict_terms(a: *mem.Arena, f: *const ef.EFit, x: []const f64, m: usize, pred_of: []usize) -> ([]f64, usize, err) {
    let (bx, e) = ef.get_bx(a, x, m, f.p, f.dirs, f.cuts, f.nt, f.sel, f.nsel)
    if e != ok { ret (bx, 0usize, e) }
    let (isadd, e2) = mem.alloc[bool](a, f.nsel + 1usize)
    let (inuse, e3) = mem.alloc[bool](a, f.p + 1usize)
    if e2 != ok || e3 != ok { ret (bx, 0usize, mem.Exhausted) }
    var j = 0usize
    while j < f.p {
        inuse[j] = false
        j += 1usize
    }
    var k = 0usize
    while k < f.nsel {
        var deg = 0usize
        j = 0usize
        while j < f.p {
            if f.dirs[f.sel[k] + j * f.nt] != 0i64 { deg += 1usize }
            j += 1usize
        }
        isadd[k] = deg == 1usize
        if isadd[k] {
            j = 0usize
            while j < f.p {
                if f.dirs[f.sel[k] + j * f.nt] != 0i64 { inuse[j] = true }
                j += 1usize
            }
        }
        k += 1usize
    }
    var nc = 0usize
    j = 0usize
    while j < f.p {
        if inuse[j] {
            pred_of[nc] = j
            nc += 1usize
        }
        j += 1usize
    }
    let (tm, e4) = mem.alloc[f64](a, m * nc + 1usize)
    if e4 != ok { ret (bx, 0usize, mem.Exhausted) }
    var c = 0usize
    while c < nc {
        var i = 0usize
        while i < m {
            tm[c * m + i] = 0.0f64
            i += 1usize
        }
        k = 0usize
        while k < f.nsel {
            if isadd[k] && f.dirs[f.sel[k] + pred_of[c] * f.nt] != 0i64 {
                i = 0usize
                while i < m {
                    tm[c * m + i] = tm[c * m + i] + f.coef[k] * bx[k * m + i]
                    i += 1usize
                }
            }
            k += 1usize
        }
        c += 1usize
    }
    ret (tm, nc, ok)
}

// ---- evimp

// the 7 columns of evimp(): col (1-based predictor number), used, nsubsets, gcv, gcv.match, rss, rss.match; rows in the order evimp sorts them
type Evimp = struct { nrow: usize, tab: []f64, p: usize }

fn evimp(a: *mem.Arena, f: *const ef.EFit, trim: bool, sqrt_on: bool) -> (Evimp, err) {
    var out: Evimp = zero
    let p = f.p
    let ns = f.nsel
    let (imp, e1) = mem.alloc[f64](a, p * 7usize + 1usize)
    let (hit, e2) = mem.alloc[bool](a, p + 1usize)
    let (ord, e3) = mem.alloc[usize](a, p + 1usize)
    let (res, e4) = mem.alloc[f64](a, p * 7usize + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (out, mem.Exhausted) }
    var z = 0usize
    while z < p * 7usize {
        imp[z] = 0.0f64
        z += 1usize
    }
    var j = 0usize
    while j < p {
        imp[j] = f64(j + 1usize)
        j += 1usize
    }
    var k = 0usize
    while k < ns {
        j = 0usize
        while j < p {
            if f.dirs[f.sel[k] + j * f.nt] != 0i64 { imp[p + j] = 1.0f64 }
            j += 1usize
        }
        k += 1usize
    }
    var s = 2usize
    while s <= ns {
        j = 0usize
        while j < p {
            hit[j] = false
            j += 1usize
        }
        var c = 1usize
        while c < f.nall {
            let tn = f.prune[(s - 1usize) + c * f.nall]
            if tn != 0usize {
                j = 0usize
                while j < p {
                    if f.dirs[(tn - 1usize) + j * f.nt] != 0i64 { hit[j] = true }
                    j += 1usize
                }
            }
            c += 1usize
        }
        let dg = f.gcv_sub[s - 2usize] - f.gcv_sub[s - 1usize]
        let dr = f.rss_sub[s - 2usize] - f.rss_sub[s - 1usize]
        j = 0usize
        while j < p {
            if hit[j] {
                imp[2usize * p + j] = imp[2usize * p + j] + 1.0f64
                imp[3usize * p + j] = imp[3usize * p + j] + dg
                imp[5usize * p + j] = imp[5usize * p + j] + dr
            }
            j += 1usize
        }
        s += 1usize
    }
    // order(nsubsets, gcv, decreasing = TRUE), ties in the original order
    var i = 0usize
    while i < p {
        let t = i
        var q = i
        while q > 0usize && (imp[2usize * p + t] > imp[2usize * p + ord[q - 1usize]] || (imp[2usize * p + t] == imp[2usize * p + ord[q - 1usize]] && imp[3usize * p + t] > imp[3usize * p + ord[q - 1usize]])) {
            ord[q] = ord[q - 1usize]
            q -= 1usize
        }
        ord[q] = t
        i += 1usize
    }
    var r = 0usize
    while r < p {
        var c2 = 0usize
        while c2 < 7usize {
            res[r + c2 * p] = imp[ord[r] + c2 * p]
            c2 += 1usize
        }
        r += 1usize
    }
    if p > 1usize {
        var icol = 3usize
        while icol <= 5usize {
            res[0usize + (icol + 1usize) * p] = 1.0f64
            var rr2 = 1usize
            while rr2 < p {
                res[rr2 + (icol + 1usize) * p] = 1.0f64
                if res[rr2 + icol * p] > res[rr2 - 1usize + icol * p] { res[rr2 + (icol + 1usize) * p] = 0.0f64 }
                rr2 += 1usize
            }
            var mx = 0.0f64
            rr2 = 0usize
            while rr2 < p {
                let av = math.abs[f64](res[rr2 + icol * p])
                if av > mx { mx = av }
                rr2 += 1usize
            }
            if mx != 0.0f64 {
                rr2 = 0usize
                while rr2 < p {
                    let v = res[rr2 + icol * p]
                    if sqrt_on {
                        var sg = 1.0f64
                        if v < 0.0f64 { sg = 0.0f64 - 1.0f64 }
                        let tmp = math.sqrt[f64](math.abs[f64](v) / mx)
                        res[rr2 + icol * p] = 100.0f64 * sg * tmp
                    } else {
                        res[rr2 + icol * p] = 100.0f64 * v / mx
                    }
                    rr2 += 1usize
                }
            }
            icol += 2usize
        }
    }
    var nrow = p
    if trim {
        nrow = 0usize
        while nrow < p && res[nrow + 2usize * p] != 0.0f64 { nrow += 1usize }
    }
    out.nrow = nrow
    out.tab = res
    out.p = p
    ret (out, ok)
}
