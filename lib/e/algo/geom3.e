// Solid geometry over `f64` vectors and caller storage: ray casts against
// boxes, triangles, spheres, planes and disks; the separating axis test with
// the fifteen box axes or the face and edge axes of two triangulated
// polytopes; GJK distance and intersection with EPA penetration depth over a
// caller face pool; a Barnes-Hut octree of point masses; Kabsch alignment by
// Horn's quaternion; and a 3-d quickhull answering outward face triangles.
//
// Faces are index triples counter-clockwise seen from outside; `hull`,
// `polytope_axes`, `hull_volume` and `hull_area` share that layout.

use e.math

type Vec3 = struct { x: f64, y: f64, z: f64 }
type BarnesHut = struct { xs: []const f64, ys: []const f64, zs: []const f64, masses: []const f64, x0: f64, y0: f64, z0: f64, size: f64, child: []u32, body: []u32, mass: []f64, cx: []f64, cy: []f64, cz: []f64, used: usize }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32

fn vec3(x: f64, y: f64, z: f64) -> Vec3 { ret Vec3 { x: x, y: y, z: z } }
fn add(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z } }
fn sub(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z } }
fn scale(a: Vec3, s: f64) -> Vec3 { ret Vec3 { x: a.x * s, y: a.y * s, z: a.z * s } }
fn dot(a: Vec3, b: Vec3) -> f64 { ret a.x * b.x + a.y * b.y + a.z * b.z }
fn cross(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x } }
fn length(a: Vec3) -> f64 { ret math.sqrt[f64](dot(a, a)) }

fn normalize(a: Vec3) -> Vec3 {
    let n = length(a)
    if n == 0.0f64 { ret a }
    ret scale(a, 1.0f64 / n)
}

fn component(v: Vec3, axis: usize) -> f64 {
    if axis == 0usize { ret v.x }
    if axis == 1usize { ret v.y }
    ret v.z
}

fn same(a: Vec3, b: Vec3) -> bool { ret a.x == b.x && a.y == b.y && a.z == b.z }

// ---- rays ----------------------------------------------------------------

// The slab test: whether the ray meets the box and the entry parameter, which
// is negative when the origin is inside.
fn ray_box(origin: Vec3, direction: Vec3, box_min: Vec3, box_max: Vec3) -> (bool, f64) {
    var t_near = 0.0f64 - 1.0e300f64
    var t_far = 1.0e300f64
    var axis = 0usize
    while axis < 3usize {
        let o = component(origin, axis)
        let d = component(direction, axis)
        let lo = component(box_min, axis)
        let hi = component(box_max, axis)
        if d == 0.0f64 {
            if o < lo || o > hi { ret (false, 0.0f64) }
        } else {
            var t1 = (lo - o) / d
            var t2 = (hi - o) / d
            if t1 > t2 {
                let swap = t1
                t1 = t2
                t2 = swap
            }
            if t1 > t_near { t_near = t1 }
            if t2 < t_far { t_far = t2 }
            if t_near > t_far || t_far < 0.0f64 { ret (false, 0.0f64) }
        }
        axis += 1usize
    }
    ret (true, t_near)
}

// Möller-Trumbore, both faces: whether the ray meets triangle `a b c`, the
// parameter `t >= 0` and the barycentric `u`, `v` of `b` and `c`.
fn ray_triangle(origin: Vec3, direction: Vec3, a: Vec3, b: Vec3, c: Vec3) -> (bool, f64, f64, f64) {
    let e1 = sub(b, a)
    let e2 = sub(c, a)
    let p = cross(direction, e2)
    let det = dot(e1, p)
    if math.abs[f64](det) < 1.0e-12f64 { ret (false, 0.0f64, 0.0f64, 0.0f64) }
    let inv = 1.0f64 / det
    let s = sub(origin, a)
    let u = dot(s, p) * inv
    if u < 0.0f64 || u > 1.0f64 { ret (false, 0.0f64, 0.0f64, 0.0f64) }
    let q = cross(s, e1)
    let v = dot(direction, q) * inv
    if v < 0.0f64 || u + v > 1.0f64 { ret (false, 0.0f64, 0.0f64, 0.0f64) }
    let t = dot(e2, q) * inv
    if t < 0.0f64 { ret (false, 0.0f64, 0.0f64, 0.0f64) }
    ret (true, t, u, v)
}

// The nearest `t >= 0` where the ray meets the sphere (the exit when the origin is inside).
fn ray_sphere(origin: Vec3, direction: Vec3, center: Vec3, radius: f64) -> (bool, f64) {
    let m = sub(origin, center)
    let a = dot(direction, direction)
    let b = dot(m, direction)
    let c = dot(m, m) - radius * radius
    let discriminant = b * b - a * c
    if a == 0.0f64 || discriminant < 0.0f64 { ret (false, 0.0f64) }
    let root = math.sqrt[f64](discriminant)
    var t = (0.0f64 - b - root) / a
    if t < 0.0f64 { t = (0.0f64 - b + root) / a }
    if t < 0.0f64 { ret (false, 0.0f64) }
    ret (true, t)
}

// Whether the ray meets the plane through `point` with `normal`, and where.
fn ray_plane(origin: Vec3, direction: Vec3, point: Vec3, normal: Vec3) -> (bool, f64) {
    let denominator = dot(normal, direction)
    if math.abs[f64](denominator) < 1.0e-12f64 { ret (false, 0.0f64) }
    let t = dot(normal, sub(point, origin)) / denominator
    if t < 0.0f64 { ret (false, 0.0f64) }
    ret (true, t)
}

