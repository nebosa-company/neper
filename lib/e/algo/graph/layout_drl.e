// R igraph layout_with_drl (DrL, 2-D), ported from igraph 2.3.4 (layout/drl/drl_graph.cpp and DensityGrid.cpp) in single precision
// where the C++ is: every `float` of the original is an f32 here and an expression the C++ evaluates in double (it has a double literal
// in it) is evaluated in f64 and rounded when stored. R draws `runif(2 n)` for the unused default seed before the layout runs; this
// module takes that into account, then draws from `unif_rand` as DrL's random jumps do. Rows are (x, y), n rows.
//
// opts: edge_cut, then (iterations, temperature, attraction, damping_mult) for init, liquid, expansion, cooldown, crunch and simmer
// (25 numbers; igraph's defaults are 0.8, 0 2000 10 1, 200 2000 10 1, 200 2000 2 1, 200 2000 1 0.1, 50 250 1 0.25, 100 250 0.5 0).
//
// Not here: a start layout (use.seed), the 3-D variant, the weights of an edge being checked for positivity.

use e.algo.graph.games as gg
use e.algo.rand.r as rg
use e.math
use e.mem
use e.os

const GRID: usize = 1000usize
const RADIUS: i64 = 10i64

type Drl = struct {
    n: usize, px: []f32, py: []f32, sx: []f32, sy: []f32, en: []f32, wm: []f32, pres: []bool, dens: []f32, fall: []f32,
    head: []i64, tail: []i64, ex: []f32, ey: []f32, enext: []i64, ecount: usize,
    stage: i64, iterations: i64, temperature: f32, attraction: f32, damping_mult: f32, min_edges: f32, cut_end: f32,
    cut_length_end: f32, cut_off_length: f32, cut_rate: f32, first_add: bool, fine_first_add: bool, fine: bool,
    sit: []i64, stemp: []f32, satt: []f32, sdamp: []f32
}

fn grid_of(v: f32) -> i64 {
    let t = v + 2000.0f32
    ret i64((f64(t) + 0.5f64) * 0.25f64)
}

fn weight_at(d: *Drl, a: usize, b: usize) -> f32 { ret d.wm[a * d.n + b] }

fn nsize(d: *Drl, a: usize) -> usize {
    var c = 0usize
    var j = 0usize
    while j < d.n {
        if d.pres[a * d.n + j] { c += 1usize }
        j += 1usize
    }
    ret c
}

fn den_apply(d: *Drl, x: f32, y: f32, sign: f32) {
    var xg = grid_of(x) - RADIUS
    var yg = grid_of(y) - RADIUS
    if xg >= i64(GRID) || xg < 0i64 || yg >= i64(GRID) || yg < 0i64 { os.exit(7) }
    var i = 0usize
    while i <= 20usize {
        var j = 0usize
        while j <= 20usize {
            let at = (usize(yg) + i) * GRID + usize(xg) + j
            if sign > 0.0f32 { d.dens[at] += d.fall[i * 21usize + j] } else { d.dens[at] -= d.fall[i * 21usize + j] }
            j += 1usize
        }
        i += 1usize
    }
}

// DensityGrid::Add(Node&, fineDensity): also stores the position in the node's sub_x, sub_y
fn dg_add(d: *Drl, node: usize) {
    let x = d.px[node]
    let y = d.py[node]
    d.sx[node] = x
    d.sy[node] = y
    if d.fine {
        let cell = usize(grid_of(y)) * GRID + usize(grid_of(x))
        let e = d.ecount
        d.ecount += 1usize
        d.ex[e] = x
        d.ey[e] = y
        d.enext[e] = 0i64 - 1i64
        if d.head[cell] < 0i64 {
            d.head[cell] = i64(e)
        } else {
            d.enext[usize(d.tail[cell])] = i64(e)
        }
        d.tail[cell] = i64(e)
    } else {
        den_apply(d, x, y, 1.0f32)
    }
}

fn dg_subtract(d: *Drl, node: usize) {
    if d.fine && !d.fine_first_add {
        let cell = usize(grid_of(d.sy[node])) * GRID + usize(grid_of(d.sx[node]))
        let h = d.head[cell]
        d.head[cell] = d.enext[usize(h)]
    } else if !d.first_add {
        den_apply(d, d.sx[node], d.sy[node], 0.0f32 - 1.0f32)
    }
}

