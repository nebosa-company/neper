// R isotone::gpava for a vector y: the generalised pool-adjacent-violators algorithm with the solvers weighted mean,
// weighted median and weighted fractile, and the three ties treatments ("primary": ties ordered by y, "secondary":
// ties averaged before and the group fit assigned to all, "tertiary": the group fit added to each deviation).
//
// Not here: matrix or list responses, user solvers, the Lp and quantile helpers beyond the fractile, activeSet and
// pava for general partial orders.

use e.algo.sort
use e.math
use e.mem

type Item = struct { x: f64, y: f64, w: f64, pos: usize }

fn cmp_item(ctx: *u8, a: Item, b: Item) -> i32 {
    if a.x < b.x { ret 0i32 - 1i32 }
    if a.x > b.x { ret 1i32 }
    if a.y < b.y { ret 0i32 - 1i32 }
    if a.y > b.y { ret 1i32 }
    ret 0i32
}

fn cmp_f(ctx: *u8, a: f64, b: f64) -> i32 {
    if a < b { ret 0i32 - 1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// the solver on y with weights w: kind 0 weighted mean, 1 weighted median, 2 weighted fractile p
fn solve(a: *mem.Arena, y: []const f64, w: []const f64, kind: u8, p: f64) -> f64 {
    let n = y.len
    if kind == 0u8 {
        var sw = 0.0f64
        var swy = 0.0f64
        var i = 0usize
        while i < n {
            swy += y[i] * w[i]
            sw += w[i]
            i += 1usize
        }
        ret swy / sw
    }
    let (ys, e1) = mem.alloc[f64](a, n)
    let (ws, e2) = mem.alloc[f64](a, n)
    let (idx, e3) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = idx[i]
        var j = i
        while j > 0usize && y[idx[j - 1usize]] > y[v] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = v
        i += 1usize
    }
    i = 0usize
    while i < n {
        ys[i] = y[idx[i]]
        ws[i] = w[idx[i]]
        i += 1usize
    }
    var aa = 0.5f64
    var bb = 0.5f64
    if kind == 2u8 {
        aa = 1.0f64 - p
        bb = p
    }
    // R sums in long double and rounds once; a compensated sum gives the same double
    var total = 0.0f64
    var comp = 0.0f64
    i = 0usize
    while i < n {
        let t = total + ws[i]
        if math.abs[f64](total) >= math.abs[f64](ws[i]) { comp += (total - t) + ws[i] } else { comp += (ws[i] - t) + total }
        total = t
        i += 1usize
    }
    total = total + comp
    var low = 0.0f64
    var k = 1usize
    while true {
        let up = total - low
        let df = aa * low - bb * up
        if df < 0.0f64 {
            low += ws[k - 1usize]
            k += 1usize
        } else if df == 0.0f64 {
            ret (ws[k - 1usize] * ys[k - 1usize] + ws[k - 2usize] * ys[k - 2usize]) / (ws[k - 1usize] + ws[k - 2usize])
        } else {
            ret ys[k - 2usize]
        }
    }
    ret 0.0f64
}

// the PAVA on already ordered y and w; fit receives the block value of every position
fn pava(a: *mem.Arena, y: []const f64, w: []const f64, kind: u8, p: f64, fit: []f64) -> err {
    let n = y.len
    let (lo, e1) = mem.alloc[usize](a, n)
    let (hi, e2) = mem.alloc[usize](a, n)
    let (vals, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    var i = 0usize
    while i < n {
        lo[i] = i
        hi[i] = i + 1usize
        vals[i] = solve(a, y[i..i + 1usize], w[i..i + 1usize], kind, p)
        i += 1usize
    }
    var nb = n
    i = 0usize
    while i + 1usize < nb {
        if vals[i] > vals[i + 1usize] {
            var cur = i
            while true {
                hi[cur] = hi[cur + 1usize]
                vals[cur] = solve(a, y[lo[cur]..hi[cur]], w[lo[cur]..hi[cur]], kind, p)
                var j = cur + 1usize
                while j + 1usize < nb {
                    lo[j] = lo[j + 1usize]
                    hi[j] = hi[j + 1usize]
                    vals[j] = vals[j + 1usize]
                    j += 1usize
                }
                nb -= 1usize
                if cur > 0usize && vals[cur - 1usize] > vals[cur] {
                    cur -= 1usize
                } else {
                    i = cur
                    break
                }
            }
        } else {
            i += 1usize
        }
    }
    var b = 0usize
    while b < nb {
        var t = lo[b]
        while t < hi[b] {
            fit[t] = vals[b]
            t += 1usize
        }
        b += 1usize
    }
    ret ok
}

// gpava(z = x, y, weights, solver, ties): ties 0 primary, 1 secondary, 2 tertiary; out receives the fit in the input order
fn gpava(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, kind: u8, p: f64, ties: u8, out: []f64) -> err {
    let n = x.len
    if ties == 0u8 {
        let (items, e1) = mem.alloc[Item](a, n)
        let (ys, e2) = mem.alloc[f64](a, n)
        let (ws, e3) = mem.alloc[f64](a, n)
        let (fit, e4) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
        var i = 0usize
        while i < n {
            items[i] = Item { x: x[i], y: y[i], w: w[i], pos: i }
            i += 1usize
        }
        var ctx = 0u8
        sort.in_place_by[Item, u8](items, &ctx, cmp_item)
        i = 0usize
        while i < n {
            ys[i] = items[i].y
            ws[i] = items[i].w
            i += 1usize
        }
        let pe = pava(a, ys, ws, kind, p, fit)
        if pe != ok { ret pe }
        i = 0usize
        while i < n {
            out[items[i].pos] = fit[i]
            i += 1usize
        }
        ret ok
    }
    let (ux, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < n {
        ux[i] = x[i]
        i += 1usize
    }
    var ctx2 = 0u8
    sort.in_place_by[f64, u8](ux, &ctx2, cmp_f)
    var g = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || ux[i] != ux[i - 1usize] {
            ux[g] = ux[i]
            g += 1usize
        }
        i += 1usize
    }
    let (yag, e6) = mem.alloc[f64](a, g)
    let (wag, e7) = mem.alloc[f64](a, g)
    let (fit2, e8) = mem.alloc[f64](a, g)
    if e6 != ok || e7 != ok || e8 != ok { ret e6 }
    var gi = 0usize
    while gi < g {
        var sy = 0.0f64
        var sw = 0.0f64
        var c = 0.0f64
        i = 0usize
        while i < n {
            if x[i] == ux[gi] {
                sy += y[i]
                sw += w[i]
                c += 1.0f64
            }
            i += 1usize
        }
        yag[gi] = sy / c
        wag[gi] = sw
        gi += 1usize
    }
    let pe2 = pava(a, yag, wag, kind, p, fit2)
    if pe2 != ok { ret pe2 }
    i = 0usize
    while i < n {
        var gk = 0usize
        while ux[gk] != x[i] { gk += 1usize }
        if ties == 1u8 { out[i] = fit2[gk] } else { out[i] = y[i] + (fit2[gk] - yag[gk]) }
        i += 1usize
    }
    ret ok
}
