// Graph neural layers over row-major `f64` node features (`n` rows of `d`)
// in caller storage: one graph-convolutional layer (`gcn_layer`), one
// single-head graph-attention layer (`gat_layer`) and one message-passing
// step (`mpnn_step`). Edges are index pairs `src[k] -> dst[k]` (`m` of
// them, messages flowing from source to destination); every node also
// aggregates its own features, an implicit self-loop, so an isolated node
// still answers its own projection. Degrees count that loop.

use e.math

error TooSmall
error Invalid

fn relu(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    ret x
}

fn leaky_relu(x: f64, slope: f64) -> f64 {
    if x < 0.0f64 { ret slope * x }
    ret x
}

// The unnormalized attention of edge `j -> i` over the projections `p`
// (`n x e`): `leaky_relu` of `attention` (`2e`) over `[p_i || p_j]`.
fn gat_score(p: []const f64, n: usize, e: usize, i: usize, j: usize, attention: []const f64, slope: f64) -> f64 {
    var s = 0.0f64
    var c = 0usize
    while c < e {
        s += attention[c] * p[i * e + c] + attention[e + c] * p[j * e + c]
        c += 1usize
    }
    ret leaky_relu(s, slope)
}

// One graph-convolutional layer: `out[i]` is `relu` of the projected
// features `x W` (`W` is `d x e` row-major) summed over `i` and its
// incoming neighbours, each scaled by `1 / sqrt(deg_i deg_j)`; `out` is
// `n x e`. `scratch.len >= n * (e + 1)` holds the degrees and the sum.
fn gcn_layer(x: []const f64, n: usize, d: usize, e: usize, src: []const usize, dst: []const usize, m: usize, weight: []const f64, out: []f64, scratch: []f64) -> err {
    if x.len < n * d || src.len < m || dst.len < m || weight.len < d * e || out.len < n * e || scratch.len < n * (e + 1usize) { ret TooSmall }
    if n == 0usize || d == 0usize || e == 0usize { ret Invalid }
    var deg = scratch[..n]
    var agg = scratch[n..n + n * e]
    var i = 0usize
    while i < n {
        deg[i] = 1.0f64
        i += 1usize
    }
    var k = 0usize
    while k < m {
        if src[k] >= n || dst[k] >= n { ret Invalid }
        deg[dst[k]] += 1.0f64
        k += 1usize
    }
    k = 0usize
    while k < n * e {
        agg[k] = 0.0f64
        k += 1usize
    }
    // The self term carries `1 / deg_i`, the limit of the edge scaling.
    i = 0usize
    while i < n {
        let w = 1.0f64 / deg[i]
        var c = 0usize
        while c < e {
            var s = 0.0f64
            var j = 0usize
            while j < d {
                s += x[i * d + j] * weight[j * e + c]
                j += 1usize
            }
            agg[i * e + c] += w * s
            c += 1usize
        }
        i += 1usize
    }
    k = 0usize
    while k < m {
        let s = src[k]
        let t = dst[k]
        let w = 1.0f64 / math.sqrt[f64](deg[t] * deg[s])
        var c = 0usize
        while c < e {
            var v = 0.0f64
            var j = 0usize
            while j < d {
                v += x[s * d + j] * weight[j * e + c]
                j += 1usize
            }
            agg[t * e + c] += w * v
            c += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n * e {
        out[i] = relu(agg[i])
        i += 1usize
    }
    ret ok
}

// One single-head graph-attention layer: with `p = x W` (`W` is `d x e`),
// edge `j -> i` scores `gat_score(p, n, e, i, j, attention, slope)`,
// `attention` is `2e`, the scores softmax over each node's incoming edges
// plus itself (max-subtracted), and `out` (`n x e`) is `relu` of the
// attended sum. `scratch.len >= n * e + m + 2 * n` holds the projections,
// the edge scores, and one maximum and one normalizer per node.
fn gat_layer(x: []const f64, n: usize, d: usize, e: usize, src: []const usize, dst: []const usize, m: usize, weight: []const f64, attention: []const f64, slope: f64, out: []f64, scratch: []f64) -> err {
    if x.len < n * d || src.len < m || dst.len < m || weight.len < d * e || attention.len < 2usize * e || out.len < n * e || scratch.len < n * e + m + 2usize * n { ret TooSmall }
    if n == 0usize || d == 0usize || e == 0usize { ret Invalid }
    var proj = scratch[..n * e]
    var scores = scratch[n * e..n * e + m]
    var largest = scratch[n * e + m..n * e + m + n]
    var total = scratch[n * e + m + n..n * e + m + 2usize * n]
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < e {
            var s = 0.0f64
            var j = 0usize
            while j < d {
                s += x[i * d + j] * weight[j * e + c]
                j += 1usize
            }
            proj[i * e + c] = s
            c += 1usize
        }
        i += 1usize
    }
    var k = 0usize
    while k < m {
        if src[k] >= n || dst[k] >= n { ret Invalid }
        scores[k] = gat_score(proj, n, e, dst[k], src[k], attention, slope)
        k += 1usize
    }
    i = 0usize
    while i < n {
        largest[i] = gat_score(proj, n, e, i, i, attention, slope)
        i += 1usize
    }
    k = 0usize
    while k < m {
        if scores[k] > largest[dst[k]] { largest[dst[k]] = scores[k] }
        k += 1usize
    }
    i = 0usize
    while i < n {
        total[i] = math.exp[f64](gat_score(proj, n, e, i, i, attention, slope) - largest[i])
        i += 1usize
    }
    k = 0usize
    while k < m {
        total[dst[k]] += math.exp[f64](scores[k] - largest[dst[k]])
        k += 1usize
    }
    i = 0usize
    while i < n {
        let self_weight = math.exp[f64](gat_score(proj, n, e, i, i, attention, slope) - largest[i]) / total[i]
        var c = 0usize
        while c < e {
            out[i * e + c] = self_weight * proj[i * e + c]
            c += 1usize
        }
        i += 1usize
    }
    k = 0usize
    while k < m {
        let t = dst[k]
        let edge_weight = math.exp[f64](scores[k] - largest[t]) / total[t]
        var c = 0usize
        while c < e {
            out[t * e + c] += edge_weight * proj[src[k] * e + c]
            c += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n * e {
        out[i] = relu(out[i])
        i += 1usize
    }
    ret ok
}

// One message-passing step with sum aggregation: `out[i]` is `relu` of
// `x_i update` plus the `x_j message` sum over the incoming neighbours,
// `message` and `update` each `d x e`; `out` is `n x e`.
// `scratch.len >= n * e` sums the messages.
fn mpnn_step(x: []const f64, n: usize, d: usize, e: usize, src: []const usize, dst: []const usize, m: usize, message: []const f64, update: []const f64, out: []f64, scratch: []f64) -> err {
    if x.len < n * d || src.len < m || dst.len < m || message.len < d * e || update.len < d * e || out.len < n * e || scratch.len < n * e { ret TooSmall }
    if n == 0usize || d == 0usize || e == 0usize { ret Invalid }
    var agg = scratch[..n * e]
    var i = 0usize
    while i < n * e {
        agg[i] = 0.0f64
        i += 1usize
    }
    var k = 0usize
    while k < m {
        if src[k] >= n || dst[k] >= n { ret Invalid }
        let s = src[k]
        let t = dst[k]
        var c = 0usize
        while c < e {
            var v = 0.0f64
            var j = 0usize
            while j < d {
                v += x[s * d + j] * message[j * e + c]
                j += 1usize
            }
            agg[t * e + c] += v
            c += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < e {
            var s = 0.0f64
            var j = 0usize
            while j < d {
                s += x[i * d + j] * update[j * e + c]
                j += 1usize
            }
            out[i * e + c] = relu(s + agg[i * e + c])
            c += 1usize
        }
        i += 1usize
    }
    ret ok
}
