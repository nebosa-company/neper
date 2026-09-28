// A sequence's supplied `cmp` and `hash` call the element's declared ones from
// `emit_declared_cmp` and `emit_declared_hash`, not from `lower_call`. Nothing in the
// program calls `plat.point_cmp` by name.
use plat

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn hash_of[T: type](v: T) -> u64 {
    ret T.hash(v)
}

fn run() -> bool {
    var xs: [1]plat.Point = zero
    var ys: [1]plat.Point = zero
    xs[0usize] = plat.Point { x: -3i64 }
    ys[0usize] = plat.Point { x: -3i64 }
    if order[[1]plat.Point](xs, ys) == 0i32 { ret false }
    var ks: [1]plat.Key = zero
    var ls: [1]plat.Key = zero
    ks[0usize] = plat.Key { k: -7i64 }
    ls[0usize] = plat.Key { k: 7i64 }
    ret hash_of[[1]plat.Key](ks) == hash_of[[1]plat.Key](ls)
}
