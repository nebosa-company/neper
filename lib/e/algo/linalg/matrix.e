// Row-major matrix views over caller storage: element (r, c) is `data[r * stride + c]`,
// so a transpose is a view with the two dimensions swapped -- which is why a `Matrix`
// carries its stride and why `transpose` costs nothing. `Shape` is any mismatch of
// dimensions or a view its data cannot hold; `Singular` is a pivot of zero.
//
// The factorizations below are on `f64` views: `lu`/`lu_factor` with `solve_lu`, `solve`
// and `inverse` on top; `cholesky`; Householder `qr` from `householder_vector` and its two
// applies; `givens` and `givens_apply`; `orthonormalize` (modified Gram-Schmidt); `rref`;
// `pow` by squaring; `power_iteration`; symmetric `eigen` (cyclic Jacobi); `svd` (one-sided
// Jacobi); and `multigrid`, a V-cycle for the 1-D Poisson system.

use e.mem
use e.math

type Matrix[T: type] = struct { data: []T, rows: usize, cols: usize, stride: usize }
type ConstMatrix[T: type] = struct { data: []const T, rows: usize, cols: usize, stride: usize }
error Shape
error Singular
error NotPositiveDefinite
error Unsupported
error TooSmall
error NoConvergence

fn extent(rows: usize, cols: usize, stride: usize) -> usize {
    if rows == 0usize || cols == 0usize { ret 0usize }
    let last_row = rows - 1usize
    ret last_row * stride + cols
}

fn view[T: type](data: []T, rows: usize, cols: usize, stride: usize) -> (Matrix[T], err) {
    if cols > stride && rows > 1usize { ret (zero, Shape) }
    if extent(rows, cols, stride) > data.len { ret (zero, Shape) }
    var m: Matrix[T] = zero
    m.data = data
    m.rows = rows
    m.cols = cols
    m.stride = stride
    ret (m, ok)
}

fn view_const[T: type](data: []const T, rows: usize, cols: usize, stride: usize) -> (ConstMatrix[T], err) {
    if cols > stride && rows > 1usize { ret (zero, Shape) }
    if extent(rows, cols, stride) > data.len { ret (zero, Shape) }
    var m: ConstMatrix[T] = zero
    m.data = data
    m.rows = rows
    m.cols = cols
    m.stride = stride
    ret (m, ok)
}

fn as_const[T: type](m: Matrix[T]) -> ConstMatrix[T] {
    var c: ConstMatrix[T] = zero
    c.data = m.data
    c.rows = m.rows
    c.cols = m.cols
    c.stride = m.stride
    ret c
}

fn get[T: type](m: Matrix[T], row: usize, col: usize) -> T {
    if row >= m.rows || col >= m.cols { ret m.data[m.data.len] }
    ret m.data[row * m.stride + col]
}

fn set[T: type](m: Matrix[T], row: usize, col: usize, v: T) {
    if row >= m.rows || col >= m.cols {
        m.data[m.data.len] = v
        ret
    }
    m.data[row * m.stride + col] = v
}

// The same storage read column-first: a view, not a copy. A transposed view is only
// itself transposable again; the other operations here read rows through the stride.
fn transpose[T: type](m: Matrix[T]) -> Matrix[T] {
    var t: Matrix[T] = zero
    t.data = m.data
    t.rows = m.cols
    t.cols = m.rows
    t.stride = m.stride
    ret t
}

fn fill[T: type](m: Matrix[T], v: T) {
    var r = 0usize
    while r < m.rows {
        var c = 0usize
        while c < m.cols {
            m.data[r * m.stride + c] = v
            c += 1usize
        }
        r += 1usize
    }
}

