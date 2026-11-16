// R AlgDesign, the evaluation part: `gen_factorial` (the full factorial grid, first factor varying fastest, with
// `center` giving odd integers for an even number of levels and integers for an odd number) and `eval_design`
// (determinant^(1/k), A, I, G efficiency and the Deff bound, diagonality and the geometric mean of the variances of
// a design matrix X with an intercept first column).
//
// Not here: optFederov, optBlock, optMonteCarlo and their exchange searches and random starts, formula expansion
// (the model matrix is supplied), confounding.

use e.algo.stat.psych as ps
use e.math
use e.mem

// out is runs by nf row-major, runs = product of levels
fn gen_factorial(levels: []const usize, center: bool, out: []f64) -> usize {
    var runs = 1usize
    var f = 0usize
    while f < levels.len {
        runs *= levels[f]
        f += 1usize
    }
    var r = 0usize
    while r < runs {
        var stride = 1usize
        f = 0usize
        while f < levels.len {
            let idx = (r / stride) % levels[f]
            var v = f64(idx + 1usize)
            if center {
                v = f64(idx) - (f64(levels[f]) - 1.0f64) / 2.0f64
                if levels[f] % 2usize == 0usize { v = v * 2.0f64 }
            }
            out[r * levels.len + f] = v
            stride *= levels[f]
            f += 1usize
        }
        r += 1usize
    }
    ret runs
}

type Eval = struct { determinant: f64, a: f64, i: f64, geff: f64, deff: f64, diagonality: f64, gmean_var: f64 }

// x: n by k column-major with an intercept first column; cand: nc by k column-major candidate model matrix for I and G
fn eval_design(a: *mem.Arena, x: []const f64, n: usize, k: usize, cand: []const f64, nc: usize) -> (Eval, err) {
    var res: Eval = zero
    let (m, e1) = mem.alloc[f64](a, k * k)
    let (mi, e2) = mem.alloc[f64](a, k * k)
    let (sub, e3) = mem.alloc[f64](a, k * k)
    if e1 != ok || e2 != ok || e3 != ok { ret (res, e1) }
    var j = 0usize
    while j < k {
        var l = 0usize
        while l < k {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += x[j * n + i] * x[l * n + i]
                i += 1usize
            }
            m[j * k + l] = s / f64(n)
            l += 1usize
        }
        j += 1usize
    }
    let ld = ps.logdet(a, m, k)
    res.determinant = math.exp[f64](ld / f64(k))
    if !ps.invert(a, m, k, mi) { ret (res, Singular) }
    var tr = 0.0f64
    j = 0usize
    while j < k {
        tr += mi[j * k + j]
        j += 1usize
    }
    res.a = tr / f64(k)
    // I = tr(M^-1 C), G = k / max x' M^-1 x over the candidates
    var ival = 0.0f64
    var mx = 0.0f64
    var i = 0usize
    while i < nc {
        var q = 0.0f64
        j = 0usize
        while j < k {
            var l = 0usize
            while l < k {
                q += cand[j * nc + i] * mi[j * k + l] * cand[l * nc + i]
                l += 1usize
            }
            j += 1usize
        }
        ival += q / f64(nc)
        if q > mx { mx = q }
        i += 1usize
    }
    res.i = ival
    res.geff = f64(k) / mx
    res.deff = math.exp[f64](1.0f64 - 1.0f64 / res.geff)
    // diagonality with the intercept removed
    var sl = 0.0f64
    j = 1usize
    while j < k {
        sl += math.log[f64](m[j * k + j])
        j += 1usize
    }
    j = 1usize
    while j < k {
        var l = 1usize
        while l < k {
            sub[(j - 1usize) * (k - 1usize) + (l - 1usize)] = m[j * k + l]
            l += 1usize
        }
        j += 1usize
    }
    res.diagonality = math.exp[f64]((ps.logdet(a, sub[0usize..(k - 1usize) * (k - 1usize)], k - 1usize) - sl) / f64(k - 1usize))
    var sv = 0.0f64
    j = 1usize
    while j < k {
        sv += math.log[f64](mi[j * k + j])
        j += 1usize
    }
    res.gmean_var = math.exp[f64](sv / f64(k - 1usize))
    ret (res, ok)
}

error Singular