// Whether the ray meets the disk of `radius` about `center` in the plane of `normal`.
fn ray_disk(origin: Vec3, direction: Vec3, center: Vec3, normal: Vec3, radius: f64) -> (bool, f64) {
    let (hit, t) = ray_plane(origin, direction, center, normal)
    if !hit { ret (false, 0.0f64) }
    let offset = sub(add(origin, scale(direction, t)), center)
    if dot(offset, offset) > radius * radius { ret (false, 0.0f64) }
    ret (true, t)
}

// ---- separating axis -----------------------------------------------------

fn project(points: []const Vec3, axis: Vec3) -> (f64, f64) {
    var lo = 1.0e300f64
    var hi = 0.0f64 - 1.0e300f64
    var i = 0usize
    while i < points.len {
        let d = dot(points[i], axis)
        if d < lo { lo = d }
        if d > hi { hi = d }
        i += 1usize
    }
    ret (lo, hi)
}

// Whether the projections of the two point sets overlap on every candidate
// axis (zero axes skipped); false as soon as one axis separates them.
fn separating_axis(a: []const Vec3, b: []const Vec3, axes: []const Vec3) -> bool {
    if a.len == 0usize || b.len == 0usize { ret false }
    var i = 0usize
    while i < axes.len {
        let axis = axes[i]
        if dot(axis, axis) > 1.0e-18f64 {
            let (a_lo, a_hi) = project(a, axis)
            let (b_lo, b_hi) = project(b, axis)
            if a_hi < b_lo || b_hi < a_lo { ret false }
        }
        i += 1usize
    }
    ret true
}

// The fifteen axes of two oriented boxes given their three edge directions each.
fn obb_axes(a: []const Vec3, b: []const Vec3, out: []Vec3) -> (usize, err) {
    if a.len < 3usize || b.len < 3usize { ret (0usize, Invalid) }
    if out.len < 15usize { ret (0usize, TooSmall) }
    var i = 0usize
    while i < 3usize {
        out[i] = a[i]
        out[3usize + i] = b[i]
        var j = 0usize
        while j < 3usize {
            out[6usize + i * 3usize + j] = cross(a[i], b[j])
            j += 1usize
        }
        i += 1usize
    }
    ret (15usize, ok)
}

fn push_axis(out: []Vec3, n: *usize, v: Vec3) -> err {
    if *n >= out.len { ret TooSmall }
    out[*n] = v
    *n += 1usize
    ret ok
}

// The face normals of both polytopes and the cross products of their edges
// (each undirected edge once); `faces` are index triples as `hull` answers.
fn polytope_axes(a: []const Vec3, a_faces: []const u32, b: []const Vec3, b_faces: []const u32, out: []Vec3) -> (usize, err) {
    var n = 0usize
    var which = 0usize
    while which < 2usize {
        var points = a
        var faces = a_faces
        if which == 1usize {
            points = b
            faces = b_faces
        }
        var f = 0usize
        while f + 3usize <= faces.len {
            let p0 = points[usize(faces[f])]
            let normal = cross(sub(points[usize(faces[f + 1usize])], p0), sub(points[usize(faces[f + 2usize])], p0))
            let e = push_axis(out, &n, normal)
            if e != ok { ret (n, e) }
            f += 3usize
        }
        which += 1usize
    }
    var fa = 0usize
    while fa < a_faces.len {
        let ua = a_faces[fa]
        let va = a_faces[fa - fa % 3usize + (fa + 1usize) % 3usize]
        if ua < va {
            let edge_a = sub(a[usize(va)], a[usize(ua)])
            var fb = 0usize
            while fb < b_faces.len {
                let ub = b_faces[fb]
                let vb = b_faces[fb - fb % 3usize + (fb + 1usize) % 3usize]
                if ub < vb {
                    let e = push_axis(out, &n, cross(edge_a, sub(b[usize(vb)], b[usize(ub)])))
                    if e != ok { ret (n, e) }
                }
                fb += 1usize
            }
        }
        fa += 1usize
    }
    ret (n, ok)
}

// ---- GJK and EPA ---------------------------------------------------------

fn support(points: []const Vec3, d: Vec3) -> Vec3 {
    var best = points[0usize]
    var best_dot = dot(best, d)
    var i = 1usize
    while i < points.len {
        let here = dot(points[i], d)
        if here > best_dot {
            best_dot = here
            best = points[i]
        }
        i += 1usize
    }
    ret best
}

fn minkowski_support(a: []const Vec3, b: []const Vec3, d: Vec3) -> Vec3 {
    ret sub(support(a, d), support(b, scale(d, 0.0f64 - 1.0f64)))
}

