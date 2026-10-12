// C177: a comptime Field argument is an index into its owner's declaration, so the same index of two different structs
// is two different arguments. One generic function instantiated with field 0 of A and field 0 of B must give each its
// own name (an instance shared between them answered the first one's). Every check has its own exit code.
use e.os
use e.mem
use e.meta

type A = struct { a0: i32, a1: u8 }
type B = struct { bee0: u16, bee11: i64, third: bool }

fn name_len[F: meta.Field]() -> usize {
    ret F.name.len
}

fn size_of_field[F: meta.Field]() -> usize {
    ret mem.size_of[F.ty]()
}

fn names_total[T: type]() -> usize {
    var n = 0usize
    for f in meta.fields[T]() {
        n += name_len[f]()
    }
    ret n
}

fn sizes_total[T: type]() -> usize {
    var n = 0usize
    for f in meta.fields[T]() {
        n += size_of_field[f]()
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    // A: "a0" and "a1"; B: "bee0", "bee11" and "third".
    if names_total[A]() != 4usize { os.exit(1) }
    if names_total[B]() != 14usize { os.exit(2) }
    if sizes_total[A]() != 5usize { os.exit(3) }
    if sizes_total[B]() != 11usize { os.exit(4) }
    ret ok
}
