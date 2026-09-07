// `io.printf[FMT](args...)` is `format` over a buffer of its own: a 4 KiB local under
// `mem.arena_from`, claimed by a flushing builder whose sink writes through
// `io.print`. No caller's arena is involved, so it takes none -- and the output goes
// to stdout, which is what the runner compares against.

use e.io

error Failed

fn main() -> err {
    try io.printf["plain\n"]()
    try io.printf["n={} s={} b={}\n"](42i64, "x", true)
    try io.printf["hex={x} bin={b}\n"](255u32, 5u32)
    try io.printf["f={} fixed={.2}\n"](1.5f64, 1.005f64)
    try io.printf["{{braced}}\n"]()
    // 20 chunks of 256 bytes is 5120, which does not fit the 4 KiB buffer, so the
    // builder drains through the sink partway and the tail follows it. The line
    // still arrives whole and in order, which is the only thing that says the drain
    // and the final write agree about where they are.
    let chunk = "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcd"
    if chunk.len != 256usize { ret Failed }
    try io.printf["{}{}{}{}{}{}{}{}{}{}{}{}{}{}{}{}{}{}{}{}\n"](chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk, chunk)

    // Many small calls in a row: each opens a buffer of its own, so nothing carries
    // between them and the digits run together in the order they were written.
    var at = 0usize
    while at < 500usize {
        try io.printf["{}"](at)
        at += 1usize
    }
    try io.printf["\n"]()
    ret ok
}
