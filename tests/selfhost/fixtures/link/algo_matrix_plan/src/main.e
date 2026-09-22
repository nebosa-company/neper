// `e.algo.linalg.matrix` factorizations against numpy/scipy/sympy on LCG matrices: LU
// with the permutation sign, solve and solve_lu, inverse against inverse_f64, Cholesky,
// Householder QR, one reflector, a Givens rotation, Gram-Schmidt, rref, pow, power
// iteration, symmetric Jacobi eigen, one-sided Jacobi SVD both ways and a multigrid
// V-cycle. Every check has its own exit code.
use e.os
use e.io
use e.mem
use e.algo.linalg.matrix as matrix

fn near(got: f64, want: f64, tol: f64) -> bool {
    var d = got - want
    if d < 0.0 { d = 0.0 - d }
    ret d <= tol
}

fn draw(state: *u64) -> f64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64((*state >> 33u32) % 19u64) - 9.0
}

fn fill_lcg(dst: []f64, state: *u64) {
    var i = 0usize
    while i < dst.len {
        dst[i] = draw(state)
        i += 1usize
    }
}

fn mat(data: []f64, rows: usize, cols: usize) -> matrix.Matrix[f64] {
    let (m, _) = matrix.view[f64](data, rows, cols, cols)
    ret m
}

