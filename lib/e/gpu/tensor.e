// Tensors on a device (spec section 10): a `Tensor[T]` is a `gpu.Buf[T]` holding a
// row-major contiguous copy of a host view, with its shape and strides in the
// caller's arena. `upload` gathers a strided host view into that order through a
// host copy from `a`, then one `gpu.upload`; `download` is one `gpu.download` into a
// host view that is row-major contiguous (`Shape` otherwise: there is no arena here
// to gather through); `add` and `matmul` are launches of the kernels below, one per
// element type -- `f32`, `f64`, `i32`, `i64`, `u32`, `u64` -- chosen at compile time
// by `meta.kind[T]`, `mem.size_of[T]` and `meta.signed[T]` (the questions D138 and
// D782 fold), since a kernel takes no comptime parameter; a narrower integer or a
// float of another width is `gpu.Unsupported`. Every operation is one
// queue submission and nothing here opens a device. A float add or multiply-add is
// one IEEE operation each, never fused, so the CPU build and a device agree bit for
// bit (section 11).
//
// `matmul` is the plain rank-2 product, `dst[r, c] = sum over t of x[r, t] * y[t, c]`,
// with `x` `m x k`, `y` `k x n` and `dst` `m x n`; it and `add` want the operands
// contiguous, which every tensor `upload` makes is. ponytail: one invocation per
// output element and no tiling; the barrier slice brings shared-memory tiles.

use e.algo.linalg.tensor as linalg_tensor
use e.gpu
use e.mem
use e.meta

type Tensor[T: type] = struct { data: gpu.Buf[T], shape: []const usize, stride: []const usize }
error Shape

@gpu(256)
fn add_f32(n: u32, x: []const f32, y: []const f32, dst: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    dst[usize(i)] = x[usize(i)] + y[usize(i)]
}

@gpu(256)
fn add_f64(n: u32, x: []const f64, y: []const f64, dst: []f64) {
    let i = gpu.gid.x
    if i >= n { ret }
    dst[usize(i)] = x[usize(i)] + y[usize(i)]
}

@gpu(256)
fn add_i32(n: u32, x: []const i32, y: []const i32, dst: []i32) {
    let i = gpu.gid.x
    if i >= n { ret }
    dst[usize(i)] = x[usize(i)] + y[usize(i)]
}

@gpu(256)
fn add_i64(n: u32, x: []const i64, y: []const i64, dst: []i64) {
    let i = gpu.gid.x
    if i >= n { ret }
    dst[usize(i)] = x[usize(i)] + y[usize(i)]
}

@gpu(256)
fn add_u32(n: u32, x: []const u32, y: []const u32, dst: []u32) {
    let i = gpu.gid.x
    if i >= n { ret }
    dst[usize(i)] = x[usize(i)] + y[usize(i)]
}

@gpu(256)
fn add_u64(n: u32, x: []const u64, y: []const u64, dst: []u64) {
    let i = gpu.gid.x
    if i >= n { ret }
    dst[usize(i)] = x[usize(i)] + y[usize(i)]
}

@gpu(16, 16)
fn matmul_f32(m: u32, n: u32, k: u32, x: []const f32, y: []const f32, dst: []f32) {
    let c = gpu.gid.x
    let r = gpu.gid.y
    if c >= n || r >= m { ret }
    var total: f32 = 0.0
    var t = 0usize
    while t < usize(k) {
        let product = x[usize(r) * usize(k) + t] * y[t * usize(n) + usize(c)]
        total = total + product
        t += 1usize
    }
    dst[usize(r) * usize(n) + usize(c)] = total
}

@gpu(16, 16)
fn matmul_f64(m: u32, n: u32, k: u32, x: []const f64, y: []const f64, dst: []f64) {
    let c = gpu.gid.x
    let r = gpu.gid.y
    if c >= n || r >= m { ret }
    var total: f64 = 0.0
    var t = 0usize
    while t < usize(k) {
        let product = x[usize(r) * usize(k) + t] * y[t * usize(n) + usize(c)]
        total = total + product
        t += 1usize
    }
    dst[usize(r) * usize(n) + usize(c)] = total
}

