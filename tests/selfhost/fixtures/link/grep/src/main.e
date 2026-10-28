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
    // An index records the trigram snapshot of the tree it saw. Replacing a
    // three-byte file with a six-byte one makes a stale index reject instead of
    // searching the changed tree under the old metadata.
    if fs.write_file(a, "grep-d603/a.txt", "needle") != ok { os.exit(9i32) }
    let (stale, stale_error) = grep.search_index(a, index, "needle")
    if stale_error != grep.Invalid || stale.len != 0usize { os.exit(10i32) }
    let cr_directory = "grep-cr-d1168"
    if fs.make_dirs(a, cr_directory) != ok { os.exit(11i32) }
    if fs.write_file(a, "grep-cr-d1168/cr.txt", "first\rneedle one\rneedle two\r") != ok { os.exit(12i32) }
    let (cr_matches, cr_error) = grep.search(a, cr_directory, "needle")
    if cr_error != ok || cr_matches.len != 2usize { os.exit(13i32) }
    if cr_matches[0usize].line != 2u32 || cr_matches[0usize].column != 1u32 || !str.eq(cr_matches[0usize].text, "needle one") { os.exit(14i32) }
    if cr_matches[1usize].line != 3u32 || cr_matches[1usize].column != 1u32 || !str.eq(cr_matches[1usize].text, "needle two") { os.exit(15i32) }
    let crlf_directory = "grep-crlf-d1168"
    if fs.make_dirs(a, crlf_directory) != ok { os.exit(16i32) }
    if fs.write_file(a, "grep-crlf-d1168/crlf.txt", "first\r\nneedle line") != ok { os.exit(17i32) }
    let (crlf_matches, crlf_error) = grep.search(a, crlf_directory, "needle")
    if crlf_error != ok || crlf_matches.len != 1usize { os.exit(18i32) }
    if crlf_matches[0usize].line != 2u32 || crlf_matches[0usize].column != 1u32 || !str.eq(crlf_matches[0usize].text, "needle line") { os.exit(19i32) }
    if fs.remove_file(a, "grep-d603/a.txt") != ok || fs.remove_file(a, "grep-d603/b.txt") != ok || fs.remove_dir(a, directory) != ok { os.exit(20i32) }
    if fs.remove_file(a, "grep-cr-d1168/cr.txt") != ok || fs.remove_dir(a, cr_directory) != ok { os.exit(21i32) }
    if fs.remove_file(a, "grep-crlf-d1168/crlf.txt") != ok || fs.remove_dir(a, crlf_directory) != ok { os.exit(22i32) }
    ret ok
}
