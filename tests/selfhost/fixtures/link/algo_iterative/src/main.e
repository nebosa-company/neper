use e.algo.linalg.iterative as it
use e.algo.linalg.matrix as mx
use e.io
use e.math
use e.mem

error Failed

type Dense = struct { a: []const f64, n: usize }

fn apply(d: *Dense, x: []const f64, y: []f64) {
    var i = 0usize
    while i < d.n {
        var s = 0.0f64
        var j = 0usize
        while j < d.n {
            s += d.a[i * d.n + j] * x[j]
            j += 1usize
        }
        y[i] = s
        i += 1usize
    }
}

fn lcg(s: u64) -> u64 { ret (s * 1103515245u64 + 12345u64) % 2147483648u64 }

fn unit(seed: *u64) -> f64 {
    *seed = lcg(*seed)
    ret f64((*seed >> 8u64) % 20001u64) / 10000.0f64 - 1.0f64
}

fn main(arena: *mem.Arena, args: []str) -> err {
    let n = 12usize
    var seed = 12345u64
    var trial = 0usize
    while trial < 20usize {
        var a: [144]f64 = zero
        var b: [12]f64 = zero
        var i = 0usize
        while i < 144usize {
            a[i] = unit(&seed)
            i += 1usize
        }
        i = 0usize
        while i < 12usize {
            b[i] = unit(&seed)
            i += 1usize
        }
        // a general matrix made safely nonsingular and a symmetric positive-definite one, both from a
        var gen: [144]f64 = zero
        var spd: [144]f64 = zero
        i = 0usize
        while i < 12usize {
            var j = 0usize
            while j < 12usize {
                var s = 0.0f64
                var k = 0usize
                while k < 12usize {
                    s += a[k * 12usize + i] * a[k * 12usize + j]
                    k += 1usize
                }
                spd[i * 12usize + j] = s
                gen[i * 12usize + j] = a[i * 12usize + j] * 0.3f64
                j += 1usize
            }
            spd[i * 12usize + i] += 1.0f64
            gen[i * 12usize + i] += 3.0f64
            i += 1usize
        }
        var xcg: [12]f64 = zero
        var xgm: [12]f64 = zero
        var xdir: [12]f64 = zero
        var scr: [36]f64 = zero
        var big: [400]f64 = zero
        var d1 = Dense { a: spd[..], n: n }
        let (r1, e1) = it.cg[Dense](&d1, apply, b[..], xcg[..], 1.0e-12f64, 200usize, scr[..])
        if e1 != ok || !r1.converged { ret Failed }
        let (sm, se) = mx.view_const[f64](spd[..], 12usize, 12usize, 12usize)
        if se != ok { ret se }
        let de = mx.solve(arena, xdir[..], sm, b[..])
        if de != ok { ret de }
        i = 0usize
        while i < 12usize {
            if math.abs[f64](xcg[i] - xdir[i]) > 1.0e-8f64 { ret Failed }
            i += 1usize
        }
        var d2 = Dense { a: gen[..], n: n }
        let need = it.gmres_scratch(n, 6usize)
        if need > 400usize { ret Failed }
        let (r2, e2) = it.gmres[Dense](&d2, apply, b[..], xgm[..], 6usize, 1.0e-12f64, 500usize, big[..])
        if e2 != ok || !r2.converged { ret Failed }
        let (gm, ge) = mx.view_const[f64](gen[..], 12usize, 12usize, 12usize)
        if ge != ok { ret ge }
        var xd2: [12]f64 = zero
        let de2 = mx.solve(arena, xd2[..], gm, b[..])
        if de2 != ok { ret de2 }
        i = 0usize
        while i < 12usize {
            if math.abs[f64](xgm[i] - xd2[i]) > 1.0e-8f64 { ret Failed }
            i += 1usize
        }
        trial += 1usize
    }
    ret ok
}
