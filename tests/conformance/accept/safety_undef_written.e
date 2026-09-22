// The written forms of an `undef` value that holds a reference (D918, H03): every
// reference the type holds is written before the value is read, so the base and the
// length a bounds check works over are ones the program chose.
type Frame = struct { items: []const u8, count: usize }
type Link = struct { next: *Link, value: u64 }

// A field at a time, in any order, before the first read.
fn framed(source: []const u8) -> usize {
    var f: Frame = undef
    f.count = source.len
    f.items = source
    ret f.items.len + f.count
}

// The whole value at once.
fn replaced(source: []const u8) -> usize {
    var f: Frame = undef
    f = Frame { items: source, count: source.len }
    ret f.items.len
}

// The address of a value is not a read of what it holds, so a node may point at
// itself while it is still being written.
fn linked() -> u64 {
    var tail: Link = undef
    tail.next = &tail
    tail.value = 5u64
    ret tail.next.value
}

// A type holding no reference is unchanged: bytes are all it has.
fn scratch() -> u8 {
    var buffer: [16]u8 = undef
    buffer[0usize] = 7u8
    ret buffer[0usize]
}

fn main() -> i32 {
    var bytes: [4]u8 = zero
    let total = framed(bytes[0usize..4usize]) + replaced(bytes[0usize..4usize]) + usize(linked()) + usize(scratch())
    if total == 0usize { ret 1i32 }
    ret 0i32
}