// Ericson's closest point to the origin on triangle `a b c`; answers the point
// and which vertices carry it as bits (1 = a, 2 = b, 4 = c).
fn closest_on_triangle(a: Vec3, b: Vec3, c: Vec3) -> (Vec3, u32) {
    let ab = sub(b, a)
    let ac = sub(c, a)
    let d1 = 0.0f64 - dot(ab, a)
    let d2 = 0.0f64 - dot(ac, a)
    if d1 <= 0.0f64 && d2 <= 0.0f64 { ret (a, 1u32) }
    let d3 = 0.0f64 - dot(ab, b)
    let d4 = 0.0f64 - dot(ac, b)
    if d3 >= 0.0f64 && d4 <= d3 { ret (b, 2u32) }
    let vc = d1 * d4 - d3 * d2
    if vc <= 0.0f64 && d1 >= 0.0f64 && d3 <= 0.0f64 { ret (add(a, scale(ab, d1 / (d1 - d3))), 3u32) }
    let d5 = 0.0f64 - dot(ab, c)
    let d6 = 0.0f64 - dot(ac, c)
    if d6 >= 0.0f64 && d5 <= d6 { ret (c, 4u32) }
    let vb = d5 * d2 - d1 * d6
    if vb <= 0.0f64 && d2 >= 0.0f64 && d6 <= 0.0f64 { ret (add(a, scale(ac, d2 / (d2 - d6))), 5u32) }
    let va = d3 * d6 - d5 * d4
    if va <= 0.0f64 && d4 - d3 >= 0.0f64 && d5 - d6 >= 0.0f64 {
        let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        ret (add(b, scale(sub(c, b), w)), 6u32)
    }
    let denominator = 1.0f64 / (va + vb + vc)
    ret (add(add(a, scale(ab, vb * denominator)), scale(ac, vc * denominator)), 7u32)
}

// Keeps the vertices of `s[base..base+3]` named by `bits` at the front of `s`; answers how many.
fn keep_triangle(s: []Vec3, base: usize, bits: u32) -> usize {
    var kept: [3]Vec3 = zero
    var n = 0usize
    var k = 0usize
    while k < 3usize {
        if ((bits >> u32(k)) & 1u32) == 1u32 {
            kept[n] = s[base + k]
            n += 1usize
        }
        k += 1usize
    }
    k = 0usize
    while k < n {
        s[k] = kept[k]
        k += 1usize
    }
    ret n
}

// The closest point to the origin on the simplex `s[..n]` (1 to 4 points),
// the simplex reduced in place to the vertices that carry it. A tetrahedron
// enclosing the origin answers the origin and keeps all four.
fn closest_on_simplex(s: []Vec3, n: usize) -> (Vec3, usize) {
    if n == 1usize { ret (s[0usize], 1usize) }
    if n == 2usize {
        let ab = sub(s[1usize], s[0usize])
        let ab2 = dot(ab, ab)
        if ab2 == 0.0f64 { ret (s[0usize], 1usize) }
        let t = 0.0f64 - dot(s[0usize], ab) / ab2
        if t <= 0.0f64 { ret (s[0usize], 1usize) }
        if t >= 1.0f64 {
            s[0usize] = s[1usize]
            ret (s[0usize], 1usize)
        }
        ret (add(s[0usize], scale(ab, t)), 2usize)
    }
    if n == 3usize {
        let (p, bits) = closest_on_triangle(s[0usize], s[1usize], s[2usize])
        let m = keep_triangle(s, 0usize, bits)
        ret (p, m)
    }
    let a = s[0usize]
    let b = s[1usize]
    let c = s[2usize]
    let d = s[3usize]
    let n_abc = cross(sub(b, a), sub(c, a))
    let volume = dot(sub(d, a), n_abc)
    let extent = length(sub(b, a)) * length(sub(c, a)) * length(sub(d, a))
    if math.abs[f64](volume) <= 1.0e-12f64 * extent {
        // Flat: drop the oldest vertex and answer for the triangle.
        s[0usize] = b
        s[1usize] = c
        s[2usize] = d
        let (p, bits) = closest_on_triangle(b, c, d)
        let m = keep_triangle(s, 0usize, bits)
        ret (p, m)
    }
    var faces: [12]Vec3 = zero
    faces[0usize] = a
    faces[1usize] = b
    faces[2usize] = c
    faces[3usize] = a
    faces[4usize] = c
    faces[5usize] = d
    faces[6usize] = a
    faces[7usize] = d
    faces[8usize] = b
    faces[9usize] = b
    faces[10usize] = d
    faces[11usize] = c
    var best = 1.0e300f64
    var best_point = vec3(0.0f64, 0.0f64, 0.0f64)
    var best_face = 4usize
    var best_bits = 0u32
    var f = 0usize
    while f < 4usize {
        let fa = faces[f * 3usize]
        let fb = faces[f * 3usize + 1usize]
        let fc = faces[f * 3usize + 2usize]
        var opposite = d
        if f == 1usize { opposite = b }
        if f == 2usize { opposite = c }
        if f == 3usize { opposite = a }
        let normal = cross(sub(fb, fa), sub(fc, fa))
        let sign_origin = 0.0f64 - dot(fa, normal)
        let sign_opposite = dot(sub(opposite, fa), normal)
        if sign_origin * sign_opposite < 0.0f64 {
            let (p, bits) = closest_on_triangle(fa, fb, fc)
            let here = dot(p, p)
            if here < best {
                best = here
                best_point = p
                best_face = f
                best_bits = bits
            }
        }
        f += 1usize
    }
    if best_face == 4usize { ret (vec3(0.0f64, 0.0f64, 0.0f64), 4usize) }
    s[0usize] = faces[best_face * 3usize]
    s[1usize] = faces[best_face * 3usize + 1usize]
    s[2usize] = faces[best_face * 3usize + 2usize]
    let m = keep_triangle(s, 0usize, best_bits)
    ret (best_point, m)
}

