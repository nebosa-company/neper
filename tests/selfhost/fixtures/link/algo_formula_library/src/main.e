// The whole `e.algo.formula` library in one registry: the same 279 functions and 330 distinct names as appdor's default
// registry (counted by node over src/formula/index.js), and sentences that cross the groups.
use e.algo.formula as f
use e.algo.formula.library as library
use e.io
use e.mem
use e.os
use e.str

fn check(a: *mem.Arena, ctx: *f.Context, reg: *f.Registry, src: str, want: str) -> bool {
    let v = f.evaluate(a, src, ctx, reg)
    var got = ""
    if v.kind == .Text {
        got = v.s
    } else if v.kind == .Number {
        got = f.number_text(a, v.n)
    } else if v.kind == .Bool {
        got = "false"
        if v.n != 0.0f64 { got = "true" }
    } else {
        got = "?"
    }
    ret str.eq(got, want)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (reg, e) = library.build(a)
    var registry = reg
    if e != ok { os.exit(1i32) }
    if registry.count != 279usize { os.exit(2i32) }
    if registry.key_count != 330usize { os.exit(3i32) }
    var ctx: f.Context = zero
    if !check(a, &ctx, &registry, "JOIN(SORT(MAP([3, 1, 2], current * 2)), \"-\")", "2-4-6") { os.exit(4i32) }
    if !check(a, &ctx, &registry, "LET(x, 5, IF(x > 3, UPPER(TEXT(x * 2)), \"no\"))", "10") { os.exit(5i32) }
    if !check(a, &ctx, &registry, "SHA256(\"abc\")", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") { os.exit(6i32) }
    if !check(a, &ctx, &registry, "TEXT(DATEDIF(DATE(2024, 1, 31), DATE(2024, 3, 1), \"D\"))", "30") { os.exit(7i32) }
    if !check(a, &ctx, &registry, "ISERROR(1 / 0)", "true") { os.exit(8i32) }
    try io.print("algo formula library ok")
    ret ok
}
