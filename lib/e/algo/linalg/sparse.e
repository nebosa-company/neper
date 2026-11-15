// Compressed sparse column matrices: triplets in (duplicates summed, rows sorted per column),
// transpose, product with a dense matrix, product of two sparse matrices, and the sparse Cholesky
// factorisation A = L L' of a symmetric positive-definite matrix in its natural order (left-looking,
// the pattern of L found as the columns are computed) with the triangular solves. What the Matrix
// package answers for `A %*% B`, `crossprod(A)`, `chol(A)` and `solve(A, b)`.
//
// Not here: fill-reducing orderings (the factor of a permuted matrix is a different factor, the
// solution is the same), supernodal factors, LDL', sparse QR and complex entries.

use e.math
use e.mem

error Shape
error NotPositiveDefinite

type Csc = struct { nrow: usize, ncol: usize, colptr: []usize, rowidx: []usize, val: []f64 }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// The matrix of the triplets (i, j, x), 0-based; an entry listed twice is their sum.
fn from_triplets(a: *mem.Arena, nrow: usize, ncol: usize, ti: []const usize, tj: []const usize, tx: []const f64) -> (Csc, err) {
    var empty: Csc = zero
    let nnz = ti.len
    let (count, ce) = mem.alloc[usize](a, ncol + 2usize)
    let (order, oe) = mem.alloc[usize](a, nnz + 1usize)
    if ce != ok { ret (empty, ce) }
    if oe != ok { ret (empty, oe) }
    var k = 0usize
    while k <= ncol {
        count[k] = 0usize
        k += 1usize
    }
    k = 0usize
    while k < nnz {
        if ti[k] >= nrow || tj[k] >= ncol { ret (empty, Shape) }
        count[tj[k] + 1usize] += 1usize
        k += 1usize
    }
    var c = 0usize
    while c < ncol {
        count[c + 1usize] += count[c]
        c += 1usize
    }
    let (fill, fe) = mem.alloc[usize](a, ncol + 1usize)
    if fe != ok { ret (empty, fe) }
    c = 0usize
    while c < ncol {
        fill[c] = count[c]
        c += 1usize
    }
    k = 0usize
    while k < nnz {
        order[fill[tj[k]]] = k
        fill[tj[k]] += 1usize
        k += 1usize
    }
    let (colptr, pe) = mem.alloc[usize](a, ncol + 1usize)
    let (rowidx, re) = mem.alloc[usize](a, nnz + 1usize)
    let (val, ve) = mem.alloc[f64](a, nnz + 1usize)
    if pe != ok { ret (empty, pe) }
    if re != ok { ret (empty, re) }
    if ve != ok { ret (empty, ve) }
    var out = 0usize
    c = 0usize
    colptr[0usize] = 0usize
    while c < ncol {
        let from = count[c]
        let to = count[c + 1usize]
        // insertion sort of the column's entries by row (stable), then merge duplicates
        var p = from + 1usize
        while p < to {
            let item = order[p]
            var q = p
            while q > from && ti[order[q - 1usize]] > ti[item] {
                order[q] = order[q - 1usize]
                q -= 1usize
            }
            order[q] = item
            p += 1usize
        }
        p = from
        while p < to {
            let r = ti[order[p]]
            var s = 0.0f64
            while p < to && ti[order[p]] == r {
                s = s + tx[order[p]]
                p += 1usize
            }
            rowidx[out] = r
            val[out] = s
            out += 1usize
        }
        c += 1usize
        colptr[c] = out
    }
    ret (Csc { nrow: nrow, ncol: ncol, colptr: colptr, rowidx: rowidx[0usize..out], val: val[0usize..out] }, ok)
}

fn transpose(a: *mem.Arena, m: Csc) -> (Csc, err) {
    var empty: Csc = zero
    let nnz = m.rowidx.len
    let (ti, ie) = mem.alloc[usize](a, nnz + 1usize)
    let (tj, je) = mem.alloc[usize](a, nnz + 1usize)
    let (tx, xe) = mem.alloc[f64](a, nnz + 1usize)
    if ie != ok { ret (empty, ie) }
    if je != ok { ret (empty, je) }
    if xe != ok { ret (empty, xe) }
    var c = 0usize
    var n = 0usize
    while c < m.ncol {
        var p = m.colptr[c]
        while p < m.colptr[c + 1usize] {
            ti[n] = c
            tj[n] = m.rowidx[p]
            tx[n] = m.val[p]
            n += 1usize
            p += 1usize
        }
        c += 1usize
    }
    let (r, e) = from_triplets(a, m.ncol, m.nrow, ti[0usize..n], tj[0usize..n], tx[0usize..n])
    ret (r, e)
}

// A %*% B for a dense column-major B with `k` columns and ncol rows.
fn multiply_dense(a: *mem.Arena, m: Csc, b: []const f64, k: usize) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, m.nrow * k + 1usize)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < m.nrow * k {
        out[i] = 0.0f64
        i += 1usize
    }
    var col = 0usize
    while col < k {
        var c = 0usize
        while c < m.ncol {
            let bv = b[col * m.ncol + c]
            var p = m.colptr[c]
            while p < m.colptr[c + 1usize] {
                out[col * m.nrow + m.rowidx[p]] = out[col * m.nrow + m.rowidx[p]] + m.val[p] * bv
                p += 1usize
            }
            c += 1usize
        }
        col += 1usize
    }
    ret (out[0usize..m.nrow * k], ok)
}

