// R's vmmin, optim's BFGS (abstol -Inf): b is the start and the answer, the function and its gradient are passed with a context; reltol and the iteration cap as optim takes them (sqrt(eps) and 100 by default). Returns the minimum
//
// A port of the loop in src/appl/optim.c; isotone.e keeps its own copy tied to its context.

use e.math
use e.mem

fn vmmin[Ctx: type](a: *mem.Arena, c: *Ctx, fn_: fn(*Ctx, []const f64) -> f64, gr: fn(*Ctx, []const f64, []f64), b: []f64, reltol: f64, maxit: usize) -> f64 {
    let n = b.len
    let (g, e1) = mem.alloc[f64](a, n)
    let (t, e2) = mem.alloc[f64](a, n)
    let (xv, e3) = mem.alloc[f64](a, n)
    let (cv, e4) = mem.alloc[f64](a, n)
    let (bm, e5) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    var f = fn_(c, b)
    var fmin = f
    gr(c, b, g)
    var gradcount = 1usize
    var iter = 1usize
    var ilast = gradcount
    var count = 0usize
    var go = true
    while go {
        var i = 0usize
        if ilast == gradcount {
            i = 0usize
            while i < n {
                var j = 0usize
                while j < i {
                    bm[i * n + j] = 0.0f64
                    j += 1usize
                }
                bm[i * n + i] = 1.0f64
                i += 1usize
            }
        }
        i = 0usize
        while i < n {
            xv[i] = b[i]
            cv[i] = g[i]
            i += 1usize
        }
        var gradproj = 0.0f64
        i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j <= i {
                s -= bm[i * n + j] * g[j]
                j += 1usize
            }
            j = i + 1usize
            while j < n {
                s -= bm[j * n + i] * g[j]
                j += 1usize
            }
            t[i] = s
            gradproj += s * g[i]
            i += 1usize
        }
        if gradproj < 0.0f64 {
            var steplength = 1.0f64
            var accpoint = false
            var again = true
            while again {
                count = 0usize
                i = 0usize
                while i < n {
                    b[i] = xv[i] + steplength * t[i]
                    if 10.0f64 + xv[i] == 10.0f64 + b[i] { count += 1usize }
                    i += 1usize
                }
                if count < n {
                    f = fn_(c, b)
                    accpoint = f - f == 0.0f64 && f <= fmin + gradproj * steplength * 0.0001f64
                    if !accpoint { steplength *= 0.2f64 }
                }
                again = !(count == n || accpoint)
            }
            let enough = math.abs[f64](f - fmin) > reltol * (math.abs[f64](fmin) + reltol)
            if !enough {
                count = n
                fmin = f
            }
            if count < n {
                fmin = f
                gr(c, b, g)
                gradcount += 1usize
                iter += 1usize
                var d1 = 0.0f64
                i = 0usize
                while i < n {
                    t[i] = steplength * t[i]
                    cv[i] = g[i] - cv[i]
                    d1 += t[i] * cv[i]
                    i += 1usize
                }
                if d1 > 0.0f64 {
                    var d2 = 0.0f64
                    i = 0usize
                    while i < n {
                        var s = 0.0f64
                        var j = 0usize
                        while j <= i {
                            s += bm[i * n + j] * cv[j]
                            j += 1usize
                        }
                        j = i + 1usize
                        while j < n {
                            s += bm[j * n + i] * cv[j]
                            j += 1usize
                        }
                        xv[i] = s
                        d2 += s * cv[i]
                        i += 1usize
                    }
                    d2 = 1.0f64 + d2 / d1
                    i = 0usize
                    while i < n {
                        var j = 0usize
                        while j <= i {
                            bm[i * n + j] += (d2 * t[i] * t[j] - xv[i] * t[j] - t[i] * xv[j]) / d1
                            j += 1usize
                        }
                        i += 1usize
                    }
                } else {
                    ilast = gradcount
                }
            } else if ilast < gradcount {
                count = 0usize
                ilast = gradcount
            }
        } else {
            count = 0usize
            if ilast == gradcount { count = n } else { ilast = gradcount }
        }
        if iter >= maxit { go = false }
        if go {
            if gradcount - ilast > 2usize * n { ilast = gradcount }
            go = count != n || ilast != gradcount
        }
    }
    ret fmin
}