fn get_density(d: *Drl, nx: f32, ny: f32) -> f32 {
    let xg = grid_of(nx)
    let yg = grid_of(ny)
    if xg > i64(GRID) - 10i64 || xg < 10i64 { ret 10000.0f32 }
    if yg > i64(GRID) - 10i64 || yg < 10i64 { ret 10000.0f32 }
    var density = 0.0f32
    if d.fine {
        var i = yg - 1i64
        while i <= yg + 1i64 {
            var j = xg - 1i64
            while j <= xg + 1i64 {
                var e = d.head[usize(i) * GRID + usize(j)]
                while e >= 0i64 {
                    let xd = nx - d.ex[usize(e)]
                    let yd = ny - d.ey[usize(e)]
                    let distance = xd * xd + yd * yd
                    density = f32(f64(density) + 1e-4f64 / (f64(distance) + 1e-50f64))
                    e = d.enext[usize(e)]
                }
                j += 1i64
            }
            i += 1i64
        }
    } else {
        density = d.dens[usize(yg) * GRID + usize(xg)]
        density = density * density
    }
    ret density
}

fn node_energy(d: *Drl, node: usize) -> f32 {
    let a = d.attraction
    let factor = f32(f64(a * a * a * a) * 2e-2f64)
    var e = 0.0f32
    var j = 0usize
    while j < d.n {
        if d.pres[node * d.n + j] {
            let w = d.wm[node * d.n + j]
            let xd = d.px[node] - d.px[j]
            let yd = d.py[node] - d.py[j]
            var ed = xd * xd + yd * yd
            if d.stage < 2i64 { ed = ed * ed }
            if d.stage == 0i64 { ed = ed * ed }
            e += w * factor * ed
        }
        j += 1usize
    }
    e += get_density(d, d.px[node], d.py[node])
    ret e
}

// Solve_Analytic: the new position, and the possible cutting of the longest edge
fn solve_analytic(d: *Drl, node: usize) -> (f32, f32) {
    var total = 0.0f32
    var x = 0.0f32
    var y = 0.0f32
    var xc = 0.0f32
    var yc = 0.0f32
    var j = 0usize
    while j < d.n {
        if d.pres[node * d.n + j] {
            let w = d.wm[node * d.n + j]
            total += w
            x += w * d.px[j]
            y += w * d.py[j]
        }
        j += 1usize
    }
    var posx = d.px[node]
    var posy = d.py[node]
    if total > 0.0f32 {
        xc = x / total
        yc = y / total
        let damping = f32(1.0f64 - f64(d.damping_mult))
        let p1 = damping * d.px[node]
        let p2 = damping * d.py[node]
        posx = f32(f64(p1) + (1.0f64 - f64(damping)) * f64(xc))
        posy = f32(f64(p2) + (1.0f64 - f64(damping)) * f64(yc))
    }
    if d.min_edges == 99.0f32 { ret (posx, posy) }
    if d.cut_end >= 39500.0f32 { ret (posx, posy) }
    let size = nsize(d, node)
    let numc = f32(math.sqrt[f64](f64(size)))
    var maxlen = 0.0f32
    var maxidx = 0usize
    var first = true
    j = 0usize
    while j < d.n {
        if d.pres[node * d.n + j] {
            if first {
                maxidx = j
                first = false
            }
            if !(f32(size) < d.min_edges) {
                let xd = xc - d.px[j]
                let yd = yc - d.py[j]
                var dis = xd * xd + yd * yd
                dis = dis * numc
                if dis > maxlen {
                    maxlen = dis
                    maxidx = j
                }
            }
        }
        j += 1usize
    }
    if maxlen > d.cut_off_length && !first { d.pres[node * d.n + maxidx] = false }
    ret (posx, posy)
}