fn copy[T: type](dst: Matrix[T], src: ConstMatrix[T]) -> err {
    if dst.rows != src.rows || dst.cols != src.cols { ret Shape }
    var r = 0usize
    while r < dst.rows {
        var c = 0usize
        while c < dst.cols {
            dst.data[r * dst.stride + c] = src.data[r * src.stride + c]
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

fn add[T: type](dst: Matrix[T], a: ConstMatrix[T], b: ConstMatrix[T]) -> err {
    if dst.rows != a.rows || dst.cols != a.cols || a.rows != b.rows || a.cols != b.cols { ret Shape }
    var r = 0usize
    while r < dst.rows {
        var c = 0usize
        while c < dst.cols {
            dst.data[r * dst.stride + c] = a.data[r * a.stride + c] + b.data[r * b.stride + c]
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// `dst` may not alias either operand: each element is accumulated in place.
fn multiply[T: type](dst: Matrix[T], a: ConstMatrix[T], b: ConstMatrix[T]) -> err {
    if a.cols != b.rows || dst.rows != a.rows || dst.cols != b.cols { ret Shape }
    var r = 0usize
    while r < dst.rows {
        var c = 0usize
        while c < dst.cols {
            var total: T = zero
            var k = 0usize
            while k < a.cols {
                total = total + a.data[r * a.stride + k] * b.data[k * b.stride + c]
                k += 1usize
            }
            dst.data[r * dst.stride + c] = total
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// Gaussian elimination with partial pivoting on a scratch copy; the determinant is the
// product of the pivots, negated once per row swap.
fn determinant_f64(a: *mem.Arena, m: ConstMatrix[f64]) -> (f64, err) {
    if m.rows != m.cols { ret (0.0, Shape) }
    let n = m.rows
    if n == 0usize { ret (1.0, ok) }
    let (scratch, scratch_error) = mem.alloc[f64](a, n * n)
    if scratch_error != ok { ret (0.0, scratch_error) }
    var r = 0usize
    while r < n {
        var c = 0usize
        while c < n {
            scratch[r * n + c] = m.data[r * m.stride + c]
            c += 1usize
        }
        r += 1usize
    }
    var result: f64 = 1.0
    var col = 0usize
    while col < n {
        let pivot = pivot_row(scratch[0..], n, col)
        if scratch[pivot * n + col] == 0.0 { ret (0.0, ok) }
        if pivot != col {
            swap_rows(scratch[0..], n, pivot, col)
            result = 0.0 - result
        }
        let lead = scratch[col * n + col]
        result = result * lead
        eliminate_below(scratch[0..], n, col, lead)
        col += 1usize
    }
    ret (result, ok)
}

// Gauss-Jordan on `[src | I]`, reading the inverse out of the right half.
fn inverse_f64(a: *mem.Arena, dst: Matrix[f64], src: ConstMatrix[f64]) -> err {
    if src.rows != src.cols || dst.rows != src.rows || dst.cols != src.cols { ret Shape }
    let n = src.rows
    let width = n * 2usize
    let (scratch, scratch_error) = mem.alloc[f64](a, n * width)
    if scratch_error != ok { ret scratch_error }
    var r = 0usize
    while r < n {
        var c = 0usize
        while c < n {
            scratch[r * width + c] = src.data[r * src.stride + c]
            scratch[r * width + n + c] = 0.0
            c += 1usize
        }
        scratch[r * width + n + r] = 1.0
        r += 1usize
    }
    var col = 0usize
    while col < n {
        let pivot = pivot_row(scratch[0..], width, col)
        if scratch[pivot * width + col] == 0.0 { ret Singular }
        if pivot != col { swap_rows(scratch[0..], width, pivot, col) }
        let lead = scratch[col * width + col]
        var c = 0usize
        while c < width {
            scratch[col * width + c] = scratch[col * width + c] / lead
            c += 1usize
        }
        r = 0usize
        while r < n {
            if r != col {
                let factor = scratch[r * width + col]
                if factor != 0.0 {
                    c = 0usize
                    while c < width {
                        scratch[r * width + c] = scratch[r * width + c] - factor * scratch[col * width + c]
                        c += 1usize
                    }
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    r = 0usize
    while r < n {
        var c = 0usize
        while c < n {
            dst.data[r * dst.stride + c] = scratch[r * width + n + c]
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// The row at or below `col` with the largest magnitude in column `col`.
fn pivot_row(scratch: []f64, width: usize, col: usize) -> usize {
    let n = scratch.len / width
    var best = col
    var best_size = scratch[col * width + col]
    if best_size < 0.0 { best_size = 0.0 - best_size }
    var r = col + 1usize
    while r < n {
        var size = scratch[r * width + col]
        if size < 0.0 { size = 0.0 - size }
        if size > best_size {
            best = r
            best_size = size
        }
        r += 1usize
    }
    ret best
}

fn swap_rows(scratch: []f64, width: usize, first: usize, second: usize) {
    var c = 0usize
    while c < width {
        let carried = scratch[first * width + c]
        scratch[first * width + c] = scratch[second * width + c]
        scratch[second * width + c] = carried
        c += 1usize
    }
}

fn eliminate_below(scratch: []f64, n: usize, col: usize, lead: f64) {
    var r = col + 1usize
    while r < n {
        let factor = scratch[r * n + col] / lead
        if factor != 0.0 {
            var c = col
            while c < n {
                scratch[r * n + c] = scratch[r * n + c] - factor * scratch[col * n + c]
                c += 1usize
            }
        }
        r += 1usize
    }
}

// A view of `m` from (`row`, `col`), `rows` x `cols`, sharing its storage.
fn sub(m: Matrix[f64], row: usize, col: usize, rows: usize, cols: usize) -> Matrix[f64] {
    var s: Matrix[f64] = zero
    s.data = m.data[row * m.stride + col..]
    s.rows = rows
    s.cols = cols
    s.stride = m.stride
    ret s
}

fn identity(m: Matrix[f64]) {
    fill[f64](m, 0.0)
    var i = 0usize
    while i < m.rows && i < m.cols {
        m.data[i * m.stride + i] = 1.0
        i += 1usize
    }
}

fn swap_view_rows(m: Matrix[f64], first: usize, second: usize) {
    var c = 0usize
    while c < m.cols {
        let carried = m.data[first * m.stride + c]
        m.data[first * m.stride + c] = m.data[second * m.stride + c]
        m.data[second * m.stride + c] = carried
        c += 1usize
    }
}

// Doolittle LU with partial pivoting in compact form: `lu` holds U on and above the
// diagonal and the multipliers of a unit-diagonal L below it, `perm[i]` is the source
// row of row `i` (so P·A = L·U), and the answer is the permutation sign for a determinant.
fn lu_factor(factors: Matrix[f64], perm: []usize, src: ConstMatrix[f64]) -> (f64, err) {
    if src.rows != src.cols || factors.rows != src.rows || factors.cols != src.cols { ret (0.0, Shape) }
    let n = src.rows
    if perm.len < n { ret (0.0, TooSmall) }
    let copy_error = copy[f64](factors, src)
    if copy_error != ok { ret (0.0, copy_error) }
    var i = 0usize
    while i < n {
        perm[i] = i
        i += 1usize
    }
    var sign: f64 = 1.0
    var col = 0usize
    while col < n {
        var best = col
        var best_size = math.abs[f64](factors.data[col * factors.stride + col])
        var r = col + 1usize
        while r < n {
            let size = math.abs[f64](factors.data[r * factors.stride + col])
            if size > best_size {
                best = r
                best_size = size
            }
            r += 1usize
        }
        if best_size == 0.0 { ret (0.0, Singular) }
        if best != col {
            swap_view_rows(factors, best, col)
            let carried = perm[best]
            perm[best] = perm[col]
            perm[col] = carried
            sign = 0.0 - sign
        }
        let lead = factors.data[col * factors.stride + col]
        r = col + 1usize
        while r < n {
            let factor = factors.data[r * factors.stride + col] / lead
            factors.data[r * factors.stride + col] = factor
            var c = col + 1usize
            while c < n {
                factors.data[r * factors.stride + c] = factors.data[r * factors.stride + c] - factor * factors.data[col * factors.stride + c]
                c += 1usize
            }
            r += 1usize
        }
        col += 1usize
    }
    ret (sign, ok)
}

// `lu_factor` split into a unit lower `l` and an upper `u`.
fn lu(l: Matrix[f64], u: Matrix[f64], perm: []usize, src: ConstMatrix[f64]) -> (f64, err) {
    if l.rows != src.rows || l.cols != src.cols { ret (0.0, Shape) }
    let (sign, factor_error) = lu_factor(u, perm, src)
    if factor_error != ok { ret (0.0, factor_error) }
    var r = 0usize
    while r < u.rows {
        var c = 0usize
        while c < u.cols {
            var lower: f64 = 0.0
            if c < r {
                lower = u.data[r * u.stride + c]
                u.data[r * u.stride + c] = 0.0
            }
            if c == r { lower = 1.0 }
            l.data[r * l.stride + c] = lower
            c += 1usize
        }
        r += 1usize
    }
    ret (sign, ok)
}

// `x` solving A·x = b from a compact `lu_factor` of A; `x` may not alias `b`.
fn solve_lu(factors: ConstMatrix[f64], perm: []const usize, x: []f64, b: []const f64) -> err {
    if factors.rows != factors.cols { ret Shape }
    let n = factors.rows
    if perm.len < n || x.len < n || b.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        var total = b[perm[i]]
        var j = 0usize
        while j < i {
            total = total - factors.data[i * factors.stride + j] * x[j]
            j += 1usize
        }
        x[i] = total
        i += 1usize
    }
    i = n
    while i > 0usize {
        i -= 1usize
        var total = x[i]
        var j = i + 1usize
        while j < n {
            total = total - factors.data[i * factors.stride + j] * x[j]
            j += 1usize
        }
        x[i] = total / factors.data[i * factors.stride + i]
    }
    ret ok
}

// A·x = b by Gaussian elimination (an LU on arena scratch).
fn solve(a: *mem.Arena, x: []f64, m: ConstMatrix[f64], b: []const f64) -> err {
    if m.rows != m.cols { ret Shape }
    let n = m.rows
    let (scratch, scratch_error) = mem.alloc[f64](a, n * n)
    if scratch_error != ok { ret scratch_error }
    let (perm, perm_error) = mem.alloc[usize](a, n)
    if perm_error != ok { ret perm_error }
    let (factors, view_error) = view[f64](scratch, n, n, n)
    if view_error != ok { ret view_error }
    let (_, factor_error) = lu_factor(factors, perm, m)
    if factor_error != ok { ret factor_error }
    ret solve_lu(as_const[f64](factors), perm, x, b)
}

// The inverse through the LU, one solve per column of the identity.
fn inverse(a: *mem.Arena, dst: Matrix[f64], src: ConstMatrix[f64]) -> err {
    if src.rows != src.cols || dst.rows != src.rows || dst.cols != src.cols { ret Shape }
    let n = src.rows
    let (scratch, scratch_error) = mem.alloc[f64](a, n * n + n * 2usize)
    if scratch_error != ok { ret scratch_error }
    let (perm, perm_error) = mem.alloc[usize](a, n)
    if perm_error != ok { ret perm_error }
    let (factors, view_error) = view[f64](scratch[..n * n], n, n, n)
    if view_error != ok { ret view_error }
    let (_, factor_error) = lu_factor(factors, perm, src)
    if factor_error != ok { ret factor_error }
    let unit = scratch[n * n..n * n + n]
    let column = scratch[n * n + n..]
    var c = 0usize
    while c < n {
        var i = 0usize
        while i < n {
            unit[i] = 0.0
            i += 1usize
        }
        unit[c] = 1.0
        let solve_error = solve_lu(as_const[f64](factors), perm, column, unit)
        if solve_error != ok { ret solve_error }
        i = 0usize
        while i < n {
            dst.data[i * dst.stride + c] = column[i]
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// The lower Cholesky factor of a symmetric positive-definite `src` (only its lower
// triangle is read): `src` = L·Lᵀ.
fn cholesky(l: Matrix[f64], src: ConstMatrix[f64]) -> err {
    if src.rows != src.cols || l.rows != src.rows || l.cols != src.cols { ret Shape }
    let n = src.rows
    fill[f64](l, 0.0)
    var j = 0usize
    while j < n {
        var i = j
        while i < n {
            var total = src.data[i * src.stride + j]
            var k = 0usize
            while k < j {
                total = total - l.data[i * l.stride + k] * l.data[j * l.stride + k]
                k += 1usize
            }
            if i == j {
                if total <= 0.0 { ret NotPositiveDefinite }
                l.data[j * l.stride + j] = math.sqrt[f64](total)
            } else {
                l.data[i * l.stride + j] = total / l.data[j * l.stride + j]
            }
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// The Householder reflector H = I - beta·v·vᵀ sending `x` to ‖x‖·e1: `out` receives v
// with v[0] = 1 and the answer is beta (0 when `x` already lies on e1). `out` may be `x`.
fn householder_vector(x: []const f64, out: []f64) -> (f64, err) {
    let n = x.len
    if n == 0usize || out.len < n { ret (0.0, TooSmall) }
    let head = x[0]
    var sigma: f64 = 0.0
    var i = 1usize
    while i < n {
        sigma = sigma + x[i] * x[i]
        i += 1usize
    }
    if sigma == 0.0 {
        out[0] = 1.0
        i = 1usize
        while i < n {
            out[i] = 0.0
            i += 1usize
        }
        ret (0.0, ok)
    }
    let mu = math.sqrt[f64](head * head + sigma)
    var lead = head - mu
    if head > 0.0 { lead = (0.0 - sigma) / (head + mu) }
    let beta = 2.0 * lead * lead / (sigma + lead * lead)
    i = 1usize
    while i < n {
        out[i] = x[i] / lead
        i += 1usize
    }
    out[0] = 1.0
    ret (beta, ok)
}

// `m` ← H·m for the reflector (`v`, `beta`); `m.rows` = `v.len`.
fn householder_apply_left(m: Matrix[f64], v: []const f64, beta: f64) -> err {
    if m.rows != v.len { ret Shape }
    var c = 0usize
    while c < m.cols {
        var w: f64 = 0.0
        var k = 0usize
        while k < m.rows {
            w = w + v[k] * m.data[k * m.stride + c]
            k += 1usize
        }
        w = w * beta
        k = 0usize
        while k < m.rows {
            m.data[k * m.stride + c] = m.data[k * m.stride + c] - w * v[k]
            k += 1usize
        }
        c += 1usize
    }
    ret ok
}

// `m` ← m·H for the reflector (`v`, `beta`); `m.cols` = `v.len`.
fn householder_apply_right(m: Matrix[f64], v: []const f64, beta: f64) -> err {
    if m.cols != v.len { ret Shape }
    var r = 0usize
    while r < m.rows {
        var w: f64 = 0.0
        var k = 0usize
        while k < m.cols {
            w = w + m.data[r * m.stride + k] * v[k]
            k += 1usize
        }
        w = w * beta
        k = 0usize
        while k < m.cols {
            m.data[r * m.stride + k] = m.data[r * m.stride + k] - w * v[k]
            k += 1usize
        }
        r += 1usize
    }
    ret ok
}

// Householder QR of an m x n `src`: `q` is m x m orthogonal, `r` is m x n upper
// triangular and `q`·`r` = `src`; `work` holds one reflector (`work.len` >= m).
fn qr(q: Matrix[f64], r: Matrix[f64], src: ConstMatrix[f64], work: []f64) -> err {
    let m = src.rows
    let n = src.cols
    if q.rows != m || q.cols != m || r.rows != m || r.cols != n { ret Shape }
    if work.len < m { ret TooSmall }
    let copy_error = copy[f64](r, src)
    if copy_error != ok { ret copy_error }
    identity(q)
    var steps = n
    if m == 0usize { ret ok }
    if m - 1usize < steps { steps = m - 1usize }
    var k = 0usize
    while k < steps {
        let v = work[k..m]
        var i = k
        while i < m {
            v[i - k] = r.data[i * r.stride + k]
            i += 1usize
        }
        let (beta, vector_error) = householder_vector(v, v)
        if vector_error != ok { ret vector_error }
        let left_error = householder_apply_left(sub(r, k, k, m - k, n - k), v, beta)
        if left_error != ok { ret left_error }
        i = k + 1usize
        while i < m {
            r.data[i * r.stride + k] = 0.0
            i += 1usize
        }
        let right_error = householder_apply_right(sub(q, 0usize, k, m, m - k), v, beta)
        if right_error != ok { ret right_error }
        k += 1usize
    }
    ret ok
}

// The rotation (c, s) with [c s; -s c]·[a; b] = [r; 0].
fn givens(a: f64, b: f64) -> (f64, f64) {
    if b == 0.0 { ret (1.0, 0.0) }
    if a == 0.0 { ret (0.0, 1.0) }
    let r = math.sqrt[f64](a * a + b * b)
    ret (a / r, b / r)
}

// Rows `i` and `k` of `m` rotated by (c, s): row i ← c·row i + s·row k, row k ← c·row k - s·row i.
fn givens_apply(m: Matrix[f64], i: usize, k: usize, c: f64, s: f64) -> err {
    if i >= m.rows || k >= m.rows || i == k { ret Shape }
    var col = 0usize
    while col < m.cols {
        let xi = m.data[i * m.stride + col]
        let xk = m.data[k * m.stride + col]
        m.data[i * m.stride + col] = c * xi + s * xk
        m.data[k * m.stride + col] = c * xk - s * xi
        col += 1usize
    }
    ret ok
}

// Modified Gram-Schmidt on the columns of `m` in place; `Singular` when a column lies in
// the span of those before it.
fn orthonormalize(m: Matrix[f64]) -> err {
    var j = 0usize
    while j < m.cols {
        var norm: f64 = 0.0
        var i = 0usize
        while i < m.rows {
            let x = m.data[i * m.stride + j]
            norm = norm + x * x
            i += 1usize
        }
        if norm == 0.0 { ret Singular }
        norm = math.sqrt[f64](norm)
        i = 0usize
        while i < m.rows {
            m.data[i * m.stride + j] = m.data[i * m.stride + j] / norm
            i += 1usize
        }
        var k = j + 1usize
        while k < m.cols {
            var dot: f64 = 0.0
            i = 0usize
            while i < m.rows {
                dot = dot + m.data[i * m.stride + j] * m.data[i * m.stride + k]
                i += 1usize
            }
            i = 0usize
            while i < m.rows {
                m.data[i * m.stride + k] = m.data[i * m.stride + k] - dot * m.data[i * m.stride + j]
                i += 1usize
            }
            k += 1usize
        }
        j += 1usize
    }
    ret ok
}

// Reduced row echelon form in place, treating magnitudes at or under `eps` as zero:
// answers the rank, with `pivots[0..rank]` the pivot columns.
fn rref(m: Matrix[f64], pivots: []usize, eps: f64) -> (usize, err) {
    var limit = m.rows
    if m.cols < limit { limit = m.cols }
    if pivots.len < limit { ret (0usize, TooSmall) }
    var rank = 0usize
    var col = 0usize
    while col < m.cols && rank < m.rows {
        var best = rank
        var best_size = math.abs[f64](m.data[rank * m.stride + col])
        var r = rank + 1usize
        while r < m.rows {
            let size = math.abs[f64](m.data[r * m.stride + col])
            if size > best_size {
                best = r
                best_size = size
            }
            r += 1usize
        }
        if best_size <= eps {
            col += 1usize
            continue
        }
        if best != rank { swap_view_rows(m, best, rank) }
        let lead = m.data[rank * m.stride + col]
        var c = col
        while c < m.cols {
            m.data[rank * m.stride + c] = m.data[rank * m.stride + c] / lead
            c += 1usize
        }
        r = 0usize
        while r < m.rows {
            let factor = m.data[r * m.stride + col]
            if r != rank && factor != 0.0 {
                c = col
                while c < m.cols {
                    m.data[r * m.stride + c] = m.data[r * m.stride + c] - factor * m.data[rank * m.stride + c]
                    c += 1usize
                }
            }
            r += 1usize
        }
        pivots[rank] = col
        rank += 1usize
        col += 1usize
    }
    ret (rank, ok)
}

// `dst` = `base`^`n` by repeated squaring; `dst` may not alias `base`.
fn pow(a: *mem.Arena, dst: Matrix[f64], base: ConstMatrix[f64], n: u64) -> err {
    if base.rows != base.cols || dst.rows != base.rows || dst.cols != base.cols { ret Shape }
    let k = base.rows
    let (scratch, scratch_error) = mem.alloc[f64](a, k * k * 2usize)
    if scratch_error != ok { ret scratch_error }
    let (square, square_error) = view[f64](scratch[..k * k], k, k, k)
    if square_error != ok { ret square_error }
    let (product, product_error) = view[f64](scratch[k * k..], k, k, k)
    if product_error != ok { ret product_error }
    identity(dst)
    let copy_error = copy[f64](square, base)
    if copy_error != ok { ret copy_error }
    var remaining = n
    while remaining > 0u64 {
        if (remaining & 1u64) == 1u64 {
            let _ = multiply[f64](product, as_const[f64](dst), as_const[f64](square))
            let _ = copy[f64](dst, as_const[f64](product))
        }
        remaining = remaining >> 1u32
        if remaining > 0u64 {
            let _ = multiply[f64](product, as_const[f64](square), as_const[f64](square))
            let _ = copy[f64](square, as_const[f64](product))
        }
    }
    ret ok
}

// The dominant eigenpair from the start vector `x` (which becomes the unit eigenvector):
// the Rayleigh quotient once it moves by at most `tolerance` between iterations, and the
// iterations used; `NoConvergence` after `max_iterations`. `work.len` >= n.
fn power_iteration(m: ConstMatrix[f64], x: []f64, work: []f64, tolerance: f64, max_iterations: u32) -> (f64, u32, err) {
    if m.rows != m.cols { ret (0.0, 0u32, Shape) }
    let n = m.rows
    if x.len < n || work.len < n { ret (0.0, 0u32, TooSmall) }
    var norm = vector_norm(x[..n])
    if norm == 0.0 { ret (0.0, 0u32, Singular) }
    var i = 0usize
    while i < n {
        x[i] = x[i] / norm
        i += 1usize
    }
    var value: f64 = 0.0
    var iterations = 0u32
    while iterations < max_iterations {
        var rayleigh: f64 = 0.0
        i = 0usize
        while i < n {
            var total: f64 = 0.0
            var j = 0usize
            while j < n {
                total = total + m.data[i * m.stride + j] * x[j]
                j += 1usize
            }
            work[i] = total
            rayleigh = rayleigh + x[i] * total
            i += 1usize
        }
        norm = vector_norm(work[..n])
        if norm == 0.0 { ret (0.0, iterations, Singular) }
        i = 0usize
        while i < n {
            x[i] = work[i] / norm
            i += 1usize
        }
        iterations += 1u32
        let moved = math.abs[f64](rayleigh - value)
        value = rayleigh
        if moved <= tolerance { ret (value, iterations, ok) }
    }
    ret (value, iterations, NoConvergence)
}

fn vector_norm(x: []const f64) -> f64 {
    var total: f64 = 0.0
    var i = 0usize
    while i < x.len {
        total = total + x[i] * x[i]
        i += 1usize
    }
    ret math.sqrt[f64](total)
}

// Eigenvalues (falling) and unit eigenvectors (the columns of `vectors`, in the same
// order) of a symmetric `src` by cyclic Jacobi rotations until the off-diagonal sum of
// squares is at most `tolerance`; `Unsupported` when `src` is not symmetric to within
// `tolerance`, `NoConvergence` after `sweeps`.
fn eigen(a: *mem.Arena, values: []f64, vectors: Matrix[f64], src: ConstMatrix[f64], tolerance: f64, sweeps: u32) -> err {
    if src.rows != src.cols || vectors.rows != src.rows || vectors.cols != src.cols { ret Shape }
    let n = src.rows
    if values.len < n { ret TooSmall }
    var p = 0usize
    while p < n {
        var q = p + 1usize
        while q < n {
            if math.abs[f64](src.data[p * src.stride + q] - src.data[q * src.stride + p]) > tolerance { ret Unsupported }
            q += 1usize
        }
        p += 1usize
    }
    let (scratch, scratch_error) = mem.alloc[f64](a, n * n)
    if scratch_error != ok { ret scratch_error }
    let (w, view_error) = view[f64](scratch, n, n, n)
    if view_error != ok { ret view_error }
    let _ = copy[f64](w, src)
    identity(vectors)
    var sweep = 0u32
    var converged = false
    while sweep < sweeps && !converged {
        var off: f64 = 0.0
        p = 0usize
        while p < n {
            var q = p + 1usize
            while q < n {
                let apq = scratch[p * n + q]
                off = off + apq * apq
                if apq != 0.0 {
                    let theta = (scratch[q * n + q] - scratch[p * n + p]) / (2.0 * apq)
                    var t = 1.0 / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0))
                    if theta < 0.0 { t = 0.0 - t }
                    let c = 1.0 / math.sqrt[f64](t * t + 1.0)
                    let s = t * c
                    var k = 0usize
                    while k < n {
                        let akp = scratch[k * n + p]
                        let akq = scratch[k * n + q]
                        scratch[k * n + p] = c * akp - s * akq
                        scratch[k * n + q] = s * akp + c * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < n {
                        let apk = scratch[p * n + k]
                        let aqk = scratch[q * n + k]
                        scratch[p * n + k] = c * apk - s * aqk
                        scratch[q * n + k] = s * apk + c * aqk
                        k += 1usize
                    }
                    rotate_columns(vectors, p, q, c, s)
                }
                q += 1usize
            }
            p += 1usize
        }
        sweep += 1u32
        if off <= tolerance { converged = true }
    }
    if !converged { ret NoConvergence }
    var i = 0usize
    while i < n {
        values[i] = scratch[i * n + i]
        i += 1usize
    }
    var none: Matrix[f64] = zero
    sort_columns(values[..n], vectors, none)
    ret ok
}

// Columns `p` and `q` of `m` rotated: col p ← c·col p - s·col q, col q ← s·col p + c·col q.
fn rotate_columns(m: Matrix[f64], p: usize, q: usize, c: f64, s: f64) {
    var k = 0usize
    while k < m.rows {
        let vkp = m.data[k * m.stride + p]
        let vkq = m.data[k * m.stride + q]
        m.data[k * m.stride + p] = c * vkp - s * vkq
        m.data[k * m.stride + q] = s * vkp + c * vkq
        k += 1usize
    }
}

fn swap_columns(m: Matrix[f64], first: usize, second: usize) {
    var k = 0usize
    while k < m.rows {
        let carried = m.data[k * m.stride + first]
        m.data[k * m.stride + first] = m.data[k * m.stride + second]
        m.data[k * m.stride + second] = carried
        k += 1usize
    }
}

// Selection sort of `values` falling, carrying the columns of `left` and `right` along
// (a zero-row `right` carries nothing).
fn sort_columns(values: []f64, left: Matrix[f64], right: Matrix[f64]) {
    var i = 0usize
    while i < values.len {
        var best = i
        var j = i + 1usize
        while j < values.len {
            if values[j] > values[best] { best = j }
            j += 1usize
        }
        if best != i {
            let carried = values[i]
            values[i] = values[best]
            values[best] = carried
            swap_columns(left, i, best)
            swap_columns(right, i, best)
        }
        i += 1usize
    }
}

// Thin SVD of an m x n `src` with k = min(m, n): `u` is m x k, `s` the k singular values
// falling, `v` is n x k, and u·diag(s)·vᵀ = `src`. One-sided (Hestenes) Jacobi sweeps
// until every column pair is orthogonal to within `tolerance`; `NoConvergence` after `sweeps`.
fn svd(a: *mem.Arena, u: Matrix[f64], s: []f64, v: Matrix[f64], src: ConstMatrix[f64], tolerance: f64, sweeps: u32) -> err {
    let m = src.rows
    let n = src.cols
    var k = n
    if m < k { k = m }
    if u.rows != m || u.cols != k || v.rows != n || v.cols != k { ret Shape }
    if s.len < k { ret TooSmall }
    // The tall side (max(m, n) x k) is worked on; the square side collects the rotations.
    var tall = u
    var square = v
    var source = src
    if m < n {
        tall = v
        square = u
        var flipped: ConstMatrix[f64] = zero
        flipped.data = src.data
        flipped.rows = n
        flipped.cols = m
        flipped.stride = src.stride
        source = flipped
    }
    let rows = tall.rows
    let (scratch, scratch_error) = mem.alloc[f64](a, rows * k)
    if scratch_error != ok { ret scratch_error }
    let (w, view_error) = view[f64](scratch, rows, k, k)
    if view_error != ok { ret view_error }
    if m < n {
        var r = 0usize
        while r < rows {
            var c = 0usize
            while c < k {
                scratch[r * k + c] = source.data[c * source.stride + r]
                c += 1usize
            }
            r += 1usize
        }
    } else {
        let _ = copy[f64](w, source)
    }
    identity(square)
    var sweep = 0u32
    var converged = false
    while sweep < sweeps && !converged {
        converged = true
        var p = 0usize
        while p < k {
            var q = p + 1usize
            while q < k {
                var alpha: f64 = 0.0
                var beta: f64 = 0.0
                var gamma: f64 = 0.0
                var i = 0usize
                while i < rows {
                    let wp = scratch[i * k + p]
                    let wq = scratch[i * k + q]
                    alpha = alpha + wp * wp
                    beta = beta + wq * wq
                    gamma = gamma + wp * wq
                    i += 1usize
                }
                if math.abs[f64](gamma) > tolerance * math.sqrt[f64](alpha * beta) {
                    converged = false
                    let zeta = (beta - alpha) / (2.0 * gamma)
                    var t = 1.0 / (math.abs[f64](zeta) + math.sqrt[f64](1.0 + zeta * zeta))
                    if zeta < 0.0 { t = 0.0 - t }
                    let c = 1.0 / math.sqrt[f64](1.0 + t * t)
                    rotate_columns(w, p, q, c, c * t)
                    rotate_columns(square, p, q, c, c * t)
                }
                q += 1usize
            }
            p += 1usize
        }
        sweep += 1u32
    }
    if !converged { ret NoConvergence }
    var j = 0usize
    while j < k {
        var norm: f64 = 0.0
        var i = 0usize
        while i < rows {
            norm = norm + scratch[i * k + j] * scratch[i * k + j]
            i += 1usize
        }
        norm = math.sqrt[f64](norm)
        s[j] = norm
        // ponytail: a zero singular value leaves a zero column, not an orthonormal completion.
        i = 0usize
        while i < rows {
            var x = scratch[i * k + j]
            if norm != 0.0 { x = x / norm }
            tall.data[i * tall.stride + j] = x
            i += 1usize
        }
        j += 1usize
    }
    sort_columns(s[..k], tall, square)
    ret ok
}

// A multigrid V-cycle solver for -u'' = f on (0, 1) with u(0) = u(1) = 0, discretised on
// the `n` = 2^k - 1 interior points of a uniform grid (`u.len` = n, `Shape` otherwise):
// `cycles` V-cycles from the caller's `u`, each with `smooth` weighted-Jacobi sweeps
// (weight 2/3) before and after full-weighting restriction, recursion to one point and
// linear prolongation. Answers the 2-norm of the residual f - A·u.
fn multigrid(a: *mem.Arena, u: []f64, f: []const f64, cycles: u32, smooth: u32) -> (f64, err) {
    let n = u.len
    if n == 0usize || ((n + 1usize) & n) != 0usize { ret (0.0, Shape) }
    if f.len < n { ret (0.0, TooSmall) }
    var cycle = 0u32
    while cycle < cycles {
        let cycle_error = vcycle(a, u, f[..n], smooth)
        if cycle_error != ok { ret (0.0, cycle_error) }
        cycle += 1u32
    }
    let (scratch, scratch_error) = mem.alloc[f64](a, n)
    if scratch_error != ok { ret (0.0, scratch_error) }
    poisson_residual(scratch, u, f[..n])
    ret (vector_norm(scratch), ok)
}

fn poisson_spacing_squared(n: usize) -> f64 {
    let h = 1.0 / f64(n + 1usize)
    ret h * h
}

fn poisson_residual(r: []f64, u: []const f64, f: []const f64) {
    let n = u.len
    let h2 = poisson_spacing_squared(n)
    var i = 0usize
    while i < n {
        var neighbours: f64 = 0.0
        if i > 0usize { neighbours = neighbours + u[i - 1usize] }
        if i + 1usize < n { neighbours = neighbours + u[i + 1usize] }
        r[i] = f[i] - (2.0 * u[i] - neighbours) / h2
        i += 1usize
    }
}

fn weighted_jacobi(u: []f64, f: []const f64, scratch: []f64, sweeps: u32) {
    let n = u.len
    let h2 = poisson_spacing_squared(n)
    var sweep = 0u32
    while sweep < sweeps {
        var i = 0usize
        while i < n {
            var neighbours: f64 = 0.0
            if i > 0usize { neighbours = neighbours + u[i - 1usize] }
            if i + 1usize < n { neighbours = neighbours + u[i + 1usize] }
            scratch[i] = (f[i] * h2 + neighbours) / 2.0
            i += 1usize
        }
        i = 0usize
        while i < n {
            u[i] = u[i] / 3.0 + scratch[i] * 2.0 / 3.0
            i += 1usize
        }
        sweep += 1u32
    }
}

fn vcycle(a: *mem.Arena, u: []f64, f: []const f64, smooth: u32) -> err {
    let n = u.len
    if n == 1usize {
        u[0] = f[0] * poisson_spacing_squared(n) / 2.0
        ret ok
    }
    let coarse = (n - 1usize) / 2usize
    let (scratch, scratch_error) = mem.alloc[f64](a, n * 2usize + coarse * 2usize)
    if scratch_error != ok { ret scratch_error }
    let work = scratch[..n]
    let residual = scratch[n..n * 2usize]
    let coarse_f = scratch[n * 2usize..n * 2usize + coarse]
    let coarse_u = scratch[n * 2usize + coarse..]
    weighted_jacobi(u, f, work, smooth)
    poisson_residual(residual, u, f)
    var j = 0usize
    while j < coarse {
        coarse_f[j] = (residual[2usize * j] + 2.0 * residual[2usize * j + 1usize] + residual[2usize * j + 2usize]) / 4.0
        coarse_u[j] = 0.0
        j += 1usize
    }
    let coarse_error = vcycle(a, coarse_u, coarse_f, smooth)
    if coarse_error != ok { ret coarse_error }
    j = 0usize
    while j < coarse {
        u[2usize * j + 1usize] = u[2usize * j + 1usize] + coarse_u[j]
        j += 1usize
    }
    j = 0usize
    while j <= coarse {
        var correction: f64 = 0.0
        if j > 0usize { correction = correction + coarse_u[j - 1usize] }
        if j < coarse { correction = correction + coarse_u[j] }
        u[2usize * j] = u[2usize * j] + correction / 2.0
        j += 1usize
    }
    weighted_jacobi(u, f, work, smooth)
    ret ok
}

// The planned name of `householder_vector`: the reflector sending `x` to ‖x‖·e1.
fn householder(x: []const f64, out: []f64) -> (f64, err) {
    let (beta, reflect_error) = householder_vector(x, out)
    ret (beta, reflect_error)
}
