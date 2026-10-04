// Recurrent layers over `f64` vectors in caller storage: one long
// short-term memory step (`lstm_step`) and one gated recurrent unit step
// (`gru_step`), with `lstm_forward` and `gru_forward` running a whole
// sequence from an initial state and keeping every state.
//
// The LSTM packs its weights as `wx` (`4h x d`), `wh` (`4h x h`) and a bias
// `b` (`4h`), rows `0..h` the input gate, `h..2h` the forget gate, `2h..3h`
// the cell candidate and `3h..4h` the output gate: with `i`, `f`, `g`, `o`
// those rows through the sigmoid (tanh for the candidate),
// `c = f c_prev + i g` and `h = o tanh(c)`. The GRU packs `wx` (`3h x d`),
// `wh` (`3h x h`) and `b` (`3h`), rows the reset gate, the update gate and
// the candidate: `r` and `z` through the sigmoid,
// `n = tanh(wx_n x + b_n + r (wh_n h_prev))` and
// `h = (1 - z) n + z h_prev`.

use e.math

error TooSmall
error Invalid

fn sigmoid(x: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }

fn tanh(x: f64) -> f64 {
    let e2 = math.exp[f64](2.0f64 * x)
    ret (e2 - 1.0f64) / (e2 + 1.0f64)
}

// One LSTM step of input `x` (`d`) from `h_prev`/`c_prev` (`h`): the four
// gate rows into `scratch` (`4h`), the new states into `h_new`/`c_new`.
fn lstm_step(x: []const f64, h_prev: []const f64, c_prev: []const f64, d: usize, h: usize, wx: []const f64, wh: []const f64, b: []const f64, h_new: []f64, c_new: []f64, scratch: []f64) -> err {
    if x.len < d || h_prev.len < h || c_prev.len < h || wx.len < 4usize * h * d || wh.len < 4usize * h * h || b.len < 4usize * h || h_new.len < h || c_new.len < h || scratch.len < 4usize * h { ret TooSmall }
    if d == 0usize || h == 0usize { ret Invalid }
    var r = 0usize
    while r < 4usize * h {
        var s = b[r]
        var k = 0usize
        while k < d {
            s += wx[r * d + k] * x[k]
            k += 1usize
        }
        k = 0usize
        while k < h {
            s += wh[r * h + k] * h_prev[k]
            k += 1usize
        }
        // Rows 0..2h are sigmoid gates, rows 2h..3h the tanh candidate.
        if r / h == 2usize {
            scratch[r] = tanh(s)
        } else {
            scratch[r] = sigmoid(s)
        }
        r += 1usize
    }
    var u = 0usize
    while u < h {
        let input = scratch[u]
        let forget = scratch[h + u]
        let cell = scratch[2usize * h + u]
        let output = scratch[3usize * h + u]
        c_new[u] = forget * c_prev[u] + input * cell
        h_new[u] = output * tanh(c_new[u])
        u += 1usize
    }
    ret ok
}

// `steps` LSTM steps over `x` (`steps x d`) from `h0`/`c0`: `h_out`/`c_out`
// (`steps x h`) receive every state in order; `scratch.len >= 4 * h`.
fn lstm_forward(x: []const f64, steps: usize, d: usize, h: usize, wx: []const f64, wh: []const f64, b: []const f64, h0: []const f64, c0: []const f64, h_out: []f64, c_out: []f64, scratch: []f64) -> err {
    if x.len < steps * d || h0.len < h || c0.len < h || h_out.len < steps * h || c_out.len < steps * h { ret TooSmall }
    if steps == 0usize { ret Invalid }
    var t = 0usize
    while t < steps {
        let input = x[t * d..(t + 1usize) * d]
        let h_next = h_out[t * h..(t + 1usize) * h]
        let c_next = c_out[t * h..(t + 1usize) * h]
        if t == 0usize {
            let step_error = lstm_step(input, h0, c0, d, h, wx, wh, b, h_next, c_next, scratch)
            if step_error != ok { ret step_error }
        } else {
            let step_error = lstm_step(input, h_out[(t - 1usize) * h..t * h], c_out[(t - 1usize) * h..t * h], d, h, wx, wh, b, h_next, c_next, scratch)
            if step_error != ok { ret step_error }
        }
        t += 1usize
    }
    ret ok
}

// One GRU step of input `x` (`d`) from `h_prev` (`h`) into `h_new`;
// `scratch.len >= 3 * h` holds the reset row, the update row and the candidate.
fn gru_step(x: []const f64, h_prev: []const f64, d: usize, h: usize, wx: []const f64, wh: []const f64, b: []const f64, h_new: []f64, scratch: []f64) -> err {
    if x.len < d || h_prev.len < h || wx.len < 3usize * h * d || wh.len < 3usize * h * h || b.len < 3usize * h || h_new.len < h || scratch.len < 3usize * h { ret TooSmall }
    if d == 0usize || h == 0usize { ret Invalid }
    // The reset and update rows through the sigmoid.
    var r = 0usize
    while r < 2usize * h {
        var s = b[r]
        var k = 0usize
        while k < d {
            s += wx[r * d + k] * x[k]
            k += 1usize
        }
        k = 0usize
        while k < h {
            s += wh[r * h + k] * h_prev[k]
            k += 1usize
        }
        scratch[r] = sigmoid(s)
        r += 1usize
    }
    // The candidate, gated by the reset row, then the update blend.
    var u = 0usize
    while u < h {
        let reset = scratch[u]
        let update = scratch[h + u]
        var s = b[2usize * h + u]
        var k = 0usize
        while k < d {
            s += wx[(2usize * h + u) * d + k] * x[k]
            k += 1usize
        }
        var recurrent = 0.0f64
        k = 0usize
        while k < h {
            recurrent += wh[(2usize * h + u) * h + k] * h_prev[k]
            k += 1usize
        }
        let candidate = tanh(s + reset * recurrent)
        h_new[u] = (1.0f64 - update) * candidate + update * h_prev[u]
        u += 1usize
    }
    ret ok
}

// `steps` GRU steps over `x` (`steps x d`) from `h0`: `h_out` (`steps x h`)
// receives every state in order; `scratch.len >= 3 * h`.
fn gru_forward(x: []const f64, steps: usize, d: usize, h: usize, wx: []const f64, wh: []const f64, b: []const f64, h0: []const f64, h_out: []f64, scratch: []f64) -> err {
    if x.len < steps * d || h0.len < h || h_out.len < steps * h { ret TooSmall }
    if steps == 0usize { ret Invalid }
    var t = 0usize
    while t < steps {
        let input = x[t * d..(t + 1usize) * d]
        let h_next = h_out[t * h..(t + 1usize) * h]
        if t == 0usize {
            let step_error = gru_step(input, h0, d, h, wx, wh, b, h_next, scratch)
            if step_error != ok { ret step_error }
        } else {
            let step_error = gru_step(input, h_out[(t - 1usize) * h..t * h], d, h, wx, wh, b, h_next, scratch)
            if step_error != ok { ret step_error }
        }
        t += 1usize
    }
    ret ok
}
