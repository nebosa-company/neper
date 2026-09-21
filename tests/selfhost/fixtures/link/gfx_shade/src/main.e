// `e.gfx.shade`: Cook-Torrance GGX, Schlick Fresnel and Lambert summed over 30
// LCG configurations against a Python replica to 1e-12; the white furnace of
// GGX at roughness 0.5 by importance sampling (20000 samples of one PCG stream)
// is above 0.9, at most 1, and matches the replica to 1e-9; every sampled half
// vector is unit and above the horizon. Each check exits with its own code.

use e.algo.rand
use e.gfx.shade
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn unit(state: *u64) -> shade.Vec3 {
    let x = f64(draw(state) % 2000u64) / 1000.0f64 - 1.0f64
    let y = f64(draw(state) % 2000u64) / 1000.0f64 - 1.0f64
    let z = f64(draw(state) % 2000u64) / 1000.0f64 - 1.0f64
    ret shade.normalize(shade.vec3(x, y, z))
}

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= tolerance
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 5u64

    // 1: brdf_ggx, fresnel_schlick and brdf_lambert over 30 configurations.
    var sum = shade.rgb(0.0f64, 0.0f64, 0.0f64)
    var fresnel = 0.0f64
    var lambert = 0.0f64
    var i = 0usize
    while i < 30usize {
        let n = unit(&state)
        let v = unit(&state)
        let l = unit(&state)
        let roughness = 0.3f64 + f64(draw(&state) % 700u64) / 1000.0f64
        let f0_red = f64(draw(&state) % 1000u64) / 1000.0f64
        let f0_green = f64(draw(&state) % 1000u64) / 1000.0f64
        let f0_blue = f64(draw(&state) % 1000u64) / 1000.0f64
        let f0 = shade.rgb(f0_red, f0_green, f0_blue)
        sum = shade.rgb_add(sum, shade.brdf_ggx(n, v, l, roughness, f0))
        fresnel += shade.fresnel_schlick(shade.dot(n, v), f0).green
        lambert += shade.brdf_lambert(f0).blue
        i += 1usize
    }
    if !near(sum.red, 1.2933683112788206f64, 1.0e-12f64) || !near(sum.green, 1.4716906188254961f64, 1.0e-12f64) || !near(sum.blue, 1.231717100304025f64, 1.0e-12f64) { os.exit(1i32) }
    if !near(fresnel, 25.663850470414605f64, 1.0e-12f64) { os.exit(2i32) }
    if !near(lambert, 4.820803226253511f64, 1.0e-12f64) { os.exit(3i32) }

    // 4: the white furnace by GGX importance sampling.
    var r = rand.pcg64(3u64, 5u64)
    let n = shade.vec3(0.0f64, 0.0f64, 1.0f64)
    let v = shade.normalize(shade.vec3(0.3f64, 0.0f64, 0.9f64))
    let white = shade.rgb(1.0f64, 1.0f64, 1.0f64)
    var energy = 0.0f64
    i = 0usize
    while i < 20000usize {
        let h = shade.ggx_sample(&r, 0.5f64, n)
        if !near(shade.dot(h, h), 1.0f64, 1.0e-12f64) || shade.dot(n, h) <= 0.0f64 { os.exit(5i32) }
        let l = shade.reflect(v, h)
        if shade.dot(n, l) > 0.0f64 {
            let pdf = shade.ggx_pdf(n, v, h, 0.5f64)
            let f = shade.brdf_ggx(n, v, l, 0.5f64, white)
            energy += f.red * shade.dot(n, l) / pdf
        }
        i += 1usize
    }
    energy = energy / 20000.0f64
    if energy <= 0.9f64 || energy > 1.0f64 { os.exit(4i32) }
    if !near(energy, 0.9093154791991723f64, 1.0e-9f64) { os.exit(4i32) }

    // 6: below the horizon is black.
    let dark = shade.brdf_ggx(n, v, shade.vec3(0.0f64, 0.0f64, -1.0f64), 0.5f64, white)
    if dark.red != 0.0f64 || dark.green != 0.0f64 || dark.blue != 0.0f64 { os.exit(6i32) }

    try io.print("gfx shade ok\n")
    ret ok
}
