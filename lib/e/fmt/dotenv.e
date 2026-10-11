// Env files (`.env`), read the way python-dotenv reads them. `parse` turns the text
// into ordered bindings in the caller's storage; `interpolate` resolves `${NAME}` and
// `${NAME:-default}` against earlier bindings and a caller-supplied external
// environment. Nothing reads the process environment and nothing writes it: the
// caller applies the result.
//
// A binding is `[export ]KEY[=value]` on its own line. A key is a run of bytes that are
// not `=`, `#` or white space, or a single-quoted string. A value is single-quoted
// (only `\\` and `\'` are escapes), double-quoted (`\\ \' \" \a \b \f \n \r \t \v`; both
// may span lines), or unquoted: to the end of the line, cut at the first white space
// followed by `#`, trailing white space removed. `KEY= # note` is empty, `KEY=#x` is the
// text `#x`, and `KEY` alone is a binding with no value. A line that is not a binding
// is skipped and counted. A leading byte-order mark is ignored; `\r`, `\n` and `\r\n`
// all end a line. A key repeated keeps every binding in order; `get` takes the last.
//
// ponytail: white space is ASCII (space, tab, form feed, vertical tab); python-dotenv's
// regexes also treat Unicode white space as separators.

use e.mem
use e.str

type Entry = struct { key: str, value: str, has_value: bool }
error TooMany

fn is_blank(b: u8) -> bool { ret b == 32u8 || b == 9u8 || b == 12u8 || b == 11u8 }

fn is_space(b: u8) -> bool { ret is_blank(b) || b == 10u8 || b == 13u8 }

fn line_end(text: str, from: usize) -> usize {
    var at = from
    while at < text.len && text[at] != 10u8 && text[at] != 13u8 { at += 1usize }
    ret at
}

// One newline (a `\r\n` counts as one), or nothing at the end of the text.
fn after_newline(text: str, at: usize) -> usize {
    if at >= text.len { ret at }
    if text[at] == 13u8 && at + 1usize < text.len && text[at + 1usize] == 10u8 { ret at + 2usize }
    ret at + 1usize
}

// The index after the closing quote, or `text.len + 1` when there is none. A backslash
// always takes the byte after it.
fn closing_quote(text: str, open: usize, quote: u8) -> usize {
    var at = open + 1usize
    while at < text.len {
        if text[at] == 92u8 {
            at += 2usize
            continue
        }
        if text[at] == quote { ret at + 1usize }
        at += 1usize
    }
    ret text.len + 1usize
}

fn escape_char(c: u8, double: bool) -> (u8, bool) {
    if c == 92u8 || c == 39u8 { ret (c, true) }
    if !double { ret (0u8, false) }
    if c == 34u8 { ret (34u8, true) }
    if c == 97u8 { ret (7u8, true) }
    if c == 98u8 { ret (8u8, true) }
    if c == 102u8 { ret (12u8, true) }
    if c == 110u8 { ret (10u8, true) }
    if c == 114u8 { ret (13u8, true) }
    if c == 116u8 { ret (9u8, true) }
    if c == 118u8 { ret (11u8, true) }
    ret (0u8, false)
}

fn decode(a: *mem.Arena, raw: str, double: bool) -> (str, err) {
    var has_escape = false
    var i = 0usize
    while i < raw.len {
        if raw[i] == 92u8 { has_escape = true }
        i += 1usize
    }
    if !has_escape { ret (raw, ok) }
    let (buffer, buffer_error) = mem.alloc[u8](a, raw.len)
    if buffer_error != ok { ret ("", buffer_error) }
    var n = 0usize
    i = 0usize
    while i < raw.len {
        if raw[i] == 92u8 && i + 1usize < raw.len {
            let (decoded, known) = escape_char(raw[i + 1usize], double)
            if known {
                buffer[n] = decoded
                n += 1usize
                i += 2usize
                continue
            }
        }
        buffer[n] = raw[i]
        n += 1usize
        i += 1usize
    }
    ret (buffer[0usize..n], ok)
}

// Text up to the first white-space run that is followed by `#`, without trailing white space.
fn trim_unquoted(part: str) -> str {
    var end = part.len
    var i = 0usize
    while i < part.len {
        if is_space(part[i]) {
            var j = i
            while j < part.len && is_space(part[j]) { j += 1usize }
            if j < part.len && part[j] == 35u8 {
                end = i
                break
            }
            i = j
            continue
        }
        i += 1usize
    }
    while end > 0usize && is_space(part[end - 1usize]) { end -= 1usize }
    ret part[0usize..end]
}

