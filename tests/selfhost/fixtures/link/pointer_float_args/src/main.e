// A pointer to a float is an integer-class argument: it must reach the callee
// through the integer registers and the stack overflow area whatever floats
// precede it and however many arguments there are. Each check exits with its
// own code.

use e.io
use e.mem
use e.os

fn after_floats(x: f64, y: f64, seed: u64, f1: *f64, f2: *f64) -> f64 { ret *f1 * 10.0f64 + *f2 + x + y + f64(seed) }

fn after_floats32(x: f32, y: f32, seed: u64, f1: *f32, f2: *f32) -> f32 { ret *f1 * 10.0f32 + *f2 + x + y + f32(seed) }

fn writes_through(x: f64, count: u64, out: *f64) { *out = x * f64(count) }

fn seven(a: usize, b: usize, c: usize, d: usize, e: usize, f: usize, g: *f64) -> f64 { ret *g + f64(a + b + c + d + e + f) }

fn eight(a: usize, b: usize, c: usize, d: usize, e: usize, f: usize, g: *usize, h: *f64) -> f64 { ret f64(*g) * 1000.0f64 + *h }

fn nine(a: f64, b: usize, c: f64, d: usize, e: f64, f: usize, g: *f64, h: *usize, i: *f64) -> f64 { ret a + f64(b) + c + f64(d) + e + f64(f) + *g * 100.0f64 + f64(*h) * 1000.0f64 + *i * 10000.0f64 }

fn slice_then_pointers(a: usize, b: usize, c: usize, d: usize, q: []const f64, g: *usize, h: *f64) -> f64 { ret f64(*g) * 1000.0f64 + *h + q[0usize] }

type Sample = struct { weight: f64, tag: u32 }

fn field_pointer(a: f64, b: f64, c: f64, d: f64, p: *f64) -> f64 { ret *p + a + b + c + d }

fn main(a: *mem.Arena, args: []str) -> err {
    var f1 = 3.0f64
    var f2 = 0.5f64
    // 1: pointers after two floats (Win64 slot 3 is the failing one).
    if after_floats(1.0f64, 2.0f64, 42u64, &f1, &f2) != 75.5f64 { os.exit(1i32) }
    var g1 = 3.0f32
    var g2 = 0.5f32
    if after_floats32(1.0f32, 2.0f32, 42u64, &g1, &g2) != 75.5f32 { os.exit(1i32) }
    // 2: written through.
    var sink = 0.0f64
    writes_through(2.5f64, 4u64, &sink)
    if sink != 10.0f64 { os.exit(2i32) }
    // 3: the seventh and eighth arguments (the System V overflow area).
    var h = 8.0f64
    var g = 7usize
    if seven(1usize, 2usize, 3usize, 4usize, 5usize, 6usize, &h) != 29.0f64 { os.exit(3i32) }
    if eight(1usize, 2usize, 3usize, 4usize, 5usize, 6usize, &g, &h) != 7008.0f64 { os.exit(3i32) }
    // 4: nine arguments of mixed classes.
    var i = 0.25f64
    if nine(1.0f64, 2usize, 3.0f64, 4usize, 5.0f64, 6usize, &h, &g, &i) != 10321.0f64 { os.exit(4i32) }
    // 5: a slice before the pointers.
    var q: [2]f64 = zero
    q[0usize] = 5.0f64
    if slice_then_pointers(1usize, 2usize, 3usize, 4usize, q[..], &g, &h) != 7013.0f64 { os.exit(5i32) }
    // 6: the address of a float field and of an array element.
    var s = Sample { weight: 1.5f64, tag: 1u32 }
    if field_pointer(1.0f64, 2.0f64, 3.0f64, 4.0f64, &s.weight) != 11.5f64 { os.exit(6i32) }
    if field_pointer(1.0f64, 2.0f64, 3.0f64, 4.0f64, &q[0usize]) != 15.0f64 { os.exit(6i32) }
    // 7: a pointer to a float kept in a local and compared.
    let p = &h
    let p2 = &h
    if p != p2 || *p != 8.0f64 { os.exit(7i32) }
    try io.print("pointer float args ok\n")
    ret ok
}
