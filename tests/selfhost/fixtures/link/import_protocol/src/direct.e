// Calls `plat.key_hash` by name, which `lower_call` binds from the declaration. The
// other modules reach the same extern only through a supplied protocol; before the
// fix they linked only when a worker had lowered this module first (D1664).
use plat

fn run() -> bool {
    ret plat.key_hash(plat.Key { k: -7i64 }) == plat.key_hash(plat.Key { k: 7i64 })
}