@gpu(16, 16)
fn matmul_i32(m: u32, n: u32, k: u32, x: []const i32, y: []const i32, dst: []i32) {
    let c = gpu.gid.x
    let r = gpu.gid.y
    if c >= n || r >= m { ret }
    var total = 0i32
    var t = 0usize
    while t < usize(k) {
        total = total + x[usize(r) * usize(k) + t] * y[t * usize(n) + usize(c)]
        t += 1usize
    }
    dst[usize(r) * usize(n) + usize(c)] = total
}

@gpu(16, 16)
fn matmul_i64(m: u32, n: u32, k: u32, x: []const i64, y: []const i64, dst: []i64) {
    let c = gpu.gid.x
    let r = gpu.gid.y
    if c >= n || r >= m { ret }
    var total = 0i64
    var t = 0usize
    while t < usize(k) {
        total = total + x[usize(r) * usize(k) + t] * y[t * usize(n) + usize(c)]
        t += 1usize
    }
    dst[usize(r) * usize(n) + usize(c)] = total
}

@gpu(16, 16)
fn matmul_u32(m: u32, n: u32, k: u32, x: []const u32, y: []const u32, dst: []u32) {
    let c = gpu.gid.x
    let r = gpu.gid.y
    if c >= n || r >= m { ret }
    var total = 0u32
    var t = 0usize
    while t < usize(k) {
        total = total + x[usize(r) * usize(k) + t] * y[t * usize(n) + usize(c)]
        t += 1usize
    }
    dst[usize(r) * usize(n) + usize(c)] = total
}

@gpu(16, 16)
fn matmul_u64(m: u32, n: u32, k: u32, x: []const u64, y: []const u64, dst: []u64) {
    let c = gpu.gid.x
    let r = gpu.gid.y
    if c >= n || r >= m { ret }
    var total = 0u64
    var t = 0usize
    while t < usize(k) {
        total = total + x[usize(r) * usize(k) + t] * y[t * usize(n) + usize(c)]
        t += 1usize
    }
    dst[usize(r) * usize(n) + usize(c)] = total
}

fn count_of(shape: []const usize) -> usize {
    var total = 1usize
    var d = 0usize
    while d < shape.len {
        total = total * shape[d]
        d += 1usize
    }
    ret total
}

fn same_shape(a: []const usize, b: []const usize) -> bool {
    if a.len != b.len { ret false }
    var d = 0usize
    while d < a.len {
        if a[d] != b[d] { ret false }
        d += 1usize
    }
    ret true
}

fn upload[T: type](a: *mem.Arena, queue: *gpu.Queue, src: linalg_tensor.ConstTensor[T]) -> (Tensor[T], err) {
    if src.shape.len == 0usize || src.shape.len > 8usize || src.stride.len != src.shape.len { ret (zero, Shape) }
    let total = count_of(src.shape)
    let (shape, shape_error) = mem.alloc[usize](a, src.shape.len)
    if shape_error != ok { ret (zero, shape_error) }
    let (stride, stride_error) = mem.alloc[usize](a, src.shape.len)
    if stride_error != ok { ret (zero, stride_error) }
    var step = 1usize
    var d = src.shape.len
    while d > 0usize {
        d -= 1usize
        shape[d] = src.shape[d]
        stride[d] = step
        step = step * src.shape[d]
    }
    // Gathered row-major into a host copy, then uploaded in one submission.
    let (packed, packed_error) = mem.alloc[T](a, total)
    if packed_error != ok { ret (zero, packed_error) }
    if total > 0usize {
        var index: [8]usize = zero
        let cursor = index[..src.shape.len]
        var at = 0usize
        while true {
            packed[at] = src.data[linalg_tensor.offset_of(cursor, src.stride)]
            at += 1usize
            if !linalg_tensor.next_index(src.shape, cursor) { break }
        }
    }
    let (data, upload_error) = gpu.upload[T](queue, packed)
    if upload_error != ok { ret (zero, upload_error) }
    ret (Tensor[T] { data: data, shape: shape, stride: stride }, ok)
}

fn download[T: type](queue: *gpu.Queue, src: Tensor[T], dst: linalg_tensor.Tensor[T]) -> err {
    if !same_shape(src.shape, dst.shape) || !linalg_tensor.is_row_major[T](dst) { ret Shape }
    let total = count_of(src.shape)
    if dst.data.len < total { ret Shape }
    ret gpu.download[T](queue, src.data, dst.data[..total])
}

