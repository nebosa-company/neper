// `e.gfx.trace`: the furnace (a camera inside an emissive sphere) answers the
// emission exactly at albedo zero and the geometric series at albedo one half
// for all three renderers; CSG intervals over 20 LCG rays against a membership
// oracle (count, end-point sum, first-hit sum); and a 16x16 four-sample render
// of a four-sphere scene in each mode matches a Python replica walking the same
// PCG stream, as an FNV hash of the 8-bit image and the channel sum to 1e-9.
// Each check exits with its own code.

use e.algo.rand
use e.gfx.shade
use e.gfx.trace
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= tolerance
}

fn q8(v: f64) -> u64 {
    var c = v
    if c < 0.0f64 { c = 0.0f64 }
    if c > 1.0f64 { c = 1.0f64 }
    ret u64(c * 255.0f64 + 0.5f64)
}

fn image_hash(image: []const shade.Rgb) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < image.len {
        h = (h ^ q8(image[i].red)) *% 1099511628211u64
        h = (h ^ q8(image[i].green)) *% 1099511628211u64
        h = (h ^ q8(image[i].blue)) *% 1099511628211u64
        i += 1usize
    }
    ret h
}

fn image_sum(image: []const shade.Rgb) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < image.len {
        s += image[i].red + image[i].green + image[i].blue
        i += 1usize
    }
    ret s
}

