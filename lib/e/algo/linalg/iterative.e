// Iterative linear solvers over an operator callback y = A x: conjugate gradients for symmetric positive-definite systems and restarted GMRES for general ones. The operator is a function taking a caller context, the input vector and the output vector.
//
// Not here: preconditioning, BiCGSTAB, MINRES, sparse-format helpers (e.algo.linalg.sparse has its own products) and the mesh-private conjugate_gradient of e.gfx.mesh, which keeps its pinned-entry operator.

use e.math

error TooSmall

type Result = struct { iterations: usize, residual: f64, converged: bool }

fn norm(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * v[i]
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

// conjugate gradients from the starting x until the residual norm is at most tol times the norm of b, or at most abs_tol when that is larger; r, p and q are scratch of n values each (a caller that owns them separately, such as e.gfx.mesh, passes them here)
fn cg_parts[Ctx: type](ctx: *Ctx, op: fn(*Ctx, []const f64, []f64), b: []const f64, x: []f64, tol: f64, abs_tol: f64, max_iter: usize, r: []f64, p: []f64, q: []f64) -> Result {
    let n = b.len
    op(ctx, x, q)
    var i = 0usize
    var rr = 0.0f64
    while i < n {
        r[i] = b[i] - q[i]
        p[i] = r[i]
        rr += r[i] * r[i]
        i += 1usize
    }
    var goal = tol * norm(b)
    if abs_tol > goal { goal = abs_tol }
    var it = 0usize
    while it < max_iter && math.sqrt[f64](rr) > goal {
        op(ctx, p, q)
        var pq = 0.0f64
        i = 0usize
        while i < n {
            pq += p[i] * q[i]
            i += 1usize
        }
        if pq <= 0.0f64 { break }
        let alpha = rr / pq
        var rr_next = 0.0f64
        i = 0usize
        while i < n {
            x[i] += alpha * p[i]
            r[i] -= alpha * q[i]
            rr_next += r[i] * r[i]
            i += 1usize
        }
        let beta = rr_next / rr
        i = 0usize
        while i < n {
            p[i] = r[i] + beta * p[i]
            i += 1usize
        }
        rr = rr_next
        it += 1usize
    }
    let res = math.sqrt[f64](rr)
    ret Result { iterations: it, residual: res, converged: res <= goal }
}

// conjugate gradients with the scratch in one slice of 3 n values; the goal is tol times the norm of b (tol itself when b is zero)
fn cg[Ctx: type](ctx: *Ctx, op: fn(*Ctx, []const f64, []f64), b: []const f64, x: []f64, tol: f64, max_iter: usize, scratch: []f64) -> (Result, err) {
    let n = b.len
    if scratch.len < 3usize * n || x.len < n { ret (zero, TooSmall) }
    var abs_tol = 0.0f64
    if norm(b) == 0.0f64 { abs_tol = tol }
    let res = cg_parts[Ctx](ctx, op, b, x, tol, abs_tol, max_iter, scratch[..n], scratch[n..2usize * n], scratch[2usize * n..3usize * n])
    ret (res, ok)
}

// the scratch GMRES(m) needs for n unknowns: (m + 1) n for the basis, (m + 1) m for the Hessenberg matrix, 4 m + 3 for the rotations and the solution, n for the product
fn gmres_scratch(n: usize, m: usize) -> usize { ret (m + 1usize) * n + (m + 1usize) * m + 4usize * m + 3usize + n }

// restarted GMRES(m): Arnoldi with modified Gram-Schmidt and Givens rotations, restarting every m steps from the current x, until the residual norm is at most tol times the norm of b; max_iter counts the inner steps
fn gmres[Ctx: type](ctx: *Ctx, op: fn(*Ctx, []const f64, []f64), b: []const f64, x: []f64, m: usize, tol: f64, max_iter: usize, scratch: []f64) -> (Result, err) {
    let n = b.len
    if scratch.len < gmres_scratch(n, m) || x.len < n { ret (zero, TooSmall) }
    let basis = scratch[..(m + 1usize) * n]
    let h = scratch[(m + 1usize) * n..(m + 1usize) * n + (m + 1usize) * m]
    let rest = scratch[(m + 1usize) * n + (m + 1usize) * m..]
    let cs = rest[..m]
    let sn = rest[m..2usize * m]
    let g = rest[2usize * m..3usize * m + 1usize]
    let y = rest[3usize * m + 1usize..4usize * m + 1usize]
    let w = rest[4usize * m + 1usize..4usize * m + 1usize + n]
    var goal = tol * norm(b)
    if goal == 0.0f64 { goal = tol }
    var total = 0usize
    var res = 0.0f64
    var restart_count = 0usize
    while total < max_iter {
        op(ctx, x, w)
        var i = 0usize
        while i < n {
            w[i] = b[i] - w[i]
            i += 1usize
        }
        let beta = norm(w)
        res = beta
        if beta <= goal { break }
        i = 0usize
        while i < n {
            basis[i] = w[i] / beta
            i += 1usize
        }
        i = 0usize
        while i <= m {
            g[i] = 0.0f64
            i += 1usize
        }
        g[0usize] = beta
        var k = 0usize
        while k < m && total < max_iter {
            op(ctx, basis[k * n..(k + 1usize) * n], w)
            var j = 0usize
            while j <= k {
                var d = 0.0f64
                i = 0usize
                while i < n {
                    d += w[i] * basis[j * n + i]
                    i += 1usize
                }
                h[j * m + k] = d
                i = 0usize
                while i < n {
                    w[i] -= d * basis[j * n + i]
                    i += 1usize
                }
                j += 1usize
            }
            let hn = norm(w)
            h[(k + 1usize) * m + k] = hn
            if hn > 0.0f64 {
                i = 0usize
                while i < n {
                    basis[(k + 1usize) * n + i] = w[i] / hn
                    i += 1usize
                }
            }
            // apply the earlier rotations to the new column, then form the next one
            j = 0usize
            while j < k {
                let t = cs[j] * h[j * m + k] + sn[j] * h[(j + 1usize) * m + k]
                h[(j + 1usize) * m + k] = 0.0f64 - sn[j] * h[j * m + k] + cs[j] * h[(j + 1usize) * m + k]
                h[j * m + k] = t
                j += 1usize
            }
            let a1 = h[k * m + k]
            let a2 = h[(k + 1usize) * m + k]
            let rr = math.sqrt[f64](a1 * a1 + a2 * a2)
            if rr == 0.0f64 {
                cs[k] = 1.0f64
                sn[k] = 0.0f64
            } else {
                cs[k] = a1 / rr
                sn[k] = a2 / rr
            }
            h[k * m + k] = cs[k] * a1 + sn[k] * a2
            h[(k + 1usize) * m + k] = 0.0f64
            g[k + 1usize] = 0.0f64 - sn[k] * g[k]
            g[k] = cs[k] * g[k]
            res = math.abs[f64](g[k + 1usize])
            k += 1usize
            total += 1usize
            if res <= goal || hn == 0.0f64 { break }
        }
        // back-substitute the k x k triangular system and update x
        var row = k
        while row > 0usize {
            row -= 1usize
            var s = g[row]
            var c = row + 1usize
            while c < k {
                s -= h[row * m + c] * y[c]
                c += 1usize
            }
            y[row] = s / h[row * m + row]
        }
        var c2 = 0usize
        while c2 < k {
            var j2 = 0usize
            while j2 < n {
                x[j2] += y[c2] * basis[c2 * n + j2]
                j2 += 1usize
            }
            c2 += 1usize
        }
        restart_count += 1usize
        if res <= goal { break }
    }
    // the true residual after the final update
    op(ctx, x, w)
    var s2 = 0.0f64
    var q = 0usize
    while q < n {
        s2 += (b[q] - w[q]) * (b[q] - w[q])
        q += 1usize
    }
    let final_res = math.sqrt[f64](s2)
    ret (Result { iterations: total, residual: final_res, converged: final_res <= goal * 10.0f64 + 1.0e-14f64 }, ok)
}
