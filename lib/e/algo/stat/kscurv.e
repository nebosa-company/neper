// R ks kcurv in one to three dimensions: the kernel curvature of kdde(x, H, deriv.order = 2) on its grid (exact estimation, H given), the absolute
// Hessian determinant where the Hessian is negative semi-definite and zero elsewhere, and the contour levels of the observations it covers.

use e.algo.stat.classint as ci
use e.algo.stat.ksnd as nd
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// the curvature on the grid in gp (m^d cells); gp is built from the data and 3.7 bandwidths as kde.grid does
fn curv_grid(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, m: usize, gp: []f64, out: []f64) -> err {
    let total = nd.pow_usize(m, d)
    let (hess, e1) = mem.alloc[f64](a, d * d * total)
    let (tmp, e2) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok { ret e1 }
    nd.kde_grid(a, x, n, d, h, m, gp, tmp)
    var jj = 0usize
    while jj < d {
        var kc = jj
        while kc < d {
            nd.kde_grid_on(a, x, n, d, h, m, gp, tmp, 10usize + jj * d + kc)
            var c = 0usize
            while c < total {
                hess[(jj * d + kc) * total + c] = tmp[c]
                hess[(kc * d + jj) * total + c] = tmp[c]
                c += 1usize
            }
            kc += 1usize
        }
        jj += 1usize
    }
    var cell = 0usize
    while cell < total {
        var mat: [16]f64 = zero
        var i = 0usize
        while i < d * d {
            mat[i] = hess[i * total + cell]
            i += 1usize
        }
        var det = mat[0usize]
        var mode = false
        if d == 1usize {
            mode = mat[0usize] < 0.0f64
        } else {
            var vals: [4]f64 = zero
            var vecs: [16]f64 = zero
            nd.jacobi(mat[0usize..16usize], d, vals[0usize..4usize], vecs[0usize..16usize])
            mode = true
            i = 0usize
            while i < d {
                if vals[i] > 0.0f64 { mode = false }
                i += 1usize
            }
            if d == 2usize {
                det = mat[0usize] * mat[3usize] - mat[1usize] * mat[2usize]
            } else {
                det = mat[0usize] * (mat[4usize] * mat[8usize] - mat[5usize] * mat[7usize]) - mat[1usize] * (mat[3usize] * mat[8usize] - mat[5usize] * mat[6usize]) + mat[2usize] * (mat[3usize] * mat[7usize] - mat[4usize] * mat[6usize])
            }
        }
        var v = 0.0f64
        if mode {
            v = det
            if v < 0.0f64 { v = 0.0f64 - v }
        }
        out[cell] = v
        cell += 1usize
    }
    ret ok
}

// kcurv(fhat)$cont at cont = c: the quantile of the curvature interpolated at the observations where it is positive
fn curv_contour(a: *mem.Arena, x: []const f64, n: usize, d: usize, h: []const f64, m: usize, cont: f64) -> f64 {
    let total = nd.pow_usize(m, d)
    let (gp, e1) = mem.alloc[f64](a, d * m)
    let (cv, e2) = mem.alloc[f64](a, total)
    let (dv, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret nan() }
    if curv_grid(a, x, n, d, h, m, gp, cv) != ok { ret nan() }
    var kept = 0usize
    var i = 0usize
    while i < n {
        let v = nd.interp_nd(gp, m, d, cv, x[i * d..i * d + d])
        if v > 0.0f64 {
            dv[kept] = v
            kept += 1usize
        }
        i += 1usize
    }
    if kept == 0usize { ret nan() }
    let (s, se) = ci.sorted_copy(a, dv[0usize..kept])
    if se != ok { ret nan() }
    ret ci.quantile7(s, (100.0f64 - cont) / 100.0f64)
}
