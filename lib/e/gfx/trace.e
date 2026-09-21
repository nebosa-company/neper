// A small path tracer over sphere scenes in caller storage, and ray casts
// against constructive solid geometry. A `Sphere` is Lambertian with an
// `albedo` and an `emission`; the background is black. A `Job` names the
// spheres, the camera, the image size, the samples per pixel, the bounce
// after which a path stops (`max_depth`) and the bounce from which Russian
// roulette starts (`roulette_depth`, equal to `max_depth` for none). The three
// renderers share one walk and differ in how light reaches a path:
// `path_trace` counts emission wherever a bounce lands; `next_event_estimation`
// also casts one shadow ray per emissive sphere at every vertex (uniform cone
// sampling of the sphere's solid angle) and then counts emission at a bounce
// only when that light could not be sampled from the previous vertex, which is
// when the vertex lay inside it; `multiple_importance` does both and weights
// each by the balance heuristic over the cosine and cone densities.
//
// Sampling order, for a replica: per pixel in row-major order, per sample two
// `rand.pcg64_f64` draws jitter the pixel (x then y); per vertex, the shadow
// rays (two draws each, polar then azimuth, one emissive sphere after another
// in scene order, only when the vertex is outside it and facing it) come first,
// then one draw for roulette when it applies, then two draws for the cosine
// bounce (polar then azimuth). Frames come from `shade.onb`, ray origins are
// moved `EPSILON` along the shading normal, and hits closer than that are
// ignored. Radiance is linear `shade.Rgb`, the average over the samples.
//
// `csg` answers the sorted, disjoint parameter intervals along a ray where it
// is inside a tree of spheres and axis-aligned boxes joined by union,
// intersection and difference: leaves give their own interval, an operator
// sweeps the two lists' end points and keeps each elementary segment its
// operation admits. `csg_hit` is the first boundary at a positive parameter.

use e.algo.rand
use e.gfx.shade
use e.math

type Sphere = struct { center: shade.Vec3, radius: f64, albedo: shade.Rgb, emission: shade.Rgb }
type Camera = struct { origin: shade.Vec3, forward: shade.Vec3, right: shade.Vec3, up: shade.Vec3, tan_half: f64 }
type Ray = struct { origin: shade.Vec3, direction: shade.Vec3 }
type Job = struct { spheres: []const Sphere, camera: Camera, width: usize, height: usize, samples: usize, max_depth: usize, roulette_depth: usize }
type Mode = enum u8 { Naive, Nee, Mis }
type CsgKind = enum u8 { Sphere, Box, Union, Intersection, Difference }
type CsgNode = struct { kind: CsgKind, left: u32, right: u32, center: shade.Vec3, radius: f64, lo: shade.Vec3, hi: shade.Vec3 }
type Interval = struct { enter: f64, exit: f64 }
error Invalid
error TooSmall

fn epsilon() -> f64 { ret 1.0e-6f64 }
fn two_pi() -> f64 { ret 6.283185307179586f64 }

fn sphere(center: shade.Vec3, radius: f64, albedo: shade.Rgb, emission: shade.Rgb) -> Sphere {
    ret Sphere { center: center, radius: radius, albedo: albedo, emission: emission }
}

// A camera at `origin` looking at `aim` with `up` roughly upward and a vertical field of view.
fn camera(origin: shade.Vec3, aim: shade.Vec3, up: shade.Vec3, vertical_fov: f64) -> Camera {
    let forward = shade.normalize(shade.sub(aim, origin))
    let right = shade.normalize(shade.cross(forward, up))
    let true_up = shade.cross(right, forward)
    ret Camera { origin: origin, forward: forward, right: right, up: true_up, tan_half: math.tan[f64](vertical_fov * 0.5f64) }
}

