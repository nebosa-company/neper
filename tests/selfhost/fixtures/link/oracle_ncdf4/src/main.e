// e.fmt.netcdf against ncdf4. tests/oracle/ncdf4.json and the files tests/oracle/data/ncdf4_<i>.nc come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ncdf4`; the layout is at the top of scripts/r_oracle/groups/ncdf4.R.

use e.fmt.netcdf as nc
use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn path_of(a: *mem.Arena, idx: usize) -> str {
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/ncdf4_")
    let _ = str.push_byte(&bb, u8(48usize + idx))
    let _ = str.push(&bb, ".nc")
    ret str.done(&bb)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let (bytes, re) = fs.read_file(a, path_of(a, usize(x[0usize])), 1048576usize)
    if re != ok { os.exit(6) }
    let (f, pe) = nc.parse(a, bytes)
    if pe != ok { os.exit(7) }
    let name = c.inputs[0usize]
    if str.eq(c.name, "ncd") {
        let d = nc.find_dim(&f, name)
        if d >= f.ndims { ret 0.0f64 - 1.0f64 }
        ret f64(nc.dim_length(&f, d))
    }
    let v = nc.find_var(&f, name)
    if v >= f.nvars { ret 0.0f64 - 1.0f64 }
    let n = nc.var_count(&f, v)
    if str.eq(c.name, "ncn") { ret f64(n) }
    let (vals, ve) = mem.alloc[f64](a, n + 1usize)
    if ve != ok { os.exit(8) }
    nc.var_values(&f, bytes, v, vals)
    if str.eq(c.name, "ncv") { ret vals[usize(x[1usize])] }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += vals[i]
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ncdf4.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
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
