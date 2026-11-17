// R's optim(method = "Nelder-Mead"): nmmin of src/appl/optim.c, Nash's Nelder-Mead with reflection 1, contraction 0.5, extension 2, the starting simplex built from a step of a tenth of the largest coordinate
// (0.1 when all are zero), the stop when the spread of the function values is within intol (|f| + intol) or abstol is reached, a shrink that fails to reduce the simplex size being a failure, and a budget of maxit function calls.
//
// fscale multiplies the function (optim divides by fnscale, so -1 maximises).

use e.math
use e.mem

fn fin(v: f64) -> f64 {
    if v != v || v > 1.7976931348623157e308f64 || v < 0.0f64 - 1.7976931348623157e308f64 { ret 1.0e35f64 }
    ret v
}

// minimises f(ctx, x) from start; x receives the best vertex, the answer is (the minimum, the call count, the failure code 0 / 1 / 10)
fn nmmin[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, start: []const f64, abstol: f64, intol: f64, alpha: f64, bet: f64, gamm: f64, maxit: usize, fscale: f64, x: []f64) -> (f64, usize, usize) {
    let n = start.len
    let n1 = n + 1usize
    let cc = n + 2usize
    let (p, e1) = mem.alloc[f64](a, n1 * cc)
    let (bvec, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (0.0f64 / 0.0f64, 0usize, 10usize) }
    var i = 0usize
    while i < n {
        bvec[i] = start[i]
        i += 1usize
    }
    var fv = fscale * f(ctx, bvec)
    var fail = 0usize
    var funcount = 1usize
    let convtol = intol * (math.abs[f64](fv) + intol)
    p[(n1 - 1usize) * cc + 0usize] = fv
    i = 0usize
    while i < n {
        p[i * cc + 0usize] = bvec[i]
        i += 1usize
    }
    var l = 1usize
    var size = 0.0f64
    var step = 0.0f64
    i = 0usize
    while i < n {
        if 0.1f64 * math.abs[f64](bvec[i]) > step { step = 0.1f64 * math.abs[f64](bvec[i]) }
        i += 1usize
    }
    if step == 0.0f64 { step = 0.1f64 }
    var j = 2usize
    while j <= n1 {
        i = 0usize
        while i < n {
            p[i * cc + j - 1usize] = bvec[i]
            i += 1usize
        }
        var trystep = step
        while p[(j - 2usize) * cc + j - 1usize] == bvec[j - 2usize] {
            p[(j - 2usize) * cc + j - 1usize] = bvec[j - 2usize] + trystep
            trystep = trystep * 10.0f64
        }
        size += trystep
        j += 1usize
    }
    var oldsize = size
    var calcvert = true
    var done = false
    while !done {
        if calcvert {
            j = 0usize
            while j < n1 {
                if j + 1usize != l {
                    i = 0usize
                    while i < n {
                        bvec[i] = p[i * cc + j]
                        i += 1usize
                    }
                    fv = fin(fscale * f(ctx, bvec))
                    funcount += 1usize
                    p[(n1 - 1usize) * cc + j] = fv
                }
                j += 1usize
            }
            calcvert = false
        }
        var vl = p[(n1 - 1usize) * cc + l - 1usize]
        var vh = vl
        var h = l
        j = 1usize
        while j <= n1 {
            if j != l {
                fv = p[(n1 - 1usize) * cc + j - 1usize]
                if fv < vl {
                    l = j
                    vl = fv
                }
                if fv > vh {
                    h = j
                    vh = fv
                }
            }
            j += 1usize
        }
        if vh <= vl + convtol || vl <= abstol { break }
        i = 0usize
        while i < n {
            var temp = 0.0f64 - p[i * cc + h - 1usize]
            j = 0usize
            while j < n1 {
                temp += p[i * cc + j]
                j += 1usize
            }
            p[i * cc + cc - 1usize] = temp / f64(n)
            i += 1usize
        }
        i = 0usize
        while i < n {
            bvec[i] = (1.0f64 + alpha) * p[i * cc + cc - 1usize] - alpha * p[i * cc + h - 1usize]
            i += 1usize
        }
        fv = fin(fscale * f(ctx, bvec))
        funcount += 1usize
        let vr = fv
        if vr < vl {
            p[(n1 - 1usize) * cc + cc - 1usize] = fv
            i = 0usize
            while i < n {
                fv = gamm * bvec[i] + (1.0f64 - gamm) * p[i * cc + cc - 1usize]
                p[i * cc + cc - 1usize] = bvec[i]
                bvec[i] = fv
                i += 1usize
            }
            fv = fin(fscale * f(ctx, bvec))
            funcount += 1usize
            if fv < vr {
                i = 0usize
                while i < n {
                    p[i * cc + h - 1usize] = bvec[i]
                    i += 1usize
                }
                p[(n1 - 1usize) * cc + h - 1usize] = fv
            } else {
                i = 0usize
                while i < n {
                    p[i * cc + h - 1usize] = p[i * cc + cc - 1usize]
                    i += 1usize
                }
                p[(n1 - 1usize) * cc + h - 1usize] = vr
            }
        } else {
            if vr < vh {
                i = 0usize
                while i < n {
                    p[i * cc + h - 1usize] = bvec[i]
                    i += 1usize
                }
                p[(n1 - 1usize) * cc + h - 1usize] = vr
            }
            i = 0usize
            while i < n {
                bvec[i] = (1.0f64 - bet) * p[i * cc + h - 1usize] + bet * p[i * cc + cc - 1usize]
                i += 1usize
            }
            fv = fin(fscale * f(ctx, bvec))
            funcount += 1usize
            if fv < p[(n1 - 1usize) * cc + h - 1usize] {
                i = 0usize
                while i < n {
                    p[i * cc + h - 1usize] = bvec[i]
                    i += 1usize
                }
                p[(n1 - 1usize) * cc + h - 1usize] = fv
            } else if vr >= vh {
                calcvert = true
                size = 0.0f64
                j = 0usize
                while j < n1 {
                    if j + 1usize != l {
                        i = 0usize
                        while i < n {
                            p[i * cc + j] = bet * (p[i * cc + j] - p[i * cc + l - 1usize]) + p[i * cc + l - 1usize]
                            size += math.abs[f64](p[i * cc + j] - p[i * cc + l - 1usize])
                            i += 1usize
                        }
                    }
                    j += 1usize
                }
                if size < oldsize {
                    oldsize = size
                } else {
                    fail = 10usize
                    done = true
                }
            }
        }
        if !done && funcount > maxit { done = true }
    }
    i = 0usize
    while i < n {
        x[i] = p[i * cc + l - 1usize]
        i += 1usize
    }
    if funcount > maxit { fail = 1usize }
    ret (p[(n1 - 1usize) * cc + l - 1usize], funcount, fail)
}
