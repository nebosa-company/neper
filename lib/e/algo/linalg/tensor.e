// N-dimensional strided views over caller storage: element `index` is at
// `sum(index[d] * stride[d])`. `contiguous` builds the row-major strides for a shape;
// `reshape` reuses the storage when the view is row-major contiguous and copies into
// the arena otherwise. `Shape` is a rank or extent that does not agree.

use e.mem

type Tensor[T: type] = struct { data: []T, shape: []const usize, stride: []const usize }
type ConstTensor[T: type] = struct { data: []const T, shape: []const usize, stride: []const usize }
error Shape

fn count_of(shape: []const usize) -> usize {
    var total = 1usize
    var d = 0usize
    while d < shape.len {
        total = total * shape[d]
        d += 1usize
    }
    ret total
}

// The largest offset a view reaches, plus one; zero for an empty extent.
fn reach(shape: []const usize, stride: []const usize) -> usize {
    var last = 0usize
    var d = 0usize
    while d < shape.len {
        if shape[d] == 0usize { ret 0usize }
        last += (shape[d] - 1usize) * stride[d]
        d += 1usize
    }
    ret last + 1usize
}

fn view[T: type](data: []T, shape: []const usize, stride: []const usize) -> (Tensor[T], err) {
    if shape.len != stride.len { ret (zero, Shape) }
    if reach(shape, stride) > data.len { ret (zero, Shape) }
    var t: Tensor[T] = zero
    t.data = data
    t.shape = shape
    t.stride = stride
    ret (t, ok)
}

// Row-major: the last dimension is contiguous.
fn contiguous[T: type](a: *mem.Arena, data: []T, shape: []const usize) -> (Tensor[T], err) {
    if count_of(shape) > data.len { ret (zero, Shape) }
    let (stride, stride_error) = mem.alloc[usize](a, shape.len)
    if stride_error != ok { ret (zero, stride_error) }
    var step = 1usize
    var d = shape.len
    while d > 0usize {
        d -= 1usize
        stride[d] = step
        step = step * shape[d]
    }
    var t: Tensor[T] = zero
    t.data = data
    t.shape = shape
    t.stride = stride[0..]
    ret (t, ok)
}

fn as_const[T: type](tensor: Tensor[T]) -> ConstTensor[T] {
    var c: ConstTensor[T] = zero
    c.data = tensor.data
    c.shape = tensor.shape
    c.stride = tensor.stride
    ret c
}

fn elements[T: type](t: Tensor[T]) -> usize { ret count_of(t.shape) }

fn offset[T: type](t: Tensor[T], index: []const usize) -> usize {
    if index.len != t.shape.len { ret t.data.len }
    var at = 0usize
    var d = 0usize
    while d < index.len {
        if index[d] >= t.shape[d] { ret t.data.len }
        at += index[d] * t.stride[d]
        d += 1usize
    }
    ret at
}

fn is_row_major[T: type](t: Tensor[T]) -> bool {
    var step = 1usize
    var d = t.shape.len
    while d > 0usize {
        d -= 1usize
        if t.shape[d] != 1usize && t.stride[d] != step { ret false }
        step = step * t.shape[d]
    }
    ret true
}

// Walks every element of a view in row-major index order, calling back with its offset:
// written out as an odometer over the index, so a strided view is read in place.
fn next_index(shape: []const usize, index: []usize) -> bool {
    var d = shape.len
    while d > 0usize {
        d -= 1usize
        index[d] += 1usize
        if index[d] < shape[d] { ret true }
        index[d] = 0usize
    }
    ret false
}

fn offset_of(index: []const usize, stride: []const usize) -> usize {
    var at = 0usize
    var d = 0usize
    while d < index.len {
        at += index[d] * stride[d]
        d += 1usize
    }
    ret at
}

fn reshape[T: type](a: *mem.Arena, t: Tensor[T], shape: []const usize) -> (Tensor[T], err) {
    if count_of(shape) != count_of(t.shape) { ret (zero, Shape) }
    if is_row_major[T](t) {
        let (same_storage, same_error) = contiguous[T](a, t.data, shape)
        ret (same_storage, same_error)
    }
    let total = count_of(t.shape)
    let (copied, copied_error) = mem.alloc[T](a, total)
    if copied_error != ok { ret (zero, copied_error) }
    let (index, index_error) = mem.alloc[usize](a, t.shape.len)
    if index_error != ok { ret (zero, index_error) }
    var d = 0usize
    while d < index.len {
        index[d] = 0usize
        d += 1usize
    }
    var at = 0usize
    if total != 0usize {
        while true {
            let source_at = offset_of(index[0..], t.stride)
            copied[at] = t.data[source_at]
            at += 1usize
            if !next_index(t.shape, index[0..]) { break }
        }
    }
    let (fresh, fresh_error) = contiguous[T](a, copied[0..], shape)
    ret (fresh, fresh_error)
}

fn fill[T: type](tensor: Tensor[T], value: T) {
    if count_of(tensor.shape) == 0usize { ret }
    var index: [8]usize = zero
    if tensor.shape.len > index.len { ret }
    let cursor = index[..tensor.shape.len]
    while true {
        let target_at = offset_of(cursor, tensor.stride)
        tensor.data[target_at] = value
        if !next_index(tensor.shape, cursor) { break }
    }
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

fn copy[T: type](dst: Tensor[T], src: ConstTensor[T]) -> err {
    if !same_shape(dst.shape, src.shape) { ret Shape }
    if count_of(dst.shape) == 0usize { ret ok }
    var index: [8]usize = zero
    if dst.shape.len > index.len { ret Shape }
    let cursor = index[..dst.shape.len]
    while true {
        let target_at = offset_of(cursor, dst.stride)
        let source_at = offset_of(cursor, src.stride)
        dst.data[target_at] = src.data[source_at]
        if !next_index(dst.shape, cursor) { break }
    }
    ret ok
}

fn add[T: type](dst: Tensor[T], x: ConstTensor[T], y: ConstTensor[T]) -> err {
    if !same_shape(dst.shape, x.shape) || !same_shape(dst.shape, y.shape) { ret Shape }
    if count_of(dst.shape) == 0usize { ret ok }
    var index: [8]usize = zero
    if dst.shape.len > index.len { ret Shape }
    let cursor = index[..dst.shape.len]
    while true {
        let target_at = offset_of(cursor, dst.stride)
        let x_at = offset_of(cursor, x.stride)
        let y_at = offset_of(cursor, y.stride)
        dst.data[target_at] = x.data[x_at] + y.data[y_at]
        if !next_index(dst.shape, cursor) { break }
    }
    ret ok
}