fn update_node_pos(d: *Drl, r: *rg.Rng, node: usize, oldx: f32, oldy: f32) -> (f32, f32) {
    let jump = f32(0.010f64 * f64(d.temperature))
    dg_subtract(d, node)
    let e0 = node_energy(d, node)
    let (sx, sy) = solve_analytic(d, node)
    d.px[node] = sx
    d.py[node] = sy
    let u1 = rg.unif(r)
    let x1 = f32(f64(sx) + (0.5f64 - u1) * f64(jump))
    let u2 = rg.unif(r)
    let y1 = f32(f64(sy) + (0.5f64 - u2) * f64(jump))
    d.px[node] = x1
    d.py[node] = y1
    let e1 = node_energy(d, node)
    d.px[node] = oldx
    d.py[node] = oldy
    if !d.fine && !d.first_add {
        dg_add(d, node)
    } else if !d.fine_first_add {
        dg_add(d, node)
    }
    if e0 < e1 {
        d.en[node] = e0
        ret (sx, sy)
    }
    d.en[node] = e1
    ret (x1, y1)
}

fn update_nodes(d: *Drl, r: *rg.Rng) {
    var i = 0usize
    while i < d.n {
        let oldx = d.px[i]
        let oldy = d.py[i]
        let (nx, ny) = update_node_pos(d, r, i, oldx, oldy)
        // update_density: back to the old position, subtract, move to the new one, add
        d.px[i] = oldx
        d.py[i] = oldy
        dg_subtract(d, i)
        d.px[i] = nx
        d.py[i] = ny
        dg_add(d, i)
        i += 1usize
    }
    d.first_add = false
    if d.fine { d.fine_first_add = false }
}

// ReCompute: one sweep, then the schedule; false once the last stage is reached
fn recompute(d: *Drl, r: *rg.Rng) -> bool {
    update_nodes(d, r)
    if d.stage == 0i64 {
        if d.iterations < d.sit[1usize] {
            d.temperature = d.stemp[1usize]
            d.attraction = d.satt[1usize]
            d.damping_mult = d.sdamp[1usize]
            d.iterations += 1i64
        } else {
            d.temperature = d.stemp[2usize]
            d.attraction = d.satt[2usize]
            d.damping_mult = d.sdamp[2usize]
            d.iterations = 0i64
            d.stage = 1i64
        }
    }
    if d.stage == 1i64 {
        if d.iterations < d.sit[2usize] {
            if f64(d.attraction) > 1.0f64 { d.attraction = d.attraction - 0.05f32 }
            if d.min_edges > 12.0f32 { d.min_edges = d.min_edges - 0.05f32 }
            d.cut_off_length = d.cut_off_length - d.cut_rate
            if f64(d.damping_mult) > 0.1f64 { d.damping_mult = d.damping_mult - 0.005f32 }
            d.iterations += 1i64
        } else {
            d.min_edges = 12.0f32
            d.damping_mult = d.sdamp[3usize]
            d.stage = 2i64
            d.attraction = d.satt[3usize]
            d.temperature = d.stemp[3usize]
            d.iterations = 0i64
        }
    } else if d.stage == 2i64 {
        if d.iterations < d.sit[3usize] {
            if d.temperature > 50.0f32 { d.temperature = d.temperature - 10.0f32 }
            if d.cut_off_length > d.cut_length_end { d.cut_off_length = d.cut_off_length - d.cut_rate * 2.0f32 }
            if d.min_edges > 1.0f32 { d.min_edges = d.min_edges - 0.2f32 }
            d.iterations += 1i64
        } else {
            d.cut_off_length = d.cut_length_end
            d.temperature = d.stemp[4usize]
            d.damping_mult = d.sdamp[4usize]
            d.min_edges = 1.0f32
            d.stage = 3i64
            d.iterations = 0i64
            d.attraction = d.satt[4usize]
        }
    } else if d.stage == 3i64 {
        if d.iterations < d.sit[4usize] {
            d.iterations += 1i64
        } else {
            d.iterations = 0i64
            d.temperature = d.stemp[5usize]
            d.attraction = d.satt[5usize]
            d.damping_mult = d.sdamp[5usize]
            d.min_edges = 99.0f32
            d.fine = true
            d.stage = 5i64
        }
    } else if d.stage == 5i64 {
        if d.iterations < d.sit[5usize] {
            if d.temperature > 50.0f32 { d.temperature = d.temperature - 2.0f32 }
            d.iterations += 1i64
        } else {
            d.stage = 6i64
        }
    } else if d.stage == 6i64 {
        ret false
    }
    ret true
}

