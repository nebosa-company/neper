use e.mem
use e.os

type Nothing = struct { unused: u8 }

// The first parameters are dead, so their values share one register with the first used one; the float among them is made by its
// Parameter instruction, which must not overwrite what the prologue already moved into that register. Called through a function
// value so that the body is not inlined away.
fn decay(ctx: *Nothing, t: f64, y: []const f64, out: []f64) { out[0usize] = 0.0f64 - y[0usize] }

fn mixed(ctx: *Nothing, t: f64, n: usize, scale: f64, m: usize) -> f64 { ret scale * f64(n + m) }

fn apply(ctx: *Nothing, f: fn(*Nothing, f64, []const f64, []f64), y: []const f64, out: []f64) { f(ctx, 0.5f64, y, out) }

fn apply_mixed(ctx: *Nothing, f: fn(*Nothing, f64, usize, f64, usize) -> f64) -> f64 { ret f(ctx, 1.0f64, 4usize, 0.5f64, 6usize) }

fn main(a: *mem.Arena, args: []str) -> err {
    var nothing = Nothing { unused: 0u8 }
    var y: [2]f64 = zero
    var out: [2]f64 = zero
    y[0usize] = 3.0f64
    apply(&nothing, decay, y[0usize..2usize], out[0usize..2usize])
    if out[0usize] != 0.0f64 - 3.0f64 { os.exit(1i32) }
    if apply_mixed(&nothing, mixed) != 5.0f64 { os.exit(2i32) }
    ret ok
}
