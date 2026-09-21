// `e.game.anim`: quaternion helpers agree with scipy, FABRIK and CCD reach a
// target and answer the replica's joints, an unreachable target straightens
// the chain, and linear-blend and dual-quaternion skinning match numpy (and
// each other on a single bone). Every expected value comes from
// scratchpad/anim_ref.py; each check exits with its own code.

use e.game.anim as anim
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tolerance
}

fn near3(v: anim.Vec3, x: f64, y: f64, z: f64, tolerance: f64) -> bool {
    ret near(v.x, x, tolerance) && near(v.y, y, tolerance) && near(v.z, z, tolerance)
}

fn straight_chain(joints: []f64) {
    var i = 0usize
    while i < 12usize {
        joints[i] = 0.0f64
        i += 1usize
    }
    joints[3usize] = 1.0f64
    joints[6usize] = 2.0f64
    joints[9usize] = 3.0f64
}

fn lengths_kept(joints: []const f64) -> bool {
    var i = 0usize
    while i < 3usize {
        let d = anim.length(anim.sub(anim.get(joints, i + 1usize), anim.get(joints, i)))
        if !near(d, 1.0f64, 0.000000000001f64) { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: quaternions against scipy.spatial.transform.Rotation.
    let q0 = anim.quat_from_axis_angle(anim.vec3(0.0f64, 0.0f64, 1.0f64), 0.5235987755982988f64)
    let q1 = anim.quat_from_axis_angle(anim.vec3(0.0f64, 1.0f64, 0.0f64), 0.7853981633974483f64)
    if !near(q0.z, 0.25881904510252074f64, 0.000000000001f64) || !near(q0.w, 0.9659258262890683f64, 0.000000000001f64) || q0.x != 0.0f64 { os.exit(1i32) }
    if !near(q1.y, 0.3826834323650898f64, 0.000000000001f64) || !near(q1.w, 0.9238795325112867f64, 0.000000000001f64) { os.exit(1i32) }
    let turned = anim.quat_rotate(q0, anim.vec3(0.3f64, 0.0f64 - 0.7f64, 1.1f64))
    if !near3(turned, 0.6098076211353315f64, 0.0f64 - 0.456217782649107f64, 1.1f64, 0.000000000001f64) { os.exit(1i32) }
    let product = anim.quat_mul(q0, q1)
    if !near(product.x, 0.0f64 - 0.09904576054128762f64, 0.000000000001f64) || !near(product.y, 0.3696438106143861f64, 0.000000000001f64) { os.exit(1i32) }
    if !near(product.z, 0.23911761839433449f64, 0.000000000001f64) || !near(product.w, 0.8923991008325228f64, 0.000000000001f64) { os.exit(1i32) }
    let quarter = anim.quat_between(anim.vec3(1.0f64, 0.0f64, 0.0f64), anim.vec3(0.0f64, 1.0f64, 0.0f64))
    if !near(quarter.z, 0.7071067811865475f64, 0.000000000001f64) || !near(quarter.w, 0.7071067811865475f64, 0.000000000001f64) { os.exit(1i32) }
    if !near3(anim.quat_rotate(quarter, anim.vec3(1.0f64, 0.0f64, 0.0f64)), 0.0f64, 1.0f64, 0.0f64, 0.000000000001f64) { os.exit(1i32) }
    let flipped = anim.quat_between(anim.vec3(0.0f64, 0.0f64, 1.0f64), anim.vec3(0.0f64, 0.0f64, 0.0f64 - 1.0f64))
    if !near3(anim.quat_rotate(flipped, anim.vec3(0.0f64, 0.0f64, 1.0f64)), 0.0f64, 0.0f64, 0.0f64 - 1.0f64, 0.000000000001f64) { os.exit(1i32) }
    if !near(anim.quat_dot(anim.quat_normalize(anim.quat(3.0f64, 0.0f64, 4.0f64, 0.0f64)), anim.quat(0.6f64, 0.0f64, 0.8f64, 0.0f64)), 1.0f64, 0.000000000001f64) { os.exit(1i32) }

    // 2: FABRIK reaches a target within reach and answers the replica's joints.
    var joints: [12]f64 = zero
    var lengths: [3]f64 = zero
    let goal = anim.vec3(1.5f64, 1.5f64, 0.5f64)
    straight_chain(joints[..])
    let (fabrik_gap, fabrik_error) = anim.ik_fabrik(joints[..], lengths[..], goal, 20usize, 0.000001f64)
    if fabrik_error != ok || fabrik_gap >= 0.000001f64 || !lengths_kept(joints[..]) { os.exit(2i32) }
    if !near3(anim.get(joints[..], 3usize), 1.500000048418166f64, 1.4999998486959243f64, 0.49999994956530813f64, 0.000000001f64) { os.exit(2i32) }
    if !near3(anim.get(joints[..], 1usize), 0.999929416961239f64, 0.011271423423912132f64, 0.0037571411413040256f64, 0.000000001f64) { os.exit(2i32) }
    if lengths[0usize] != 1.0f64 || lengths[2usize] != 1.0f64 { os.exit(2i32) }

    // 3: CCD on the same chain.
    straight_chain(joints[..])
    let (ccd_gap, ccd_error) = anim.ik_ccd(joints[..], lengths[..], goal, 30usize, 0.000001f64)
    if ccd_error != ok || ccd_gap >= 0.000001f64 || !lengths_kept(joints[..]) { os.exit(3i32) }
    if !near3(anim.get(joints[..], 3usize), 1.4999996962693718f64, 1.4999996962693716f64, 0.4999998987564571f64, 0.000000001f64) { os.exit(3i32) }
    if !near3(anim.get(joints[..], 1usize), 0.9902082543942957f64, 0.1324343295239633f64, 0.04414477650798774f64, 0.000000001f64) { os.exit(3i32) }

    // 4: an unreachable target straightens the chain toward it, in both solvers.
    let far = anim.vec3(5.0f64, 4.0f64, 0.0f64)
    straight_chain(joints[..])
    let (far_gap, far_error) = anim.ik_fabrik(joints[..], lengths[..], far, 20usize, 0.000001f64)
    if far_error != ok || !near(far_gap, 3.403124237432849f64, 0.000000000001f64) { os.exit(4i32) }
    if !near3(anim.get(joints[..], 3usize), 2.342606428329091f64, 1.8740851426632728f64, 0.0f64, 0.000000000001f64) { os.exit(4i32) }
    straight_chain(joints[..])
    let (far_ccd, far_ccd_error) = anim.ik_ccd(joints[..], lengths[..], far, 20usize, 0.000001f64)
    if far_ccd_error != ok || far_ccd != far_gap || !near3(anim.get(joints[..], 3usize), 2.342606428329091f64, 1.8740851426632728f64, 0.0f64, 0.000000000001f64) { os.exit(4i32) }
    var short: [1]f64 = zero
    let (_, short_error) = anim.ik_fabrik(joints[..], short[..], far, 1usize, 0.000001f64)
    if short_error != anim.TooSmall { os.exit(4i32) }
    let (_, lone_error) = anim.ik_ccd(joints[..3usize], lengths[..], far, 1usize, 0.000001f64)
    if lone_error != anim.Invalid { os.exit(4i32) }

    // 5: linear blend skinning over two 3 x 4 bones matches numpy.
    var matrices: [24]f64 = zero
    matrices[0usize] = 0.8660254037844387f64
    matrices[1usize] = 0.0f64 - 0.49999999999999994f64
    matrices[3usize] = 1.0f64
    matrices[4usize] = 0.49999999999999994f64
    matrices[5usize] = 0.8660254037844387f64
    matrices[10usize] = 1.0f64
    matrices[12usize] = 0.7071067811865475f64
    matrices[14usize] = 0.7071067811865476f64
    matrices[17usize] = 1.0f64
    matrices[19usize] = 2.0f64
    matrices[20usize] = 0.0f64 - 0.7071067811865476f64
    matrices[22usize] = 0.7071067811865475f64
    var verts: [9]f64 = zero
    verts[0usize] = 0.5f64
    verts[1usize] = 0.2f64
    verts[2usize] = 0.0f64 - 0.3f64
    verts[3usize] = 1.0f64
    verts[4usize] = 1.0f64
    verts[5usize] = 1.0f64
    verts[6usize] = 0.0f64 - 0.4f64
    verts[7usize] = 0.8f64
    verts[8usize] = 0.6f64
    var indices: [12]u32 = zero
    var weights: [12]f64 = zero
    indices[1usize] = 1u32
    indices[5usize] = 1u32
    indices[9usize] = 1u32
    weights[0usize] = 1.0f64
    weights[4usize] = 0.5f64
    weights[5usize] = 0.5f64
    weights[8usize] = 0.25f64
    weights[9usize] = 0.75f64
    var lbs: [9]f64 = zero
    if anim.skin_linear_blend(matrices[..], verts[..], indices[..], weights[..], lbs[..]) != ok { os.exit(5i32) }
    if !near3(anim.get(lbs[..], 0usize), 1.3330127018922193f64, 0.42320508075688773f64, 0.0f64 - 0.3f64, 0.000000001f64) { os.exit(5i32) }
    if !near3(anim.get(lbs[..], 1usize), 1.3901194830787669f64, 2.183012701892219f64, 0.49999999999999994f64, 0.000000001f64) { os.exit(5i32) }
    if !near3(anim.get(lbs[..], 2usize), 0.16946347679953827f64, 2.2232050807568875f64, 0.6803300858899106f64, 0.000000001f64) { os.exit(5i32) }
    indices[9usize] = 7u32
    if anim.skin_linear_blend(matrices[..], verts[..], indices[..], weights[..], lbs[..]) != anim.Invalid { os.exit(5i32) }
    indices[9usize] = 1u32
    if anim.skin_linear_blend(matrices[..], verts[..], indices[..], weights[..], lbs[..6usize]) != anim.TooSmall { os.exit(5i32) }

    // 6: dual quaternion skinning matches the numpy replica and equals LBS on one bone.
    var bones: [2]anim.DualQuat = zero
    bones[0usize] = anim.dq_from(q0, anim.vec3(1.0f64, 0.0f64, 0.0f64))
    bones[1usize] = anim.dq_from(q1, anim.vec3(0.0f64, 2.0f64, 0.0f64))
    if !near3(anim.dq_translation(bones[1usize]), 0.0f64, 2.0f64, 0.0f64, 0.000000000001f64) { os.exit(6i32) }
    var dqs: [9]f64 = zero
    if anim.skin_dual_quaternion(bones[..], verts[..], indices[..], weights[..], dqs[..]) != ok { os.exit(6i32) }
    if !near3(anim.get(dqs[..], 0usize), lbs[0usize], lbs[1usize], lbs[2usize], 0.000000000001f64) { os.exit(6i32) }
    if !near3(anim.get(dqs[..], 1usize), 1.3845529238523715f64, 2.2122265178914904f64, 0.5474663909625305f64, 0.000000001f64) { os.exit(6i32) }
    if !near3(anim.get(dqs[..], 2usize), 0.052758116846297956f64, 2.240144342743946f64, 0.7180032821070497f64, 0.000000001f64) { os.exit(6i32) }
    // A blend of the two bones in the antipodal sign is the same rigid motion.
    bones[1usize] = anim.dq_scale(bones[1usize], 0.0f64 - 1.0f64)
    if anim.skin_dual_quaternion(bones[..], verts[..], indices[..], weights[..], dqs[..]) != ok { os.exit(6i32) }
    if !near3(anim.get(dqs[..], 2usize), 0.052758116846297956f64, 2.240144342743946f64, 0.7180032821070497f64, 0.000000001f64) { os.exit(6i32) }
    indices[9usize] = 7u32
    if anim.skin_dual_quaternion(bones[..], verts[..], indices[..], weights[..], dqs[..]) != anim.Invalid { os.exit(6i32) }
    weights[8usize] = 0.0f64
    weights[9usize] = 0.0f64
    if anim.skin_dual_quaternion(bones[..], verts[..], indices[..], weights[..], dqs[..]) != anim.Invalid { os.exit(6i32) }

    try io.print("game anim ok\n")
    ret ok
}