// The ray through image position `(sx, sy)` in `0..1`, y downward.
fn camera_ray(c: Camera, sx: f64, sy: f64, aspect: f64) -> Ray {
    let x = (2.0f64 * sx - 1.0f64) * aspect * c.tan_half
    let y = (1.0f64 - 2.0f64 * sy) * c.tan_half
    let direction = shade.normalize(shade.add(shade.add(c.forward, shade.scale(c.right, x)), shade.scale(c.up, y)))
    ret Ray { origin: c.origin, direction: direction }
}

// The entry and exit parameters of a unit-direction ray through a sphere.
fn sphere_span(origin: shade.Vec3, direction: shade.Vec3, center: shade.Vec3, radius: f64) -> (bool, f64, f64) {
    let oc = shade.sub(origin, center)
    let b = shade.dot(oc, direction)
    let c = shade.dot(oc, oc) - radius * radius
    let discriminant = b * b - c
    if discriminant < 0.0f64 { ret (false, 0.0f64, 0.0f64) }
    let root = math.sqrt[f64](discriminant)
    ret (true, 0.0f64 - b - root, 0.0f64 - b + root)
}

// The nearest sphere the ray meets beyond `EPSILON`, and where.
fn intersect(spheres: []const Sphere, ray: Ray) -> (bool, usize, f64) {
    var best = 0.0f64
    var index = 0usize
    var found = false
    var i = 0usize
    while i < spheres.len {
        let (hit, t_enter, t_exit) = sphere_span(ray.origin, ray.direction, spheres[i].center, spheres[i].radius)
        if hit {
            var t = t_enter
            if t <= epsilon() { t = t_exit }
            if t > epsilon() && (!found || t < best) {
                best = t
                index = i
                found = true
            }
        }
        i += 1usize
    }
    ret (found, index, best)
}

fn is_emissive(s: Sphere) -> bool {
    ret s.emission.red > 0.0f64 || s.emission.green > 0.0f64 || s.emission.blue > 0.0f64
}

fn max_channel(c: shade.Rgb) -> f64 {
    var m = c.red
    if c.green > m { m = c.green }
    if c.blue > m { m = c.blue }
    ret m
}

// The cosine of the half angle of the cone `s` subtends from `p`, or 1 when `p` is inside.
fn cone_cos(p: shade.Vec3, s: Sphere) -> (bool, f64) {
    let to_center = shade.sub(s.center, p)
    let d2 = shade.dot(to_center, to_center)
    if d2 <= s.radius * s.radius { ret (false, 1.0f64) }
    ret (true, math.sqrt[f64](1.0f64 - s.radius * s.radius / d2))
}

fn balance(a: f64, b: f64) -> f64 { ret a / (a + b) }

// A direction in the frame of `axis`: polar cosine `cos_theta`, azimuth `phi`.
fn direction_about(axis: shade.Vec3, cos_theta: f64, phi: f64) -> shade.Vec3 {
    let sin_theta = math.sqrt[f64](1.0f64 - cos_theta * cos_theta)
    let (t, b) = shade.onb(axis)
    let x = sin_theta * math.cos[f64](phi)
    let y = sin_theta * math.sin[f64](phi)
    ret shade.add(shade.add(shade.scale(t, x), shade.scale(b, y)), shade.scale(axis, cos_theta))
}

