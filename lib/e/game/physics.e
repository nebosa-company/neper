// Small 2-d physics kernels over caller `[]f64` storage: position-based and
// extended position-based dynamics over distance constraints, a projected
// Gauss-Seidel contact solver, conservative advancement for two moving
// circles, sweep-and-prune broadphase, a smoothed-particle fluid step and a
// staggered (MAC) grid fluid step.
//
// Positions and velocities are packed pairs (`xs[2 * i]`, `xs[2 * i + 1]`);
// `inv_mass[i] == 0.0` pins a particle. Nothing here allocates: every scratch
// array is the caller's, and every loop runs in a fixed order so a replica
// with the same inputs reaches the same bits.

use e.math

type Constraint = struct { a: u32, b: u32, rest: f64, stiffness: f64, compliance: f64 }
// A velocity-level contact: `n` points from `a` to `b`, `bias` is the separating speed
// wanted along it (a positional-recovery or restitution term), `friction` the coefficient.
type Contact = struct { a: u32, b: u32, nx: f64, ny: f64, bias: f64, friction: f64 }
type Aabb = struct { min_x: f64, min_y: f64, max_x: f64, max_y: f64 }
type Pair = struct { a: u32, b: u32 }
type Circle = struct { x: f64, y: f64, radius: f64, vx: f64, vy: f64 }
type SphParams = struct { h: f64, mass: f64, rest_density: f64, stiffness: f64, viscosity: f64, gravity: f64 }
// `u` is (w + 1) x h face velocities, `v` is w x (h + 1); `p`, `div` are w x h. The two
// `next` planes are scratch for the advection.
type MacGrid = struct { w: usize, h: usize, u: []f64, v: []f64, p: []f64, div: []f64, u_next: []f64, v_next: []f64 }
error TooSmall
error Invalid

fn pi() -> f64 { ret 3.141592653589793f64 }

fn distance(pos: []const f64, a: usize, b: usize) -> (f64, f64, f64) {
    let dx = pos[2usize * b] - pos[2usize * a]
    let dy = pos[2usize * b + 1usize] - pos[2usize * a + 1usize]
    ret (dx, dy, math.sqrt[f64](dx * dx + dy * dy))
}

fn predict(pos: []f64, vel: []f64, inv_mass: []const f64, prev: []f64, gravity_y: f64, dt: f64) -> err {
    let n = inv_mass.len
    if pos.len < 2usize * n || vel.len < 2usize * n || prev.len < 2usize * n { ret TooSmall }
    if dt <= 0.0f64 { ret Invalid }
    var i = 0usize
    while i < n {
        if inv_mass[i] > 0.0f64 { vel[2usize * i + 1usize] += gravity_y * dt }
        prev[2usize * i] = pos[2usize * i]
        prev[2usize * i + 1usize] = pos[2usize * i + 1usize]
        pos[2usize * i] += vel[2usize * i] * dt
        pos[2usize * i + 1usize] += vel[2usize * i + 1usize] * dt
        i += 1usize
    }
    ret ok
}

fn derive_velocity(pos: []const f64, vel: []f64, prev: []const f64, n: usize, dt: f64) {
    var i = 0usize
    while i < 2usize * n {
        vel[i] = (pos[i] - prev[i]) / dt
        i += 1usize
    }
}

fn check_constraints(constraints: []const Constraint, n: usize) -> err {
    var j = 0usize
    while j < constraints.len {
        if usize(constraints[j].a) >= n || usize(constraints[j].b) >= n { ret Invalid }
        j += 1usize
    }
    ret ok
}

// One PBD step: predict under gravity, project every distance constraint `iterations`
// times, then read velocities back from the motion. `prev` is scratch of `pos.len`.
fn pbd_step(pos: []f64, vel: []f64, inv_mass: []const f64, prev: []f64, constraints: []const Constraint, gravity_y: f64, dt: f64, iterations: usize) -> err {
    let n = inv_mass.len
    let bad = check_constraints(constraints, n)
    if bad != ok { ret bad }
    let predicted = predict(pos, vel, inv_mass, prev, gravity_y, dt)
    if predicted != ok { ret predicted }
    var it = 0usize
    while it < iterations {
        var j = 0usize
        while j < constraints.len {
            let c = constraints[j]
            let a = usize(c.a)
            let b = usize(c.b)
            let w = inv_mass[a] + inv_mass[b]
            let (dx, dy, span) = distance(pos, a, b)
            if span > 0.0f64 && w > 0.0f64 {
                let s = c.stiffness * (span - c.rest) / (span * w)
                pos[2usize * a] += inv_mass[a] * s * dx
                pos[2usize * a + 1usize] += inv_mass[a] * s * dy
                pos[2usize * b] -= inv_mass[b] * s * dx
                pos[2usize * b + 1usize] -= inv_mass[b] * s * dy
            }
            j += 1usize
        }
        it += 1usize
    }
    derive_velocity(pos, vel, prev, n, dt)
    ret ok
}

