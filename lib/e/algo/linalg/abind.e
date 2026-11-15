// abind: bind arrays of any rank along any dimension, as R's abind package does it. Arrays are
// column-major, as in R: element (i1, .., iN) is at i1 + d1 (i2 + d2 (i3 + ..)). A rank-1 array
// is a vector.
//
// `along` names the dimension, 1 .. N, with N the largest rank among the arrays; a value below 1
// or above N, or one between two integers, makes a new dimension (before the next one for 1.5,
// after the last for N + 1 and 2.5 with N = 2). `rev_along` counts from the last dimension
// instead (NaN leaves it unset). An array one rank below the others is taken to have a unit
// dimension at `along`. With `force_array` false and a result of rank 2 the call is R's
// `cbind` or `rbind`, which recycles a vector to the matrix's length.
//
// Not here: dimnames and `new.names`, since an `Array` has no names to carry.

use e.math
use e.mem

type Array = struct { dims: []const usize, data: []const f64 }

error Mismatch
error BadAlong

fn product(d: []const usize, from: usize, to: usize) -> usize {
    var p = 1usize
    var i = from
    while i < to {
        p = p * d[i]
        i += 1usize
    }
    ret p
}

fn is_nan(x: f64) -> bool { ret x != x }

// cbind (along 2) or rbind (along 1) of matrices and vectors, vectors recycled.
fn bind_matrices(a: *mem.Arena, arrays: []const Array, rows: bool) -> (Array, err) {
    var none: Array = zero
    var fixed = 0usize
    var have_matrix = false
    var longest = 0usize
    var i = 0usize
    while i < arrays.len {
        if arrays[i].dims.len == 2usize {
            var extent = arrays[i].dims[0usize]
            if rows { extent = arrays[i].dims[1usize] }
            if have_matrix && extent != fixed { ret (none, Mismatch) }
            fixed = extent
            have_matrix = true
        } else {
            if arrays[i].data.len > longest { longest = arrays[i].data.len }
        }
        i += 1usize
    }
    if !have_matrix { fixed = longest }
    var total = 0usize
    i = 0usize
    while i < arrays.len {
        if arrays[i].dims.len == 2usize {
            if rows { total += arrays[i].dims[0usize] } else { total += arrays[i].dims[1usize] }
        } else {
            total += 1usize
        }
        i += 1usize
    }
    let (data, data_error) = mem.alloc[f64](a, fixed * total)
    let (dims, dims_error) = mem.alloc[usize](a, 2usize)
    if data_error != ok { ret (none, data_error) }
    if dims_error != ok { ret (none, dims_error) }
    var at = 0usize
    i = 0usize
    while i < arrays.len {
        let m = arrays[i]
        var count = 1usize
        if m.dims.len == 2usize {
            if rows { count = m.dims[0usize] } else { count = m.dims[1usize] }
        }
        var k = 0usize
        while k < count {
            var j = 0usize
            while j < fixed {
                var value = 0.0f64
                if m.dims.len == 2usize {
                    if rows { value = m.data[k + m.dims[0usize] * j] } else { value = m.data[j + m.dims[0usize] * k] }
                } else {
                    if m.data.len > 0usize { value = m.data[j % m.data.len] }
                }
                if rows { data[(at + k) + total * j] = value } else { data[j + fixed * (at + k)] = value }
                j += 1usize
            }
            k += 1usize
        }
        at += count
        i += 1usize
    }
    if rows {
        dims[0usize] = total
        dims[1usize] = fixed
    } else {
        dims[0usize] = fixed
        dims[1usize] = total
    }
    ret (Array { dims: dims, data: data }, ok)
}

fn abind(a: *mem.Arena, arrays: []const Array, along0: f64, rev_along: f64, force_array: bool) -> (Array, err) {
    var none: Array = zero
    if arrays.len == 0usize { ret (none, Mismatch) }
    var n = 1usize
    var i = 0usize
    while i < arrays.len {
        if arrays[i].dims.len > n { n = arrays[i].dims.len }
        i += 1usize
    }
    var along = along0
    if !is_nan(rev_along) { along = f64(n) + 1.0f64 - rev_along }
    if along < 1.0f64 || along > f64(n) || (along > math.floor[f64](along) && along < math.ceil[f64](along)) {
        n += 1usize
        var up = math.ceil[f64](along)
        if up > f64(n) + 1.0f64 { up = f64(n) + 1.0f64 }
        if up < 1.0f64 { up = 1.0f64 }
        along = up
    }
    if along < 1.0f64 || along > f64(n) + 1.0f64 { ret (none, BadAlong) }
    if !force_array && n == 2usize {
        if along == 2.0f64 {
            let (r2, e2) = bind_matrices(a, arrays, false)
            ret (r2, e2)
        }
        if along == 1.0f64 {
            let (r1, e1) = bind_matrices(a, arrays, true)
            ret (r1, e1)
        }
    }
    if along > f64(n) { ret (none, BadAlong) }
    let ax = usize(along) - 1usize
    let (dims, dims_error) = mem.alloc[usize](a, n)
    if dims_error != ok { ret (none, dims_error) }
    var total_along = 0usize
    var first = true
    i = 0usize
    while i < arrays.len {
        let m = arrays[i]
        var d: [16]usize = zero
        if n > 16usize { ret (none, Mismatch) }
        if m.dims.len == n {
            var k = 0usize
            while k < n {
                d[k] = m.dims[k]
                k += 1usize
            }
        } else if m.dims.len + 1usize == n {
            var k = 0usize
            var src = 0usize
            while k < n {
                if k == ax {
                    d[k] = 1usize
                } else {
                    d[k] = m.dims[src]
                    src += 1usize
                }
                k += 1usize
            }
        } else {
            ret (none, Mismatch)
        }
        var k = 0usize
        while k < n {
            if k != ax {
                if first { dims[k] = d[k] } else if dims[k] != d[k] { ret (none, Mismatch) }
            }
            k += 1usize
        }
        first = false
        total_along += d[ax]
        i += 1usize
    }
    dims[ax] = total_along
    var pre = 1usize
    var k = 0usize
    while k < ax {
        pre = pre * dims[k]
        k += 1usize
    }
    var post = 1usize
    k = ax + 1usize
    while k < n {
        post = post * dims[k]
        k += 1usize
    }
    let (data, data_error) = mem.alloc[f64](a, pre * total_along * post)
    if data_error != ok { ret (none, data_error) }
    var offset = 0usize
    i = 0usize
    while i < arrays.len {
        let m = arrays[i]
        var extent = 1usize
        if m.dims.len == n { extent = m.dims[ax] }
        var q = 0usize
        while q < post {
            var s = 0usize
            while s < extent {
                var p = 0usize
                while p < pre {
                    data[p + pre * ((offset + s) + total_along * q)] = m.data[p + pre * (s + extent * q)]
                    p += 1usize
                }
                s += 1usize
            }
            q += 1usize
        }
        offset += extent
        i += 1usize
    }
    ret (Array { dims: dims, data: data }, ok)
}

// R's default `along`: the last dimension, N, the largest rank among the arrays (at least 1).
fn default_along(arrays: []const Array) -> f64 {
    var n = 1usize
    var i = 0usize
    while i < arrays.len {
        if arrays[i].dims.len > n { n = arrays[i].dims.len }
        i += 1usize
    }
    ret f64(n)
}
