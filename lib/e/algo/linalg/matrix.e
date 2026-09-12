// Row-major matrix views over caller storage: element (r, c) is `data[r * stride + c]`,
// so a transpose is a view with the two dimensions swapped -- which is why a `Matrix`
// carries its stride and why `transpose` costs nothing. `Shape` is any mismatch of
// dimensions or a view its data cannot hold; `Singular` is a pivot of zero.

use e.mem

type Matrix[T: type] = struct { data: []T, rows: usize, cols: usize, stride: usize }
type ConstMatrix[T: type] = struct { data: []const T, rows: usize, cols: usize, stride: usize }
error Shape
error Singular

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
