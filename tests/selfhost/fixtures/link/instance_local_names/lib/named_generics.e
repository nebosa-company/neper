// Generics whose parameters and locals carry names the instantiating module uses
// for module-scope functions: an instance keeps its own names (D872).
fn fill[Ctx: type](ctx: *Ctx, x: []const f64, gradient: []f64) {
    var i = 0usize
    while i < x.len {
        gradient[i] = x[i] * 2.0f64
        i += 1usize
    }
}

fn apply[Ctx: type](ctx: *Ctx, g: fn(*Ctx, []const f64, []f64), x: []const f64, scratch: []f64) -> f64 {
    let n = x.len
    var gradient = scratch[..n]
    g(ctx, x, gradient)
    var measure = 0.0f64
    var i = 0usize
    while i < n {
        measure += gradient[i]
        i += 1usize
    }
    fill[Ctx](ctx, x, gradient)
    i = 0usize
    while i < n {
        measure += gradient[i]
        i += 1usize
    }
    ret measure
}