fn furnace(job: *const trace.Job, out: []shade.Rgb, want: shade.Rgb, code: i32) {
    var mode = 0usize
    while mode < 3usize {
        var r = rand.pcg64(1u64, 2u64)
        var render_error = ok
        if mode == 0usize {
            render_error = trace.path_trace(job, &r, out)
        } else if mode == 1usize {
            render_error = trace.next_event_estimation(job, &r, out)
        } else {
            render_error = trace.multiple_importance(job, &r, out)
        }
        if render_error != ok { os.exit(code) }
        var i = 0usize
        while i < 4usize {
            if !near(out[i].red, want.red, 1.0e-9f64) || !near(out[i].green, want.green, 1.0e-9f64) || !near(out[i].blue, want.blue, 1.0e-9f64) { os.exit(code) }
            i += 1usize
        }
        mode += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let black = shade.rgb(0.0f64, 0.0f64, 0.0f64)
    let emission = shade.rgb(1.0f64, 0.5f64, 0.25f64)
    let inside = trace.camera(shade.vec3(0.0f64, 0.0f64, 0.0f64), shade.vec3(0.0f64, 0.0f64, 1.0f64), shade.vec3(0.0f64, 1.0f64, 0.0f64), 1.2f64)
    var small: [4]shade.Rgb = zero

    // 1: furnace at albedo zero: every pixel is the emission.
    var shell: [1]trace.Sphere = zero
    shell[0usize] = trace.sphere(shade.vec3(0.0f64, 0.0f64, 0.0f64), 5.0f64, black, emission)
    var job = trace.Job { spheres: shell[..], camera: inside, width: 2usize, height: 2usize, samples: 4usize, max_depth: 4usize, roulette_depth: 4usize }
    furnace(&job, small[..], emission, 1i32)

    // 2: furnace at albedo one half over eight bounces: the geometric series.
    shell[0usize] = trace.sphere(shade.vec3(0.0f64, 0.0f64, 0.0f64), 5.0f64, shade.rgb(0.5f64, 0.5f64, 0.5f64), emission)
    job = trace.Job { spheres: shell[..], camera: inside, width: 2usize, height: 2usize, samples: 4usize, max_depth: 8usize, roulette_depth: 8usize }
    furnace(&job, small[..], shade.rgb(1.99609375f64, 0.998046875f64, 0.4990234375f64), 2i32)
    var spare = rand.pcg64(1u64, 2u64)
    if trace.path_trace(&job, &spare, small[..3usize]) != trace.TooSmall { os.exit(2i32) }

    // 3: CSG intervals against the membership oracle.
    var nodes: [7]trace.CsgNode = zero
    nodes[0usize] = trace.csg_sphere(shade.vec3(0.0f64, 0.0f64, 0.0f64), 1.0f64)
    nodes[1usize] = trace.csg_box(shade.vec3(-0.5f64, -0.5f64, -0.5f64), shade.vec3(1.5f64, 1.5f64, 1.5f64))
    nodes[2usize] = trace.csg_sphere(shade.vec3(1.0f64, 0.0f64, 0.0f64), 0.7f64)
    nodes[3usize] = trace.csg_op(.Union, 0u32, 1u32)
    nodes[4usize] = trace.csg_op(.Difference, 3u32, 2u32)
    nodes[5usize] = trace.csg_op(.Intersection, 0u32, 1u32)
    nodes[6usize] = trace.csg_op(.Difference, 1u32, 0u32)
    var intervals: [16]trace.Interval = zero
    var scratch: [32]f64 = zero
    var state = 21u64
    var count = 0usize
    var acc = 0.0f64
    var hits = 0usize
    var hit_acc = 0.0f64
    var i = 0usize
    while i < 20usize {
        let ox = f64(draw(&state) % 4000u64) / 1000.0f64 - 2.0f64
        let oy = f64(draw(&state) % 4000u64) / 1000.0f64 - 2.0f64
        let oz = f64(draw(&state) % 4000u64) / 1000.0f64 - 2.0f64
        let jx = f64(draw(&state) % 2000u64) / 1000.0f64 - 1.0f64
        let jy = f64(draw(&state) % 2000u64) / 1000.0f64 - 1.0f64
        let jz = f64(draw(&state) % 2000u64) / 1000.0f64 - 1.0f64
        let origin = shade.vec3(ox, oy, oz)
        let direction = shade.normalize(shade.sub(shade.add(shade.vec3(0.5f64, 0.5f64, 0.5f64), shade.vec3(jx, jy, jz)), origin))
        var root = 4u32
        while root <= 6u32 {
            let (n, csg_error) = trace.csg(nodes[..], root, origin, direction, intervals[..], scratch[..])
            if csg_error != ok { os.exit(3i32) }
            count += n
            var k = 0usize
            while k < n {
                if intervals[k].exit <= intervals[k].enter { os.exit(3i32) }
                if k > 0usize && intervals[k].enter <= intervals[k - 1usize].exit { os.exit(3i32) }
                acc += intervals[k].enter + intervals[k].exit
                k += 1usize
            }
            let (hit, t, hit_error) = trace.csg_hit(nodes[..], root, origin, direction, intervals[..], scratch[..])
            if hit_error != ok { os.exit(3i32) }
            if hit {
                hits += 1usize
                hit_acc += t
            }
            root += 1u32
        }
        i += 1usize
    }
    if count != 58usize || !near(acc, 235.22166666735245f64, 1.0e-9f64) { os.exit(3i32) }
    if hits != 52usize || !near(hit_acc, 75.22852444365527f64, 1.0e-9f64) { os.exit(3i32) }
    let (_, tiny) = trace.csg(nodes[..], 4u32, shade.vec3(0.0f64, 0.0f64, 0.0f64), shade.vec3(1.0f64, 0.0f64, 0.0f64), intervals[..], scratch[..1usize])
    if tiny != trace.TooSmall { os.exit(3i32) }

    // 4-6: a 16x16 render in each mode against the replica.
    var scene: [4]trace.Sphere = zero
    scene[0usize] = trace.sphere(shade.vec3(0.0f64, -1001.0f64, 0.0f64), 1000.0f64, shade.rgb(0.75f64, 0.75f64, 0.75f64), black)
    scene[1usize] = trace.sphere(shade.vec3(-1.2f64, 0.0f64, 4.0f64), 1.0f64, shade.rgb(0.8f64, 0.3f64, 0.3f64), black)
    scene[2usize] = trace.sphere(shade.vec3(1.2f64, 0.0f64, 4.5f64), 1.0f64, shade.rgb(0.3f64, 0.3f64, 0.8f64), black)
    scene[3usize] = trace.sphere(shade.vec3(0.0f64, 3.0f64, 3.0f64), 0.8f64, black, shade.rgb(12.0f64, 11.0f64, 10.0f64))
    let cam = trace.camera(shade.vec3(0.0f64, 0.5f64, -2.0f64), shade.vec3(0.0f64, 0.0f64, 4.0f64), shade.vec3(0.0f64, 1.0f64, 0.0f64), 1.0f64)
    let scene_job = trace.Job { spheres: scene[..], camera: cam, width: 16usize, height: 16usize, samples: 4usize, max_depth: 5usize, roulette_depth: 3usize }
    var image: [256]shade.Rgb = zero
    var r = rand.pcg64(9u64, 4u64)
    if trace.path_trace(&scene_job, &r, image[..]) != ok { os.exit(4i32) }
    if image_hash(image[..]) != 5530566833814996612u64 || !near(image_sum(image[..]), 305.505f64, 1.0e-9f64) { os.exit(4i32) }
    r = rand.pcg64(9u64, 4u64)
    if trace.next_event_estimation(&scene_job, &r, image[..]) != ok { os.exit(5i32) }
    if image_hash(image[..]) != 6942906111176662196u64 || !near(image_sum(image[..]), 288.4523515272546f64, 1.0e-9f64) { os.exit(5i32) }
    r = rand.pcg64(9u64, 4u64)
    if trace.multiple_importance(&scene_job, &r, image[..]) != ok { os.exit(6i32) }
    if image_hash(image[..]) != 5380450904219785331u64 || !near(image_sum(image[..]), 290.4487737041245f64, 1.0e-9f64) { os.exit(6i32) }

    try io.print("gfx trace ok\n")
    ret ok
}
