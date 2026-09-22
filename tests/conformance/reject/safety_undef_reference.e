// Definite initialization of an `undef` value that holds a reference (D918, H03):
// `Frame` holds a slice, whose base and length `undef` leaves as whatever the stack
// held. A bounds check establishes that an index is under a length, not that the
// length is one the program chose (D355), so the read of `f.items` below is refused
// rather than checked. Writing `f.items` before the read is what `accept/safety.e`
// does; `f.count` is not a reference and does not answer for one.
type Frame = struct { items: []const u8, count: usize }

fn main() -> i32 {
    var f: Frame = undef
    f.count = 0usize
    if f.items.len > 0usize { ret 1i32 }
    ret 0i32
}
