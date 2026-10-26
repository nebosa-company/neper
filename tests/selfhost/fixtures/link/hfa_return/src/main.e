// Three- and four-member double HFAs and a four-member float HFA coming back from C (C178), against a shared object cc builds from
// cabi.c. On aarch64 they return in v0-v3 and the call stores them into its slot; elsewhere they take the existing paths.
use e.mem
use e.os

type D3 = struct { a: f64, b: f64, c: f64 }
type D4 = struct { a: f64, b: f64, c: f64, d: f64 }
type F4 = struct { a: f32, b: f32, c: f32, d: f32 }

@import("nepercabi", "hfa_make_d3")
extern fn make_d3(a: f64, b: f64, c: f64) -> D3

@import("nepercabi", "hfa_make_d4")
extern fn make_d4(a: f64, b: f64, c: f64, d: f64) -> D4

@import("nepercabi", "hfa_make_f4")
extern fn make_f4(a: f32, b: f32, c: f32, d: f32) -> F4

@import("nepercabi", "hfa_rotate_d4")
extern fn rotate_d4(v: D4) -> D4

@import("nepercabi", "hfa_scale_d3")
extern fn scale_d3(v: D3, k: f64) -> D3

fn main(a: *mem.Arena) -> err {
    let d3 = make_d3(1.5, 2.5, 3.5)
    if d3.a != 1.5 || d3.b != 2.5 || d3.c != 3.5 { os.exit(2i32) }
    let d4 = make_d4(1.0, 2.0, 3.0, 4.0)
    if d4.a != 1.0 || d4.b != 2.0 || d4.c != 3.0 || d4.d != 4.0 { os.exit(3i32) }
    let f4 = make_f4(1.0, 2.0, 3.0, 4.0)
    if f4.a != 1.0 || f4.b != 2.0 || f4.c != 3.0 || f4.d != 4.0 { os.exit(4i32) }
    let turned = rotate_d4(d4)
    if turned.a != 2.0 || turned.b != 3.0 || turned.c != 4.0 || turned.d != 1.0 { os.exit(5i32) }
    let scaled = scale_d3(d3, 2.0)
    if scaled.a != 3.0 || scaled.b != 5.0 || scaled.c != 7.0 { os.exit(6i32) }
    // A result used after other calls: the slot survives them.
    let again = make_d4(5.0, 6.0, 7.0, 8.0)
    let other = make_d3(9.0, 10.0, 11.0)
    if again.a != 5.0 || again.d != 8.0 || other.c != 11.0 { os.exit(7i32) }
    ret ok
}
