// A tagged union's supplied `cmp` and `hash` reach the payload's declared ones from
// `emit_declared_cmp` and `emit_declared_hash`.
use plat

type Ordered = union enum u8 {
    Nil,
    P: plat.Point,
}

type Hashed = union enum u8 {
    Nil,
    K: plat.Key,
}

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn hash_of[T: type](v: T) -> u64 {
    ret T.hash(v)
}

fn run() -> bool {
    let a = Ordered{ P: plat.Point { x: -3i64 } }
    let b = Ordered{ P: plat.Point { x: -3i64 } }
    if order[Ordered](a, b) == 0i32 { ret false }
    let k1 = Hashed{ K: plat.Key { k: -7i64 } }
    let k2 = Hashed{ K: plat.Key { k: 7i64 } }
    ret hash_of[Hashed](k1) == hash_of[Hashed](k2)
}
