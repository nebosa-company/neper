// e.algo.linalg.abind against R's abind package: arrays of rank 1 to 4 bound along any
// dimension, between dimensions, counted from the end, with force.array on and off.
// tests/oracle/abind.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R abind`.
// A case is (along, rev.along, force, k, [rank, dims..] x k, e): the e-th element of the result,
// or, for "abind_dim", its e-th dimension (0 is the rank). Array j holds 1000 j + 1, 1000 j + 2, ...

use e.algo.linalg.abind as ab
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn build(a: *mem.Arena, args: []const f64, k: usize) -> []ab.Array {
    let (arrays, e) = mem.alloc[ab.Array](a, k)
    if e != ok { os.exit(5) }
    var at = 4usize
    var j = 0usize
    while j < k {
        let rank = usize(args[at])
        at += 1usize
        let (dims, de) = mem.alloc[usize](a, rank)
        if de != ok { os.exit(5) }
        var count = 1usize
        var r = 0usize
        while r < rank {
            dims[r] = usize(args[at + r])
            count = count * dims[r]
            r += 1usize
        }
        at += rank
        let (data, ge) = mem.alloc[f64](a, count)
        if ge != ok { os.exit(5) }
        var i = 0usize
        while i < count {
            data[i] = f64(1000usize * (j + 1usize) + i + 1usize)
            i += 1usize
        }
        arrays[j] = ab.Array { dims: dims, data: data }
        j += 1usize
    }
    ret arrays
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/abind.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let arrays = build(a, x, usize(x[3usize]))
        let element = usize(x[x.len - 1usize])
        let (r, e) = ab.abind(a, arrays, x[0usize], x[1usize], x[2usize] != 0.0f64)
        var got = 0.0f64 / 0.0f64
        if e == ok {
            if c.name.len == 9usize {
                if element == 0usize { got = f64(r.dims.len) } else { got = f64(r.dims[element - 1usize]) }
            } else {
                got = r.data[element]
            }
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 15usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