// A %*% B for two sparse matrices, dense in the result's columns one at a time.
fn multiply(a: *mem.Arena, m: Csc, b: Csc) -> (Csc, err) {
    var empty: Csc = zero
    if m.ncol != b.nrow { ret (empty, Shape) }
    let (w, we) = mem.alloc[f64](a, m.nrow + 1usize)
    let (mark, mke) = mem.alloc[usize](a, m.nrow + 1usize)
    if we != ok { ret (empty, we) }
    if mke != ok { ret (empty, mke) }
    var cap = m.rowidx.len + b.rowidx.len + m.nrow + 16usize
    let (ti0, ie) = mem.alloc[usize](a, cap)
    let (tj0, je) = mem.alloc[usize](a, cap)
    let (tx0, xe) = mem.alloc[f64](a, cap)
    if ie != ok { ret (empty, ie) }
    if je != ok { ret (empty, je) }
    if xe != ok { ret (empty, xe) }
    var ti = ti0
    var tj = tj0
    var tx = tx0
    var n = 0usize
    var j = 0usize
    while j < b.ncol {
        var touched = 0usize
        var q = b.colptr[j]
        while q < b.colptr[j + 1usize] {
            let kcol = b.rowidx[q]
            let bv = b.val[q]
            var p = m.colptr[kcol]
            while p < m.colptr[kcol + 1usize] {
                let r = m.rowidx[p]
                if mark[r] != j + 1usize {
                    mark[r] = j + 1usize
                    w[r] = 0.0f64
                    touched += 1usize
                    if n >= cap {
                        let newcap = cap * 2usize
                        let (ni, nie) = mem.alloc[usize](a, newcap)
                        let (nj, nje) = mem.alloc[usize](a, newcap)
                        let (nx, nxe) = mem.alloc[f64](a, newcap)
                        if nie != ok { ret (empty, nie) }
                        if nje != ok { ret (empty, nje) }
                        if nxe != ok { ret (empty, nxe) }
                        var z = 0usize
                        while z < n {
                            ni[z] = ti[z]
                            nj[z] = tj[z]
                            nx[z] = tx[z]
                            z += 1usize
                        }
                        ti = ni
                        tj = nj
                        tx = nx
                        cap = newcap
                    }
                    ti[n] = r
                    tj[n] = j
                    n += 1usize
                }
                w[r] = w[r] + m.val[p] * bv
                p += 1usize
            }
            q += 1usize
        }
        var z = n - touched
        while z < n {
            tx[z] = w[ti[z]]
            z += 1usize
        }
        j += 1usize
    }
    let (r, e) = from_triplets(a, m.nrow, b.ncol, ti[0usize..n], tj[0usize..n], tx[0usize..n])
    ret (r, e)
}

type Chol = struct { n: usize, colptr: []usize, rowidx: []usize, val: []f64 }

