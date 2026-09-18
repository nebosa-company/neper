// Recursive literal byte search over `e.fs`. Results retain matching file contents
// and walk paths in the caller arena; line and column are one-based byte positions.
// The frozen Index value carries only a root and trigram count, so indexed search
// validates that snapshot metadata and performs the same bounded fresh walk.

use e.fs
use e.mem
use e.path
use e.str

type Match = struct { path: str, line: u32, column: u32, text: str }
type Index = struct { root: str, trigrams: u32 }
error Invalid

fn at(bytes: []const u8, pattern: str, offset: usize) -> bool {
    if offset + pattern.len > bytes.len { ret false }
    var i = 0usize
    while i < pattern.len {
        if bytes[offset + i] != pattern[i] { ret false }
        i += 1usize
    }
    ret true
}

fn occurrences(bytes: []const u8, pattern: str) -> usize {
    var count = 0usize
    var offset = 0usize
    while offset + pattern.len <= bytes.len {
        if at(bytes, pattern, offset) { count += 1usize }
        offset += 1usize
    }
    ret count
}

fn build_index(a: *mem.Arena, root: str) -> (Index, err) {
    let options = fs.WalkOptions { recursive: true, follow_symlinks: false }
    let (created, walk_error) = fs.walk(a, root, options)
    if walk_error != ok { ret (zero, Invalid) }
    var walker = created
    var trigrams = 0u64
    while true {
        let (entry, present, next_error) = fs.walk_next_err(&walker)
        if next_error != ok {
            let ignored = fs.walk_close(&walker)
            ret (zero, Invalid)
        }
        if !present { break }
        if entry.kind == .File && entry.size >= 3u64 {
            trigrams += entry.size - 2u64
            if trigrams > 4294967295u64 {
                let ignored = fs.walk_close(&walker)
                ret (zero, Invalid)
            }
        }
    }
    let close_error = fs.walk_close(&walker)
    if close_error != ok { ret (zero, Invalid) }
    ret (Index { root: root, trigrams: u32(trigrams) }, ok)
}

fn search(a: *mem.Arena, root: str, pattern: str) -> ([]Match, err) {
    var none: []Match = zero
    if pattern.len == 0usize { ret (none, Invalid) }
    let call_mark = mem.mark(a)
    let options = fs.WalkOptions { recursive: true, follow_symlinks: false }
    let (created, walk_error) = fs.walk(a, root, options)
    if walk_error != ok { ret (none, Invalid) }
    var walker = created
    var total = 0usize
    while true {
        let (entry, present, next_error) = fs.walk_next_err(&walker)
        if next_error != ok {
            let ignored = fs.walk_close(&walker)
            mem.reset(a, call_mark)
            ret (none, Invalid)
        }
        if !present { break }
        if entry.kind == .File {
            let file_mark = mem.mark(a)
            let (bytes, read_error) = fs.read_file(a, entry.path, 0usize)
            if read_error != ok {
                let ignored = fs.walk_close(&walker)
                mem.reset(a, call_mark)
                ret (none, Invalid)
            }
            total += occurrences(bytes, pattern)
            mem.reset(a, file_mark)
        }
    }
    let close_error = fs.walk_close(&walker)
    if close_error != ok {
        mem.reset(a, call_mark)
        ret (none, Invalid)
    }
    let (matches, allocation_error) = mem.alloc[Match](a, total)
    if allocation_error != ok {
        mem.reset(a, call_mark)
        ret (none, allocation_error)
    }
    let (created_again, again_error) = fs.walk(a, root, options)
    if again_error != ok {
        mem.reset(a, call_mark)
        ret (none, Invalid)
    }
    walker = created_again
    var used = 0usize
    while true {
        let (entry, present, next_error) = fs.walk_next_err(&walker)
        if next_error != ok {
            let ignored = fs.walk_close(&walker)
            mem.reset(a, call_mark)
            ret (none, Invalid)
        }
        if !present { break }
        if entry.kind == .File {
            let file_mark = mem.mark(a)
            let (bytes, read_error) = fs.read_file(a, entry.path, 0usize)
            if read_error != ok {
                let ignored = fs.walk_close(&walker)
                mem.reset(a, call_mark)
                ret (none, Invalid)
            }
            let before = used
            var offset = 0usize
            var line = 1u32
            var line_start = 0usize
            while offset + pattern.len <= bytes.len {
                if at(bytes, pattern, offset) {
                    var line_end = offset
                    while line_end < bytes.len && bytes[line_end] != 10u8 && bytes[line_end] != 13u8 { line_end += 1usize }
                    matches[used] = Match { path: entry.path, line: line, column: u32(offset - line_start + 1usize), text: bytes[line_start..line_end] }
                    used += 1usize
                }
                if bytes[offset] == 10u8 {
                    line += 1u32
                    line_start = offset + 1usize
                }
                offset += 1usize
            }
            if before == used { mem.reset(a, file_mark) }
        }
    }
    let final_close = fs.walk_close(&walker)
    if final_close != ok {
        mem.reset(a, call_mark)
        ret (none, Invalid)
    }
    ret (matches[0usize..used], ok)
}

fn search_index(a: *mem.Arena, ix: Index, pattern: str) -> ([]Match, err) {
    if ix.root.len == 0usize { ret (zero, Invalid) }
    let (matches, search_error) = search(a, ix.root, pattern)
    ret (matches, search_error)
}