fn add[T: type](queue: *gpu.Queue, dst: Tensor[T], x: Tensor[T], y: Tensor[T]) -> err {
    if !same_shape(dst.shape, x.shape) || !same_shape(dst.shape, y.shape) { ret Shape }
    let total = count_of(dst.shape)
    if total > 4294967295usize { ret gpu.TooLarge }
    let n = u32(total)
    let grid = gpu.grid1(total)
    // Each arm the folded questions leave is the one kernel `T` can reach.
    if meta.kind[T]() == .Float {
        if mem.size_of[T]() == 4usize {
            ret gpu.launch[add_f32](queue, grid, n, x.data, y.data, dst.data)
        } else {
            if mem.size_of[T]() == 8usize {
                ret gpu.launch[add_f64](queue, grid, n, x.data, y.data, dst.data)
            } else {
                ret gpu.Unsupported
            }
        }
    } else {
        if meta.kind[T]() == .Int {
            if meta.signed[T]() {
                if mem.size_of[T]() == 4usize {
                    ret gpu.launch[add_i32](queue, grid, n, x.data, y.data, dst.data)
                } else {
                    if mem.size_of[T]() == 8usize {
                        ret gpu.launch[add_i64](queue, grid, n, x.data, y.data, dst.data)
                    } else {
                        ret gpu.Unsupported
                    }
                }
            } else {
                if mem.size_of[T]() == 4usize {
                    ret gpu.launch[add_u32](queue, grid, n, x.data, y.data, dst.data)
                } else {
                    if mem.size_of[T]() == 8usize {
                        ret gpu.launch[add_u64](queue, grid, n, x.data, y.data, dst.data)
                    } else {
                        ret gpu.Unsupported
                    }
                }
            }
        } else {
            ret gpu.Unsupported
        }
    }
}

fn matmul[T: type](queue: *gpu.Queue, dst: Tensor[T], x: Tensor[T], y: Tensor[T]) -> err {
    if dst.shape.len != 2usize || x.shape.len != 2usize || y.shape.len != 2usize { ret Shape }
    if x.shape[1usize] != y.shape[0usize] || dst.shape[0usize] != x.shape[0usize] || dst.shape[1usize] != y.shape[1usize] { ret Shape }
    if dst.shape[0usize] > 4294967295usize || dst.shape[1usize] > 4294967295usize || x.shape[1usize] > 4294967295usize { ret gpu.TooLarge }
    let m = u32(dst.shape[0usize])
    let n = u32(dst.shape[1usize])
    let k = u32(x.shape[1usize])
    let grid = gpu.grid2(dst.shape[1usize], dst.shape[0usize])
    if meta.kind[T]() == .Float {
        if mem.size_of[T]() == 4usize {
            ret gpu.launch[matmul_f32](queue, grid, m, n, k, x.data, y.data, dst.data)
        } else {
            if mem.size_of[T]() == 8usize {
                ret gpu.launch[matmul_f64](queue, grid, m, n, k, x.data, y.data, dst.data)
            } else {
                ret gpu.Unsupported
            }
        }
    } else {
        if meta.kind[T]() == .Int {
            if meta.signed[T]() {
                if mem.size_of[T]() == 4usize {
                    ret gpu.launch[matmul_i32](queue, grid, m, n, k, x.data, y.data, dst.data)
                } else {
                    if mem.size_of[T]() == 8usize {
                        ret gpu.launch[matmul_i64](queue, grid, m, n, k, x.data, y.data, dst.data)
                    } else {
                        ret gpu.Unsupported
                    }
                }
            } else {
                if mem.size_of[T]() == 4usize {
                    ret gpu.launch[matmul_u32](queue, grid, m, n, k, x.data, y.data, dst.data)
                } else {
                    if mem.size_of[T]() == 8usize {
                        ret gpu.launch[matmul_u64](queue, grid, m, n, k, x.data, y.data, dst.data)
                    } else {
                        ret gpu.Unsupported
                    }
                }
            }
        } else {
            ret gpu.Unsupported
        }
    }
}

fn release[T: type](queue: *gpu.Queue, tensor_view: Tensor[T]) -> err {
    ret gpu.release[T](queue, tensor_view.data)
}
