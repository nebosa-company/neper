// A module-scope `var` is storage the linker lays out and the code reaches through a
// relocation. D154 gave the `.em` format a section for it, so this links the same whether
// the image comes straight from source or from the artifact `emit-em-all` writes -- the
// case that stayed unlinkable until then. It imports nothing, so its one artifact links in
// no time; that `e.os`'s own `var`s link from artifacts too is true but slow, and left to the
// reach walk's own row.

error Wrong

var counter: usize = 0usize
var flag: bool
var narrow: u8 = 0u8
var seeded: u32 = 7u32
var signed: i64 = -3i64

fn bump() {
    counter += 1usize
}

fn observe() -> usize {
    ret counter
}

fn raise() {
    flag = true
}

fn main() -> err {
    // Zero without an initialiser, the image's own zeroing.
    if counter != 0usize { ret Wrong }
    if flag { ret Wrong }
    if narrow != 0u8 { ret Wrong }
    // An initialiser's bits are in the image.
    if seeded != 7u32 { ret Wrong }
    if signed != -3i64 { ret Wrong }

    // Storage, not a per-use copy: a write in one function is seen by a read in another.
    bump()
    bump()
    if observe() != 2usize { ret Wrong }
    raise()
    if !flag { ret Wrong }

    // Each keeps its own width beside the others.
    narrow = 255u8
    if narrow != 255u8 { ret Wrong }
    if seeded != 7u32 { ret Wrong }
    ret ok
}
