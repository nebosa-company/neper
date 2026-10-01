// `e.ml.recurrent`: one LSTM step and one GRU step against hand-computed
// gates, both two-step forwards against the same reference, and the storage
// and empty cases. Each check exits with its own code.

use e.mem
use e.ml.recurrent as rec
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [4]f64 = zero
    x[0usize] = 1.0f64
    x[1usize] = 0.5f64
    x[2usize] = 0.0f64 - 0.5f64
    x[3usize] = 1.5f64
    var wx: [16]f64 = zero
    wx[0usize] = 0.5f64
    wx[1usize] = 0.0f64 - 0.5f64
    wx[2usize] = 0.25f64
    wx[3usize] = 0.75f64
    wx[4usize] = 0.0f64 - 0.25f64
    wx[5usize] = 0.5f64
    wx[6usize] = 0.1f64
    wx[7usize] = 0.2f64
    wx[8usize] = 0.3f64
    wx[9usize] = 0.0f64 - 0.1f64
    wx[10usize] = 0.0f64 - 0.4f64
    wx[11usize] = 0.4f64
    wx[12usize] = 0.6f64
    wx[13usize] = 0.1f64
    wx[14usize] = 0.0f64 - 0.2f64
    wx[15usize] = 0.0f64 - 0.3f64
    var wh: [16]f64 = zero
    wh[0usize] = 0.1f64
    wh[1usize] = 0.2f64
    wh[2usize] = 0.0f64 - 0.1f64
    wh[3usize] = 0.3f64
    wh[4usize] = 0.2f64
    wh[5usize] = 0.0f64 - 0.2f64
    wh[6usize] = 0.4f64
    wh[7usize] = 0.1f64
    wh[8usize] = 0.0f64 - 0.3f64
    wh[9usize] = 0.1f64
    wh[10usize] = 0.2f64
    wh[11usize] = 0.2f64
    wh[12usize] = 0.1f64
    wh[13usize] = 0.0f64 - 0.4f64
    wh[14usize] = 0.3f64
    wh[15usize] = 0.3f64
    var b: [8]f64 = zero
    b[0usize] = 0.1f64
    b[1usize] = 0.0f64 - 0.1f64
    b[2usize] = 0.0f64
    b[3usize] = 0.2f64
    b[4usize] = 0.0f64 - 0.2f64
    b[5usize] = 0.1f64
    b[6usize] = 0.0f64
    b[7usize] = 0.0f64 - 0.1f64
    var h0: [2]f64 = zero
    var c0: [2]f64 = zero
    var h: [2]f64 = zero
    var c: [2]f64 = zero
    var scratch: [8]f64 = zero

    // 1: one LSTM step from zero states.
    if rec.lstm_step(x[0usize..2usize], h0[..], c0[..], 2usize, 2usize, wx[..], wh[..], b[..], h[..], c[..], scratch[..]) != ok { os.exit(1i32) }
    if !near(h[0usize], 0.019249140965147293f64, 0.000000001f64) || !near(h[1usize], 0.0f64 - 0.024351121082729715f64, 0.000000001f64) { os.exit(1i32) }
    if !near(c[0usize], 0.029306460964435687f64, 0.000000001f64) || !near(c[1usize], 0.0f64 - 0.06262301447779531f64, 0.000000001f64) { os.exit(1i32) }

    // 2: the two-step forward keeps both states.
    var hall: [4]f64 = zero
    var call: [4]f64 = zero
    if rec.lstm_forward(x[..], 2usize, 2usize, 2usize, wx[..], wh[..], b[..], h0[..], c0[..], hall[..], call[..], scratch[..]) != ok { os.exit(2i32) }
    if !near(hall[0usize], 0.019249140965147293f64, 0.000000001f64) || !near(hall[1usize], 0.0f64 - 0.024351121082729715f64, 0.000000001f64) { os.exit(2i32) }
    if !near(hall[2usize], 0.0f64 - 0.05302523909941074f64, 0.000000001f64) || !near(hall[3usize], 0.1702127314532562f64, 0.000000001f64) { os.exit(2i32) }
    if !near(call[2usize], 0.0f64 - 0.11441393718129995f64, 0.000000001f64) || !near(call[3usize], 0.4692193298701686f64, 0.000000001f64) { os.exit(2i32) }

    // 3: GRU step and forward.
    var gx: [12]f64 = zero
    gx[0usize] = 0.5f64
    gx[1usize] = 0.0f64 - 0.25f64
    gx[2usize] = 0.1f64
    gx[3usize] = 0.4f64
    gx[4usize] = 0.0f64 - 0.3f64
    gx[5usize] = 0.2f64
    gx[6usize] = 0.6f64
    gx[7usize] = 0.0f64 - 0.1f64
    gx[8usize] = 0.2f64
    gx[9usize] = 0.3f64
    gx[10usize] = 0.0f64 - 0.5f64
    gx[11usize] = 0.0f64 - 0.2f64
    var gh: [12]f64 = zero
    gh[0usize] = 0.3f64
    gh[1usize] = 0.1f64
    gh[2usize] = 0.0f64 - 0.2f64
    gh[3usize] = 0.2f64
    gh[4usize] = 0.1f64
    gh[5usize] = 0.0f64 - 0.3f64
    gh[6usize] = 0.4f64
    gh[7usize] = 0.2f64
    gh[8usize] = 0.0f64 - 0.1f64
    gh[9usize] = 0.1f64
    gh[10usize] = 0.2f64
    gh[11usize] = 0.0f64 - 0.2f64
    var gb: [6]f64 = zero
    gb[0usize] = 0.0f64
    gb[1usize] = 0.1f64
    gb[2usize] = 0.0f64 - 0.1f64
    gb[3usize] = 0.0f64
    gb[4usize] = 0.1f64
    gb[5usize] = 0.0f64 - 0.1f64
    var gscratch: [6]f64 = zero
    if rec.gru_step(x[0usize..2usize], h0[..], 2usize, 2usize, gx[..], gh[..], gb[..], h[..], gscratch[..]) != ok { os.exit(3i32) }
    if !near(h[0usize], 0.24235672641614983f64, 0.000000001f64) || !near(h[1usize], 0.0f64 - 0.22111665958708712f64, 0.000000001f64) { os.exit(3i32) }
    var gall: [4]f64 = zero
    if rec.gru_forward(x[..], 2usize, 2usize, 2usize, gx[..], gh[..], gb[..], h0[..], gall[..], gscratch[..]) != ok { os.exit(3i32) }
    if !near(gall[2usize], 0.30725455351311204f64, 0.000000001f64) || !near(gall[3usize], 0.0f64 - 0.14318953593661454f64, 0.000000001f64) { os.exit(3i32) }

    // 4: storage and empty cases.
    if rec.lstm_step(x[0usize..2usize], h0[..], c0[..], 2usize, 2usize, wx[..], wh[..], b[..], h[..], c[..], scratch[..3usize]) != rec.TooSmall { os.exit(4i32) }
    if rec.gru_step(scratch[..0usize], scratch[..0usize], 0usize, 0usize, scratch[..0usize], scratch[..0usize], scratch[..0usize], scratch[..0usize], scratch[..0usize]) != rec.Invalid { os.exit(4i32) }
    if rec.lstm_forward(scratch[..0usize], 0usize, 0usize, 0usize, scratch[..0usize], scratch[..0usize], scratch[..0usize], scratch[..0usize], scratch[..0usize], scratch[..0usize], scratch[..0usize], scratch[..0usize]) != rec.Invalid { os.exit(4i32) }
    ret ok
}
