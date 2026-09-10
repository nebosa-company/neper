// A branch whose condition is settled at compile time has one arm, and the other is not code:
// it is never checked and never emitted. Only a `meta` question can settle one (D138), which is
// narrow on purpose -- no condition an ordinary program writes is folded by accident.
//
// The two things that could not be written before are both here. A walk over `meta.fields[T]()`
// where the fields differ in kind: without the fold, the arm for an integer still had to type
// check for the iteration whose field is a `str`. And a generic that recurses on
// `meta.element_type[T]()`: without the fold the recursion has no base case, because the guard
// that would stop it was still live.

use e.mem
use e.meta
use e.os
use e.str

error Failed

type Mixed = struct { count: i64, label: str, flag: bool }
type Pair = struct { left: u8, right: []const u8 }

// One walk, three field kinds, three arms that do not type check for each other's types.
fn measure[T: type](v: *const T) -> usize {
    var total = 0usize
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](v)
        if meta.kind[f.ty]() == .Int {
            total += usize(slot)
        } else {
        if meta.kind[f.ty]() == .Slice {
            total += slot.len
        } else {
            if slot { total += 100usize }
        }
        }
    }
    ret total
}

// `!=` folds as well as `==`.
fn non_integers[T: type]() -> usize {
    var total = 0usize
    for f in meta.fields[T]() {
        if meta.kind[f.ty]() != .Int { total += 1usize }
    }
    ret total
}

// A length is a number, so the same fold settles an ordinary integer comparison. Written with
// the question on the right, which is the other side the fold looks at -- a bare `.Int` there
// has no type to be read against and does not type check at all, so only a number reaches it.
// `T` must still be an array: a folded condition is an expression that has to check like any
// other, and only the arm it does not choose is excused.
fn is_pair[T: type]() -> bool {
    if 2usize == meta.array_len[T]() { ret true }
    ret false
}

// The recursion that had no base case: the arm holding the call is gone once the element is no
// longer an array, so the walk stops instead of instantiating forever.
fn depth[T: type]() -> usize {
    if meta.kind[T]() == .Array { ret 1usize + depth[meta.element_type[T]()]() }
    ret 0usize
}

// A struct is not an array, so this instantiates once and the recursive arm never exists.
fn nested_depth[T: type]() -> usize {
    var deepest = 0usize
    for f in meta.fields[T]() {
        let here = depth[f.ty]()
        if here > deepest { deepest = here }
    }
    ret deepest
}

// Ordinary control flow is untouched: this condition is not a `meta` question, so both arms
// stay, and which one runs is decided while the program runs.
fn runtime_choice(n: i64) -> i64 {
    if n > 10i64 { ret n * 2i64 }
    ret n + 1i64
}

fn main(a: *mem.Arena) -> err {
    // Every arm runs for the field it was written for: 5 from the integer, 3 from the slice's
    // length, 100 from the bool. A fold that always took one arm could not reach 108.
    var m = Mixed { count: 5i64, label: "abc", flag: true }
    if measure[Mixed](&m) != 108usize { os.exit(10i32) }
    // The same walk over a different struct, so the arms are chosen per instantiation and not
    // once for the template. Its fields are of the same two kinds in the other order.
    var p = Pair { left: 7u8, right: "wxyz" }
    if measure[Pair](&p) != 11usize { os.exit(11i32) }

    if non_integers[Mixed]() != 2usize { os.exit(12i32) }

    if !is_pair[[2]u8]() { os.exit(20i32) }
    if is_pair[[3]u8]() { os.exit(21i32) }

    if depth[u8]() != 0usize { os.exit(30i32) }
    if depth[[4]u8]() != 1usize { os.exit(31i32) }
    if depth[[2][4]u8]() != 2usize { os.exit(32i32) }
    if depth[[2][2][4]u64]() != 3usize { os.exit(33i32) }
    if nested_depth[Mixed]() != 0usize { os.exit(34i32) }

    if runtime_choice(4i64) != 5i64 { os.exit(40i32) }
    if runtime_choice(40i64) != 80i64 { os.exit(41i32) }
    ret ok
}
