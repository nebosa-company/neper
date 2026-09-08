// Paths as pure strings. Nothing here asks the host anything: every function takes the
// `Style` it is to apply, so a Windows path can be taken apart on Linux and the answer
// is the same on both. That is what makes this module testable without a filesystem and
// what keeps `e.fs` the only place host behaviour is decided.

use e.mem

type Style = enum u8 { Posix, Windows }

type Parts = struct { root: str, dir: str, base: str, stem: str, ext: str }

error Invalid

fn separator(style: Style) -> u8 {
    if style == .Windows { ret 92u8 }
    ret 47u8
}

// Windows accepts either separator; Posix only its own, so a backslash there is an
// ordinary character in a name.
fn is_separator(byte: u8, style: Style) -> bool {
    if byte == 47u8 { ret true }
    if style == .Windows && byte == 92u8 { ret true }
    ret false
}

fn is_drive_letter(byte: u8) -> bool {
    if byte >= 65u8 && byte <= 90u8 { ret true }
    ret byte >= 97u8 && byte <= 122u8
}

// The part of a path that cannot be walked out of: `/` on Posix, and on Windows a
// drive with or without a separator, or the leading pair of a UNC name.
fn root_length(path: str, style: Style) -> usize {
    if path.len == 0usize { ret 0usize }
    if style == .Windows {
        if path.len >= 2usize && is_separator(path[0usize], style) && is_separator(path[1usize], style) {
            ret 2usize
        }
        if path.len >= 2usize && is_drive_letter(path[0usize]) && path[1usize] == 58u8 {
            if path.len >= 3usize && is_separator(path[2usize], style) { ret 3usize }
            ret 2usize
        }
    }
    if is_separator(path[0usize], style) { ret 1usize }
    ret 0usize
}

// A drive-relative Windows path (`C:file`) has a root but is not absolute: it is
// resolved against that drive's own current directory.
fn is_absolute(path: str, style: Style) -> bool {
    let root = root_length(path, style)
    if root == 0usize { ret false }
    ret is_separator(path[root - 1usize], style)
}

fn split(path: str, style: Style) -> Parts {
    let root = root_length(path, style)
    // Trailing separators are not part of the name: `a/b/` names `b`.
    var end = path.len
    while end > root && is_separator(path[end - 1usize], style) { end = end - 1usize }
    var start = end
    while start > root && !is_separator(path[start - 1usize], style) { start = start - 1usize }
    var directory_end = start
    while directory_end > root && is_separator(path[directory_end - 1usize], style) { directory_end = directory_end - 1usize }
    if directory_end < root { directory_end = root }
    let base = path[start..end]
    // The extension is the last dot inside the name, and a leading dot is not one:
    // `.gitignore` is a stem, not an empty stem with an extension.
    var dot = base.len
    var at = base.len
    while at > 1usize {
        at = at - 1usize
        if base[at] == 46u8 {
            dot = at
            break
        }
    }
    var stem_text = base
    var extension_text = ""
    if dot < base.len {
        stem_text = base[0usize..dot]
        extension_text = base[dot..base.len]
    }
    ret Parts { root: path[0usize..root], dir: path[0usize..directory_end], base: base, stem: stem_text, ext: extension_text }
}

fn basename(path: str, style: Style) -> str {
    let parts = split(path, style)
    ret parts.base
}

fn dirname(path: str, style: Style) -> str {
    let parts = split(path, style)
    ret parts.dir
}

fn extension(path: str, style: Style) -> str {
    let parts = split(path, style)
    ret parts.ext
}

fn stem(path: str, style: Style) -> str {
    let parts = split(path, style)
    ret parts.stem
}

fn copy_into(destination: []u8, at: usize, text: str) -> usize {
    var offset = 0usize
    while offset < text.len {
        destination[at + offset] = text[offset]
        offset += 1usize
    }
    ret at + text.len
}

// An absolute part discards everything before it, which is what makes `join` usable for
// resolving a possibly-absolute argument against a base.
fn join(a: *mem.Arena, parts: []const str, style: Style) -> (str, err) {
    var first = 0usize
    var at = 0usize
    while at < parts.len {
        if is_absolute(parts[at], style) { first = at }
        at += 1usize
    }
    var total = 0usize
    at = first
    while at < parts.len {
        if parts[at].len != 0usize { total += parts[at].len + 1usize }
        at += 1usize
    }
    if total == 0usize { ret ("", ok) }
    let (buffer, allocation_error) = mem.alloc[u8](a, total)
    if allocation_error != ok { ret ("", allocation_error) }
    var written = 0usize
    at = first
    while at < parts.len {
        let part = parts[at]
        if part.len != 0usize {
            if written != 0usize && !is_separator(buffer[written - 1usize], style) {
                buffer[written] = separator(style)
                written += 1usize
            }
            var offset = 0usize
            // A part that begins with a separator would double the one just written.
            if written != 0usize {
                while offset < part.len && is_separator(part[offset], style) { offset += 1usize }
            }
            written = copy_into(buffer, written, part[offset..part.len])
        }
        at += 1usize
    }
    ret (buffer[0usize..written], ok)
}

