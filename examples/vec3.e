// Records live on the stack and are passed by value.

use e.math

type Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
}

fn dot(a: Vec3, b: Vec3) -> f32 {
    ret a.x*b.x + a.y*b.y + a.z*b.z
}

fn scale(v: Vec3, s: f32) -> Vec3 {
    ret Vec3{ x: v.x*s, y: v.y*s, z: v.z*s }
}

fn length(v: Vec3) -> f32 {
    ret math.sqrt(dot(v, v))
}

fn normalize(v: Vec3) -> Vec3 {
    let n = length(v)
    if n == 0.0 {
        ret v
    }
    ret scale(v, 1.0/n)
}
