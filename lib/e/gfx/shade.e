// Physically based reflectance over `f64` vectors: Cook-Torrance with the GGX
// normal distribution, Smith's height-correlated masking-shadowing in Heitz's
// visibility form `V = G / (4 n.l n.v)` and Schlick's Fresnel, so `brdf_ggx`
// is `D * V * F` and already carries the `1 / (4 n.l n.v)` of the microfacet
// model; `brdf_lambert` is `albedo / pi`. `roughness` is the perceptual value,
// squared into the GGX `alpha`, and clamped below at 1e-4 so a mirror still
// samples. Every direction points away from the surface and is unit length;
// a light or view below the horizon answers black.
//
// `ggx_sample` draws a microfacet normal `h` about `n` from the GGX distribution
// (two `rand.pcg64_f64` draws in that order: the first sets the polar angle, the
// second the azimuth, in the frame `onb` builds from `n`); `reflect(v, h)` is the
// light direction that half vector reflects `v` into, and `ggx_pdf(n, v, h, ..)`
// is the density of that light direction, `D(h) n.h / (4 v.h)`, which is what
// an estimator divides by. `onb` is the branchless frame of Duff et al. 2017.

use e.algo.rand
use e.math

type Vec3 = struct { x: f64, y: f64, z: f64 }
type Rgb = struct { red: f64, green: f64, blue: f64 }

fn pi() -> f64 { ret 3.141592653589793f64 }

fn vec3(x: f64, y: f64, z: f64) -> Vec3 { ret Vec3 { x: x, y: y, z: z } }
fn rgb(red: f64, green: f64, blue: f64) -> Rgb { ret Rgb { red: red, green: green, blue: blue } }
fn add(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z } }
fn sub(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z } }
fn scale(a: Vec3, s: f64) -> Vec3 { ret Vec3 { x: a.x * s, y: a.y * s, z: a.z * s } }
fn dot(a: Vec3, b: Vec3) -> f64 { ret a.x * b.x + a.y * b.y + a.z * b.z }
fn cross(a: Vec3, b: Vec3) -> Vec3 { ret Vec3 { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x } }
fn length(a: Vec3) -> f64 { ret math.sqrt[f64](dot(a, a)) }
fn rgb_scale(c: Rgb, s: f64) -> Rgb { ret Rgb { red: c.red * s, green: c.green * s, blue: c.blue * s } }
fn rgb_mul(a: Rgb, b: Rgb) -> Rgb { ret Rgb { red: a.red * b.red, green: a.green * b.green, blue: a.blue * b.blue } }
fn rgb_add(a: Rgb, b: Rgb) -> Rgb { ret Rgb { red: a.red + b.red, green: a.green + b.green, blue: a.blue + b.blue } }

fn normalize(a: Vec3) -> Vec3 {
    let n = length(a)
    if n == 0.0f64 { ret a }
    ret scale(a, 1.0f64 / n)
}

fn alpha_of(roughness: f64) -> f64 {
    var r = roughness
    if r < 1.0e-4f64 { r = 1.0e-4f64 }
    if r > 1.0f64 { r = 1.0f64 }
    ret r * r
}

fn brdf_lambert(albedo: Rgb) -> Rgb { ret rgb_scale(albedo, 1.0f64 / pi()) }

fn fresnel_schlick(cos_theta: f64, f0: Rgb) -> Rgb {
    var c = cos_theta
    if c < 0.0f64 { c = 0.0f64 }
    if c > 1.0f64 { c = 1.0f64 }
    let m = 1.0f64 - c
    let m5 = m * m * m * m * m
    ret Rgb { red: f0.red + (1.0f64 - f0.red) * m5, green: f0.green + (1.0f64 - f0.green) * m5, blue: f0.blue + (1.0f64 - f0.blue) * m5 }
}

// The GGX (Trowbridge-Reitz) normal distribution at `n.h`.
fn ggx_d(n_dot_h: f64, roughness: f64) -> f64 {
    if n_dot_h <= 0.0f64 { ret 0.0f64 }
    let a2 = alpha_of(roughness) * alpha_of(roughness)
    let t = n_dot_h * n_dot_h * (a2 - 1.0f64) + 1.0f64
    ret a2 / (pi() * t * t)
}

// Smith height-correlated visibility `G / (4 n.l n.v)`.
fn ggx_v(n_dot_v: f64, n_dot_l: f64, roughness: f64) -> f64 {
    let a2 = alpha_of(roughness) * alpha_of(roughness)
    let gv = n_dot_l * math.sqrt[f64](n_dot_v * n_dot_v * (1.0f64 - a2) + a2)
    let gl = n_dot_v * math.sqrt[f64](n_dot_l * n_dot_l * (1.0f64 - a2) + a2)
    ret 0.5f64 / (gv + gl)
}

fn brdf_ggx(n: Vec3, v: Vec3, l: Vec3, roughness: f64, f0: Rgb) -> Rgb {
    let n_dot_v = dot(n, v)
    let n_dot_l = dot(n, l)
    if n_dot_v <= 0.0f64 || n_dot_l <= 0.0f64 { ret zero }
    let h = normalize(add(v, l))
    let d = ggx_d(dot(n, h), roughness)
    let vis = ggx_v(n_dot_v, n_dot_l, roughness)
    ret rgb_scale(fresnel_schlick(dot(v, h), f0), d * vis)
}

// An orthonormal frame `(t, b)` about unit `n`, without a branch or a division by zero.
fn onb(n: Vec3) -> (Vec3, Vec3) {
    var sign = 1.0f64
    if n.z < 0.0f64 { sign = -1.0f64 }
    let a = -1.0f64 / (sign + n.z)
    let b = n.x * n.y * a
    let t = Vec3 { x: 1.0f64 + sign * n.x * n.x * a, y: sign * b, z: 0.0f64 - sign * n.x }
    let u = Vec3 { x: b, y: sign + n.y * n.y * a, z: 0.0f64 - n.y }
    ret (t, u)
}

// A microfacet normal about `n` with density `D(h) n.h`.
fn ggx_sample(r: *rand.Pcg64, roughness: f64, n: Vec3) -> Vec3 {
    let a2 = alpha_of(roughness) * alpha_of(roughness)
    let u1 = rand.pcg64_f64(r)
    let u2 = rand.pcg64_f64(r)
    let cos_theta = math.sqrt[f64]((1.0f64 - u1) / (1.0f64 + (a2 - 1.0f64) * u1))
    let sin_theta = math.sqrt[f64](1.0f64 - cos_theta * cos_theta)
    let phi = 2.0f64 * pi() * u2
    let (t, b) = onb(n)
    let local_x = sin_theta * math.cos[f64](phi)
    let local_y = sin_theta * math.sin[f64](phi)
    ret add(add(scale(t, local_x), scale(b, local_y)), scale(n, cos_theta))
}

fn reflect(v: Vec3, h: Vec3) -> Vec3 {
    ret sub(scale(h, 2.0f64 * dot(v, h)), v)
}

// The density of `reflect(v, h)` when `h` came from `ggx_sample`.
fn ggx_pdf(n: Vec3, v: Vec3, h: Vec3, roughness: f64) -> f64 {
    let v_dot_h = dot(v, h)
    if v_dot_h <= 0.0f64 { ret 0.0f64 }
    ret ggx_d(dot(n, h), roughness) * dot(n, h) / (4.0f64 * v_dot_h)
}
