// A cyclic artifact reference (D472, H24): `main` imports `ring`, and the runner
// makes `ring`'s artifact claim an edge back to `main`. A warm build must not
// follow the cycle for ever: the edge is stale, `ring` is rebuilt, and the image
// is the clean build's; the linker over the two artifacts refuses or links,
// never crashes.
use ring

fn main() -> err {
    if ring.code() != 7i32 { ret ok }
    ret ok
}
