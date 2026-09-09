// Paths as pure strings. Nothing here asks the host anything: every function takes the
// `Style` it is to apply, so a Windows path can be taken apart on Linux and the answer
// is the same on both. That is what makes this module testable without a filesystem and
// what keeps `e.fs` the only place host behaviour is decided.

use e.mem

type Style = enum u8 { Posix, Windows }

type Parts = struct { root: str, dir: str, base: str, stem: str, ext: str }

error Invalid
error TooLarge

type Glob = struct { state: *const void }
type GlobOptions = struct { style: Style, case_sensitive: bool, max_pattern_bytes: usize, max_steps: usize }

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

// --- Globs.
//
// Pure matching over relative paths, and no filesystem: a pattern that matches says the two
// strings correspond, never that anything exists or is contained anywhere. Pattern separators
// are always `/`; the path's separators are whatever its `Style` says, so one compiled pattern
// matches Windows and Posix spellings of the same relative path.

// The compiled pattern. The pattern is copied into the arena rather than referenced, so the
// `Glob` does not depend on the caller keeping their string alive.
type GlobState = struct { pattern: str, style: Style, case_sensitive: bool, max_steps: usize }

// The work a single match is allowed to do, carried through the matcher so a limit reached deep
// inside stops the whole thing rather than being reported as "no match".
type Matcher = struct { case_sensitive: bool, steps: usize, max_steps: usize, exhausted: bool }

fn charge(m: *Matcher, amount: usize) -> bool {
    // A zero limit is no limit: a caller who wants one sets it, and a zeroed `GlobOptions`
    // should not refuse every pattern it is given.
    if m.max_steps == 0usize { ret true }
    m.steps += amount
    if m.steps > m.max_steps {
        m.exhausted = true
        ret false
    }
    ret true
}

fn fold_byte(byte: u8) -> u8 {
    if byte >= 65u8 && byte <= 90u8 { ret byte + 32u8 }
    ret byte
}

fn equal_byte(left: u8, right: u8, case_sensitive: bool) -> bool {
    if case_sensitive { ret left == right }
    ret fold_byte(left) == fold_byte(right)
}

// A range holds a byte if it holds it as written, or -- when case is being folded -- if the
// other case of it falls inside. Comparing folded bounds instead would turn `[A-z]` into
// something else entirely, and `[0-9]` is unaffected either way.
fn in_range(byte: u8, low: u8, high: u8, case_sensitive: bool) -> bool {
    if byte >= low && byte <= high { ret true }
    if case_sensitive { ret false }
    var flipped = byte
    if byte >= 65u8 && byte <= 90u8 { flipped = byte + 32u8 }
    if byte >= 97u8 && byte <= 122u8 { flipped = byte - 32u8 }
    ret flipped >= low && flipped <= high
}

// Where a bracket class ends. A `]` first inside the class is a literal one, which is how this
// syntax has always spelled it -- there is no escape character, because the fence names none.
fn class_end(pattern: str, open: usize) -> (usize, bool) {
    var at = open + 1usize
    if at < pattern.len && pattern[at] == 33u8 { at += 1usize }
    if at < pattern.len && pattern[at] == 93u8 { at += 1usize }
    while at < pattern.len && pattern[at] != 93u8 { at += 1usize }
    if at >= pattern.len { ret (0usize, false) }
    ret (at, true)
}

fn class_matches(pattern: str, open: usize, close: usize, byte: u8, case_sensitive: bool) -> bool {
    var at = open + 1usize
    var negated = false
    if at < close && pattern[at] == 33u8 {
        negated = true
        at += 1usize
    }
    var matched = false
    while at < close {
        // A `-` between two members is a range; first or last in the class it is a literal.
        if at + 2usize < close && pattern[at + 1usize] == 45u8 {
            if in_range(byte, pattern[at], pattern[at + 2usize], case_sensitive) { matched = true }
            at += 3usize
        } else {
            if equal_byte(byte, pattern[at], case_sensitive) { matched = true }
            at += 1usize
        }
    }
    if negated { ret !matched }
    ret matched
}

// One component against one name. `*` and `?` stay inside the component, which is what makes
// them different from `**` and is the whole reason matching is done a component at a time.
//
// The backtracking is the two-cursor kind rather than recursion: on a mismatch the last `*`
// gives up one more byte to the name and the scan resumes after it. That needs no stack and
// cannot run away, which matters in a module that allocates nothing while matching.
fn match_component(m: *Matcher, pattern: str, name: str) -> bool {
    var p = 0usize
    var s = 0usize
    var star_p = 0usize
    var star_s = 0usize
    var has_star = false
    while s < name.len {
        if !charge(m, 1usize) { ret false }
        var advanced = false
        if p < pattern.len {
            if pattern[p] == 42u8 {
                // A run of them is one of them.
                while p < pattern.len && pattern[p] == 42u8 { p += 1usize }
                has_star = true
                star_p = p
                star_s = s
                advanced = true
            } else {
                if pattern[p] == 63u8 {
                    p += 1usize
                    s += 1usize
                    advanced = true
                } else {
                    if pattern[p] == 91u8 {
                        let (close, valid) = class_end(pattern, p)
                        if valid && class_matches(pattern, p, close, name[s], m.case_sensitive) {
                            p = close + 1usize
                            s += 1usize
                            advanced = true
                        }
                    } else {
                        if equal_byte(name[s], pattern[p], m.case_sensitive) {
                            p += 1usize
                            s += 1usize
                            advanced = true
                        }
                    }
                }
            }
        }
        if !advanced {
            if !has_star { ret false }
            star_s += 1usize
            s = star_s
            p = star_p
        }
    }
    // What is left of the pattern can only be stars, and stars are allowed to match nothing.
    while p < pattern.len && pattern[p] == 42u8 { p += 1usize }
    ret p == pattern.len
}

