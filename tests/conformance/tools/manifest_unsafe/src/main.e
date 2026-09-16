// `build-manifest --json`'s `unsafe` inventory (D355, D371, H27): every escape hatch
// of the program, declared or trusted -- an `@unsafe` function, a `@nocheck` block,
// an `extern fn`, a `mem.cast`, a `mem.bitcast` and a bare `union` -- with its kind,
// provenance, module, function and line. The comment and the string on the last
// lines spell two of them and are not sites.
use e.mem

type Bits = union { whole: u32, halves: [2]u16 }

@import("kernel32.dll", "GetCurrentProcessId")
extern fn raw_process_id() -> u32

@unsafe
fn peek(p: *const u32) -> u32 {
    ret *p
}

fn reinterpret(x: f32) -> u32 {
    ret mem.bitcast[u32](x)
}

fn erase(p: *u32) -> *void {
    ret mem.cast[*void](p)
}

fn main() {
    var cell = 7u32
    var seen = peek(&cell)
    @nocheck {
        seen = seen + reinterpret(1.5)
    }
    let gone = erase(&cell)
    // not a site: mem.cast[*void](gone)
    let spelled = "mem.bitcast[u32](x) is text"
}