// GJK over two point clouds: whether their convex hulls meet and, when they do
// not, the distance between them. `simplex` (4 or more) receives the final
// simplex of the Minkowski difference and the third answer is its size; a
// hit leaves the tetrahedron `epa` expands.
fn gjk(a: []const Vec3, b: []const Vec3, simplex: []Vec3) -> (bool, f64, usize, err) {
    if a.len == 0usize || b.len == 0usize { ret (false, 0.0f64, 0usize, Invalid) }
    if simplex.len < 4usize { ret (false, 0.0f64, 0usize, TooSmall) }
    var n = 1usize
    simplex[0usize] = minkowski_support(a, b, sub(a[0usize], b[0usize]))
    var iteration = 0usize
    while iteration < 64usize {
        let (v, m) = closest_on_simplex(simplex, n)
        n = m
        let vv = dot(v, v)
        if vv < 1.0e-20f64 { ret (true, 0.0f64, n, ok) }
        let w = minkowski_support(a, b, scale(v, 0.0f64 - 1.0f64))
        if vv - dot(v, w) <= 1.0e-9f64 * vv { ret (false, math.sqrt[f64](vv), n, ok) }
        var k = 0usize
        while k < n {
            if same(simplex[k], w) { ret (false, math.sqrt[f64](vv), n, ok) }
            k += 1usize
        }
        simplex[n] = w
        n += 1usize
        iteration += 1usize
    }
    let (v_last, m_last) = closest_on_simplex(simplex, n)
    ret (false, length(v_last), m_last, ok)
}

fn face_normal(vertices: []const Vec3, faces: []const u32, f: usize) -> Vec3 {
    let p0 = vertices[usize(faces[f * 3usize])]
    ret cross(sub(vertices[usize(faces[f * 3usize + 1usize])], p0), sub(vertices[usize(faces[f * 3usize + 2usize])], p0))
}

// Whether the polytope face `f` faces point `p` (strictly beyond `tolerance`).
fn face_sees(vertices: []const Vec3, faces: []const u32, f: usize, p: Vec3, tolerance: f64) -> bool {
    let normal = face_normal(vertices, faces, f)
    let n = length(normal)
    if n == 0.0f64 { ret false }
    ret dot(sub(p, vertices[usize(faces[f * 3usize])]), normal) / n > tolerance
}

// Removes the faces seeing `p`, then closes the horizon with faces to `p`
// (already `vertices[p_index]`). `edges` scratch holds three pairs per removed face.
fn expand_polytope(vertices: []const Vec3, faces: []u32, count: usize, edges: []u32, p_index: usize, tolerance: f64) -> (usize, err) {
    let p = vertices[p_index]
    var edge_count = 0usize
    var f = 0usize
    while f < count {
        if face_sees(vertices, faces, f, p, tolerance) {
            if (edge_count + 3usize) * 2usize > edges.len { ret (count, TooSmall) }
            var k = 0usize
            while k < 3usize {
                edges[edge_count * 2usize] = faces[f * 3usize + k]
                edges[edge_count * 2usize + 1usize] = faces[f * 3usize + (k + 1usize) % 3usize]
                edge_count += 1usize
                k += 1usize
            }
        }
        f += 1usize
    }
    var kept = 0usize
    f = 0usize
    while f < count {
        if !face_sees(vertices, faces, f, p, tolerance) {
            faces[kept * 3usize] = faces[f * 3usize]
            faces[kept * 3usize + 1usize] = faces[f * 3usize + 1usize]
            faces[kept * 3usize + 2usize] = faces[f * 3usize + 2usize]
            kept += 1usize
        }
        f += 1usize
    }
    var e = 0usize
    while e < edge_count {
        let u = edges[e * 2usize]
        let v = edges[e * 2usize + 1usize]
        var horizon = true
        var other = 0usize
        while other < edge_count {
            if edges[other * 2usize] == v && edges[other * 2usize + 1usize] == u { horizon = false }
            other += 1usize
        }
        if horizon {
            if (kept + 1usize) * 3usize > faces.len { ret (kept, TooSmall) }
            faces[kept * 3usize] = u
            faces[kept * 3usize + 1usize] = v
            faces[kept * 3usize + 2usize] = u32(p_index)
            kept += 1usize
        }
        e += 1usize
    }
    ret (kept, ok)
}

