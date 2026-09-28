// Reaches `plat.key_hash` only through a sequence's supplied `hash` (D1664), which
// binds from the declaration as a call by name does.
use plat

fn hash_of[T: type](v: T) -> u64 {
    ret T.hash(v)
}

fn run() -> bool {
    var ks: [1]plat.Key = zero
    var ls: [1]plat.Key = zero
    ks[0usize] = plat.Key { k: -7i64 }
    ls[0usize] = plat.Key { k: 7i64 }
    ret hash_of[[1]plat.Key](ks) == hash_of[[1]plat.Key](ls)
}
