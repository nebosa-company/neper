// A generic instance's parameter or local named like a module-scope function of
// the module that instantiated it: `fill[Target]` binds `gradient: []f64` and `apply`
// a local `gradient`, while this module passes its own `fn gradient` and `fn measure`
// as values. Before D872 the last checked instance's locals were still in the
// checker's table when lowering began, so `gradient` here read as `[]f64`.
use named_generics as ng
use e.io
use e.mem
use e.os

type Target = struct { scale: f64 }

fn gradient(t: *Target, x: []const f64, g: []f64) {
    var i = 0usize
    while i < x.len {
        g[i] = x[i] * t.scale
        i += 1usize
    }
}

fn measure(t: *Target, x: []const f64, g: []f64) {
    var i = 0usize
    while i < x.len {
        g[i] = t.scale
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var t = Target { scale: 3.0f64 }
    var x: [2]f64 = zero
    x[0usize] = 1.0f64
    x[1usize] = 2.0f64
    var scratch: [4]f64 = zero
    // 1: (1 + 2) * 3 from `gradient`, then (1 + 2) * 2 from `fill`.
    if ng.apply[Target](&t, gradient, x[..], scratch[..]) != 15.0f64 { os.exit(1i32) }
    // 2: `measure` is a local of the template as well.
    if ng.apply[Target](&t, measure, x[..], scratch[..]) != 12.0f64 { os.exit(2i32) }
    // 3: the module's own function still calls as itself.
    gradient(&t, x[..], scratch[..])
    if scratch[1usize] != 6.0f64 { os.exit(3i32) }
    try io.print("instance local names ok\n")
    ret ok
}
