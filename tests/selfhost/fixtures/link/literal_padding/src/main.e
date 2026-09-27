// D1609: a struct literal's padding is zero, as `zero`'s is, and a tagged union literal's
// unused payload bytes too. Each check branches on those bytes, so under valgrind (the
// Linux suite) a literal that wrote only its fields is an uninitialised read even where
// the stack happened to hold zeros. Every value derives from the argument count, so none
// of it folds. Each check exits with its own code.

use e.io
use e.mem
use e.os

type Head = struct { a: u8, b: u64 }
type Tail = struct { b: u64, a: u8 }
type Nest = struct { flag: bool, inner: Head, last: u16 }
type Even = struct { x: f32, y: f32 }
type Length = union enum u8 { Auto, Px: f32, Wide: u64 }

fn bytes_of[T: type](p: *const T) -> []const u8 {
    let n = mem.size_of[T]()
    var over: mem.Arena = zero
    over.base = mem.cast[*u8](p)
    over.cap = n
    over.off = n
    ret mem.view(&over, 0usize, n)
}

fn zeros(bytes: []const u8, from: usize, to: usize) -> bool {
    var at = from
    while at < to {
        if bytes[at] != 0u8 { ret false }
        at += 1usize
    }
    ret true
}

fn check(s: usize) -> i32 {
    let small = u8(s + 1usize)
    let wide = u64(s + 2usize)
    // Padding between fields, and after the last.
    let head = Head { a: small, b: wide }
    let head_bytes = bytes_of[Head](&head)
    if head.a != small || head.b != wide { ret 1i32 }
    if !zeros(head_bytes, 1usize, 8usize) { ret 2i32 }
    let tail = Tail { b: wide, a: small }
    if tail.a != small || tail.b != wide { ret 3i32 }
    if !zeros(bytes_of[Tail](&tail), 9usize, 16usize) { ret 4i32 }
    // A literal inside a literal: the outer's padding and the inner's alike.
    let nest = Nest { flag: s == 0usize, inner: Head { a: small, b: wide }, last: u16(s + 3usize) }
    let nest_bytes = bytes_of[Nest](&nest)
    if nest.inner.b != wide || nest.last != u16(s + 3usize) { ret 5i32 }
    if !zeros(nest_bytes, 1usize, 8usize) || !zeros(nest_bytes, 9usize, 16usize) || !zeros(nest_bytes, 26usize, 32usize) { ret 6i32 }
    // No padding: the fields are the value.
    let even = Even { x: f32(s), y: f32(s + 1usize) }
    if even.x != f32(s) || even.y != f32(s + 1usize) { ret 7i32 }
    // A tagged union: the bytes after the tag, and a payload shorter than the widest.
    let auto: Length = .Auto
    if !zeros(bytes_of[Length](&auto), 1usize, 16usize) { ret 8i32 }
    let px = Length { Px: f32(s) }
    let px_bytes = bytes_of[Length](&px)
    if !zeros(px_bytes, 1usize, 8usize) || !zeros(px_bytes, 12usize, 16usize) { ret 9i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let code = check(args.len - 1usize)
    if code != 0i32 { os.exit(code) }
    ret io.print("literal padding ok\n")
}
