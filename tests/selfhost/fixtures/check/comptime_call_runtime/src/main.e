// A `const` whose call reaches runtime state -- here an `extern` through `os.exit` --
// is refused, naming the constant and what it reached (D218).
use e.os

const CODE = pick(3i32)

fn pick(x: i32) -> i32 {
    if x > 2i32 { os.exit(x) }
    ret x
}

fn main() {}
