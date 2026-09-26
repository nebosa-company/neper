// `patch SPEC` (D1455): exact-text edits for the working tree, written in neper so
// the patches the sessions make no longer need Python. SPEC holds blocks:
//
//   @@@ path/to/file.e
//   <<<
//   the old text, exactly (any number of lines)
//   ===
//   the new text
//   >>>
//
// Every old text must stand exactly once in its file (the spec's line ends are
// taken as the file's own, LF or CRLF). Nothing is written unless every edit of
// every file applies; then each file is written whole. It prints one line per file.
use e.fs
use e.io
use e.mem
use e.os
use e.str as string

const MAX_FILES: usize = 16usize
const MAX_EDITS: usize = 256usize
const MAX_BYTES: usize = 67108864usize

type Edit = struct { file: usize, old: str, new: str }

fn fail(message: str) -> err {
    try io.print("patch: ")
    try io.print(message)
    try io.print("\n")
    os.exit(1i32)
    ret ok
}

// `text` with every LF made CRLF.
fn crlf(a: *mem.Arena, text: str) -> (str, err) {
    let lines = string.count(text, "\n")
    let (out, out_error) = mem.alloc[u8](a, text.len + lines)
    if out_error != ok { ret ("", out_error) }
    var n = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            out[n] = 13u8
            n += 1usize
        }
        out[n] = text[i]
        n += 1usize
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// The text between the line after `open` and `marker` (its closing line with the
// line ends round it), from `at`; and where the search goes on after `marker`.
fn section(spec: str, at: usize, open: str, marker: str) -> (str, usize, bool) {
    if !string.starts_with(spec[at..spec.len], open) { ret ("", at, false) }
    let body = at + open.len + 1usize
    let (end, found) = string.find_from(spec, marker, body - 1usize)
    if !found { ret ("", at, false) }
    var text = ""
    if end >= body { text = spec[body..end] }
    ret (text, end + marker.len, true)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret fail("usage: patch SPEC") }
    let (raw, raw_error) = fs.read_file(a, args[1usize], MAX_BYTES)
    if raw_error != ok { ret fail("the spec cannot be read") }
    // The spec is read with LF line ends whatever it was written with.
    let (spec_bytes, spec_error) = mem.alloc[u8](a, raw.len + 1usize)
    if spec_error != ok { ret fail("out of memory") }
    var n = 0usize
    var r = 0usize
    while r < raw.len {
        if raw[r] != 13u8 {
            spec_bytes[n] = raw[r]
            n += 1usize
        }
        r += 1usize
    }
    if n == 0usize || spec_bytes[n - 1usize] != 10u8 {
        spec_bytes[n] = 10u8
        n += 1usize
    }
    let spec: str = spec_bytes[0usize..n]
    let (paths, paths_error) = mem.alloc[str](a, MAX_FILES)
    let (texts, texts_error) = mem.alloc[str](a, MAX_FILES)
    let (windows, windows_error) = mem.alloc[bool](a, MAX_FILES)
    let (edits, edits_error) = mem.alloc[Edit](a, MAX_EDITS)
    if paths_error != ok || texts_error != ok || windows_error != ok || edits_error != ok { ret fail("out of memory") }
    var files = 0usize
    var count = 0usize
    var file = MAX_FILES
    var at = 0usize
    while at < spec.len {
        let (line_end, has_end) = string.find_from(spec, "\n", at)
        if !has_end { break }
        let line = spec[at..line_end]
        if string.starts_with(line, "@@@ ") {
            if files == MAX_FILES { ret fail("too many files") }
            paths[files] = line[4usize..line.len]
            let (bytes, read_error) = fs.read_file(a, paths[files], MAX_BYTES)
            if read_error != ok { ret fail("a file named by the spec cannot be read") }
            texts[files] = bytes
            windows[files] = string.contains(bytes, "\r\n")
            file = files
            files += 1usize
            at = line_end + 1usize
            continue
        }
        if string.starts_with(line, "<<<") && line.len == 3usize {
            if file == MAX_FILES { ret fail("an edit before any @@@ file line") }
            if count == MAX_EDITS { ret fail("too many edits") }
            let (old, after_old, has_old) = section(spec, at, "<<<", "\n===\n")
            if !has_old { ret fail("an edit without its === line") }
            let (new, after_new, has_new) = section(spec, after_old - 4usize, "===", "\n>>>\n")
            if !has_new { ret fail("an edit without its >>> line") }
            edits[count] = Edit { file: file, old: old, new: new }
            count += 1usize
            at = after_new
            continue
        }
        at = line_end + 1usize
    }
    if count == 0usize { ret fail("the spec holds no edits") }
    // Apply in memory, file by file; write only once every edit applied.
    var e = 0usize
    while e < count {
        let f = edits[e].file
        var old = edits[e].old
        var new = edits[e].new
        if windows[f] {
            let (old_crlf, old_error) = crlf(a, old)
            let (new_crlf, new_error) = crlf(a, new)
            if old_error != ok || new_error != ok { ret fail("out of memory") }
            old = old_crlf
            new = new_crlf
        }
        let seen = string.count(texts[f], old)
        if seen != 1usize {
            try io.print("patch: ")
            try io.print(paths[f])
            if seen == 0usize { try io.print(": an old text is not there:\n") } else { try io.print(": an old text stands more than once:\n") }
            try io.print(edits[e].old)
            try io.print("\n")
            os.exit(1i32)
        }
        let (where, _) = string.find(texts[f], old)
        let (joined, joined_error) = mem.alloc[u8](a, texts[f].len - old.len + new.len)
        if joined_error != ok { ret fail("out of memory") }
        mem.copy[u8](joined[0usize..where], texts[f][0usize..where])
        mem.copy[u8](joined[where..where + new.len], new)
        mem.copy[u8](joined[where + new.len..joined.len], texts[f][where + old.len..texts[f].len])
        texts[f] = joined
        e += 1usize
    }
    var w = 0usize
    while w < files {
        if fs.write_file(a, paths[w], texts[w]) != ok { ret fail("a file cannot be written") }
        try io.print("patched ")
        try io.print(paths[w])
        try io.print("\n")
        w += 1usize
    }
    ret ok
}
