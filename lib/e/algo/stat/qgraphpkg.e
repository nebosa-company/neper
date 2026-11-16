// R qgraph centrality_auto on a weighted undirected graph (symmetric weight matrix, zero diagonal): strength (sum of absolute weights), expected influence (sum of signed weights), closeness (the reciprocal of the summed shortest-path distances, an edge of weight w having length 1 / |w|) and betweenness (the fraction of shortest paths through a node, each pair once). Connected graphs.
//
// Not here: directed graphs, the clustering coefficients, EBICglasso, cor_auto, layouts, networks from data, centrality of disconnected graphs.

use e.math
use e.mem

// out: 4 blocks of n: betweenness, closeness, strength, expected influence
fn centrality(a: *mem.Arena, w: []const f64, n: usize, out: []f64) -> err {
    let (dist, e1) = mem.alloc[f64](a, n * n)
    let (cnt, e2) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    let inf = 1.0e300f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            dist[i * n + j] = inf
            cnt[i * n + j] = 0.0f64
            if i == j {
                dist[i * n + j] = 0.0f64
                cnt[i * n + j] = 1.0f64
            } else if w[i * n + j] != 0.0f64 {
                dist[i * n + j] = 1.0f64 / math.abs[f64](w[i * n + j])
                cnt[i * n + j] = 1.0f64
            }
            j += 1usize
        }
        i += 1usize
    }
    var k = 0usize
    while k < n {
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                if i != k && j != k && dist[i * n + k] < inf && dist[k * n + j] < inf {
                    let via = dist[i * n + k] + dist[k * n + j]
                    let tol = 1.0e-9f64 * (1.0f64 + via)
                    if via < dist[i * n + j] - tol {
                        dist[i * n + j] = via
                        cnt[i * n + j] = cnt[i * n + k] * cnt[k * n + j]
                    } else if math.abs[f64](via - dist[i * n + j]) <= tol && i != j {
                        cnt[i * n + j] += cnt[i * n + k] * cnt[k * n + j]
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < 4usize * n {
        out[i] = 0.0f64
        i += 1usize
    }
    var s = 0usize
    while s < n {
        var tt = s + 1usize
        while tt < n {
            var v = 0usize
            while v < n {
                if v != s && v != tt {
                    let via = dist[s * n + v] + dist[v * n + tt]
                    if math.abs[f64](via - dist[s * n + tt]) <= 1.0e-9f64 * (1.0f64 + via) { out[v] += cnt[s * n + v] * cnt[v * n + tt] / cnt[s * n + tt] }
                }
                v += 1usize
            }
            tt += 1usize
        }
        s += 1usize
    }
    i = 0usize
    while i < n {
        var sum = 0.0f64
        var st = 0.0f64
        var ei = 0.0f64
        var j = 0usize
        while j < n {
            if j != i {
                sum += dist[i * n + j]
                st += math.abs[f64](w[i * n + j])
                ei += w[i * n + j]
            }
            j += 1usize
        }
        out[n + i] = 1.0f64 / sum
        out[2usize * n + i] = st
        out[3usize * n + i] = ei
        i += 1usize
    }
    ret ok
}