// Direct light at `p` with normal `n` and diffuse `albedo`, one cone sample per emissive sphere.
fn direct_light(spheres: []const Sphere, p: shade.Vec3, n: shade.Vec3, albedo: shade.Rgb, r: *rand.Pcg64, mode: Mode) -> shade.Rgb {
    var sum = shade.rgb(0.0f64, 0.0f64, 0.0f64)
    var i = 0usize
    while i < spheres.len {
        let light = spheres[i]
        if is_emissive(light) {
            let (outside, cos_max) = cone_cos(p, light)
            let axis = shade.normalize(shade.sub(light.center, p))
            if outside {
                let u1 = rand.pcg64_f64(r)
                let u2 = rand.pcg64_f64(r)
                let cos_theta = 1.0f64 - u1 * (1.0f64 - cos_max)
                let direction = direction_about(axis, cos_theta, two_pi() * u2)
                let cosine = shade.dot(n, direction)
                if cosine > 0.0f64 {
                    let (hit, index, _) = intersect(spheres, Ray { origin: p, direction: direction })
                    if hit && index == i {
                        let pdf_light = 1.0f64 / (two_pi() * (1.0f64 - cos_max))
                        var weight = 1.0f64
                        if mode == .Mis { weight = balance(pdf_light, cosine / shade.pi()) }
                        let f = shade.brdf_lambert(albedo)
                        sum = shade.rgb_add(sum, shade.rgb_scale(shade.rgb_mul(f, light.emission), cosine / pdf_light * weight))
                    }
                }
            }
        }
        i += 1usize
    }
    ret sum
}

// The radiance arriving along `ray`, one path.
fn radiance(job: *const Job, first: Ray, r: *rand.Pcg64, mode: Mode) -> shade.Rgb {
    var ray = first
    var total = shade.rgb(0.0f64, 0.0f64, 0.0f64)
    var throughput = shade.rgb(1.0f64, 1.0f64, 1.0f64)
    var depth = 0usize
    var previous = ray.origin
    var previous_pdf = 0.0f64
    while true {
        let (hit, index, t) = intersect(job.spheres, ray)
        if !hit { ret total }
        let s = job.spheres[index]
        let p = shade.add(ray.origin, shade.scale(ray.direction, t))
        var n = shade.normalize(shade.sub(p, s.center))
        if shade.dot(n, ray.direction) > 0.0f64 { n = shade.scale(n, -1.0f64) }
        if is_emissive(s) {
            var weight = 1.0f64
            if depth > 0usize && mode != .Naive {
                let (outside, cos_max) = cone_cos(previous, s)
                if outside {
                    weight = 0.0f64
                    if mode == .Mis { weight = balance(previous_pdf, 1.0f64 / (two_pi() * (1.0f64 - cos_max))) }
                }
            }
            total = shade.rgb_add(total, shade.rgb_scale(shade.rgb_mul(throughput, s.emission), weight))
        }
        if depth >= job.max_depth { ret total }
        let origin = shade.add(p, shade.scale(n, epsilon()))
        if mode != .Naive {
            let direct = direct_light(job.spheres, origin, n, s.albedo, r, mode)
            total = shade.rgb_add(total, shade.rgb_mul(throughput, direct))
        }
        if depth >= job.roulette_depth {
            let q = max_channel(s.albedo)
            if rand.pcg64_f64(r) >= q { ret total }
            throughput = shade.rgb_scale(throughput, 1.0f64 / q)
        }
        let u1 = rand.pcg64_f64(r)
        let u2 = rand.pcg64_f64(r)
        let cos_theta = math.sqrt[f64](1.0f64 - u1)
        let direction = direction_about(n, cos_theta, two_pi() * u2)
        throughput = shade.rgb_mul(throughput, s.albedo)
        previous = origin
        previous_pdf = cos_theta / shade.pi()
        ray = Ray { origin: origin, direction: direction }
        depth += 1usize
    }
    ret total
}

