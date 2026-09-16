use e.mem
use e.data.list
use e.str

// The lexical region and view rules' valid shapes (D354): a scratch region reset
// after its last use; a value allocated before the mark, which the reset leaves; a
// deferred reset; a view taken again after the push; a read through `&const`; a
// second mark inside the first.
fn count_after(a: *mem.Arena, text: str) -> (usize, err) {
    let kept = try mem.alloc[u8](a, 4usize)
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, text.len)
    mem.copy[u8](scratch, text)
    var total = 0usize
    for byte in scratch { total += usize(byte) }
    mem.reset(a, checkpoint)
    kept[0usize] = 1u8
    ret (total + usize(kept[0usize]), ok)
}

fn deferred(a: *mem.Arena) -> (usize, err) {
    let checkpoint = mem.mark(a)
    defer mem.reset(a, checkpoint)
    let scratch = try mem.alloc[u8](a, 8usize)
    scratch[7usize] = 7u8
    ret (usize(scratch[7usize]), ok)
}

fn nested(a: *mem.Arena) -> (usize, err) {
    let outer = mem.mark(a)
    let first = try mem.alloc[u8](a, 2usize)
    let inner = mem.mark(a)
    let second = try mem.alloc[u8](a, 2usize)
    second[0usize] = 2u8
    mem.reset(a, inner)
    first[0usize] = 1u8
    let total = usize(first[0usize])
    mem.reset(a, outer)
    ret (total, ok)
}

fn views(a: *mem.Arena) -> (usize, err) {
    var numbers = try list.init[u32](a, 1usize)
    try list.push[u32](&numbers, 1u32)
    let before = list.slice[u32](&numbers)
    let first = before[0usize]
    try list.push[u32](&numbers, 2u32)
    let after = list.slice[u32](&numbers)
    let stable = list.slice_const[u32](&numbers)
    ret (usize(first) + usize(after[1usize]) + stable.len, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (counted, count_error) = count_after(a, "abc")
    if count_error != ok { ret count_error }
    let (seven, defer_error) = deferred(a)
    if defer_error != ok { ret defer_error }
    let (one, nested_error) = nested(a)
    if nested_error != ok { ret nested_error }
    let (five, view_error) = views(a)
    if view_error != ok { ret view_error }
    if counted + seven + one + five != 0usize { ret ok }
    ret ok
}