// Grows a GJK hit simplex of `count` points to a tetrahedron in `vertices`.
fn complete_tetrahedron(a: []const Vec3, b: []const Vec3, vertices: []Vec3, count: usize) -> (usize, err) {
    var n = count
    if n == 0usize || n > 4usize { ret (n, Invalid) }
    if n == 1usize {
        var axis = 0usize
        while axis < 3usize && n == 1usize {
            var dir = vec3(1.0f64, 0.0f64, 0.0f64)
            if axis == 1usize { dir = vec3(0.0f64, 1.0f64, 0.0f64) }
            if axis == 2usize { dir = vec3(0.0f64, 0.0f64, 1.0f64) }
            let w = minkowski_support(a, b, dir)
            if !same(w, vertices[0usize]) {
                vertices[1usize] = w
                n = 2usize
            }
            axis += 1usize
        }
        if n == 1usize { ret (n, Invalid) }
    }
    if n == 2usize {
        let ab = sub(vertices[1usize], vertices[0usize])
        var least = vec3(1.0f64, 0.0f64, 0.0f64)
        if math.abs[f64](ab.y) < math.abs[f64](ab.x) { least = vec3(0.0f64, 1.0f64, 0.0f64) }
        if math.abs[f64](ab.z) < math.abs[f64](ab.x) && math.abs[f64](ab.z) < math.abs[f64](ab.y) { least = vec3(0.0f64, 0.0f64, 1.0f64) }
        var d = cross(ab, least)
        var w = minkowski_support(a, b, d)
        if math.abs[f64](dot(sub(w, vertices[0usize]), d)) <= 1.0e-12f64 * dot(d, d) {
            d = scale(d, 0.0f64 - 1.0f64)
            w = minkowski_support(a, b, d)
            if math.abs[f64](dot(sub(w, vertices[0usize]), d)) <= 1.0e-12f64 * dot(d, d) { ret (n, Invalid) }
        }
        vertices[2usize] = w
        n = 3usize
    }
    if n == 3usize {
        var normal = cross(sub(vertices[1usize], vertices[0usize]), sub(vertices[2usize], vertices[0usize]))
        let n2 = dot(normal, normal)
        if n2 == 0.0f64 { ret (n, Invalid) }
        var w = minkowski_support(a, b, normal)
        if dot(sub(w, vertices[0usize]), normal) <= 1.0e-12f64 * n2 {
            normal = scale(normal, 0.0f64 - 1.0f64)
            w = minkowski_support(a, b, normal)
            if dot(sub(w, vertices[0usize]), normal) <= 1.0e-12f64 * n2 { ret (n, Invalid) }
        }
        vertices[3usize] = w
        n = 4usize
    }
    ret (n, ok)
}

// The expanding polytope: from a GJK hit simplex (`count` points), the unit
// direction and depth of least penetration, so that moving `a` by
// `-depth * normal` separates the hulls. `vertices` holds the polytope's
// points, `faces` its index triples and `edges` scratch (three pairs per face
// removed in one step); the loop stops when a step grows the polytope by less
// than `tolerance` or after `max_iterations`.
fn epa(a: []const Vec3, b: []const Vec3, simplex: []const Vec3, count: usize, vertices: []Vec3, faces: []u32, edges: []u32, tolerance: f64, max_iterations: usize) -> (Vec3, f64, err) {
    if a.len == 0usize || b.len == 0usize || count == 0usize || count > simplex.len { ret (zero, 0.0f64, Invalid) }
    if vertices.len < 5usize || faces.len < 12usize { ret (zero, 0.0f64, TooSmall) }
    var k = 0usize
    while k < count {
        vertices[k] = simplex[k]
        k += 1usize
    }
    let (n, complete_error) = complete_tetrahedron(a, b, vertices, count)
    if complete_error != ok { ret (zero, 0.0f64, complete_error) }
    var vertex_count = n
    let centroid = scale(add(add(vertices[0usize], vertices[1usize]), add(vertices[2usize], vertices[3usize])), 0.25f64)
    var f = 0usize
    while f < 4usize {
        var i0 = 0u32
        var i1 = 1u32
        var i2 = 2u32
        if f == 1usize {
            i1 = 2u32
            i2 = 3u32
        }
        if f == 2usize {
            i1 = 3u32
            i2 = 1u32
        }
        if f == 3usize {
            i0 = 1u32
            i1 = 3u32
            i2 = 2u32
        }
        faces[f * 3usize] = i0
        faces[f * 3usize + 1usize] = i1
        faces[f * 3usize + 2usize] = i2
        let normal = face_normal(vertices, faces, f)
        if dot(sub(centroid, vertices[usize(i0)]), normal) > 0.0f64 {
            faces[f * 3usize + 1usize] = i2
            faces[f * 3usize + 2usize] = i1
        }
        f += 1usize
    }
    var face_count = 4usize
    var iteration = 0usize
    while true {
        var best = 1.0e300f64
        var best_normal = vec3(0.0f64, 0.0f64, 0.0f64)
        f = 0usize
        while f < face_count {
            let normal = normalize(face_normal(vertices, faces, f))
            let distance = dot(normal, vertices[usize(faces[f * 3usize])])
            if dot(normal, normal) > 0.0f64 && distance < best {
                best = distance
                best_normal = normal
            }
            f += 1usize
        }
        if best == 1.0e300f64 { ret (zero, 0.0f64, Invalid) }
        let w = minkowski_support(a, b, best_normal)
        if dot(w, best_normal) - best < tolerance || iteration >= max_iterations { ret (best_normal, best, ok) }
        if vertex_count >= vertices.len { ret (best_normal, best, TooSmall) }
        vertices[vertex_count] = w
        let (grown, grow_error) = expand_polytope(vertices, faces, face_count, edges, vertex_count, 0.0f64)
        if grow_error != ok { ret (best_normal, best, grow_error) }
        face_count = grown
        vertex_count += 1usize
        iteration += 1usize
    }
    ret (zero, 0.0f64, Invalid)
}

// ---- Barnes-Hut ----------------------------------------------------------

fn octant(x: f64, y: f64, z: f64, cx: f64, cy: f64, cz: f64) -> usize {
    var q = 0usize
    if x >= cx { q += 1usize }
    if y >= cy { q += 2usize }
    if z >= cz { q += 4usize }
    ret q
}

fn clear_node(t: *BarnesHut, node: usize) {
    var k = 0usize
    while k < 8usize {
        t.child[node * 8usize + k] = NONE
        k += 1usize
    }
    t.body[node] = NONE
    t.mass[node] = 0.0f64
    t.cx[node] = 0.0f64
    t.cy[node] = 0.0f64
    t.cz[node] = 0.0f64
}

