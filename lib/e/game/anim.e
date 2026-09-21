// Skeletal animation over caller `[]f64` storage: quaternions and dual
// quaternions, FABRIK and cyclic-coordinate-descent inverse kinematics on a
// chain of joints, and skinning by linear blend or dual quaternion blend.
//
// Points are packed triples (`xs[3 * i]`, `xs[3 * i + 1]`, `xs[3 * i + 2]`).
// A chain is its joints in order, joint 0 the fixed root; the segment lengths
// are the distances between neighbours when the solve starts. Skinning takes
// four bone indices and four weights per vertex; a weight of zero is skipped,
// so a vertex bound to fewer bones pads with zeros.

use e.math

type Vec3 = struct { x: f64, y: f64, z: f64 }
type Quat = struct { x: f64, y: f64, z: f64, w: f64 }
type DualQuat = struct { real: Quat, dual: Quat }
error TooSmall
error Invalid

fn vec3(x: f64, y: f64, z: f64) -> Vec3 { ret Vec3 { x: x, y: y, z: z } }
fn add(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z } }
fn sub(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z } }
fn scale(a: Vec3, s: f64) -> Vec3 { ret Vec3 { x: a.x * s, y: a.y * s, z: a.z * s } }
fn dot(a: Vec3, b: Vec3) -> f64 { ret a.x * b.x + a.y * b.y + a.z * b.z }
fn cross(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x } }
fn length(a: Vec3) -> f64 { ret math.sqrt[f64](dot(a, a)) }
fn get(xs: []const f64, i: usize) -> Vec3 { ret Vec3 { x: xs[3usize * i], y: xs[3usize * i + 1usize], z: xs[3usize * i + 2usize] } }

fn put(xs: []f64, i: usize, v: Vec3) {
    xs[3usize * i] = v.x
    xs[3usize * i + 1usize] = v.y
    xs[3usize * i + 2usize] = v.z
}

fn quat(x: f64, y: f64, z: f64, w: f64) -> Quat { ret Quat { x: x, y: y, z: z, w: w } }
fn quat_identity() -> Quat { ret Quat { x: 0.0f64, y: 0.0f64, z: 0.0f64, w: 1.0f64 } }
fn quat_conjugate(q: Quat) -> Quat { ret Quat { x: 0.0f64 - q.x, y: 0.0f64 - q.y, z: 0.0f64 - q.z, w: q.w } }
fn quat_dot(a: Quat, b: Quat) -> f64 { ret a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w }
fn quat_add(a: Quat, b: Quat) -> Quat { ret Quat { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, w: a.w + b.w } }
fn quat_scale(q: Quat, s: f64) -> Quat { ret Quat { x: q.x * s, y: q.y * s, z: q.z * s, w: q.w * s } }

// Hamilton product: `quat_mul(a, b)` rotates by `b` first, then `a`.
fn quat_mul(a: Quat, b: Quat) -> Quat {
    ret Quat {
        x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    }
}

fn quat_normalize(q: Quat) -> Quat {
    let n = math.sqrt[f64](quat_dot(q, q))
    if n == 0.0f64 { ret quat_identity() }
    ret quat_scale(q, 1.0f64 / n)
}

fn quat_from_axis_angle(axis: Vec3, angle: f64) -> Quat {
    let n = length(axis)
    if n == 0.0f64 { ret quat_identity() }
    let s = math.sin[f64](angle * 0.5f64) / n
    ret Quat { x: axis.x * s, y: axis.y * s, z: axis.z * s, w: math.cos[f64](angle * 0.5f64) }
}

// The shortest rotation taking direction `from` onto direction `to`, without trig:
// the quaternion (from x to, 1 + from . to) normalised is the half-angle rotation.
// Opposite directions turn about any axis perpendicular to `from`.
fn quat_between(from: Vec3, to: Vec3) -> Quat {
    let a = length(from)
    let b = length(to)
    if a == 0.0f64 || b == 0.0f64 { ret quat_identity() }
    let c = cross(from, to)
    let w = a * b + dot(from, to)
    if w <= 0.000000000001f64 * a * b {
        var axis = cross(from, vec3(1.0f64, 0.0f64, 0.0f64))
        if length(axis) == 0.0f64 { axis = cross(from, vec3(0.0f64, 1.0f64, 0.0f64)) }
        ret quat_normalize(quat(axis.x, axis.y, axis.z, 0.0f64))
    }
    ret quat_normalize(quat(c.x, c.y, c.z, w))
}

// v' = v + 2 w (q x v) + 2 q x (q x v), for a unit `q`.
fn quat_rotate(q: Quat, v: Vec3) -> Vec3 {
    let u = vec3(q.x, q.y, q.z)
    let t = scale(cross(u, v), 2.0f64)
    ret add(add(v, scale(t, q.w)), cross(u, t))
}

