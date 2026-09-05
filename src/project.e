// Project-root discovery and source-root module naming.

use e.mem
use e.os

error InvalidPath
error InvalidTarget
error ModuleNotFound
error AmbiguousVariant

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

fn path_equal(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if !path_byte_equal(a[i], b[i]) { ret false }
        i += 1usize
    }
    ret true
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

fn target_suffix(value: str) -> bool {
    ret same(value, "windows") || same(value, "linux") || same(value, "macos") || same(value, "none") || same(value, "x64") || same(value, "x86") || same(value, "aarch64") || same(value, "spv") || same(value, "ptx")
}

fn without_target_suffix(stem: str) -> str {
    var at = stem.len
    while at > 0usize {
        at = at - 1usize
        if stem[at] == 46u8 {
            if target_suffix(stem[at + 1usize..]) { ret stem[..at] }
            ret stem
        }
    }
    ret stem
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
    let (raw_stem, extension_error) = without_extension(relative)
    if extension_error != ok { ret ("", extension_error) }
    let stem = without_target_suffix(raw_stem)
    if without_target_suffix(stem).len != stem.len { ret ("", InvalidPath) }
    if target_suffix(basename(stem)) { ret ("", InvalidPath) }
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

fn valid_arch(arch: str) -> bool {
    ret same(arch, "x64") || same(arch, "x86") || same(arch, "aarch64") || same(arch, "spv") || same(arch, "ptx")
}

fn valid_os(value: str) -> bool {
    ret same(value, "windows") || same(value, "linux") || same(value, "macos") || same(value, "none")
}

fn valid_target(arch: str, target_os: str) -> bool {
    if same(arch, "spv") || same(arch, "ptx") { ret same(target_os, "none") }
    if same(target_os, "none") { ret false }
    if same(arch, "x86") && same(target_os, "macos") { ret false }
    ret true
}

fn module_parts(module: str) -> (str, str, err) {
    if module.len == 0usize { ret ("", "", InvalidPath) }
    var last_dot = module.len
    var i = 0usize
    var segment_start = 0usize
    while i < module.len {
        if module[i] == 46u8 {
            if i == segment_start { ret ("", "", InvalidPath) }
            last_dot = i
            segment_start = i + 1usize
        }
        i += 1usize
    }
    if segment_start == module.len { ret ("", "", InvalidPath) }
    if last_dot == module.len {
        if target_suffix(module) { ret ("", "", InvalidPath) }
        ret ("", module, ok)
    }
    let stem = module[last_dot + 1usize..]
    if target_suffix(stem) { ret ("", "", InvalidPath) }
    ret (module[..last_dot], stem, ok)
}

fn source_directory(a: *mem.Arena, root: str, source_root: str, module_prefix: str) -> (str, err) {
    if root.len == 0usize || (!same(source_root, "lib") && !same(source_root, "src")) { ret ("", InvalidPath) }
    var root_separator = 1usize
    if root.len > 0usize && is_separator(root[root.len - 1usize]) { root_separator = 0usize }
    var prefix_separator = 0usize
    if module_prefix.len > 0usize { prefix_separator = 1usize }
    let length = root.len + root_separator + source_root.len + prefix_separator + module_prefix.len
    let (directory, allocation_error) = mem.alloc[u8](a, length)
    if allocation_error != ok { ret ("", allocation_error) }
    var at = 0usize
    var i = 0usize
    while i < root.len {
        directory[at] = root[i]
        at += 1usize
        i += 1usize
    }
    if root_separator == 1usize {
        directory[at] = 47u8
        at += 1usize
    }
    i = 0usize
    while i < source_root.len {
        if is_separator(source_root[i]) || source_root[i] == 46u8 { ret ("", InvalidPath) }
        directory[at] = source_root[i]
        at += 1usize
        i += 1usize
    }
    if prefix_separator == 1usize {
        directory[at] = 47u8
        at += 1usize
    }
    i = 0usize
    while i < module_prefix.len {
        if module_prefix[i] == 46u8 {
            directory[at] = 47u8
        } else {
            directory[at] = module_prefix[i]
        }
        at += 1usize
        i += 1usize
    }
    ret (directory, ok)
}

fn plain_source(name: str, stem: str) -> bool {
    if name.len != stem.len + 2usize { ret false }
    var i = 0usize
    while i < stem.len {
        if name[i] != stem[i] { ret false }
        i += 1usize
    }
    ret name[stem.len] == 46u8 && name[stem.len + 1usize] == 101u8
}

fn variant_source(name: str, stem: str, suffix: str) -> bool {
    if name.len != stem.len + suffix.len + 3usize { ret false }
    var i = 0usize
    while i < stem.len {
        if name[i] != stem[i] { ret false }
        i += 1usize
    }
    if name[stem.len] != 46u8 { ret false }
    i = 0usize
    while i < suffix.len {
        if name[stem.len + 1usize + i] != suffix[i] { ret false }
        i += 1usize
    }
    ret name[name.len - 2usize] == 46u8 && name[name.len - 1usize] == 101u8
}

fn source_path(a: *mem.Arena, directory: str, stem: str, suffix: str) -> (str, err) {
    var suffix_length = 0usize
    if suffix.len > 0usize { suffix_length = suffix.len + 1usize }
    let length = directory.len + stem.len + suffix_length + 3usize
    let (path, allocation_error) = mem.alloc[u8](a, length)
    if allocation_error != ok { ret ("", allocation_error) }
    var at = 0usize
    var i = 0usize
    while i < directory.len {
        path[at] = directory[i]
        at += 1usize
        i += 1usize
    }
    path[at] = 47u8
    at += 1usize
    i = 0usize
    while i < stem.len {
        path[at] = stem[i]
        at += 1usize
        i += 1usize
    }
    if suffix.len > 0usize {
        path[at] = 46u8
        at += 1usize
        i = 0usize
        while i < suffix.len {
            path[at] = suffix[i]
            at += 1usize
            i += 1usize
        }
    }
    path[at] = 46u8
    path[at + 1usize] = 101u8
    ret (path, ok)
}

fn select_source(a: *mem.Arena, root: str, source_root: str, module: str, arch: str, target_os: str) -> (str, err) {
    if !valid_arch(arch) || !valid_os(target_os) || !valid_target(arch, target_os) { ret ("", InvalidTarget) }
    let checkpoint = mem.mark(a)
    let (prefix, stem, parts_error) = module_parts(module)
    if parts_error != ok {
        mem.reset(a, checkpoint)
        ret ("", parts_error)
    }
    let (directory, path_error) = source_directory(a, root, source_root, prefix)
    if path_error != ok {
        mem.reset(a, checkpoint)
        ret ("", path_error)
    }
    let (entries, directory_error) = os.readdir(a, directory)
    if directory_error != ok {
        mem.reset(a, checkpoint)
        if directory_error == os.NotFound { ret ("", ModuleNotFound) }
        ret ("", directory_error)
    }
    var has_plain = false
    var has_arch = false
    var has_os = false
    for entry in entries {
        if entry.kind == .File || entry.kind == .Symlink {
            if plain_source(entry.name, stem) { has_plain = true }
            if variant_source(entry.name, stem, arch) { has_arch = true }
            if variant_source(entry.name, stem, target_os) { has_os = true }
        }
    }
    mem.reset(a, checkpoint)
    if has_arch && has_os { ret ("", AmbiguousVariant) }
    if !has_arch && !has_os && !has_plain { ret ("", ModuleNotFound) }
    let (stable_prefix, stable_stem, stable_parts_error) = module_parts(module)
    if stable_parts_error != ok { ret ("", stable_parts_error) }
    let (stable_directory, stable_path_error) = source_directory(a, root, source_root, stable_prefix)
    if stable_path_error != ok { ret ("", stable_path_error) }
    if has_arch {
        let (selected, selected_error) = source_path(a, stable_directory, stable_stem, arch)
        ret (selected, selected_error)
    }
    if has_os {
        let (selected, selected_error) = source_path(a, stable_directory, stable_stem, target_os)
        ret (selected, selected_error)
    }
    if has_plain {
        let (selected, selected_error) = source_path(a, stable_directory, stable_stem, "")
        ret (selected, selected_error)
    }
    ret ("", ModuleNotFound)
}