// The next component at or after `from`, and where to look for the one after it. Separate from
// `next_component` above, which the older functions use: this one says whether it found anything
// rather than answering with an empty string, and it skips what a glob has to skip. Empty
// components are skipped, so `a//b` and `a/b/` are both `a/b`; so is `./a`, since `.` names the
// directory the relative path is already relative to.
fn glob_next(text: str, from: usize, style: Style) -> (str, usize, bool) {
    var start = from
    while start < text.len {
        if !is_separator(text[start], style) { break }
        start += 1usize
    }
    if start >= text.len { ret ("", text.len, false) }
    var end = start
    while end < text.len && !is_separator(text[end], style) { end += 1usize }
    if end - start == 1usize && text[start] == 46u8 {
        let (skipped, after, found) = glob_next(text, end, style)
        ret (skipped, after, found)
    }
    ret (text[start..end], end, true)
}

fn is_parent(component: str) -> bool {
    if component.len != 2usize { ret false }
    ret component[0usize] == 46u8 && component[1usize] == 46u8
}

fn is_double_star(component: str) -> bool {
    if component.len != 2usize { ret false }
    ret component[0usize] == 42u8 && component[1usize] == 42u8
}

// A relative path with nothing above it in it. Both the pattern and the path have to be one:
// an absolute path is not what a glob is for, and a `..` would be asking about containment,
// which pure matching cannot answer.
fn glob_path_ok(text: str, style: Style) -> bool {
    if is_absolute(text, .Posix) { ret false }
    if is_absolute(text, .Windows) { ret false }
    if root_length(text, .Windows) != 0usize { ret false }
    var at = 0usize
    while true {
        let (component, after, found) = glob_next(text, at, style)
        if !found { break }
        if is_parent(component) { ret false }
        at = after
    }
    ret true
}

fn glob(a: *mem.Arena, pattern: str, options: GlobOptions) -> (Glob, err) {
    var compiled: Glob = zero
    // A zero limit is no limit, the same as `max_steps`.
    if options.max_pattern_bytes != 0usize && pattern.len > options.max_pattern_bytes {
        ret (compiled, TooLarge)
    }
    // A pattern is always `/`-separated whatever the paths it will be matched against are, so
    // it is read with the one style regardless of the option.
    if !glob_path_ok(pattern, .Posix) { ret (compiled, Invalid) }
    var components = 0usize
    var at = 0usize
    while true {
        let (component, after, found) = glob_next(pattern, at, .Posix)
        if !found { break }
        components += 1usize
        // Every class has to close. A pattern that cannot be read is refused when it is
        // compiled rather than quietly failing to match later.
        var scan = 0usize
        while scan < component.len {
            if component[scan] == 91u8 {
                let (close, valid) = class_end(component, scan)
                if !valid { ret (compiled, Invalid) }
                scan = close + 1usize
            } else {
                scan += 1usize
            }
        }
        at = after
    }
    // A pattern with no components at all matches nothing and is not a pattern.
    if components == 0usize { ret (compiled, Invalid) }
    let (copy, copy_error) = mem.alloc[u8](a, pattern.len)
    if copy_error != ok { ret (compiled, copy_error) }
    var index = 0usize
    while index < pattern.len {
        copy[index] = pattern[index]
        index += 1usize
    }
    let (state, state_error) = mem.alloc[GlobState](a, 1usize)
    if state_error != ok { ret (compiled, state_error) }
    state[0usize].pattern = copy[0usize..pattern.len]
    state[0usize].style = options.style
    state[0usize].case_sensitive = options.case_sensitive
    state[0usize].max_steps = options.max_steps
    compiled.state = mem.cast[*const void](&state[0usize])
    ret (compiled, ok)
}

// The same two-cursor backtracking as within a component, one level up: a whole `**` component
// gives up one more component of the path each time the rest of the pattern fails after it.
fn glob_match(pattern: *const Glob, path: str) -> (bool, err) {
    let state = mem.cast[*const GlobState](pattern.state)
    if !glob_path_ok(path, state.style) { ret (false, Invalid) }
    var m: Matcher = zero
    m.case_sensitive = state.case_sensitive
    m.max_steps = state.max_steps
    var pattern_at = 0usize
    var path_at = 0usize
    var star_pattern = 0usize
    var star_path = 0usize
    var has_star = false
    while true {
        let (name, path_after, has_name) = glob_next(path, path_at, state.style)
        if !has_name { break }
        if !charge(&m, 1usize) { ret (false, TooLarge) }
        let (component, pattern_after, has_component) = glob_next(state.pattern, pattern_at, .Posix)
        var advanced = false
        if has_component {
            if is_double_star(component) {
                has_star = true
                star_pattern = pattern_after
                star_path = path_at
                pattern_at = pattern_after
                advanced = true
            } else {
                if match_component(&m, component, name) {
                    pattern_at = pattern_after
                    path_at = path_after
                    advanced = true
                }
            }
        }
        if m.exhausted { ret (false, TooLarge) }
        if !advanced {
            if !has_star { ret (false, ok) }
            // The `**` takes one more component of the path, and the rest of the pattern is
            // tried again from there.
            let (given, given_after, given_found) = glob_next(path, star_path, state.style)
            if !given_found { ret (false, ok) }
            star_path = given_after
            path_at = given_after
            pattern_at = star_pattern
        }
    }
    // A `**` at the end of the pattern matches the nothing that is left.
    while true {
        let (component, pattern_after, has_component) = glob_next(state.pattern, pattern_at, .Posix)
        if !has_component { break }
        if !is_double_star(component) { ret (false, ok) }
        pattern_at = pattern_after
    }
    ret (true, ok)
}
