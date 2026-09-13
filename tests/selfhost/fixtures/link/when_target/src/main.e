// Section 6's `when`: a condition over `target.arch` and `target.os`, settled at compile
// time, both blocks type checked and the taken one emitted (D216). The exit code says
// which arms were taken: 10 for Windows, 20 for Linux, plus 1 for x64 through a
// negated, parenthesized `&&`, plus 2 through an `||` whose false side is a target that
// is not this one. A `when` without `else` on an untaken condition contributes nothing.
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
    ret total
}

fn main() {
    os.exit(code())
}