fn dq_from(rotation: Quat, translation: Vec3) -> DualQuat {
    let r = quat_normalize(rotation)
    let t = quat(translation.x, translation.y, translation.z, 0.0f64)
    ret DualQuat { real: r, dual: quat_scale(quat_mul(t, r), 0.5f64) }
}

fn dq_identity() -> DualQuat { ret DualQuat { real: quat_identity(), dual: quat(0.0f64, 0.0f64, 0.0f64, 0.0f64) } }
fn dq_add(a: DualQuat, b: DualQuat) -> DualQuat { ret DualQuat { real: quat_add(a.real, b.real), dual: quat_add(a.dual, b.dual) } }
fn dq_scale(d: DualQuat, s: f64) -> DualQuat { ret DualQuat { real: quat_scale(d.real, s), dual: quat_scale(d.dual, s) } }
fn dq_mul(a: DualQuat, b: DualQuat) -> DualQuat { ret DualQuat { real: quat_mul(a.real, b.real), dual: quat_add(quat_mul(a.real, b.dual), quat_mul(a.dual, b.real)) } }

// Divide both parts by the real norm; a zero real part answers the identity.
fn dq_normalize(d: DualQuat) -> DualQuat {
    let n = math.sqrt[f64](quat_dot(d.real, d.real))
    if n == 0.0f64 { ret dq_identity() }
    ret dq_scale(d, 1.0f64 / n)
}

fn dq_translation(d: DualQuat) -> Vec3 {
    let t = quat_scale(quat_mul(d.dual, quat_conjugate(d.real)), 2.0f64)
    ret vec3(t.x, t.y, t.z)
}

fn dq_transform(d: DualQuat, v: Vec3) -> Vec3 { ret add(quat_rotate(d.real, v), dq_translation(d)) }

// Weighted sum of the bones a vertex names, each flipped onto the hemisphere of the
// first so antipodal quaternions do not cancel, then normalised. Zero weights skip.
fn dq_blend(bones: []const DualQuat, indices: []const u32, weights: []const f64) -> (DualQuat, err) {
    var sum = DualQuat { real: quat(0.0f64, 0.0f64, 0.0f64, 0.0f64), dual: quat(0.0f64, 0.0f64, 0.0f64, 0.0f64) }
    var pivot = quat_identity()
    var first = true
    var k = 0usize
    while k < indices.len && k < weights.len {
        if weights[k] != 0.0f64 {
            if usize(indices[k]) >= bones.len { ret (dq_identity(), Invalid) }
            var bone = bones[usize(indices[k])]
            if first {
                pivot = bone.real
                first = false
            } else if quat_dot(pivot, bone.real) < 0.0f64 {
                bone = dq_scale(bone, 0.0f64 - 1.0f64)
            }
            sum = dq_add(sum, dq_scale(bone, weights[k]))
        }
        k += 1usize
    }
    if first { ret (dq_identity(), Invalid) }
    ret (dq_normalize(sum), ok)
}

// Dual quaternion skinning: four `indices`/`weights` per vertex, positions in and out
// as triples. Rigid blending -- no candy-wrapper collapse, a slight bulge on twists.
fn skin_dual_quaternion(bones: []const DualQuat, positions: []const f64, indices: []const u32, weights: []const f64, out: []f64) -> err {
    let n = positions.len / 3usize
    if out.len < 3usize * n || indices.len < 4usize * n || weights.len < 4usize * n { ret TooSmall }
    var i = 0usize
    while i < n {
        let (blend, blend_error) = dq_blend(bones, indices[4usize * i..4usize * i + 4usize], weights[4usize * i..4usize * i + 4usize])
        if blend_error != ok { ret blend_error }
        put(out, i, dq_transform(blend, get(positions, i)))
        i += 1usize
    }
    ret ok
}

fn transform_affine(m: []const f64, v: Vec3) -> Vec3 {
    ret Vec3 {
        x: m[0usize] * v.x + m[1usize] * v.y + m[2usize] * v.z + m[3usize],
        y: m[4usize] * v.x + m[5usize] * v.y + m[6usize] * v.z + m[7usize],
        z: m[8usize] * v.x + m[9usize] * v.y + m[10usize] * v.z + m[11usize],
    }
}

// Linear blend skinning with row-major 3 x 4 bone matrices (twelve values per bone,
// the last column the translation): the weighted sum of each bone's image of the
// vertex. A 4 x 4 matrix with an affine last row is the same twelve values first.
fn skin_linear_blend(bones: []const f64, positions: []const f64, indices: []const u32, weights: []const f64, out: []f64) -> err {
    let n = positions.len / 3usize
    let bone_count = bones.len / 12usize
    if out.len < 3usize * n || indices.len < 4usize * n || weights.len < 4usize * n { ret TooSmall }
    var i = 0usize
    while i < n {
        let v = get(positions, i)
        var acc = vec3(0.0f64, 0.0f64, 0.0f64)
        var k = 0usize
        while k < 4usize {
            let w = weights[4usize * i + k]
            if w != 0.0f64 {
                let bone = usize(indices[4usize * i + k])
                if bone >= bone_count { ret Invalid }
                acc = add(acc, scale(transform_affine(bones[12usize * bone..12usize * bone + 12usize], v), w))
            }
            k += 1usize
        }
        put(out, i, acc)
        i += 1usize
    }
    ret ok
}

