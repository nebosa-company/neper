// `e.algo.linalg.matrix` and `e.algo.linalg.tensor`: strided views, transpose as a view,
// multiply, add, fill and copy, a determinant and an inverse checked by the product, the
// singular case, and tensors through contiguous, strided and reshaped views. Every check
// has its own exit code.
use e.os
use e.mem
use e.algo.linalg.matrix as matrix
use e.algo.linalg.tensor as tensor

fn near(got: f64, want: f64) -> bool {
    var d = got - want
    if d < 0.0 { d = 0.0 - d }
    ret d <= 0.000000001
}

fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [6]f64 = [6]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 }
    let (m, view_error) = matrix.view[f64](storage[0..], 2usize, 3usize, 3usize)
    if view_error != ok { os.exit(10) }
    if matrix.get[f64](m, 1usize, 2usize) != 6.0 || matrix.get[f64](m, 0usize, 1usize) != 2.0 { os.exit(11) }
    let t = matrix.transpose[f64](m)
    if t.rows != 3usize || t.cols != 2usize { os.exit(12) }
    matrix.set[f64](m, 0usize, 0usize, 10.0)
    if storage[0] != 10.0 { os.exit(13) }
    let (_, bad) = matrix.view[f64](storage[0..], 3usize, 3usize, 3usize)
    if bad != matrix.Shape { os.exit(14) }
    var right_storage: [6]f64 = [6]f64{ 1.0, 0.0, 0.0, 1.0, 1.0, 1.0 }
    let (right, _) = matrix.view_const[f64](right_storage[0..], 3usize, 2usize, 2usize)
    var out_storage: [4]f64 = zero
    let (out, _) = matrix.view[f64](out_storage[0..], 2usize, 2usize, 2usize)
    if matrix.multiply[f64](out, matrix.as_const[f64](m), right) != ok { os.exit(15) }
    if out_storage[0] != 13.0 || out_storage[1] != 5.0 || out_storage[2] != 10.0 || out_storage[3] != 11.0 { os.exit(16) }
    if matrix.multiply[f64](out, right, right) != matrix.Shape { os.exit(17) }
    var sum_storage: [4]f64 = zero
    let (sum, _) = matrix.view[f64](sum_storage[0..], 2usize, 2usize, 2usize)
    if matrix.add[f64](sum, matrix.as_const[f64](out), matrix.as_const[f64](out)) != ok || sum_storage[3] != 22.0 { os.exit(18) }
    matrix.fill[f64](sum, 1.5)
    if sum_storage[0] != 1.5 || sum_storage[3] != 1.5 { os.exit(19) }
    if matrix.copy[f64](sum, matrix.as_const[f64](out)) != ok || sum_storage[2] != 10.0 { os.exit(20) }
    var square: [9]f64 = [9]f64{ 2.0, 0.0, 1.0, 1.0, 3.0, 2.0, 1.0, 1.0, 2.0 }
    let (sq, _) = matrix.view_const[f64](square[0..], 3usize, 3usize, 3usize)
    let (det, det_error) = matrix.determinant_f64(a, sq)
    if det_error != ok || !near(det, 6.0) { os.exit(21) }
    var inv_storage: [9]f64 = zero
    let (inv, _) = matrix.view[f64](inv_storage[0..], 3usize, 3usize, 3usize)
    if matrix.inverse_f64(a, inv, sq) != ok { os.exit(22) }
    var product: [9]f64 = zero
    let (prod, _) = matrix.view[f64](product[0..], 3usize, 3usize, 3usize)
    if matrix.multiply[f64](prod, sq, matrix.as_const[f64](inv)) != ok { os.exit(23) }
    var i = 0usize
    while i < 9usize {
        var want: f64 = 0.0
        if i % 4usize == 0usize { want = 1.0 }
        if !near(product[i], want) { os.exit(24) }
        i += 1usize
    }
    var singular: [4]f64 = [4]f64{ 1.0, 2.0, 2.0, 4.0 }
    let (sg, _) = matrix.view_const[f64](singular[0..], 2usize, 2usize, 2usize)
    var sg_out: [4]f64 = zero
    let (sgo, _) = matrix.view[f64](sg_out[0..], 2usize, 2usize, 2usize)
    let (zero_det, _) = matrix.determinant_f64(a, sg)
    if zero_det != 0.0 || matrix.inverse_f64(a, sgo, sg) != matrix.Singular { os.exit(25) }
    var td: [6]i32 = [6]i32{ 1, 2, 3, 4, 5, 6 }
    let shape: [2]usize = [2]usize{ 2, 3 }
    let (tn, tn_error) = tensor.contiguous[i32](a, td[0..], shape[0..])
    if tn_error != ok || tensor.elements[i32](tn) != 6usize || tn.stride[0] != 3usize || tn.stride[1] != 1usize { os.exit(30) }
    let idx: [2]usize = [2]usize{ 1, 2 }
    let at5 = tensor.offset[i32](tn, idx[0..])
    if at5 != 5usize || td[at5] != 6i32 { os.exit(31) }
    let tshape: [2]usize = [2]usize{ 3, 2 }
    let tstride: [2]usize = [2]usize{ 1, 3 }
    let (tt, tt_error) = tensor.view[i32](td[0..], tshape[0..], tstride[0..])
    if tt_error != ok { os.exit(32) }
    let tidx: [2]usize = [2]usize{ 2, 1 }
    let at6 = tensor.offset[i32](tt, tidx[0..])
    if td[at6] != 6i32 { os.exit(33) }
    let flat: [1]usize = [1]usize{ 6 }
    let (re, re_error) = tensor.reshape[i32](a, tt, flat[0..])
    if re_error != ok || re.data[0] != 1i32 || re.data[1] != 4i32 || re.data[2] != 2i32 || re.data[5] != 6i32 { os.exit(34) }
    let (same, same_error) = tensor.reshape[i32](a, tn, flat[0..])
    if same_error != ok || same.data[5] != 6i32 || same.stride[0] != 1usize { os.exit(35) }
    let (_, bad_shape) = tensor.reshape[i32](a, tn, tshape[..1])
    if bad_shape != tensor.Shape { os.exit(36) }
    var out_data: [6]i32 = zero
    let (out_t, _) = tensor.contiguous[i32](a, out_data[0..], shape[0..])
    if tensor.add[i32](out_t, tensor.as_const[i32](tn), tensor.as_const[i32](tn)) != ok || out_data[5] != 12i32 { os.exit(37) }
    tensor.fill[i32](out_t, 7i32)
    if out_data[0] != 7i32 || out_data[5] != 7i32 { os.exit(38) }
    if tensor.copy[i32](out_t, tensor.as_const[i32](tn)) != ok || out_data[3] != 4i32 { os.exit(39) }
    let (oth, _) = tensor.contiguous[i32](a, out_data[0..], tshape[0..])
    if tensor.add[i32](out_t, tensor.as_const[i32](oth), tensor.as_const[i32](tn)) != tensor.Shape { os.exit(40) }
    os.exit(0)
    ret ok
}