// `.` is dropped and `..` cancels the component before it, except where there is none
// left to cancel: above a root there is nothing, so it is dropped, and on a relative
// path it has to be kept because the caller's own directory decides what it means.
fn normalize(a: *mem.Arena, path: str, style: Style) -> (str, err) {
    let root = root_length(path, style)
    let absolute = is_absolute(path, style)
    let (buffer, allocation_error) = mem.alloc[u8](a, path.len + 1usize)
    if allocation_error != ok { ret ("", allocation_error) }
    var written = copy_into(buffer, 0usize, path[0usize..root])
    let body_start = written
    var at = root
    while at < path.len {
        while at < path.len && is_separator(path[at], style) { at += 1usize }
        var end = at
        while end < path.len && !is_separator(path[end], style) { end = end + 1usize }
        if end > at {
            let component = path[at..end]
            if same_text(component, ".") {
                at = end
                continue
            }
            if same_text(component, "..") {
                // Walk back over the last component, if this path has one to give.
                var back = written
                while back > body_start && !is_separator(buffer[back - 1usize], style) { back = back - 1usize }
                var previous_start = back
                if back > body_start { back = back - 1usize }
                let previous = buffer[previous_start..written]
                if written > body_start && !same_slice(previous, "..") {
                    written = back
                    at = end
                    continue
                }
                if absolute {
                    at = end
                    continue
                }
            }
            if written > body_start || (root != 0usize && !absolute) {
                buffer[written] = separator(style)
                written += 1usize
            }
            written = copy_into(buffer, written, component)
        }
        at = end
    }
    if written == 0usize { ret (".", ok) }
    if written == root && root != 0usize && !absolute { ret (buffer[0usize..written], ok) }
    ret (buffer[0usize..written], ok)
}

// How to get from `base` to `target_path`, both read under one style. Two paths that
// disagree about being absolute have no relation to express.
fn relative(a: *mem.Arena, base: str, target_path: str, style: Style) -> (str, err) {
    if is_absolute(base, style) != is_absolute(target_path, style) { ret ("", Invalid) }
    let (from_text, from_error) = normalize(a, base, style)
    if from_error != ok { ret ("", from_error) }
    let (to_text, to_error) = normalize(a, target_path, style)
    if to_error != ok { ret ("", to_error) }
    let from_root = root_length(from_text, style)
    let to_root = root_length(to_text, style)
    if from_root != to_root { ret ("", Invalid) }
    if !same_text(from_text[0usize..from_root], to_text[0usize..to_root]) { ret ("", Invalid) }
    // Skip the components the two share.
    var from_at = from_root
    var to_at = to_root
    while true {
        let (from_component, from_next) = next_component(from_text, from_at, style)
        let (to_component, to_next) = next_component(to_text, to_at, style)
        if from_component.len == 0usize || to_component.len == 0usize { break }
        if !same_text(from_component, to_component) { break }
        from_at = from_next
        to_at = to_next
    }
    // One `..` per component left in `base`, then what is left of the target.
    var ups = 0usize
    var scan = from_at
    while true {
        let (component, next) = next_component(from_text, scan, style)
        if component.len == 0usize { break }
        if !same_text(component, ".") { ups += 1usize }
        scan = next
    }
    let remainder = to_text[to_at..to_text.len]
    var total = ups * 3usize + remainder.len + 1usize
    let (buffer, buffer_error) = mem.alloc[u8](a, total + 1usize)
    if buffer_error != ok { ret ("", buffer_error) }
    var written = 0usize
    var placed = 0usize
    while placed < ups {
        if written != 0usize {
            buffer[written] = separator(style)
            written += 1usize
        }
        written = copy_into(buffer, written, "..")
        placed += 1usize
    }
    var offset = 0usize
    while offset < remainder.len && is_separator(remainder[offset], style) { offset += 1usize }
    let tail = remainder[offset..remainder.len]
    if tail.len != 0usize {
        if written != 0usize {
            buffer[written] = separator(style)
            written += 1usize
        }
        written = copy_into(buffer, written, tail)
    }
    if written == 0usize { ret (".", ok) }
    ret (buffer[0usize..written], ok)
}

fn next_component(path: str, from: usize, style: Style) -> (str, usize) {
    var at = from
    while at < path.len && is_separator(path[at], style) { at += 1usize }
    var end = at
    while end < path.len && !is_separator(path[end], style) { end = end + 1usize }
    ret (path[at..end], end)
}

// The extension is replaced, not appended: a name with none gains one, and an empty
// replacement removes the one there was.
fn replace_extension(a: *mem.Arena, path: str, ext: str, style: Style) -> (str, err) {
    let parts = split(path, style)
    if parts.base.len == 0usize { ret ("", Invalid) }
    let keep = path.len - parts.ext.len
    var total = keep + ext.len + 1usize
    let (buffer, allocation_error) = mem.alloc[u8](a, total)
    if allocation_error != ok { ret ("", allocation_error) }
    var written = copy_into(buffer, 0usize, path[0usize..keep])
    if ext.len != 0usize {
        if ext[0usize] != 46u8 {
            buffer[written] = 46u8
            written += 1usize
        }
        written = copy_into(buffer, written, ext)
    }
    ret (buffer[0usize..written], ok)
}

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn same_slice(left: []const u8, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}