fn measure(joints: []const f64, lengths: []f64) -> (usize, f64, err) {
    let n = joints.len / 3usize
    if n < 2usize { ret (0usize, 0.0f64, Invalid) }
    if lengths.len < n - 1usize { ret (0usize, 0.0f64, TooSmall) }
    var total = 0.0f64
    var i = 0usize
    while i + 1usize < n {
        lengths[i] = length(sub(get(joints, i + 1usize), get(joints, i)))
        total += lengths[i]
        i += 1usize
    }
    ret (n, total, ok)
}

// Straighten the chain from the root toward `goal`; what both solvers do when the
// goal is beyond reach.
fn straighten(joints: []f64, lengths: []const f64, n: usize, goal: Vec3) {
    let root = get(joints, 0usize)
    let dir = sub(goal, root)
    let d = length(dir)
    var i = 0usize
    var reach = 0.0f64
    while i + 1usize < n {
        reach += lengths[i]
        if d == 0.0f64 { put(joints, i + 1usize, root) } else { put(joints, i + 1usize, add(root, scale(dir, reach / d))) }
        i += 1usize
    }
}

// FABRIK: pull the chain tip-first onto the goal, then root-first back onto the
// root, until the tip is within `tolerance` or `iterations` are spent. `lengths` is
// scratch of one less than the joint count. Answers the final tip distance.
fn ik_fabrik(joints: []f64, lengths: []f64, goal: Vec3, iterations: usize, tolerance: f64) -> (f64, err) {
    let (n, total, measured) = measure(joints, lengths)
    if measured != ok { ret (0.0f64, measured) }
    let root = get(joints, 0usize)
    if length(sub(goal, root)) >= total {
        straighten(joints, lengths, n, goal)
        ret (length(sub(get(joints, n - 1usize), goal)), ok)
    }
    var it = 0usize
    var gap = length(sub(get(joints, n - 1usize), goal))
    while it < iterations && gap > tolerance {
        // Backward: the tip goes to the goal and each joint follows at its length.
        put(joints, n - 1usize, goal)
        var i = n - 1usize
        while i > 0usize {
            let toward = sub(get(joints, i - 1usize), get(joints, i))
            let d = length(toward)
            if d > 0.0f64 { put(joints, i - 1usize, add(get(joints, i), scale(toward, lengths[i - 1usize] / d))) }
            i -= 1usize
        }
        // Forward: the root goes home and each joint follows at its length.
        put(joints, 0usize, root)
        i = 0usize
        while i + 1usize < n {
            let toward = sub(get(joints, i + 1usize), get(joints, i))
            let d = length(toward)
            if d > 0.0f64 { put(joints, i + 1usize, add(get(joints, i), scale(toward, lengths[i] / d))) }
            i += 1usize
        }
        gap = length(sub(get(joints, n - 1usize), goal))
        it += 1usize
    }
    ret (gap, ok)
}

// Cyclic coordinate descent: from the joint before the tip back to the root, rotate
// the joints beyond each about it so the tip swings toward the goal, until within
// `tolerance` or `iterations` are spent. `lengths` is scratch as for `ik_fabrik`;
// an unreachable goal straightens the chain toward it. Answers the tip distance.
fn ik_ccd(joints: []f64, lengths: []f64, goal: Vec3, iterations: usize, tolerance: f64) -> (f64, err) {
    let (n, total, measured) = measure(joints, lengths)
    if measured != ok { ret (0.0f64, measured) }
    let root = get(joints, 0usize)
    if length(sub(goal, root)) >= total {
        straighten(joints, lengths, n, goal)
        ret (length(sub(get(joints, n - 1usize), goal)), ok)
    }
    var it = 0usize
    var gap = length(sub(get(joints, n - 1usize), goal))
    while it < iterations && gap > tolerance {
        var i = n - 1usize
        while i > 0usize {
            let pivot = get(joints, i - 1usize)
            let q = quat_between(sub(get(joints, n - 1usize), pivot), sub(goal, pivot))
            var k = i
            while k < n {
                put(joints, k, add(pivot, quat_rotate(q, sub(get(joints, k), pivot))))
                k += 1usize
            }
            i -= 1usize
        }
        gap = length(sub(get(joints, n - 1usize), goal))
        it += 1usize
    }
    ret (gap, ok)
}