fn render(job: *const Job, r: *rand.Pcg64, out: []shade.Rgb, mode: Mode) -> err {
    if job.width == 0usize || job.height == 0usize || job.samples == 0usize { ret Invalid }
    if out.len < job.width * job.height { ret TooSmall }
    let aspect = f64(job.width) / f64(job.height)
    let inverse = 1.0f64 / f64(job.samples)
    var y = 0usize
    while y < job.height {
        var x = 0usize
        while x < job.width {
            var sum = shade.rgb(0.0f64, 0.0f64, 0.0f64)
            var s = 0usize
            while s < job.samples {
                let jx = rand.pcg64_f64(r)
                let jy = rand.pcg64_f64(r)
                let ray = camera_ray(job.camera, (f64(x) + jx) / f64(job.width), (f64(y) + jy) / f64(job.height), aspect)
                sum = shade.rgb_add(sum, radiance(job, ray, r, mode))
                s += 1usize
            }
            out[y * job.width + x] = shade.rgb_scale(sum, inverse)
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

fn path_trace(job: *const Job, r: *rand.Pcg64, out: []shade.Rgb) -> err { ret render(job, r, out, .Naive) }
fn next_event_estimation(job: *const Job, r: *rand.Pcg64, out: []shade.Rgb) -> err { ret render(job, r, out, .Nee) }
fn multiple_importance(job: *const Job, r: *rand.Pcg64, out: []shade.Rgb) -> err { ret render(job, r, out, .Mis) }

// ---- constructive solid geometry ------------------------------------------

fn csg_sphere(center: shade.Vec3, radius: f64) -> CsgNode {
    ret CsgNode { kind: .Sphere, left: 0u32, right: 0u32, center: center, radius: radius, lo: zero, hi: zero }
}

fn csg_box(lo: shade.Vec3, hi: shade.Vec3) -> CsgNode {
    ret CsgNode { kind: .Box, left: 0u32, right: 0u32, center: zero, radius: 0.0f64, lo: lo, hi: hi }
}

fn csg_op(kind: CsgKind, left: u32, right: u32) -> CsgNode {
    ret CsgNode { kind: kind, left: left, right: right, center: zero, radius: 0.0f64, lo: zero, hi: zero }
}

fn axis_of(v: shade.Vec3, axis: usize) -> f64 {
    if axis == 0usize { ret v.x }
    if axis == 1usize { ret v.y }
    ret v.z
}

// The slab interval of a box, or nothing.
fn box_span(origin: shade.Vec3, direction: shade.Vec3, lo: shade.Vec3, hi: shade.Vec3) -> (bool, f64, f64) {
    var t_near = 0.0f64 - 1.0e300f64
    var t_far = 1.0e300f64
    var axis = 0usize
    while axis < 3usize {
        let o = axis_of(origin, axis)
        let d = axis_of(direction, axis)
        let l = axis_of(lo, axis)
        let h = axis_of(hi, axis)
        if d == 0.0f64 {
            if o < l || o > h { ret (false, 0.0f64, 0.0f64) }
        } else {
            var t1 = (l - o) / d
            var t2 = (h - o) / d
            if t1 > t2 {
                let swap = t1
                t1 = t2
                t2 = swap
            }
            if t1 > t_near { t_near = t1 }
            if t2 < t_far { t_far = t2 }
            if t_near > t_far { ret (false, 0.0f64, 0.0f64) }
        }
        axis += 1usize
    }
    ret (true, t_near, t_far)
}

fn inside_list(list: []const Interval, t: f64) -> bool {
    var i = 0usize
    while i < list.len {
        if t >= list[i].enter && t <= list[i].exit { ret true }
        i += 1usize
    }
    ret false
}

fn admits(kind: CsgKind, in_left: bool, in_right: bool) -> bool {
    if kind == .Union { ret in_left || in_right }
    if kind == .Intersection { ret in_left && in_right }
    ret in_left && !in_right
}

// Combines `out[base..base + nl]` and `out[base + nl..base + nl + nr]` in place
// under `kind`, sweeping their end points through `scratch`.
fn combine(kind: CsgKind, out: []Interval, base: usize, nl: usize, nr: usize, scratch: []f64) -> (usize, err) {
    let points = 2usize * (nl + nr)
    if scratch.len < points { ret (0usize, TooSmall) }
    var i = 0usize
    while i < nl + nr {
        scratch[2usize * i] = out[base + i].enter
        scratch[2usize * i + 1usize] = out[base + i].exit
        i += 1usize
    }
    i = 1usize
    while i < points {
        let v = scratch[i]
        var j = i
        while j > 0usize && scratch[j - 1usize] > v {
            scratch[j] = scratch[j - 1usize]
            j -= 1usize
        }
        scratch[j] = v
        i += 1usize
    }
    // Classify each elementary segment by its midpoint against the operands,
    // building past them in `out` (the result has at most `nl + nr` intervals),
    // then move the result down over the operands.
    var count = 0usize
    let left = out[base..base + nl]
    let right = out[base + nl..base + nl + nr]
    let build = base + nl + nr
    i = 0usize
    while i + 1usize < points {
        let p0 = scratch[i]
        let p1 = scratch[i + 1usize]
        if p1 > p0 {
            let mid = 0.5f64 * (p0 + p1)
            if admits(kind, inside_list(left, mid), inside_list(right, mid)) {
                if count > 0usize && out[build + count - 1usize].exit == p0 {
                    out[build + count - 1usize].exit = p1
                } else {
                    if build + count >= out.len { ret (0usize, TooSmall) }
                    out[build + count] = Interval { enter: p0, exit: p1 }
                    count += 1usize
                }
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < count {
        out[base + i] = out[build + i]
        i += 1usize
    }
    ret (count, ok)
}

fn evaluate(nodes: []const CsgNode, index: u32, origin: shade.Vec3, direction: shade.Vec3, out: []Interval, base: usize, scratch: []f64) -> (usize, err) {
    if usize(index) >= nodes.len { ret (0usize, Invalid) }
    let node = nodes[usize(index)]
    if node.kind == .Sphere || node.kind == .Box {
        var hit = false
        var enter = 0.0f64
        var exit = 0.0f64
        if node.kind == .Sphere {
            let (h, a, b) = sphere_span(origin, direction, node.center, node.radius)
            hit = h
            enter = a
            exit = b
        } else {
            let (h, a, b) = box_span(origin, direction, node.lo, node.hi)
            hit = h
            enter = a
            exit = b
        }
        if !hit || exit <= enter { ret (0usize, ok) }
        if base >= out.len { ret (0usize, TooSmall) }
        out[base] = Interval { enter: enter, exit: exit }
        ret (1usize, ok)
    }
    let (nl, left_error) = evaluate(nodes, node.left, origin, direction, out, base, scratch)
    if left_error != ok { ret (0usize, left_error) }
    let (nr, right_error) = evaluate(nodes, node.right, origin, direction, out, base + nl, scratch)
    if right_error != ok { ret (0usize, right_error) }
    let (count, combine_error) = combine(node.kind, out, base, nl, nr, scratch)
    ret (count, combine_error)
}

// The intervals along the line `origin + t * direction` inside the tree at `root`,
// sorted and disjoint; `out` needs room for twice the leaves met, `scratch` for
// four times.
fn csg(nodes: []const CsgNode, root: u32, origin: shade.Vec3, direction: shade.Vec3, out: []Interval, scratch: []f64) -> (usize, err) {
    let (count, evaluate_error) = evaluate(nodes, root, origin, direction, out, 0usize, scratch)
    ret (count, evaluate_error)
}

// The first positive boundary along the ray: an entry, or the exit of an interval the origin is in.
fn csg_hit(nodes: []const CsgNode, root: u32, origin: shade.Vec3, direction: shade.Vec3, out: []Interval, scratch: []f64) -> (bool, f64, err) {
    let (count, csg_error) = csg(nodes, root, origin, direction, out, scratch)
    if csg_error != ok { ret (false, 0.0f64, csg_error) }
    var i = 0usize
    while i < count {
        if out[i].enter > 0.0f64 { ret (true, out[i].enter, ok) }
        if out[i].exit > 0.0f64 { ret (true, out[i].exit, ok) }
        i += 1usize
    }
    ret (false, 0.0f64, ok)
}