// One XPBD step: as `pbd_step`, but each constraint carries a Lagrange multiplier in
// `lambda` (one per constraint, reset here) and `alpha = compliance / dt^2` softens it
// independently of the iteration count.
fn xpbd_step(pos: []f64, vel: []f64, inv_mass: []const f64, prev: []f64, lambda: []f64, constraints: []const Constraint, gravity_y: f64, dt: f64, iterations: usize) -> err {
    let n = inv_mass.len
    if lambda.len < constraints.len { ret TooSmall }
    let bad = check_constraints(constraints, n)
    if bad != ok { ret bad }
    let predicted = predict(pos, vel, inv_mass, prev, gravity_y, dt)
    if predicted != ok { ret predicted }
    var j = 0usize
    while j < constraints.len {
        lambda[j] = 0.0f64
        j += 1usize
    }
    var it = 0usize
    while it < iterations {
        j = 0usize
        while j < constraints.len {
            let c = constraints[j]
            let a = usize(c.a)
            let b = usize(c.b)
            let w = inv_mass[a] + inv_mass[b]
            let (dx, dy, span) = distance(pos, a, b)
            if span > 0.0f64 && w > 0.0f64 {
                let alpha = c.compliance / (dt * dt)
                let d_lambda = (0.0f64 - (span - c.rest) - alpha * lambda[j]) / (w + alpha)
                lambda[j] += d_lambda
                // The gradient at `a` is -(b - a) / len, so `a` moves against it.
                let s = d_lambda / span
                pos[2usize * a] -= inv_mass[a] * s * dx
                pos[2usize * a + 1usize] -= inv_mass[a] * s * dy
                pos[2usize * b] += inv_mass[b] * s * dx
                pos[2usize * b + 1usize] += inv_mass[b] * s * dy
            }
            j += 1usize
        }
        it += 1usize
    }
    derive_velocity(pos, vel, prev, n, dt)
    ret ok
}