fn insert_body(t: *BarnesHut, b: usize) -> err {
    let x = t.xs[b]
    let y = t.ys[b]
    let z = t.zs[b]
    let m = t.masses[b]
    var node = 0usize
    var nx = t.x0
    var ny = t.y0
    var nz = t.z0
    var size = t.size
    var depth = 0usize
    while true {
        t.mass[node] += m
        t.cx[node] += m * x
        t.cy[node] += m * y
        t.cz[node] += m * z
        let half = size / 2.0f64
        if t.child[node * 8usize] == NONE {
            if t.body[node] == NONE {
                t.body[node] = u32(b)
                ret ok
            }
            // ponytail: bodies that coincide below depth 40 share one leaf as their centre of mass.
            if depth >= 40usize { ret ok }
            if t.used + 8usize > t.body.len || t.used + 8usize > t.mass.len || t.used + 8usize > t.cx.len || t.used + 8usize > t.cy.len || t.used + 8usize > t.cz.len || (t.used + 8usize) * 8usize > t.child.len { ret TooSmall }
            var q = 0usize
            while q < 8usize {
                t.child[node * 8usize + q] = u32(t.used + q)
                clear_node(t, t.used + q)
                q += 1usize
            }
            t.used += 8usize
            let old = usize(t.body[node])
            t.body[node] = NONE
            let c = usize(t.child[node * 8usize + octant(t.xs[old], t.ys[old], t.zs[old], nx + half, ny + half, nz + half)])
            t.body[c] = u32(old)
            t.mass[c] = t.masses[old]
            t.cx[c] = t.masses[old] * t.xs[old]
            t.cy[c] = t.masses[old] * t.ys[old]
            t.cz[c] = t.masses[old] * t.zs[old]
        }
        let q2 = octant(x, y, z, nx + half, ny + half, nz + half)
        node = usize(t.child[node * 8usize + q2])
        if q2 % 2usize == 1usize { nx += half }
        if (q2 / 2usize) % 2usize == 1usize { ny += half }
        if q2 >= 4usize { nz += half }
        size = half
        depth += 1usize
    }
    ret ok
}

// An octree of the point masses over caller node pools (`child` eight per
// node, the rest one per node); each node keeps its mass and centre of mass.
fn barnes_hut_build(xs: []const f64, ys: []const f64, zs: []const f64, masses: []const f64, child: []u32, body: []u32, mass: []f64, cx: []f64, cy: []f64, cz: []f64) -> (BarnesHut, err) {
    let n = xs.len
    if n == 0usize || ys.len != n || zs.len != n || masses.len != n { ret (zero, Invalid) }
    if body.len < 1usize || mass.len < 1usize || cx.len < 1usize || cy.len < 1usize || cz.len < 1usize || child.len < 8usize { ret (zero, TooSmall) }
    var lo = vec3(xs[0usize], ys[0usize], zs[0usize])
    var hi = lo
    var i = 1usize
    while i < n {
        if xs[i] < lo.x { lo.x = xs[i] }
        if ys[i] < lo.y { lo.y = ys[i] }
        if zs[i] < lo.z { lo.z = zs[i] }
        if xs[i] > hi.x { hi.x = xs[i] }
        if ys[i] > hi.y { hi.y = ys[i] }
        if zs[i] > hi.z { hi.z = zs[i] }
        i += 1usize
    }
    var size = hi.x - lo.x
    if hi.y - lo.y > size { size = hi.y - lo.y }
    if hi.z - lo.z > size { size = hi.z - lo.z }
    if size <= 0.0f64 { ret (zero, Invalid) }
    var t = BarnesHut { xs: xs, ys: ys, zs: zs, masses: masses, x0: lo.x, y0: lo.y, z0: lo.z, size: size, child: child, body: body, mass: mass, cx: cx, cy: cy, cz: cz, used: 1usize }
    clear_node(&t, 0usize)
    i = 0usize
    while i < n {
        let e = insert_body(&t, i)
        if e != ok { ret (t, e) }
        i += 1usize
    }
    i = 0usize
    while i < t.used {
        if t.mass[i] > 0.0f64 {
            t.cx[i] = t.cx[i] / t.mass[i]
            t.cy[i] = t.cy[i] / t.mass[i]
            t.cz[i] = t.cz[i] / t.mass[i]
        }
        i += 1usize
    }
    ret (t, ok)
}

fn force_node(t: *const BarnesHut, node: usize, size: f64, i: usize, theta: f64, acc: *Vec3) {
    if t.mass[node] == 0.0f64 { ret }
    let leaf = t.child[node * 8usize] == NONE
    if leaf && t.body[node] == u32(i) { ret }
    let d = sub(vec3(t.cx[node], t.cy[node], t.cz[node]), vec3(t.xs[i], t.ys[i], t.zs[i]))
    let r2 = dot(d, d)
    if leaf || size * size < theta * theta * r2 {
        if r2 == 0.0f64 { ret }
        *acc = add(*acc, scale(d, t.mass[node] / (r2 * math.sqrt[f64](r2))))
        ret
    }
    var q = 0usize
    while q < 8usize {
        force_node(t, usize(t.child[node * 8usize + q]), size / 2.0f64, i, theta, acc)
        q += 1usize
    }
}

