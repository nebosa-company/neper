// Literal recursive search returns one-based byte positions and full matching lines.

use e.fs
use e.grep
use e.mem
use e.os
use e.str

fn main(a: *mem.Arena) -> err {
    let directory = "grep-d603"
    if fs.make_dirs(a, directory) != ok { os.exit(1i32) }
    if fs.write_file(a, "grep-d603/a.txt", "alpha needle one\nnone\nneedle end\n") != ok { os.exit(2i32) }
    if fs.write_file(a, "grep-d603/b.txt", "x needle y\n") != ok { os.exit(3i32) }
    let (index, index_error) = grep.build_index(a, directory)
    if index_error != ok || index.trigrams != 40u32 || !str.eq(index.root, directory) { os.exit(4i32) }
    let (matches, search_error) = grep.search_index(a, index, "needle")
    if search_error != ok || matches.len != 3usize { os.exit(5i32) }
    var line_sum = 0u32
    var column_sum = 0u32
    var at = 0usize
    while at < matches.len {
        line_sum += matches[at].line
        column_sum += matches[at].column
        if !str.contains(matches[at].text, "needle") { os.exit(6i32) }
        at += 1usize
    }
    if line_sum != 5u32 || column_sum != 11u32 { os.exit(7i32) }
    let (empty, empty_error) = grep.search(a, directory, "")
    if empty_error != grep.Invalid || empty.len != 0usize { os.exit(8i32) }
    if fs.remove_file(a, "grep-d603/a.txt") != ok || fs.remove_file(a, "grep-d603/b.txt") != ok || fs.remove_dir(a, directory) != ok { os.exit(9i32) }
    ret ok
}