fn drl(a: *mem.Arena, r: *rg.Rng, n: usize, ed: []const i64, weights: []const f64, opts: []const f64) -> []f64 {
    // R evaluates the default seed matrix(runif(2 n)) before calling the layout
    var q = 0usize
    while q < 2usize * n {
        let _ = rg.unif(r)
        q += 1usize
    }
    let cells = GRID * GRID
    let sit = gg.zi(a, 6usize)
    let stemp = gg.zf32(a, 6usize)
    let satt = gg.zf32(a, 6usize)
    let sdamp = gg.zf32(a, 6usize)
    var s = 0usize
    while s < 6usize {
        sit[s] = i64(opts[1usize + 4usize * s])
        stemp[s] = f32(opts[2usize + 4usize * s])
        satt[s] = f32(opts[3usize + 4usize * s])
        sdamp[s] = f32(opts[4usize + 4usize * s])
        s += 1usize
    }
    var d = Drl {
        n: n, px: gg.zf32(a, n), py: gg.zf32(a, n), sx: gg.zf32(a, n), sy: gg.zf32(a, n), en: gg.zf32(a, n), wm: gg.zf32(a, n * n), pres: gg.zb(a, n * n),
        dens: gg.zf32(a, cells), fall: gg.zf32(a, 441usize), head: gg.zi(a, cells), tail: gg.zi(a, cells), ex: gg.zf32(a, n * 1200usize + 16usize),
        ey: gg.zf32(a, n * 1200usize + 16usize), enext: gg.zi(a, n * 1200usize + 16usize), ecount: 0usize,
        stage: 0i64, iterations: sit[0usize], temperature: stemp[0usize], attraction: satt[0usize], damping_mult: sdamp[0usize], min_edges: 20.0f32, cut_end: 0.0f32,
        cut_length_end: 0.0f32, cut_off_length: 0.0f32, cut_rate: 0.0f32, first_add: true, fine_first_add: true, fine: false, sit: sit, stemp: stemp, satt: satt, sdamp: sdamp
    }
    var c = 0usize
    while c < cells {
        d.head[c] = 0i64 - 1i64
        c += 1usize
    }
    var i = 0i64
    while i <= 20i64 {
        var j = 0i64
        while j <= 20i64 {
            let ai = i - 10i64
            let aj = j - 10i64
            var fi = ai
            if fi < 0i64 { fi = 0i64 - fi }
            var fj = aj
            if fj < 0i64 { fj = 0i64 - fj }
            let u = (10.0f32 - f32(fi)) / 10.0f32
            let v = (10.0f32 - f32(fj)) / 10.0f32
            d.fall[usize(i) * 21usize + usize(j)] = u * v
            j += 1i64
        }
        i += 1i64
    }
    // neighbours, later edges overwrite earlier ones
    var k = 0usize
    while k + 1usize < ed.len {
        let x = usize(ed[k])
        let y = usize(ed[k + 1usize])
        var w = 1.0f32
        if weights.len > 0usize { w = f32(weights[k / 2usize]) }
        d.pres[x * n + y] = true
        d.wm[x * n + y] = w
        d.pres[y * n + x] = true
        d.wm[y * n + x] = w
        k += 2usize
    }
    // init_parms
    let ec = f32(opts[0usize])
    d.cut_length_end = f32(40000.0f64 * (1.0f64 - f64(ec)))
    d.cut_end = d.cut_length_end
    if d.cut_length_end <= 1.0f32 { d.cut_length_end = 1.0f32 }
    let start = f32(4.0f64 * f64(d.cut_length_end))
    d.cut_off_length = start
    d.cut_rate = f32(f64(start - d.cut_length_end) / 400.0f64)
    while recompute(&d, r) { }
    let out = gg.zf(a, 2usize * n)
    i = 0i64
    while usize(i) < n {
        out[usize(i) * 2usize] = f64(d.px[usize(i)])
        out[usize(i) * 2usize + 1usize] = f64(d.py[usize(i)])
        i += 1i64
    }
    ret out[0usize..2usize * n]
}
