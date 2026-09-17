// Uses through an alias and past a same-spelled name (D509, H17): `pick` is a
// function of `deep`, imported as `d`, and of `other`, and a local is spelled
// `pick` too. The uses of `deep.pick` are the two calls through `d` alone, and a
// rename of it rewrites those and its declaration, nothing of `other` or the local.
use deep as d
use other
use e.os

fn main() -> err {
    let pick = other.pick(1usize)
    let first = d.pick(pick)
    let second = d.pick(first) + other.pick(2usize)
    os.exit(i32(second))
    ret ok
}