fn clamp(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

// Projected Gauss-Seidel over the contacts: the accumulated normal impulse never goes
// below zero and the tangent impulse stays inside the friction cone. `normal` and
// `tangent` receive the accumulated impulses, one per contact; `vel` is updated.
// ponytail: point masses only (no angular terms); add inertia when bodies rotate.
fn solve_gauss_seidel(contacts: []const Contact, vel: []f64, inv_mass: []const f64, normal: []f64, tangent: []f64, iterations: usize) -> err {
    let n = inv_mass.len
    if vel.len < 2usize * n || normal.len < contacts.len || tangent.len < contacts.len { ret TooSmall }
    var j = 0usize
    while j < contacts.len {
        if usize(contacts[j].a) >= n || usize(contacts[j].b) >= n { ret Invalid }
        normal[j] = 0.0f64
        tangent[j] = 0.0f64
        j += 1usize
    }
    var it = 0usize
    while it < iterations {
        j = 0usize
        while j < contacts.len {
            let c = contacts[j]
            let a = usize(c.a)
            let b = usize(c.b)
            let w = inv_mass[a] + inv_mass[b]
            if w > 0.0f64 {
                let tx = 0.0f64 - c.ny
                let ty = c.nx
                let rvx = vel[2usize * b] - vel[2usize * a]
                let rvy = vel[2usize * b + 1usize] - vel[2usize * a + 1usize]
                let vn = rvx * c.nx + rvy * c.ny
                let total_n = normal[j] + (c.bias - vn) / w
                var new_n = total_n
                if new_n < 0.0f64 { new_n = 0.0f64 }
                let dn = new_n - normal[j]
                normal[j] = new_n
                vel[2usize * a] -= inv_mass[a] * dn * c.nx
                vel[2usize * a + 1usize] -= inv_mass[a] * dn * c.ny
                vel[2usize * b] += inv_mass[b] * dn * c.nx
                vel[2usize * b + 1usize] += inv_mass[b] * dn * c.ny
                let rvx2 = vel[2usize * b] - vel[2usize * a]
                let rvy2 = vel[2usize * b + 1usize] - vel[2usize * a + 1usize]
                let vt = rvx2 * tx + rvy2 * ty
                let limit = c.friction * normal[j]
                let new_t = clamp(tangent[j] - vt / w, 0.0f64 - limit, limit)
                let dt = new_t - tangent[j]
                tangent[j] = new_t
                vel[2usize * a] -= inv_mass[a] * dt * tx
                vel[2usize * a + 1usize] -= inv_mass[a] * dt * ty
                vel[2usize * b] += inv_mass[b] * dt * tx
                vel[2usize * b + 1usize] += inv_mass[b] * dt * ty
            }
            j += 1usize
        }
        it += 1usize
    }
    ret ok
}

// Conservative advancement of two circles over one unit of time: advance by the
// separation over the relative speed (a bound on the closing speed) until they touch
// within `tolerance` or the step is spent. Answers the time of impact in [0, 1] and
// whether contact was reached.
// ponytail: circles only; a convex shape needs a support map to bound the distance.
fn ccd_conservative(a: Circle, b: Circle, tolerance: f64) -> (f64, bool) {
    let rvx = b.vx - a.vx
    let rvy = b.vy - a.vy
    let speed = math.sqrt[f64](rvx * rvx + rvy * rvy)
    var t = 0.0f64
    var guard = 0usize
    while guard < 64usize {
        let dx = (b.x + rvx * t) - a.x
        let dy = (b.y + rvy * t) - a.y
        let gap = math.sqrt[f64](dx * dx + dy * dy) - a.radius - b.radius
        if gap <= tolerance { ret (t, true) }
        if speed == 0.0f64 { ret (1.0f64, false) }
        // Only motion toward the other circle can close the gap.
        let centre = 0.0f64 - (dx * rvx + dy * rvy)
        if centre <= 0.0f64 { ret (1.0f64, false) }
        t += gap / speed
        if t >= 1.0f64 { ret (1.0f64, false) }
        guard += 1usize
    }
    ret (t, false)
}

// Every overlapping pair of boxes, by sorting on `min_x` (an insertion sort into
// `order`, scratch of `boxes.len`) and testing y only where the x-intervals overlap.
// Each pair is answered once with the lower index first; touching edges count.
fn sweep_and_prune(boxes: []const Aabb, order: []u32, out: []Pair) -> (usize, err) {
    let n = boxes.len
    if order.len < n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        order[i] = u32(i)
        var k = i
        while k > 0usize && boxes[usize(order[k - 1usize])].min_x > boxes[usize(order[k])].min_x {
            let tmp = order[k]
            order[k] = order[k - 1usize]
            order[k - 1usize] = tmp
            k -= 1usize
        }
        i += 1usize
    }
    var count = 0usize
    i = 0usize
    while i < n {
        let first = boxes[usize(order[i])]
        var j = i + 1usize
        while j < n {
            let second = boxes[usize(order[j])]
            if second.min_x > first.max_x { break }
            if second.min_y <= first.max_y && first.min_y <= second.max_y {
                if count == out.len { ret (count, TooSmall) }
                var lo = order[i]
                var hi = order[j]
                if lo > hi {
                    lo = order[j]
                    hi = order[i]
                }
                out[count] = Pair { a: lo, b: hi }
                count += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (count, ok)
}

// One SPH step: poly6 density, a Tait-free linear pressure `k (rho - rho0)`, spiky
// pressure gradients, the viscosity Laplacian, gravity, then semi-implicit Euler.
// `density`, `pressure`, `fx`, `fy` are scratch of `n`.
// ponytail: O(n^2) neighbour scan; hash into a grid when n grows past a few hundred.
fn sph(pos: []f64, vel: []f64, density: []f64, pressure: []f64, fx: []f64, fy: []f64, params: SphParams, dt: f64) -> err {
    let n = density.len
    if pos.len < 2usize * n || vel.len < 2usize * n || pressure.len < n || fx.len < n || fy.len < n { ret TooSmall }
    if params.h <= 0.0f64 || dt <= 0.0f64 { ret Invalid }
    let h = params.h
    let h2 = h * h
    let h4 = h2 * h2
    let poly6 = 4.0f64 / (pi() * h4 * h4)
    let spiky = 10.0f64 / (pi() * h4 * h)
    let laplacian = 40.0f64 / (pi() * h4 * h)
    var i = 0usize
    while i < n {
        var rho = 0.0f64
        var j = 0usize
        while j < n {
            let dx = pos[2usize * i] - pos[2usize * j]
            let dy = pos[2usize * i + 1usize] - pos[2usize * j + 1usize]
            let r2 = dx * dx + dy * dy
            if r2 < h2 {
                let q = h2 - r2
                rho += params.mass * poly6 * q * q * q
            }
            j += 1usize
        }
        density[i] = rho
        pressure[i] = params.stiffness * (rho - params.rest_density)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var ax = 0.0f64
        var ay = 0.0f64
        var j = 0usize
        while j < n {
            if j != i {
                let dx = pos[2usize * i] - pos[2usize * j]
                let dy = pos[2usize * i + 1usize] - pos[2usize * j + 1usize]
                let r = math.sqrt[f64](dx * dx + dy * dy)
                if r > 0.0f64 && r < h {
                    let q = h - r
                    let press = 0.0f64 - params.mass * (pressure[i] + pressure[j]) / (2.0f64 * density[j]) * spiky * q * q / r
                    ax += press * dx
                    ay += press * dy
                    let visc = params.viscosity * params.mass / density[j] * laplacian * q
                    ax += visc * (vel[2usize * j] - vel[2usize * i])
                    ay += visc * (vel[2usize * j + 1usize] - vel[2usize * i + 1usize])
                }
            }
            j += 1usize
        }
        fx[i] = ax
        fy[i] = ay + params.gravity * density[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        vel[2usize * i] += dt * fx[i] / density[i]
        vel[2usize * i + 1usize] += dt * fy[i] / density[i]
        pos[2usize * i] += dt * vel[2usize * i]
        pos[2usize * i + 1usize] += dt * vel[2usize * i + 1usize]
        i += 1usize
    }
    ret ok
}

fn mac_init(g: *MacGrid, w: usize, h: usize, u: []f64, v: []f64, p: []f64, div: []f64, u_next: []f64, v_next: []f64) -> err {
    if w == 0usize || h == 0usize { ret Invalid }
    let faces_u = (w + 1usize) * h
    let faces_v = w * (h + 1usize)
    if u.len < faces_u || u_next.len < faces_u || v.len < faces_v || v_next.len < faces_v { ret TooSmall }
    if p.len < w * h || div.len < w * h { ret TooSmall }
    g.w = w
    g.h = h
    g.u = u
    g.v = v
    g.p = p
    g.div = div
    g.u_next = u_next
    g.v_next = v_next
    var i = 0usize
    while i < faces_u {
        u[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < faces_v {
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < w * h {
        p[i] = 0.0f64
        i += 1usize
    }
    ret ok
}

// Bilinear sample of a lattice of `nx` x `ny` values whose sample (i, j) sits at
// (i + ox, j + oy) in cell units; positions outside are clamped to the edge samples.
fn sample(field: []const f64, nx: usize, ny: usize, ox: f64, oy: f64, x: f64, y: f64) -> f64 {
    let fx = clamp(x - ox, 0.0f64, f64(nx - 1usize))
    let fy = clamp(y - oy, 0.0f64, f64(ny - 1usize))
    let i0 = usize(fx)
    let j0 = usize(fy)
    var i1 = i0 + 1usize
    if i1 > nx - 1usize { i1 = nx - 1usize }
    var j1 = j0 + 1usize
    if j1 > ny - 1usize { j1 = ny - 1usize }
    let tx = fx - f64(i0)
    let ty = fy - f64(j0)
    let bottom = field[j0 * nx + i0] * (1.0f64 - tx) + field[j0 * nx + i1] * tx
    let top = field[j1 * nx + i0] * (1.0f64 - tx) + field[j1 * nx + i1] * tx
    ret bottom * (1.0f64 - ty) + top * ty
}

fn sample_u(g: *MacGrid, x: f64, y: f64) -> f64 { ret sample(g.u, g.w + 1usize, g.h, 0.0f64, 0.5f64, x, y) }
fn sample_v(g: *MacGrid, x: f64, y: f64) -> f64 { ret sample(g.v, g.w, g.h + 1usize, 0.5f64, 0.0f64, x, y) }

// One MAC-grid step with unit cells and solid walls: semi-Lagrangian advection of both
// face planes, gravity on `v`, then a Gauss-Seidel pressure solve that leaves the
// field divergence-free to the accuracy the `iterations` reach.
fn fluid_mac(g: *MacGrid, gravity_y: f64, dt: f64, iterations: usize) -> err {
    let w = g.w
    let h = g.h
    if w == 0usize || h == 0usize { ret Invalid }
    if dt <= 0.0f64 { ret Invalid }
    let nu = w + 1usize
    var j = 0usize
    while j < h {
        var i = 0usize
        while i < nu {
            let x = f64(i)
            let y = f64(j) + 0.5f64
            let ux = g.u[j * nu + i]
            let vy = sample_v(g, x, y)
            g.u_next[j * nu + i] = sample_u(g, x - dt * ux, y - dt * vy)
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < h + 1usize {
        var i = 0usize
        while i < w {
            let x = f64(i) + 0.5f64
            let y = f64(j)
            let ux = sample_u(g, x, y)
            let vy = g.v[j * w + i]
            g.v_next[j * w + i] = sample_v(g, x - dt * ux, y - dt * vy) + gravity_y * dt
            i += 1usize
        }
        j += 1usize
    }
    // Copy back; the walls carry no flow.
    j = 0usize
    while j < h {
        var i = 0usize
        while i < nu {
            var value = g.u_next[j * nu + i]
            if i == 0usize || i == w { value = 0.0f64 }
            g.u[j * nu + i] = value
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < h + 1usize {
        var i = 0usize
        while i < w {
            var value = g.v_next[j * w + i]
            if j == 0usize || j == h { value = 0.0f64 }
            g.v[j * w + i] = value
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < h {
        var i = 0usize
        while i < w {
            g.div[j * w + i] = (g.u[j * nu + i + 1usize] - g.u[j * nu + i]) + (g.v[(j + 1usize) * w + i] - g.v[j * w + i])
            g.p[j * w + i] = 0.0f64
            i += 1usize
        }
        j += 1usize
    }
    var it = 0usize
    while it < iterations {
        j = 0usize
        while j < h {
            var i = 0usize
            while i < w {
                var sum = 0.0f64
                var count = 0.0f64
                if i > 0usize {
                    sum += g.p[j * w + i - 1usize]
                    count += 1.0f64
                }
                if i + 1usize < w {
                    sum += g.p[j * w + i + 1usize]
                    count += 1.0f64
                }
                if j > 0usize {
                    sum += g.p[(j - 1usize) * w + i]
                    count += 1.0f64
                }
                if j + 1usize < h {
                    sum += g.p[(j + 1usize) * w + i]
                    count += 1.0f64
                }
                if count > 0.0f64 { g.p[j * w + i] = (sum - g.div[j * w + i]) / count }
                i += 1usize
            }
            j += 1usize
        }
        it += 1usize
    }
    j = 0usize
    while j < h {
        var i = 1usize
        while i < w {
            g.u[j * nu + i] -= g.p[j * w + i] - g.p[j * w + i - 1usize]
            i += 1usize
        }
        j += 1usize
    }
    j = 1usize
    while j < h {
        var i = 0usize
        while i < w {
            g.v[j * w + i] -= g.p[j * w + i] - g.p[(j - 1usize) * w + i]
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// The largest cell divergence after a step -- the projection's residual.
fn mac_divergence(g: *MacGrid) -> f64 {
    let w = g.w
    let nu = w + 1usize
    var worst = 0.0f64
    var j = 0usize
    while j < g.h {
        var i = 0usize
        while i < w {
            let d = math.abs[f64]((g.u[j * nu + i + 1usize] - g.u[j * nu + i]) + (g.v[(j + 1usize) * w + i] - g.v[j * w + i]))
            if d > worst { worst = d }
            i += 1usize
        }
        j += 1usize
    }
    ret worst
}