// The gravitational force on body `i` with `G = 1`: a cell of side `s` at
// distance `d` from the body stands in for its bodies when `s / d < theta`,
// so `theta = 0` is the exact pairwise sum.
fn barnes_hut_force(t: *const BarnesHut, i: usize, theta: f64) -> Vec3 {
    var acc = vec3(0.0f64, 0.0f64, 0.0f64)
    if i >= t.xs.len { ret acc }
    force_node(t, 0usize, t.size, i, theta, &acc)
    ret scale(acc, t.masses[i])
}

// ---- Kabsch --------------------------------------------------------------

// Applies a row-major 3x3 `rotation` to `v`.
fn rotate(rotation: []const f64, v: Vec3) -> Vec3 {
    ret vec3(rotation[0usize] * v.x + rotation[1usize] * v.y + rotation[2usize] * v.z, rotation[3usize] * v.x + rotation[4usize] * v.y + rotation[5usize] * v.z, rotation[6usize] * v.x + rotation[7usize] * v.y + rotation[8usize] * v.z)
}

fn mean_point(points: []const Vec3) -> Vec3 {
    var sum = vec3(0.0f64, 0.0f64, 0.0f64)
    var i = 0usize
    while i < points.len {
        sum = add(sum, points[i])
        i += 1usize
    }
    ret scale(sum, 1.0f64 / f64(points.len))
}

// The rigid motion `q ~ rotation * p + translation` of least squared error by
// Horn's quaternion: the largest eigenvector of the 4x4 profile matrix by
// shifted power iteration. `rotation` receives nine row-major entries.
fn kabsch(p: []const Vec3, q: []const Vec3, rotation: []f64) -> (Vec3, err) {
    let n = p.len
    if n == 0usize || q.len != n { ret (zero, Invalid) }
    if rotation.len < 9usize { ret (zero, TooSmall) }
    let pc = mean_point(p)
    let qc = mean_point(q)
    var s: [9]f64 = zero
    var i = 0usize
    while i < n {
        let u = sub(p[i], pc)
        let v = sub(q[i], qc)
        var r = 0usize
        while r < 3usize {
            var c = 0usize
            while c < 3usize {
                s[r * 3usize + c] += component(u, r) * component(v, c)
                c += 1usize
            }
            r += 1usize
        }
        i += 1usize
    }
    let sxx = s[0usize]
    let sxy = s[1usize]
    let sxz = s[2usize]
    let syx = s[3usize]
    let syy = s[4usize]
    let syz = s[5usize]
    let szx = s[6usize]
    let szy = s[7usize]
    let szz = s[8usize]
    var m: [16]f64 = zero
    m[0usize] = sxx + syy + szz
    m[1usize] = syz - szy
    m[2usize] = szx - sxz
    m[3usize] = sxy - syx
    m[4usize] = m[1usize]
    m[5usize] = sxx - syy - szz
    m[6usize] = sxy + syx
    m[7usize] = szx + sxz
    m[8usize] = m[2usize]
    m[9usize] = m[6usize]
    m[10usize] = 0.0f64 - sxx + syy - szz
    m[11usize] = syz + szy
    m[12usize] = m[3usize]
    m[13usize] = m[7usize]
    m[14usize] = m[11usize]
    m[15usize] = 0.0f64 - sxx - syy + szz
    var frobenius = 0.0f64
    i = 0usize
    while i < 16usize {
        frobenius += m[i] * m[i]
        i += 1usize
    }
    let shift = math.sqrt[f64](frobenius)
    i = 0usize
    while i < 4usize {
        m[i * 5usize] += shift
        i += 1usize
    }
    var v: [4]f64 = zero
    v[0usize] = 0.5f64
    v[1usize] = 0.5f64
    v[2usize] = 0.5f64
    v[3usize] = 0.5f64
    var iteration = 0usize
    while iteration < 2000usize {
        var w: [4]f64 = zero
        var norm = 0.0f64
        var r = 0usize
        while r < 4usize {
            var c = 0usize
            while c < 4usize {
                w[r] += m[r * 4usize + c] * v[c]
                c += 1usize
            }
            norm += w[r] * w[r]
            r += 1usize
        }
        norm = math.sqrt[f64](norm)
        if norm == 0.0f64 { break }
        var change = 0.0f64
        r = 0usize
        while r < 4usize {
            w[r] = w[r] / norm
            change += math.abs[f64](w[r] - v[r])
            v[r] = w[r]
            r += 1usize
        }
        if change < 1.0e-15f64 { break }
        iteration += 1usize
    }
    let qw = v[0usize]
    let qx = v[1usize]
    let qy = v[2usize]
    let qz = v[3usize]
    rotation[0usize] = 1.0f64 - 2.0f64 * (qy * qy + qz * qz)
    rotation[1usize] = 2.0f64 * (qx * qy - qw * qz)
    rotation[2usize] = 2.0f64 * (qx * qz + qw * qy)
    rotation[3usize] = 2.0f64 * (qx * qy + qw * qz)
    rotation[4usize] = 1.0f64 - 2.0f64 * (qx * qx + qz * qz)
    rotation[5usize] = 2.0f64 * (qy * qz - qw * qx)
    rotation[6usize] = 2.0f64 * (qx * qz - qw * qy)
    rotation[7usize] = 2.0f64 * (qy * qz + qw * qx)
    rotation[8usize] = 1.0f64 - 2.0f64 * (qx * qx + qy * qy)
    ret (sub(qc, rotate(rotation, pc)), ok)
}