// a·b == c to `tol`, elementwise.
fn product_is(scratch: []f64, a: matrix.Matrix[f64], b: matrix.Matrix[f64], c: matrix.Matrix[f64], tol: f64) -> bool {
    let p = mat(scratch[..a.rows * b.cols], a.rows, b.cols)
    if matrix.multiply[f64](p, matrix.as_const[f64](a), matrix.as_const[f64](b)) != ok { ret false }
    var i = 0usize
    while i < a.rows {
        var j = 0usize
        while j < b.cols {
            if !near(matrix.get[f64](p, i, j), matrix.get[f64](c, i, j), tol) { ret false }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// The columns of `m` are orthonormal to `tol`.
fn orthonormal(m: matrix.Matrix[f64], tol: f64) -> bool {
    var i = 0usize
    while i < m.cols {
        var j = 0usize
        while j < m.cols {
            var dot: f64 = 0.0
            var k = 0usize
            while k < m.rows {
                dot = dot + matrix.get[f64](m, k, i) * matrix.get[f64](m, k, j)
                k += 1usize
            }
            var want: f64 = 0.0
            if i == j { want = 1.0 }
            if !near(dot, want, tol) { ret false }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// u·diag(s)·vᵀ == src to `tol`.
fn svd_rebuilds(u: matrix.Matrix[f64], s: []f64, v: matrix.Matrix[f64], src: matrix.Matrix[f64], tol: f64) -> bool {
    var i = 0usize
    while i < src.rows {
        var j = 0usize
        while j < src.cols {
            var total: f64 = 0.0
            var k = 0usize
            while k < s.len {
                total = total + matrix.get[f64](u, i, k) * s[k] * matrix.get[f64](v, j, k)
                k += 1usize
            }
            if !near(total, matrix.get[f64](src, i, j), tol) { ret false }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// The transpose of `src` copied into `dst` (`transpose` is a shape view, not a relayout).
fn transposed(dst: []f64, src: matrix.Matrix[f64]) -> matrix.Matrix[f64] {
    let t = mat(dst[..src.rows * src.cols], src.cols, src.rows)
    var r = 0usize
    while r < src.rows {
        var c = 0usize
        while c < src.cols {
            matrix.set[f64](t, c, r, matrix.get[f64](src, r, c))
            c += 1usize
        }
        r += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 1u64
    var a_data: [36]f64 = zero
    fill_lcg(a_data[0..], &state)
    var b: [6]f64 = zero
    fill_lcg(b[0..], &state)
    var b2: [6]f64 = zero
    fill_lcg(b2[0..], &state)
    var b_data: [15]f64 = zero
    fill_lcg(b_data[0..], &state)
    var r_data: [24]f64 = zero
    fill_lcg(r_data[0..12], &state)
    fill_lcg(r_data[18..], &state)
    var p_data: [9]f64 = zero
    fill_lcg(p_data[0..], &state)
    var f: [15]f64 = zero
    fill_lcg(f[0..], &state)
    var i = 0usize
    while i < 6usize {
        r_data[12usize + i] = r_data[i] + r_data[6usize + i]
        if i < 4usize { r_data[i * 6usize] = 0.0 }
        i += 1usize
    }
    if a_data[0] != -6.0 || a_data[35] != 9.0 || r_data[13] != 12.0 { os.exit(1i32) }
    let am = mat(a_data[0..], 6usize, 6usize)
    let ac = matrix.as_const[f64](am)
    var scratch: [72]f64 = zero
    // 2-5: LU: P·A = L·U, the sign, the determinant from the pivots.
    var l_data: [36]f64 = zero
    var u_data: [36]f64 = zero
    var perm: [6]usize = zero
    let lm = mat(l_data[0..], 6usize, 6usize)
    let um = mat(u_data[0..], 6usize, 6usize)
    let (sign, lu_error) = matrix.lu(lm, um, perm[0..], ac)
    if lu_error != ok || sign != -1.0 { os.exit(2i32) }
    var pa_data: [36]f64 = zero
    i = 0usize
    while i < 36usize {
        pa_data[i] = a_data[perm[i / 6usize] * 6usize + i % 6usize]
        i += 1usize
    }
    if !product_is(scratch[0..], lm, um, mat(pa_data[0..], 6usize, 6usize), 0.000000001) { os.exit(3i32) }
    var det = sign
    i = 0usize
    while i < 6usize {
        det = det * u_data[i * 7usize]
        i += 1usize
    }
    if !near(det, -136336.0, 0.000001) || l_data[7] != 1.0 || u_data[6] != 0.0 { os.exit(4i32) }
    let (r4, _) = matrix.view_const[f64](r_data[0..], 4usize, 4usize, 6usize)
    let (_, singular) = matrix.lu_factor(mat(u_data[0..], 4usize, 4usize), perm[0..], r4)
    if singular != matrix.Singular { os.exit(5i32) }
    // 6-8: solve, solve_lu, inverse.
    var x: [6]f64 = zero
    if matrix.solve(a, x[0..], ac, b[0..]) != ok { os.exit(6i32) }
    if !near(x[0], 2.5984186128388727, 0.000000001) || !near(x[5], 3.592015315103865, 0.000000001) { os.exit(6i32) }
    let (_, factor_error) = matrix.lu_factor(um, perm[0..], ac)
    if factor_error != ok || matrix.solve_lu(matrix.as_const[f64](um), perm[0..], x[0..], b2[0..]) != ok { os.exit(7i32) }
    if !near(x[0], -0.7001085553338819, 0.000000001) || !near(x[5], -1.3030527520244113, 0.000000001) { os.exit(7i32) }
    let inv = mat(l_data[0..], 6usize, 6usize)
    let inv2 = mat(u_data[0..], 6usize, 6usize)
    if matrix.inverse(a, inv, ac) != ok || matrix.inverse_f64(a, inv2, ac) != ok { os.exit(8i32) }
    i = 0usize
    while i < 36usize {
        if !near(l_data[i], u_data[i], 0.000000001) { os.exit(8i32) }
        i += 1usize
    }
    if !near(l_data[0], -0.21997124750616143, 0.000000001) || !near(l_data[35], -0.0916192348315927, 0.000000001) { os.exit(8i32) }
    // 9-10: Cholesky of S = A·Aᵀ + 6I.
    var s_data: [36]f64 = zero
    let sm = mat(s_data[0..], 6usize, 6usize)
    var t_data: [36]f64 = zero
    if matrix.multiply[f64](sm, ac, matrix.as_const[f64](transposed(t_data[0..], am))) != ok { os.exit(9i32) }
    i = 0usize
    while i < 6usize {
        s_data[i * 7usize] = s_data[i * 7usize] + 6.0
        i += 1usize
    }
    if matrix.cholesky(lm, matrix.as_const[f64](sm)) != ok { os.exit(9i32) }
    if !product_is(scratch[0..], lm, transposed(t_data[0..], lm), sm, 0.000000001) { os.exit(9i32) }
    if l_data[0] != 16.0 || !near(l_data[35], 7.436482878270726, 0.000000001) || l_data[30] != 2.375 || l_data[1] != 0.0 { os.exit(9i32) }
    var not_pd: [4]f64 = [4]f64{ 1.0, 2.0, 2.0, 1.0 }
    if matrix.cholesky(mat(scratch[0..], 2usize, 2usize), matrix.as_const[f64](mat(not_pd[0..], 2usize, 2usize))) != matrix.NotPositiveDefinite { os.exit(10i32) }
    // 11-13: QR of the 5x3 B.
    let bm = mat(b_data[0..], 5usize, 3usize)
    var q_data: [25]f64 = zero
    let qm = mat(q_data[0..], 5usize, 5usize)
    let rm = mat(u_data[0..], 5usize, 3usize)
    if matrix.qr(qm, rm, matrix.as_const[f64](bm), x[0..]) != ok { os.exit(11i32) }
    if !product_is(scratch[0..], qm, rm, bm, 0.000000001) || !orthonormal(qm, 0.000000001) { os.exit(12i32) }
    if !near(u_data[0], 9.9498743710662, 0.000000001) && !near(u_data[0], -9.9498743710662, 0.000000001) { os.exit(13i32) }
    if !near(u_data[8], 6.4047198689788845, 0.000000001) && !near(u_data[8], -6.4047198689788845, 0.000000001) { os.exit(13i32) }
    if u_data[3] != 0.0 || u_data[7] != 0.0 || u_data[12] != 0.0 { os.exit(13i32) }
    if matrix.qr(qm, rm, matrix.as_const[f64](bm), x[..4]) != matrix.TooSmall { os.exit(13i32) }
    // 14: one reflector sends column 0 of B to ‖x‖·e1.
    i = 0usize
    while i < 5usize {
        x[i] = b_data[i * 3usize]
        i += 1usize
    }
    var v: [5]f64 = zero
    let (beta, hh_error) = matrix.householder_vector(x[..5], v[0..])
    if hh_error != ok || v[0] != 1.0 { os.exit(14i32) }
    let col = mat(x[..5], 5usize, 1usize)
    if matrix.householder_apply_left(col, v[0..], beta) != ok { os.exit(14i32) }
    if !near(x[0], 9.9498743710662, 0.000000001) || !near(x[1], 0.0, 0.000000001) || !near(x[4], 0.0, 0.000000001) { os.exit(14i32) }
    // 15: Givens on (3, 4).
    let (c, s) = matrix.givens(3.0, 4.0)
    if !near(c, 0.6, 0.000000001) || !near(s, 0.8, 0.000000001) { os.exit(15i32) }
    var pair: [4]f64 = [4]f64{ 3.0, 1.0, 4.0, 2.0 }
    let pm = mat(pair[0..], 2usize, 2usize)
    if matrix.givens_apply(pm, 0usize, 1usize, c, s) != ok || matrix.givens_apply(pm, 0usize, 2usize, c, s) != matrix.Shape { os.exit(15i32) }
    if !near(pair[0], 5.0, 0.000000001) || !near(pair[2], 0.0, 0.000000001) || !near(pair[1], 2.2, 0.000000001) || !near(pair[3], 0.4, 0.000000001) { os.exit(15i32) }
    // 16: Gram-Schmidt on a copy of B.
    i = 0usize
    while i < 15usize {
        scratch[i] = b_data[i]
        i += 1usize
    }
    let gm = mat(scratch[..15], 5usize, 3usize)
    if matrix.orthonormalize(gm) != ok || !orthonormal(gm, 0.000000001) { os.exit(16i32) }
    if !near(scratch[0], b_data[0] / 9.9498743710662, 0.000000001) { os.exit(16i32) }
    // 17-18: rref of the rank-3 4x6.
    let rr = mat(r_data[0..], 4usize, 6usize)
    var pivots: [4]usize = zero
    let (rank, rref_error) = matrix.rref(rr, pivots[0..], 0.000000001)
    if rref_error != ok || rank != 3usize || pivots[0] != 1usize || pivots[1] != 2usize || pivots[2] != 3usize { os.exit(17i32) }
    if !near(r_data[4], 0.037914691943127965, 0.000000001) || !near(r_data[5], -0.7203791469194313, 0.000000001) { os.exit(18i32) }
    if !near(r_data[16], -1.3033175355450237, 0.000000001) || !near(r_data[17], -1.2369668246445498, 0.000000001) { os.exit(18i32) }
    if r_data[1] != 1.0 || r_data[2] != 0.0 || !near(r_data[23], 0.0, 0.000000001) || !near(r_data[19], 0.0, 0.000000001) { os.exit(18i32) }
    // 19: pow.
    let pw = mat(scratch[..9], 3usize, 3usize)
    if matrix.pow(a, pw, matrix.as_const[f64](mat(p_data[0..], 3usize, 3usize)), 5u64) != ok { os.exit(19i32) }
    if scratch[0] != -10528.0 || scratch[1] != 17649.0 || scratch[8] != 31518.0 || scratch[3] != -1542.0 { os.exit(19i32) }
    if matrix.pow(a, pw, matrix.as_const[f64](mat(p_data[0..], 3usize, 3usize)), 0u64) != ok || scratch[0] != 1.0 || scratch[1] != 0.0 { os.exit(19i32) }
    // 20: power iteration on S.
    var start: [6]f64 = [6]f64{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 }
    let (dominant, used, power_error) = matrix.power_iteration(matrix.as_const[f64](sm), start[0..], x[0..], 0.000000000001, 1000u32)
    if power_error != ok || used != 66u32 || !near(dominant, 484.67410269202185, 0.0000001) { os.exit(20i32) }
    let (_, few, no_convergence) = matrix.power_iteration(matrix.as_const[f64](sm), b[0..], x[0..], 0.0, 3u32)
    if no_convergence != matrix.NoConvergence || few != 3u32 { os.exit(20i32) }
    // 21-23: symmetric eigen.
    var values: [6]f64 = zero
    let vm = mat(pa_data[0..], 6usize, 6usize)
    if matrix.eigen(a, values[0..], vm, matrix.as_const[f64](sm), 0.0000000000000001, 60u32) != ok { os.exit(21i32) }
    if !near(values[0], 484.67410269202185, 0.0000001) || !near(values[2], 190.93065489703534, 0.0000001) || !near(values[5], 6.369549509828363, 0.0000001) { os.exit(21i32) }
    if !orthonormal(vm, 0.000000001) { os.exit(22i32) }
    // S·V == V·diag(values).
    var scaled: [36]f64 = zero
    i = 0usize
    while i < 36usize {
        scaled[i] = pa_data[i] * values[i % 6usize]
        i += 1usize
    }
    if !product_is(scratch[0..], sm, vm, mat(scaled[0..], 6usize, 6usize), 0.0000001) { os.exit(22i32) }
    if matrix.eigen(a, values[0..], vm, ac, 0.0000000000000001, 60u32) != matrix.Unsupported { os.exit(23i32) }
    // 24-26: SVD of B (5x3) and of Bᵀ (3x5).
    var sv: [3]f64 = zero
    let um5 = mat(q_data[..15], 5usize, 3usize)
    let vm3 = mat(scaled[..9], 3usize, 3usize)
    if matrix.svd(a, um5, sv[0..], vm3, matrix.as_const[f64](bm), 0.000000000001, 60u32) != ok { os.exit(24i32) }
    if !near(sv[0], 12.474527574352212, 0.0000001) || !near(sv[1], 9.272760750796204, 0.0000001) || !near(sv[2], 5.138294450031032, 0.0000001) { os.exit(24i32) }
    if !orthonormal(um5, 0.000000001) || !orthonormal(vm3, 0.000000001) || !svd_rebuilds(um5, sv[0..], vm3, bm, 0.000000001) { os.exit(25i32) }
    let bt = transposed(t_data[0..], bm)
    if matrix.svd(a, vm3, sv[0..], um5, matrix.as_const[f64](bt), 0.000000000001, 60u32) != ok { os.exit(26i32) }
    if !near(sv[0], 12.474527574352212, 0.0000001) || !near(sv[2], 5.138294450031032, 0.0000001) { os.exit(26i32) }
    if !orthonormal(um5, 0.000000001) || !orthonormal(vm3, 0.000000001) || !svd_rebuilds(vm3, sv[0..], um5, bt, 0.000000001) { os.exit(26i32) }
    if matrix.svd(a, um5, sv[0..], vm3, matrix.as_const[f64](bt), 0.000000000001, 60u32) != matrix.Shape { os.exit(26i32) }
    // 27-28: multigrid on 15 points.
    var u: [15]f64 = zero
    let (residual, mg_error) = matrix.multigrid(a, u[0..], f[0..], 3u32, 2u32)
    if mg_error != ok || !near(residual, 0.0030409496432084356, 0.0000001) || !near(u[0], 0.02122662532751077, 0.000000001) { os.exit(27i32) }
    let (_, bad_size) = matrix.multigrid(a, u[..14], f[0..], 1u32, 2u32)
    if bad_size != matrix.Shape { os.exit(28i32) }
    try io.print("algo matrix plan ok\n")
    ret ok
}