// The lower factor L of a symmetric positive-definite A (both triangles may be stored; only the
// lower triangle is read), A = L L'. Each column of L has its diagonal first.
fn cholesky(a: *mem.Arena, m: Csc) -> (Chol, err) {
    var empty: Chol = zero
    if m.nrow != m.ncol { ret (empty, Shape) }
    let n = m.nrow
    let (w, we) = mem.alloc[f64](a, n + 1usize)
    let (inw, ie) = mem.alloc[bool](a, n + 1usize)
    let (head, he) = mem.alloc[usize](a, n + 2usize)
    let (nextc, ne) = mem.alloc[usize](a, n + 2usize)
    let (pos, pe) = mem.alloc[usize](a, n + 2usize)
    let (rows, re) = mem.alloc[usize](a, n + 2usize)
    if we != ok { ret (empty, we) }
    if ie != ok { ret (empty, ie) }
    if he != ok { ret (empty, he) }
    if ne != ok { ret (empty, ne) }
    if pe != ok { ret (empty, pe) }
    if re != ok { ret (empty, re) }
    let none = n + 1usize
    var i = 0usize
    while i <= n {
        head[i] = none
        nextc[i] = none
        inw[i] = false
        i += 1usize
    }
    var cap = m.rowidx.len * 2usize + n + 16usize
    let (lrow0, le) = mem.alloc[usize](a, cap)
    let (lval0, ve) = mem.alloc[f64](a, cap)
    if le != ok { ret (empty, le) }
    if ve != ok { ret (empty, ve) }
    var lrow = lrow0
    var lval = lval0
    let (colptr, cpe) = mem.alloc[usize](a, n + 2usize)
    if cpe != ok { ret (empty, cpe) }
    var used = 0usize
    colptr[0usize] = 0usize
    var j = 0usize
    while j < n {
        var nrows = 0usize
        // scatter the lower part of column j of A
        var p = m.colptr[j]
        while p < m.colptr[j + 1usize] {
            let r = m.rowidx[p]
            if r >= j {
                w[r] = m.val[p]
                inw[r] = true
                rows[nrows] = r
                nrows += 1usize
            }
            p += 1usize
        }
        if !inw[j] {
            w[j] = 0.0f64
            inw[j] = true
            rows[nrows] = j
            nrows += 1usize
        }
        // columns k < j with L[j, k] != 0 update column j
        var k = head[j]
        while k != none {
            let nk = nextc[k]
            let at = pos[k]
            let ljk = lval[at]
            var q = at
            while q < colptr[k + 1usize] {
                let r = lrow[q]
                if !inw[r] {
                    w[r] = 0.0f64
                    inw[r] = true
                    rows[nrows] = r
                    nrows += 1usize
                }
                w[r] = w[r] - lval[q] * ljk
                q += 1usize
            }
            // relink k under its next row
            pos[k] = at + 1usize
            if at + 1usize < colptr[k + 1usize] {
                let nr = lrow[at + 1usize]
                nextc[k] = head[nr]
                head[nr] = k
            }
            k = nk
        }
        let d = w[j]
        if !(d > 0.0f64) { ret (empty, NotPositiveDefinite) }
        let ljj = math.sqrt[f64](d)
        // sort the rows below the diagonal
        // place the diagonal first, the rest ascending
        var t = 0usize
        while t < nrows {
            if rows[t] == j {
                rows[t] = rows[0usize]
                rows[0usize] = j
            }
            t += 1usize
        }
        var s = 2usize
        while s < nrows {
            let item = rows[s]
            var q = s
            while q > 1usize && rows[q - 1usize] > item {
                rows[q] = rows[q - 1usize]
                q -= 1usize
            }
            rows[q] = item
            s += 1usize
        }
        if used + nrows + 1usize > cap {
            var newcap = cap * 2usize
            while newcap < used + nrows + 1usize { newcap = newcap * 2usize }
            let (nr2, nre) = mem.alloc[usize](a, newcap)
            let (nv2, nve) = mem.alloc[f64](a, newcap)
            if nre != ok { ret (empty, nre) }
            if nve != ok { ret (empty, nve) }
            var z = 0usize
            while z < used {
                nr2[z] = lrow[z]
                nv2[z] = lval[z]
                z += 1usize
            }
            lrow = nr2
            lval = nv2
            cap = newcap
        }
        let lo = used
        t = 0usize
        while t < nrows {
            let r = rows[t]
            lrow[used] = r
            if r == j { lval[used] = ljj } else { lval[used] = w[r] / ljj }
            used += 1usize
            inw[r] = false
            t += 1usize
        }
        colptr[j + 1usize] = used
        if used - lo > 1usize {
            pos[j] = lo + 1usize
            let nr = lrow[lo + 1usize]
            nextc[j] = head[nr]
            head[nr] = j
        }
        j += 1usize
    }
    ret (Chol { n: n, colptr: colptr[0usize..n + 1usize], rowidx: lrow[0usize..used], val: lval[0usize..used] }, ok)
}

// Solves L L' x = b for each of the k columns of b (n rows).
fn cholesky_solve(a: *mem.Arena, l: Chol, b: []const f64, k: usize) -> ([]f64, err) {
    let n = l.n
    let (x, e) = mem.alloc[f64](a, n * k + 1usize)
    if e != ok { ret (x, e) }
    var col = 0usize
    while col < k {
        var i = 0usize
        while i < n {
            x[col * n + i] = b[col * n + i]
            i += 1usize
        }
        // forward: L y = b
        var j = 0usize
        while j < n {
            let d = l.val[l.colptr[j]]
            x[col * n + j] = x[col * n + j] / d
            var p = l.colptr[j] + 1usize
            while p < l.colptr[j + 1usize] {
                x[col * n + l.rowidx[p]] = x[col * n + l.rowidx[p]] - l.val[p] * x[col * n + j]
                p += 1usize
            }
            j += 1usize
        }
        // backward: L' x = y
        var jj = n
        while jj > 0usize {
            jj -= 1usize
            var s = x[col * n + jj]
            var p = l.colptr[jj] + 1usize
            while p < l.colptr[jj + 1usize] {
                s = s - l.val[p] * x[col * n + l.rowidx[p]]
                p += 1usize
            }
            x[col * n + jj] = s / l.val[l.colptr[jj]]
        }
        col += 1usize
    }
    ret (x[0usize..n * k], ok)
}

// The upper factor R = L' as a dense column-major matrix, for comparison with R's chol.
fn upper_dense(a: *mem.Arena, l: Chol) -> ([]f64, err) {
    let n = l.n
    let (r, e) = mem.alloc[f64](a, n * n + 1usize)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < n * n {
        r[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < n {
        var p = l.colptr[j]
        while p < l.colptr[j + 1usize] {
            // L[row, j] is R[j, row]
            r[l.rowidx[p] * n + j] = l.val[p]
            p += 1usize
        }
        j += 1usize
    }
    ret (r[0usize..n * n], ok)
}
