// `e.game.physics`: a PBD chain settles onto its rest lengths, an XPBD spring
// and a projected Gauss-Seidel stack match a replica, conservative advancement
// finds the analytic time of impact, sweep-and-prune agrees with brute force
// on 100 boxes, and the SPH and MAC-grid steps match their replicas bit for
// bit. Every expected value comes from scratchpad/physics_ref.py; each check
// exits with its own code.

use e.game.physics as physics
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> f64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64(*state >> 33u32) / 2147483648.0f64
}

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tolerance
}

fn link(a: u32, b: u32, compliance: f64) -> physics.Constraint {
    ret physics.Constraint { a: a, b: b, rest: 1.0f64, stiffness: 1.0f64, compliance: compliance }
}

fn contact(a: u32, b: u32, bias: f64) -> physics.Contact {
    ret physics.Contact { a: a, b: b, nx: 0.0f64, ny: 1.0f64, bias: bias, friction: 0.5f64 }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: a chain of five hanging from a pinned root reaches its rest lengths.
    var pos: [10]f64 = zero
    var vel: [10]f64 = zero
    var prev: [10]f64 = zero
    var inv_mass: [5]f64 = zero
    var chain: [4]physics.Constraint = zero
    var i = 0usize
    while i < 5usize {
        pos[2usize * i + 1usize] = 0.0f64 - f64(i)
        if i > 0usize { inv_mass[i] = 1.0f64 }
        if i < 4usize { chain[i] = link(u32(i), u32(i + 1usize), 0.0f64) }
        i += 1usize
    }
    var step = 0usize
    while step < 200usize {
        if physics.pbd_step(pos[..], vel[..], inv_mass[..], prev[..], chain[..], 0.0f64 - 9.8f64, 0.01f64, 60usize) != ok { os.exit(1i32) }
        step += 1usize
    }
    i = 0usize
    while i < 4usize {
        let dy = pos[2usize * i + 3usize] - pos[2usize * i + 1usize]
        if !near(dy * dy, 1.0f64, 0.000002f64) { os.exit(1i32) }
        i += 1usize
    }
    if !near(pos[9usize], 0.0f64 - 4.000000075522516f64, 0.000000001f64) { os.exit(1i32) }
    // A constraint naming a particle outside the set is refused.
    var bad: [1]physics.Constraint = zero
    bad[0usize] = link(0u32, 9u32, 0.0f64)
    if physics.pbd_step(pos[..], vel[..], inv_mass[..], prev[..], bad[..], 0.0f64, 0.01f64, 1usize) != physics.Invalid { os.exit(1i32) }

    // 2: XPBD with compliance matches the replica, multiplier included.
    var spring_pos: [4]f64 = zero
    spring_pos[2usize] = 1.0f64
    var spring_vel: [4]f64 = zero
    var spring_prev: [4]f64 = zero
    var spring_mass: [2]f64 = zero
    spring_mass[1usize] = 1.0f64
    var lambda: [1]f64 = zero
    var spring: [1]physics.Constraint = zero
    spring[0usize] = link(0u32, 1u32, 0.01f64)
    step = 0usize
    while step < 50usize {
        if physics.xpbd_step(spring_pos[..], spring_vel[..], spring_mass[..], spring_prev[..], lambda[..], spring[..], 0.0f64 - 9.8f64, 0.01f64, 4usize) != ok { os.exit(2i32) }
        step += 1usize
    }
    if !near(spring_pos[2usize], 0.6641402247515301f64, 0.000000001f64) { os.exit(2i32) }
    if !near(spring_pos[3usize], 0.0f64 - 1.0410277988616965f64, 0.000000001f64) { os.exit(2i32) }
    if !near(lambda[0usize], 0.0f64 - 0.00234836473439233f64, 0.000000001f64) { os.exit(2i32) }

    // 3: projected Gauss-Seidel on a three-contact stack over a fixed ground.
    var stack_vel: [8]f64 = zero
    stack_vel[2usize] = 0.5f64
    stack_vel[3usize] = 0.0f64 - 1.0f64
    stack_vel[4usize] = 0.2f64
    stack_vel[5usize] = 0.0f64 - 2.0f64
    stack_vel[6usize] = 0.0f64 - 0.3f64
    stack_vel[7usize] = 0.0f64 - 3.0f64
    var stack_mass: [4]f64 = zero
    stack_mass[1usize] = 1.0f64
    stack_mass[2usize] = 0.5f64
    stack_mass[3usize] = 2.0f64
    var contacts: [3]physics.Contact = zero
    contacts[0usize] = contact(0u32, 1u32, 0.0f64)
    contacts[1usize] = contact(1u32, 2u32, 0.0f64)
    contacts[2usize] = contact(2u32, 3u32, 0.1f64)
    var normal: [3]f64 = zero
    var tangent: [3]f64 = zero
    if physics.solve_gauss_seidel(contacts[..], stack_vel[..], stack_mass[..], normal[..], tangent[..], 10usize) != ok { os.exit(3i32) }
    if !near(normal[0usize], 6.1973201238477875f64, 0.000000001f64) || !near(normal[1usize], 5.291368090821711f64, 0.000000001f64) || !near(normal[2usize], 1.4982736181643421f64, 0.000000001f64) { os.exit(3i32) }
    if !near(tangent[0usize], 0.7402420587625871f64, 0.000000001f64) || !near(tangent[1usize], 0.2428441764258972f64, 0.000000001f64) || !near(tangent[2usize], 0.0f64 - 0.15143116471482057f64, 0.000000001f64) { os.exit(3i32) }
    if !near(stack_vel[3usize], 0.0f64 - 0.09404796697392381f64, 0.000000001f64) || stack_vel[1usize] != 0.0f64 { os.exit(3i32) }

    // 4: conservative advancement meets the analytic time of impact; a pass-by misses.
    let mover = physics.Circle { x: 0.0f64, y: 0.0f64, radius: 1.0f64, vx: 2.0f64, vy: 0.5f64 }
    let other = physics.Circle { x: 5.0f64, y: 1.0f64, radius: 1.0f64, vx: 0.0f64 - 2.0f64, vy: 0.0f64 }
    let (toi, hit) = physics.ccd_conservative(mover, other, 0.000000001f64)
    if !hit || !near(toi, 0.7740621686844659f64, 0.000001f64) || !near(toi, 0.7740621686759731f64, 0.000000001f64) { os.exit(4i32) }
    let passing = physics.Circle { x: 5.0f64, y: 4.0f64, radius: 1.0f64, vx: 0.0f64 - 1.0f64, vy: 0.0f64 }
    let (miss_time, missed) = physics.ccd_conservative(mover, passing, 0.000000001f64)
    if missed || miss_time != 1.0f64 { os.exit(4i32) }

    // 5: sweep and prune over 100 LCG boxes: the brute-force pair set, in sweep order.
    var boxes: [100]physics.Aabb = zero
    var state = 12345u64
    i = 0usize
    while i < 100usize {
        let x = draw(&state) * 100.0f64
        let y = draw(&state) * 100.0f64
        let w = 1.0f64 + draw(&state) * 8.0f64
        let h = 1.0f64 + draw(&state) * 8.0f64
        boxes[i] = physics.Aabb { min_x: x, min_y: y, max_x: x + w, max_y: y + h }
        i += 1usize
    }
    var order: [100]u32 = zero
    var pairs: [128]physics.Pair = zero
    let (count, sap_error) = physics.sweep_and_prune(boxes[..], order[..], pairs[..])
    if sap_error != ok || count != 61usize { os.exit(5i32) }
    var check = 0u32
    i = 0usize
    while i < count {
        check = check *% 31u32 +% pairs[i].a *% 256u32 +% pairs[i].b
        i += 1usize
    }
    if check != 2337266368u32 { os.exit(5i32) }
    var few: [10]physics.Pair = zero
    let (_, full) = physics.sweep_and_prune(boxes[..], order[..], few[..])
    if full != physics.TooSmall { os.exit(5i32) }

    // 6: ten SPH steps over a 4 x 4 lattice match the replica bit for bit.
    var fluid_pos: [32]f64 = zero
    var fluid_vel: [32]f64 = zero
    var density: [16]f64 = zero
    var pressure: [16]f64 = zero
    var fx: [16]f64 = zero
    var fy: [16]f64 = zero
    i = 0usize
    while i < 16usize {
        fluid_pos[2usize * i] = f64(i % 4usize) * 0.5f64
        fluid_pos[2usize * i + 1usize] = f64(i / 4usize) * 0.5f64
        i += 1usize
    }
    let params = physics.SphParams { h: 1.0f64, mass: 1.0f64, rest_density: 2.0f64, stiffness: 10.0f64, viscosity: 0.1f64, gravity: 0.0f64 - 1.0f64 }
    step = 0usize
    while step < 10usize {
        if physics.sph(fluid_pos[..], fluid_vel[..], density[..], pressure[..], fx[..], fy[..], params, 0.001f64) != ok { os.exit(6i32) }
        step += 1usize
    }
    if !near(density[5usize], 4.058961631489945f64, 0.000000001f64) { os.exit(6i32) }
    if !near(fluid_pos[10usize], 0.4999996976245302f64, 0.000000001f64) || !near(fluid_pos[11usize], 0.4999446976245302f64, 0.000000001f64) { os.exit(6i32) }
    var total = 0.0f64
    i = 0usize
    while i < 32usize {
        total += fluid_pos[i]
        i += 1usize
    }
    if !near(total, 23.99912f64, 0.000000001f64) { os.exit(6i32) }

    // 7: three MAC-grid steps leave the field divergence-free and match the replica.
    var grid: physics.MacGrid = zero
    var u: [15]f64 = zero
    var v: [16]f64 = zero
    var p: [12]f64 = zero
    var div: [12]f64 = zero
    var u_next: [15]f64 = zero
    var v_next: [16]f64 = zero
    if physics.mac_init(&grid, 4usize, 3usize, u[..], v[..], p[..], div[..], u_next[..], v_next[..]) != ok { os.exit(7i32) }
    state = 777u64
    i = 0usize
    while i < 15usize {
        u[i] = draw(&state) - 0.5f64
        i += 1usize
    }
    i = 0usize
    while i < 16usize {
        v[i] = draw(&state) - 0.5f64
        i += 1usize
    }
    step = 0usize
    while step < 3usize {
        if physics.fluid_mac(&grid, 0.0f64 - 1.0f64, 0.1f64, 300usize) != ok { os.exit(7i32) }
        step += 1usize
    }
    if physics.mac_divergence(&grid) >= 0.000001f64 { os.exit(7i32) }
    if !near(u[7usize], 0.07533135646275498f64, 0.000000001f64) || !near(v[6usize], 0.17593402974971856f64, 0.000000001f64) || !near(u[12usize], 0.0f64 - 0.07436358137751316f64, 0.000000001f64) { os.exit(7i32) }
    if u[0usize] != 0.0f64 || v[0usize] != 0.0f64 || v[15usize] != 0.0f64 { os.exit(7i32) }
    if physics.mac_init(&grid, 4usize, 3usize, u[..], v[..], p[..], div[..], p[..], v_next[..]) != physics.TooSmall { os.exit(7i32) }

    try io.print("game physics ok\n")
    ret ok
}
