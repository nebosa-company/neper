// R fda, the B-spline basis of create.bspline.basis and its eval.basis: order `norder` on the breaks (the end points included), nbasis = number of breaks + norder - 2 values at x, the derivative of order `deriv`.
//
// Not here: the Fourier and other bases, smooth.basis and the roughness penalty, fd objects and the functional-data analyses.

use e.algo.stat.splines as sp
use e.mem

// out receives the nbasis basis values (or derivatives) at x
fn eval_bspline(a: *mem.Arena, norder: usize, breaks: []const f64, x: f64, deriv: usize, out: []f64) -> err {
    let degree = norder - 1usize
    let nint = breaks.len - 2usize
    let (t, e1) = mem.alloc[f64](a, nint + 2usize * norder + 2usize)
    let (tmp, e2) = mem.alloc[f64](a, 4usize * norder + 8usize)
    let (o, e3) = mem.alloc[f64](a, nint + norder + 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let cnt = sp.row(t, tmp, breaks[1usize..breaks.len - 1usize], breaks[0usize], breaks[breaks.len - 1usize], degree, true, 0u8, deriv, x, o)
    var i = 0usize
    while i < cnt {
        out[i] = o[i]
        i += 1usize
    }
    ret ok
}
