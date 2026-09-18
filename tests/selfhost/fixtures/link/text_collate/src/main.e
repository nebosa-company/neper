// Code-point order and overflow-free natural digit runs are deterministic on both hosts.

use e.os
use e.text.collate

fn main() -> err {
    if collate.codepoint_cmp("abc", "abc") != 0i32 || collate.codepoint_cmp("abc", "abd") >= 0i32 || collate.codepoint_cmp("z", "é") >= 0i32 { os.exit(1i32) }
    let folded = collate.Options { case_sensitive: false, numeric: true }
    if collate.natural_cmp("File2", "file10", folded) >= 0i32 { os.exit(2i32) }
    if collate.natural_cmp("file2", "file02", folded) >= 0i32 { os.exit(3i32) }
    if collate.natural_cmp("A", "a", folded) != 0i32 { os.exit(4i32) }
    let exact = collate.Options { case_sensitive: true, numeric: false }
    if collate.natural_cmp("A", "a", exact) >= 0i32 { os.exit(5i32) }
    if collate.natural_cmp("x9999999999999999999999999999999999999999", "x10000000000000000000000000000000000000000", folded) >= 0i32 { os.exit(6i32) }
    ret ok
}
