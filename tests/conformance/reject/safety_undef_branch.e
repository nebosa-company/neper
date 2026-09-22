// A write on some paths is not a write (D918, H03): `f.items` is written inside the
// `if`, so a run where `flag` is false reaches the read with the base and the length
// `undef` left. Only a write at the declaration's own depth answers for the read.
type Frame = struct { items: []const u8, count: usize }

fn conditional(source: []const u8, flag: bool) -> usize {
    var f: Frame = undef
    f.count = 0usize
    if flag { f.items = source }
    ret f.items.len
}

fn main() -> i32 {
    var bytes: [2]u8 = zero
    ret i32(conditional(bytes[0usize..2usize], true))
}
