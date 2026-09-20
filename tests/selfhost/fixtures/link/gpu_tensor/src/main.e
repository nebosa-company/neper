// `e.gpu.tensor` on the CPU device (D779): a strided host view uploads as a
// contiguous device tensor, `add` and `matmul` run as launches and agree with the
// host `e.algo.linalg.tensor` and with the plain formula, `download` fills a
// row-major host view and refuses a strided or mismatched one, an `i64` add reaches
// its own kernel, `Shape` names every disagreement, and a released tensor is stale.

use e.algo.linalg.tensor as linalg_tensor
use e.gpu
use e.gpu.tensor
use e.io
use e.mem
use e.os

fn near(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.0001 && d > -0.0001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }

    // x: a 2x3 view over a 3x2 row-major buffer transposed by its strides.
    var x_storage: [6]f32 = [6]f32{ 1.0, 4.0, 2.0, 5.0, 3.0, 6.0 }
    let shape_2x3: [2]usize = [2]usize{ 2usize, 3usize }
    let transposed: [2]usize = [2]usize{ 1usize, 2usize }
    let (x_host, x_view_error) = linalg_tensor.view[f32](x_storage[0..], shape_2x3[0..], transposed[0..])
    if x_view_error != ok { os.exit(3i32) }
    // x reads as [[1, 2, 3], [4, 5, 6]].
    let (x, x_error) = tensor.upload[f32](a, q, linalg_tensor.as_const[f32](x_host))
    if x_error != ok || x.shape.len != 2usize || x.shape[1] != 3usize || x.stride[0] != 3usize || x.stride[1] != 1usize || gpu.len[f32](x.data) != 6usize { os.exit(4i32) }
    var y_storage: [6]f32 = [6]f32{ 10.0, 20.0, 30.0, 40.0, 50.0, 60.0 }
    let (y_host, y_view_error) = linalg_tensor.contiguous[f32](a, y_storage[0..], shape_2x3[0..])
    if y_view_error != ok { os.exit(5i32) }
    let (y, y_error) = tensor.upload[f32](a, q, linalg_tensor.as_const[f32](y_host))
    if y_error != ok { os.exit(6i32) }
    let (sum, sum_error) = tensor.upload[f32](a, q, linalg_tensor.as_const[f32](y_host))
    if sum_error != ok { os.exit(7i32) }
    if tensor.add[f32](q, sum, x, y) != ok { os.exit(8i32) }
    var out_storage: [6]f32 = zero
    let (out, out_view_error) = linalg_tensor.contiguous[f32](a, out_storage[0..], shape_2x3[0..])
    if out_view_error != ok { os.exit(9i32) }
    if tensor.download[f32](q, sum, out) != ok { os.exit(10i32) }
    if !near(out_storage[0], 11.0) || !near(out_storage[2], 33.0) || !near(out_storage[3], 44.0) || !near(out_storage[5], 66.0) { os.exit(11i32) }
    // The host module agrees.
    var host_sum: [6]f32 = zero
    let (host_out, host_out_error) = linalg_tensor.contiguous[f32](a, host_sum[0..], shape_2x3[0..])
    if host_out_error != ok || linalg_tensor.add[f32](host_out, linalg_tensor.as_const[f32](x_host), linalg_tensor.as_const[f32](y_host)) != ok { os.exit(12i32) }
    var i = 0usize
    while i < 6usize {
        if !near(host_sum[i], out_storage[i]) { os.exit(13i32) }
        i += 1usize
    }

    // matmul: x (2x3) times z (3x2) is [[22, 28], [49, 64]].
    var z_storage: [6]f32 = [6]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 }
    let shape_3x2: [2]usize = [2]usize{ 3usize, 2usize }
    let (z_host, z_view_error) = linalg_tensor.contiguous[f32](a, z_storage[0..], shape_3x2[0..])
    if z_view_error != ok { os.exit(14i32) }
    let (z, z_error) = tensor.upload[f32](a, q, linalg_tensor.as_const[f32](z_host))
    if z_error != ok { os.exit(15i32) }
    var p_storage: [4]f32 = zero
    let shape_2x2: [2]usize = [2]usize{ 2usize, 2usize }
    let (p_host, p_view_error) = linalg_tensor.contiguous[f32](a, p_storage[0..], shape_2x2[0..])
    if p_view_error != ok { os.exit(16i32) }
    let (p, p_error) = tensor.upload[f32](a, q, linalg_tensor.as_const[f32](p_host))
    if p_error != ok { os.exit(17i32) }
    if tensor.matmul[f32](q, p, x, z) != ok { os.exit(18i32) }
    if tensor.download[f32](q, p, p_host) != ok { os.exit(19i32) }
    if !near(p_storage[0], 22.0) || !near(p_storage[1], 28.0) || !near(p_storage[2], 49.0) || !near(p_storage[3], 64.0) { os.exit(20i32) }
    // A 20x20 product against the plain formula, past one 16x16 workgroup.
    var big_storage: [400]f32 = zero
    i = 0usize
    while i < 400usize {
        big_storage[i] = f32(i % 7usize) - 3.0
        i += 1usize
    }
    let shape_20: [2]usize = [2]usize{ 20usize, 20usize }
    let (big_host, big_view_error) = linalg_tensor.contiguous[f32](a, big_storage[0..], shape_20[0..])
    if big_view_error != ok { os.exit(21i32) }
    let (big, big_error) = tensor.upload[f32](a, q, linalg_tensor.as_const[f32](big_host))
    if big_error != ok { os.exit(22i32) }
    let (square, square_error) = tensor.upload[f32](a, q, linalg_tensor.as_const[f32](big_host))
    if square_error != ok { os.exit(23i32) }
    if tensor.matmul[f32](q, square, big, big) != ok { os.exit(24i32) }
    var square_storage: [400]f32 = zero
    let (square_host, square_view_error) = linalg_tensor.contiguous[f32](a, square_storage[0..], shape_20[0..])
    if square_view_error != ok || tensor.download[f32](q, square, square_host) != ok { os.exit(25i32) }
    var r = 0usize
    while r < 20usize {
        var c = 0usize
        while c < 20usize {
            var expected: f32 = 0.0
            var t = 0usize
            while t < 20usize {
                expected = expected + big_storage[r * 20usize + t] * big_storage[t * 20usize + c]
                t += 1usize
            }
            if !near(square_storage[r * 20usize + c], expected) { os.exit(26i32) }
            c += 1usize
        }
        r += 1usize
    }

    // An i64 tensor reaches its own kernel.
    var long_storage: [4]i64 = [4]i64{ 1i64, -2i64, 3000000000i64, 4i64 }
    let shape_4: [1]usize = [1]usize{ 4usize }
    let (long_host, long_view_error) = linalg_tensor.contiguous[i64](a, long_storage[0..], shape_4[0..])
    if long_view_error != ok { os.exit(27i32) }
    let (long, long_error) = tensor.upload[i64](a, q, linalg_tensor.as_const[i64](long_host))
    if long_error != ok { os.exit(28i32) }
    if tensor.add[i64](q, long, long, long) != ok { os.exit(29i32) }
    var doubled: [4]i64 = zero
    let (doubled_host, doubled_view_error) = linalg_tensor.contiguous[i64](a, doubled[0..], shape_4[0..])
    if doubled_view_error != ok || tensor.download[i64](q, long, doubled_host) != ok { os.exit(30i32) }
    if doubled[0] != 2i64 || doubled[1] != -4i64 || doubled[2] != 6000000000i64 { os.exit(31i32) }

    // Shape refusals: add over different shapes, matmul over disagreeing extents,
    // download into a strided or a differently shaped view, an empty shape.
    if tensor.add[f32](q, sum, x, z) != tensor.Shape { os.exit(32i32) }
    if tensor.matmul[f32](q, p, x, y) != tensor.Shape { os.exit(33i32) }
    if tensor.download[f32](q, sum, x_host) != tensor.Shape { os.exit(34i32) }
    if tensor.download[f32](q, sum, p_host) != tensor.Shape { os.exit(35i32) }
    let (empty_host, empty_view_error) = linalg_tensor.view[f32](x_storage[0..], shape_2x3[0usize..0usize], transposed[0usize..0usize])
    if empty_view_error != ok { os.exit(36i32) }
    let (_, empty_error) = tensor.upload[f32](a, q, linalg_tensor.as_const[f32](empty_host))
    if empty_error != tensor.Shape { os.exit(37i32) }
    // Release: the tensor's buffer is stale afterwards.
    if tensor.release[f32](q, sum) != ok { os.exit(38i32) }
    if tensor.download[f32](q, sum, out) != gpu.InvalidHandle { os.exit(39i32) }
    if tensor.release[f32](q, sum) != gpu.InvalidHandle { os.exit(40i32) }

    try io.print("gpu tensor ok\n")
    ret ok
}