fn parse(a: *mem.Arena, text: str, out: []Entry) -> (usize, usize, err) {
    var count = 0usize
    var skipped = 0usize
    var at = 0usize
    if text.len >= 3usize && text[0usize] == 239u8 && text[1usize] == 187u8 && text[2usize] == 191u8 { at = 3usize }
    while true {
        while at < text.len && is_space(text[at]) { at += 1usize }
        if at >= text.len { break }
        // `export` and its blanks.
        if at + 6usize < text.len && text[at] == 101u8 && text[at + 1usize] == 120u8 && text[at + 2usize] == 112u8 && text[at + 3usize] == 111u8 && text[at + 4usize] == 114u8 && text[at + 5usize] == 116u8 && is_blank(text[at + 6usize]) {
            at += 6usize
            while at < text.len && is_blank(text[at]) { at += 1usize }
        }
        var key = ""
        var has_key = false
        var bad = false
        if at >= text.len {
            bad = true
        } else if text[at] == 35u8 {
            has_key = false
        } else if text[at] == 39u8 {
            var close = at + 1usize
            while close < text.len && text[close] != 39u8 { close += 1usize }
            if close >= text.len || close == at + 1usize {
                bad = true
            } else {
                key = text[at + 1usize..close]
                has_key = true
                at = close + 1usize
            }
        } else {
            let start = at
            while at < text.len && text[at] != 61u8 && text[at] != 35u8 && !is_space(text[at]) { at += 1usize }
            if at == start {
                bad = true
            } else {
                key = text[start..at]
                has_key = true
            }
        }
        if bad {
            skipped += 1usize
            at = after_newline(text, line_end(text, at))
            continue
        }
        while at < text.len && is_blank(text[at]) { at += 1usize }
        var value = ""
        var has_value = false
        if at < text.len && text[at] == 61u8 {
            at += 1usize
            let after_equal = at
            while at < text.len && is_blank(text[at]) { at += 1usize }
            if at > after_equal && at < text.len && text[at] == 35u8 {
                has_value = true
            } else if at < text.len && (text[at] == 39u8 || text[at] == 34u8) {
                let quote = text[at]
                let close = closing_quote(text, at, quote)
                if close > text.len {
                    bad = true
                } else {
                    let (decoded, decode_error) = decode(a, text[at + 1usize..close - 1usize], quote == 34u8)
                    if decode_error != ok { ret (count, skipped, decode_error) }
                    value = decoded
                    has_value = true
                    at = close
                }
            } else if at >= text.len || text[at] == 10u8 || text[at] == 13u8 {
                has_value = true
            } else {
                let end = line_end(text, at)
                value = trim_unquoted(text[at..end])
                has_value = true
                at = end
            }
        }
        if !bad {
            // An optional comment, then the end of the line.
            var look = at
            while look < text.len && is_blank(text[look]) { look += 1usize }
            if look < text.len && text[look] == 35u8 { look = line_end(text, look) }
            if look >= text.len || text[look] == 10u8 || text[look] == 13u8 {
                at = after_newline(text, look)
            } else {
                bad = true
            }
        }
        if bad {
            skipped += 1usize
            at = after_newline(text, line_end(text, at))
            continue
        }
        if has_key {
            if count == out.len { ret (count, skipped, TooMany) }
            out[count] = Entry { key: key, value: value, has_value: has_value }
            count += 1usize
        }
    }
    ret (count, skipped, ok)
}

// The last binding of `key`, if any; `has_value` tells a bare `KEY` from `KEY=`.
fn get(entries: []const Entry, key: str) -> (Entry, bool) {
    var i = entries.len
    while i > 0usize {
        i -= 1usize
        if str.eq(entries[i].key, key) { ret (entries[i], true) }
    }
    ret (Entry { key: "", value: "", has_value: false }, false)
}

// A `${NAME}` or `${NAME:-default}` at `at`: the name, the default (if given), the end.
fn variable_at(text: str, at: usize) -> (str, str, bool, usize, bool) {
    if at + 1usize >= text.len || text[at] != 36u8 || text[at + 1usize] != 123u8 { ret ("", "", false, at, false) }
    let name_start = at + 2usize
    var p = name_start
    while p < text.len && text[p] != 125u8 && text[p] != 58u8 { p += 1usize }
    if p >= text.len { ret ("", "", false, at, false) }
    if text[p] == 125u8 { ret (text[name_start..p], "", false, p + 1usize, true) }
    if p + 1usize >= text.len || text[p + 1usize] != 45u8 { ret ("", "", false, at, false) }
    let default_start = p + 2usize
    var q = default_start
    while q < text.len && text[q] != 125u8 { q += 1usize }
    if q >= text.len { ret ("", "", false, at, false) }
    ret (text[name_start..p], text[default_start..q], true, q + 1usize, true)
}

fn lookup_value(resolved: []const Entry, count: usize, external: []const Entry, override: bool, name: str) -> (str, bool) {
    // With `override` the file's own bindings shadow the external environment.
    var step = 0usize
    while step < 2usize {
        let file_first = override
        if (step == 0usize) == file_first {
            var i = count
            while i > 0usize {
                i -= 1usize
                if str.eq(resolved[i].key, name) {
                    if resolved[i].has_value { ret (resolved[i].value, true) }
                    ret ("", true)
                }
            }
        } else {
            var j = external.len
            while j > 0usize {
                j -= 1usize
                if str.eq(external[j].key, name) {
                    if external[j].has_value { ret (external[j].value, true) }
                    ret ("", true)
                }
            }
        }
        step += 1usize
    }
    ret ("", false)
}

// Expands variables in place, in order: a binding sees the ones before it.
fn interpolate(a: *mem.Arena, entries: []Entry, external: []const Entry, override: bool) -> err {
    var i = 0usize
    while i < entries.len {
        if entries[i].has_value {
            let value = entries[i].value
            var dollar = false
            var k = 0usize
            while k < value.len {
                if value[k] == 36u8 { dollar = true }
                k += 1usize
            }
            if dollar {
                var (b, builder_error) = str.builder(a, value.len)
                if builder_error != ok { ret builder_error }
                var at = 0usize
                var literal_start = 0usize
                while at < value.len {
                    let (name, fallback, has_default, after, matched) = variable_at(value, at)
                    if !matched {
                        at += 1usize
                        continue
                    }
                    let flush_error = str.push(&b, value[literal_start..at])
                    if flush_error != ok { ret flush_error }
                    let (found, present) = lookup_value(entries, i, external, override, name)
                    var piece = found
                    if !present && has_default { piece = fallback }
                    let piece_error = str.push(&b, piece)
                    if piece_error != ok { ret piece_error }
                    at = after
                    literal_start = after
                }
                let tail_error = str.push(&b, value[literal_start..value.len])
                if tail_error != ok { ret tail_error }
                entries[i].value = str.done(&b)
            }
        }
        i += 1usize
    }
    ret ok
}