// The root mean square distance between `rotation * p + translation` and `q`.
fn kabsch_rmsd(p: []const Vec3, q: []const Vec3, rotation: []const f64, translation: Vec3) -> f64 {
    if p.len == 0usize || q.len != p.len { ret 0.0f64 }
    var sum = 0.0f64
    var i = 0usize
    while i < p.len {
        let d = sub(add(rotate(rotation, p[i]), translation), q[i])
        sum += dot(d, d)
        i += 1usize
    }
    ret math.sqrt[f64](sum / f64(p.len))
}

// ---- convex hull ---------------------------------------------------------

fn farthest_from_plane(points: []const Vec3, a: Vec3, normal: Vec3) -> (usize, f64) {
    var best = 0usize
    var best_distance = 0.0f64
    var i = 0usize
    while i < points.len {
        let d = math.abs[f64](dot(sub(points[i], a), normal))
        if d > best_distance {
            best_distance = d
            best = i
        }
        i += 1usize
    }
    ret (best, best_distance)
}

// Quickhull: the convex hull of `points` as outward index triples in `faces`
// (room for `6 * points.len` entries); `edges` is scratch of the same size.
// Points within `tolerance` of a face are not hull vertices; fewer than four
// points, or all within `tolerance` of one plane, answer `Invalid`. Answers
// the number of faces.
fn hull(points: []const Vec3, faces: []u32, edges: []u32, tolerance: f64) -> (usize, err) {
    let n = points.len
    if n < 4usize { ret (0usize, Invalid) }
    if faces.len < 12usize { ret (0usize, TooSmall) }
    var i0 = 0usize
    var i1 = 0usize
    var i = 1usize
    while i < n {
        if points[i].x < points[i0].x { i0 = i }
        if points[i].x > points[i1].x { i1 = i }
        i += 1usize
    }
    let p0 = points[i0]
    let line = sub(points[i1], p0)
    let line_length = length(line)
    if line_length <= tolerance { ret (0usize, Invalid) }
    var i2 = 0usize
    var best = 0.0f64
    i = 0usize
    while i < n {
        let d = length(cross(sub(points[i], p0), line)) / line_length
        if d > best {
            best = d
            i2 = i
        }
        i += 1usize
    }
    if best <= tolerance { ret (0usize, Invalid) }
    let normal = normalize(cross(line, sub(points[i2], p0)))
    let (i3, plane_distance) = farthest_from_plane(points, p0, normal)
    if plane_distance <= tolerance { ret (0usize, Invalid) }
    faces[0usize] = u32(i0)
    faces[1usize] = u32(i1)
    faces[2usize] = u32(i2)
    faces[3usize] = u32(i0)
    faces[4usize] = u32(i2)
    faces[5usize] = u32(i3)
    faces[6usize] = u32(i0)
    faces[7usize] = u32(i3)
    faces[8usize] = u32(i1)
    faces[9usize] = u32(i1)
    faces[10usize] = u32(i3)
    faces[11usize] = u32(i2)
    let inside = scale(add(add(p0, points[i1]), add(points[i2], points[i3])), 0.25f64)
    var f = 0usize
    while f < 4usize {
        if dot(sub(inside, points[usize(faces[f * 3usize])]), face_normal(points, faces, f)) > 0.0f64 {
            let swap = faces[f * 3usize + 1usize]
            faces[f * 3usize + 1usize] = faces[f * 3usize + 2usize]
            faces[f * 3usize + 2usize] = swap
        }
        f += 1usize
    }
    var count = 4usize
    var round = 0usize
    while round < n {
        var pick = n
        f = 0usize
        while f < count && pick == n {
            let unit = normalize(face_normal(points, faces, f))
            let fa = points[usize(faces[f * 3usize])]
            var farthest = tolerance
            i = 0usize
            while i < n {
                let d = dot(sub(points[i], fa), unit)
                if d > farthest {
                    farthest = d
                    pick = i
                }
                i += 1usize
            }
            f += 1usize
        }
        if pick == n { break }
        let (grown, e) = expand_polytope(points, faces, count, edges, pick, tolerance)
        if e != ok { ret (grown, e) }
        count = grown
        round += 1usize
    }
    ret (count, ok)
}

// The volume enclosed by outward faces (as `hull` answers them).
fn hull_volume(points: []const Vec3, faces: []const u32, count: usize) -> f64 {
    var sum = 0.0f64
    var f = 0usize
    while f < count {
        let a = points[usize(faces[f * 3usize])]
        sum += dot(a, cross(points[usize(faces[f * 3usize + 1usize])], points[usize(faces[f * 3usize + 2usize])]))
        f += 1usize
    }
    ret sum / 6.0f64
}

// The total area of the face triangles.
fn hull_area(points: []const Vec3, faces: []const u32, count: usize) -> f64 {
    var sum = 0.0f64
    var f = 0usize
    while f < count {
        sum += length(face_normal(points, faces, f)) / 2.0f64
        f += 1usize
    }
    ret sum
}

// The planned name: the acceleration of every body under `G = 1` with the
// opening angle `theta`, into `ax`, `ay`, `az` (each at least the body count).
fn barnes_hut(t: *const BarnesHut, theta: f64, ax: []f64, ay: []f64, az: []f64) -> err {
    let n = t.xs.len
    if ax.len < n || ay.len < n || az.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        var acc = vec3(0.0f64, 0.0f64, 0.0f64)
        force_node(t, 0usize, t.size, i, theta, &acc)
        ax[i] = acc.x
        ay[i] = acc.y
        az[i] = acc.z
        i += 1usize
    }
    ret ok
}
