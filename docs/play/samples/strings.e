// Strings are []const u8. Nothing allocates without an arena.

use e.mem
use e.str
use e.io

fn describe(a: *mem.Arena, name: str, count: u32) -> (str, err) {
    // The builder owns the top of the arena until str.done. If anything else
    // allocates from `a` in between, the next push returns str.NotOnTop
    // (checked in every build mode) instead of overwriting that allocation.
    var b = try str.builder(a, 64)
    try str.push(&b, name)
    try str.push(&b, " has ")
    try str.push_u32(&b, count)
    try str.push(&b, " modules")
    ret (str.done(&b), ok)
}

// main receives the root arena (spec §13); nothing here carves its own.
fn main(a: *mem.Arena, args: []str) -> err {
    let greeting = "hello" // []const u8, len 5, read-only
    let name: str = "neper"

    // Two parts.
    let msg = try str.concat(a, greeting, name)

    // Many parts, from a slice. targets is let-bound, so targets[0..] is a
    // []const str — which is what str.join takes.
    let targets = [_]str{ "x64", "aarch64", "spv" }
    let joined = try str.join(a, targets[0..], ", ")

    // Incremental, growing in place at the top of the arena.
    let line = try describe(a, name, 3)

    // Formatting: the format string is a comptime parameter, so arity and
    // types are checked at compile time and no parsing happens at runtime.
    try io.printf["{} | {} | {}\n"](msg, joined, line)

    if str.eq(name, "neper") { // never ==, which would compare ptr and len
        try io.print("names match\n")
    }

    ret ok
}
