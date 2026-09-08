// `e.path` is pure string work: every function takes the `Style` it applies, so a
// Windows path is taken apart the same way on Linux and the answers below hold on both
// platforms. That is what lets this fixture assert exact strings.
//
// The cases that earn their place are the ones a naive implementation gets wrong: a
// drive-relative Windows path has a root but is not absolute, a trailing separator does
// not make an empty name, a leading dot is a stem rather than an empty stem with an
// extension, `..` above a root is dropped but on a relative path is kept, and an
// absolute part discards everything joined before it.
use e.mem
use e.os
use e.path

error Failed
error AbsoluteBad
error SplitBad
error JoinBad
error NormalizeBad
error RelativeBad
error ExtBad

fn eq(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn check_split(p: str, style: path.Style, root: str, dir: str, base: str, stem: str, ext: str) -> err {
    let parts = path.split(p, style)
    if !eq(parts.root, root) { os.exit(20i32) }
    if !eq(parts.dir, dir) { os.exit(20i32) }
    if !eq(parts.base, base) { os.exit(20i32) }
    if !eq(parts.stem, stem) { os.exit(20i32) }
    if !eq(parts.ext, ext) { os.exit(20i32) }
    ret ok
}

fn check_join(a: *mem.Arena, parts: []const str, style: path.Style, want: str, id: i32) -> err {
    let (got, join_error) = path.join(a, parts, style)
    if join_error != ok { ret join_error }
    if !eq(got, want) { os.exit(30i32 + id) }
    ret ok
}

fn check_normalize(a: *mem.Arena, p: str, style: path.Style, want: str) -> err {
    let (got, normalize_error) = path.normalize(a, p, style)
    if normalize_error != ok { ret normalize_error }
    if !eq(got, want) { os.exit(40i32) }
    ret ok
}

fn check_relative(a: *mem.Arena, base: str, wanted_path: str, style: path.Style, want: str) -> err {
    let (got, relative_error) = path.relative(a, base, wanted_path, style)
    if relative_error != ok { ret relative_error }
    if !eq(got, want) { os.exit(50i32) }
    ret ok
}

fn main(a: *mem.Arena) -> err {
    // Separators and roots.
    if path.separator(.Posix) != 47u8 { os.exit(10i32) }
    if path.separator(.Windows) != 92u8 { os.exit(10i32) }
    if !path.is_absolute("/a/b", .Posix) { os.exit(10i32) }
    if path.is_absolute("a/b", .Posix) { os.exit(10i32) }
    if !path.is_absolute("C:\\a", .Windows) { os.exit(10i32) }
    if !path.is_absolute("C:/a", .Windows) { os.exit(10i32) }
    // A drive-relative path has a root but is not absolute.
    if path.is_absolute("C:a", .Windows) { os.exit(10i32) }
    if !path.is_absolute("\\\\server", .Windows) { os.exit(10i32) }
    // A backslash is an ordinary byte on Posix.
    if path.is_absolute("C:\\a", .Posix) { os.exit(10i32) }

    // Splitting.
    try check_split("/usr/lib/libc.so.6", .Posix, "/", "/usr/lib", "libc.so.6", "libc.so", ".6")
    try check_split("a/b/c.txt", .Posix, "", "a/b", "c.txt", "c", ".txt")
    try check_split("c.txt", .Posix, "", "", "c.txt", "c", ".txt")
    try check_split("/", .Posix, "/", "/", "", "", "")
    // A trailing separator does not make an empty name.
    try check_split("a/b/", .Posix, "", "a", "b", "b", "")
    // A leading dot is a stem, not an empty stem with an extension.
    try check_split("/etc/.gitignore", .Posix, "/", "/etc", ".gitignore", ".gitignore", "")
    try check_split("archive.tar.gz", .Posix, "", "", "archive.tar.gz", "archive.tar", ".gz")
    try check_split("C:\\dir\\file.txt", .Windows, "C:\\", "C:\\dir", "file.txt", "file", ".txt")

    // Joining, including an absolute part discarding what came before it.
    var two: [2]str = zero
    two[0usize] = "a"
    two[1usize] = "b"
    try check_join(a, two[..], .Posix, "a/b", 1i32)
    two[0usize] = "a/"
    two[1usize] = "b"
    try check_join(a, two[..], .Posix, "a/b", 2i32)
    two[0usize] = "a"
    two[1usize] = "/etc"
    try check_join(a, two[..], .Posix, "/etc", 3i32)
    two[0usize] = "/base"
    two[1usize] = "rel"
    try check_join(a, two[..], .Posix, "/base/rel", 4i32)

    // Normalising.
    try check_normalize(a, "a/./b", .Posix, "a/b")
    try check_normalize(a, "a/b/../c", .Posix, "a/c")
    try check_normalize(a, "a//b///c", .Posix, "a/b/c")
    try check_normalize(a, "/a/../../b", .Posix, "/b")
    try check_normalize(a, "../a", .Posix, "../a")
    try check_normalize(a, "a/../..", .Posix, "..")
    try check_normalize(a, ".", .Posix, ".")
    try check_normalize(a, "/", .Posix, "/")
    try check_normalize(a, "C:\\a\\..\\b", .Windows, "C:\\b")

    // Relating.
    try check_relative(a, "/a/b", "/a/b/c", .Posix, "c")
    try check_relative(a, "/a/b/c", "/a/b", .Posix, "..")
    try check_relative(a, "/a/b", "/a/x/y", .Posix, "../x/y")
    try check_relative(a, "/a/b", "/a/b", .Posix, ".")
    let (_, mixed_error) = path.relative(a, "/a", "b", .Posix)
    if mixed_error != path.Invalid { os.exit(70i32) }

    // Replacing an extension: gained, changed and removed.
    let (added, added_error) = path.replace_extension(a, "a/b", "txt", .Posix)
    if added_error != ok { ret added_error }
    if !eq(added, "a/b.txt") { os.exit(60i32) }
    let (changed, changed_error) = path.replace_extension(a, "a/b.md", ".txt", .Posix)
    if changed_error != ok { ret changed_error }
    if !eq(changed, "a/b.txt") { os.exit(60i32) }
    let (removed, removed_error) = path.replace_extension(a, "a/b.md", "", .Posix)
    if removed_error != ok { ret removed_error }
    if !eq(removed, "a/b") { os.exit(60i32) }
    ret ok
}
