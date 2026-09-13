// Section 6's `when`: a condition over `target.arch` and `target.os`, settled at compile
// time, both blocks type checked and the taken one emitted (D216). The exit code says
// which arms were taken: 10 for Windows, 20 for Linux, plus 1 for x64 through a
// negated, parenthesized `&&`, plus 2 through an `||` whose false side is a target that
// is not this one, plus 4 through a condition the interpreter evaluates (D220). A `when`
// without `else` on an untaken condition contributes nothing.
use e.os

fn code() -> i32 {
    var total = 0i32
    when target.os == .Windows {
        total += 10i32
    } else {
        total += 20i32
    }
    when !(target.arch != .X64 && target.os != .Macos) {
        total += 1i32
    }
    when .Macos == target.os || target.arch == .X64 {
        total += 2i32
    }
    when target.os == .Macos {
        total += 100i32
    }
    // A condition that is not about the target is section 9's comptime evaluation
    // (D220): a constant compared, and a call the interpreter runs.
    when LEVEL > 2i64 && enabled(LEVEL) {
        total += 4i32
    }
    when enabled(1i64) {
        total += 100i32
    }
    ret total
}

const LEVEL = 3i64

fn enabled(level: i64) -> bool {
    ret level % 3i64 == 0i64
}

fn main() {
    os.exit(code())
}
