// `dis --json` (D233): one disassembly record per function, the machine bytes as hex.
// Wrapping arithmetic so a debug build embeds no trap and the bytes are path-independent.
use e.os
fn add(x: i32, y: i32) -> i32 {
    ret x +% y
}
fn main() {
    os.exit(add(2i32, 3i32))
}
