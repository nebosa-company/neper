// Association and launch-agent plist text must be escaped; the identifiers that
// name those artifacts are intentionally stricter than arbitrary descriptions.
use e.fs
use e.mem
use e.os
use e.os.shell
use e.str

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if a[at] != b[at] { ret false }
        at += 1usize
    }
    ret true
}

fn contains(haystack: str, needle: str) -> bool {
    if needle.len > haystack.len { ret false }
    var at = 0usize
    while at + needle.len <= haystack.len {
        if same(haystack[at..at + needle.len], needle) { ret true }
        at += 1usize
    }
    ret false
}

fn main(a: *mem.Arena) -> err {
    let (escaped, escape_error) = shell.plist_escape(a, "&<>")
    if escape_error != ok || !same(escaped, "&amp;&lt;&gt;") { os.exit(2i32) }
    if shell.associate_file(a, ".nxml", "neper&invalid", "bad") != shell.Invalid { os.exit(3i32) }
    if shell.associate_file(a, ".nxml", ".bad", "bad") != shell.Invalid { os.exit(4i32) }
    if shell.associate_protocol(a, "bad&scheme", "bad") != shell.Invalid { os.exit(5i32) }
    if shell.startup_set(a, "bad&launch", true) != shell.Invalid { os.exit(6i32) }
    if shell.associate_file(a, ".nxml", "neper.xml.escape", "A & < B > C") != ok { os.exit(7i32) }
    let (home, home_error) = fs.home_dir(a)
    if home_error != ok { os.exit(8i32) }
    let (root, root_error) = str.concat(a, home, "/Library/Application Support/Neper/Associations/neper.xml.escape.app/Contents/Info.plist")
    if root_error != ok { os.exit(9i32) }
    let (plist, plist_error) = fs.read_file(a, root, 16384usize)
    if plist_error != ok || !contains(plist, "<string>A &amp; &lt; B &gt; C</string>") { os.exit(10i32) }
    if shell.dissociate_file(a, ".nxml", "neper.xml.escape") != ok { os.exit(11i32) }
    ret ok
}
