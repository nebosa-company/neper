// Project-root discovery and source-root module naming.

use e.mem
use e.os

error InvalidPath

type Project = struct {
    root: str,
    has_sources: bool,
}

fn is_separator(value: u8) -> bool {
    ret value == 47u8 || value == 92u8
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn path_byte_equal(a: u8, b: u8) -> bool {
    if is_separator(a) && is_separator(b) { ret true }
    ret a == b
}

fn parent(path: str) -> str {
    if path.len == 0usize { ret "." }
    if path.len == 1usize && is_separator(path[0usize]) { ret path }
    if path.len == 3usize && path[1usize] == 58u8 && is_separator(path[2usize]) { ret path }
    var end = path.len
    while end > 1usize && is_separator(path[end - 1usize]) {
        end = end - 1usize
    }
    var at = end
    while at > 0usize && !is_separator(path[at - 1usize]) {
        at = at - 1usize
    }
    if at == 0usize { ret "." }
    if at == 1usize { ret path[..1usize] }
    if at == 3usize && path[1usize] == 58u8 { ret path[..3usize] }
    ret path[..at - 1usize]
}

fn has_source_root(a: *mem.Arena, directory: str) -> (bool, err) {
    let checkpoint = mem.mark(a)
    let (entries, directory_error) = os.readdir(a, directory)
    if directory_error != ok {
        mem.reset(a, checkpoint)
        ret (false, directory_error)
    }
    var found = false
    for entry in entries {
        if entry.kind == .Dir && (same(entry.name, "lib") || same(entry.name, "src")) {
            found = true
        }
    }
    mem.reset(a, checkpoint)
    ret (found, ok)
}

fn discover(a: *mem.Arena, named_file: str) -> (Project, err) {
    let original = parent(named_file)
    var directory = original
    while true {
        let (found, discovery_error) = has_source_root(a, directory)
        if discovery_error != ok { ret (Project{ root: "", has_sources: false }, discovery_error) }
        if found { ret (Project{ root: directory, has_sources: true }, ok) }
        let next = parent(directory)
        if same(next, directory) { break }
        directory = next
    }
    ret (Project{ root: original, has_sources: false }, ok)
}

fn relative_under(path: str, root: str, source_root: str) -> (str, bool) {
    var offset = 0usize
    if !same(root, ".") {
        if path.len <= root.len { ret ("", false) }
        var i = 0usize
        while i < root.len {
            if !path_byte_equal(path[i], root[i]) { ret ("", false) }
            i += 1usize
        }
        offset = root.len
        if !is_separator(path[offset]) { ret ("", false) }
        offset += 1usize
    }
    if path.len <= offset + source_root.len { ret ("", false) }
    var segment = 0usize
    while segment < source_root.len {
        if path[offset + segment] != source_root[segment] { ret ("", false) }
        segment += 1usize
    }
    offset += source_root.len
    if offset >= path.len || !is_separator(path[offset]) { ret ("", false) }
    ret (path[offset + 1usize..], true)
}

fn without_extension(path: str) -> (str, err) {
    if path.len < 3usize || path[path.len - 2usize] != 46u8 || path[path.len - 1usize] != 101u8 {
        ret ("", InvalidPath)
    }
    ret (path[..path.len - 2usize], ok)
}

fn basename(path: str) -> str {
    var at = path.len
    while at > 0usize && !is_separator(path[at - 1usize]) {
        at = at - 1usize
    }
    ret path[at..]
}

fn module_name(a: *mem.Arena, project: Project, named_file: str) -> (str, err) {
    var relative = basename(named_file)
    var under_source_root = false
    if project.has_sources {
        let (lib_relative, under_lib) = relative_under(named_file, project.root, "lib")
        if under_lib {
            relative = lib_relative
            under_source_root = true
        } else {
            let (src_relative, under_src) = relative_under(named_file, project.root, "src")
            if under_src {
                relative = src_relative
                under_source_root = true
            }
        }
    }
    let (stem, extension_error) = without_extension(relative)
    if extension_error != ok { ret ("", extension_error) }
    if !under_source_root { ret (stem, ok) }
    let (name, allocation_error) = mem.alloc[u8](a, stem.len)
    if allocation_error != ok { ret ("", allocation_error) }
    var i = 0usize
    while i < stem.len {
        if is_separator(stem[i]) {
            name[i] = 46u8
        } else {
            name[i] = stem[i]
        }
        i += 1usize
    }
    ret (name, ok)
}
