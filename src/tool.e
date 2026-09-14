// The machine protocol of docs/tooling.md, version 1 (D227): the stream header, the
// `tokens` command's token, trivia and diagnostic records, and the result record,
// as JSON Lines on stdout.

use e.mem
use e.os
use lex
use parse
use syntax
use resolve
use nir
use graph
use artifact_hash

error Capacity
error InvalidSource

// One record at a time: built here, printed whole, so a line is never split.
type Out = struct {
    bytes: []u8,
    count: usize,
}

fn byte(out: *Out, value: u8) -> err {
    if out.count == out.bytes.len { ret Capacity }
    out.bytes[out.count] = value
    out.count += 1usize
    ret ok
}

fn text(out: *Out, value: str) -> err {
    var at = 0usize
    while at < value.len {
        try byte(out, value[at])
        at += 1usize
    }
    ret ok
}

fn decimal(out: *Out, value: usize) -> err {
    if value >= 10usize { try decimal(out, value / 10usize) }
    ret byte(out, u8(48usize + value % 10usize))
}

fn flush(out: *Out) -> err {
    try byte(out, 10u8)
    let stdout = os.stdout()
    var at = 0usize
    while at < out.count {
        let (written, write_error) = os.write(stdout, out.bytes[at..out.count])
        if write_error != ok { ret write_error }
        if written == 0usize { ret Capacity }
        at += written
    }
    out.count = 0usize
    ret ok
}

// A JSON string of valid UTF-8: the two escapes JSON requires and `\u` for the rest
// of the controls, everything else as it is.
fn quoted(out: *Out, value: str) -> err {
    try byte(out, 34u8)
    try quoted_body(out, value)
    ret byte(out, 34u8)
}

// The bytes of a JSON string without its quotes, so several source lines can join into
// one value (D251).
fn quoted_body(out: *Out, value: str) -> err {
    var at = 0usize
    while at < value.len {
        let c = value[at]
        if c == 34u8 || c == 92u8 {
            try byte(out, 92u8)
            try byte(out, c)
        } else {
            if c == 10u8 {
                try text(out, "\\n")
            } else {
                if c == 13u8 {
                    try text(out, "\\r")
                } else {
                    if c == 9u8 {
                        try text(out, "\\t")
                    } else {
                        if c < 32u8 {
                            try text(out, "\\u00")
                            try byte(out, hex_digit(usize(c) / 16usize))
                            try byte(out, hex_digit(usize(c) % 16usize))
                        } else {
                            try byte(out, c)
                        }
                    }
                }
            }
        }
        at += 1usize
    }
    ret ok
}

fn hex_digit(value: usize) -> u8 {
    if value < 10usize { ret u8(48usize + value) }
    ret u8(87usize + value)
}

// Section 2's captured bytes for what is not valid UTF-8: canonical padded base64.
fn base64_object(out: *Out, value: str) -> err {
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    try text(out, "{\"encoding\":\"base64\",\"data\":\"")
    var at = 0usize
    while at < value.len {
        let first = usize(value[at])
        var second = 0usize
        var third = 0usize
        if at + 1usize < value.len { second = usize(value[at + 1usize]) }
        if at + 2usize < value.len { third = usize(value[at + 2usize]) }
        let group = first * 65536usize + second * 256usize + third
        try byte(out, alphabet[(group >> 18usize) & 63usize])
        try byte(out, alphabet[(group >> 12usize) & 63usize])
        if at + 1usize < value.len { try byte(out, alphabet[(group >> 6usize) & 63usize]) } else { try byte(out, 61u8) }
        if at + 2usize < value.len { try byte(out, alphabet[group & 63usize]) } else { try byte(out, 61u8) }
        at += 3usize
    }
    ret text(out, "\"}")
}

fn span(out: *Out, root: str, path: str, byte_start: usize, byte_end: usize, line: usize, column: usize, end_line: usize, end_column: usize, column_utf16: usize, end_column_utf16: usize) -> err {
    try text(out, "{\"source\":{\"root\":")
    try quoted(out, root)
    try text(out, ",\"path\":")
    try quoted(out, path)
    try text(out, "},\"byte_start\":")
    try decimal(out, byte_start)
    try text(out, ",\"byte_end\":")
    try decimal(out, byte_end)
    try text(out, ",\"line\":")
    try decimal(out, line)
    try text(out, ",\"column\":")
    try decimal(out, column)
    try text(out, ",\"end_line\":")
    try decimal(out, end_line)
    try text(out, ",\"end_column\":")
    try decimal(out, end_column)
    try text(out, ",\"column_utf16\":")
    try decimal(out, column_utf16)
    try text(out, ",\"end_column_utf16\":")
    try decimal(out, end_column_utf16)
    ret byte(out, 125u8)
}

fn header(out: *Out, command: str) -> err {
    try text(out, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":")
    try quoted(out, command)
    try text(out, ",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":1}")
    ret flush(out)
}

fn result(out: *Out, succeeded: bool, exit_code: usize, tokens: usize, diagnostics: usize) -> err {
    if succeeded { try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":") } else { try text(out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":") }
    try decimal(out, exit_code)
    try text(out, ",\"data\":{\"tokens\":")
    try decimal(out, tokens)
    try text(out, ",\"diagnostics\":")
    try decimal(out, diagnostics)
    try text(out, "}}")
    ret flush(out)
}

// `info --json` (D229): the header, one `info` record of what this build answers
// to -- every collection sorted by bytes, as section 1 requires -- and a result.
fn info_json(a: *mem.Arena, host: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, 4096usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize }
    try header(&out, "info")
    try text(&out, "{\"record\":\"info\",\"tool_version\":\"0.1.0\",\"language_profiles\":[{\"language_version\":\"0.1\",\"grammar_revision\":1,\"stream_version\":1,\"experimental\":false}],\"commands\":[\"check\",\"info\",\"parse\",\"tokens\"],\"host_target\":")
    try quoted(&out, host)
    // ponytail: the emitter selects nothing above SSE2 and SIMD lowers as lane loops (D148),
    // so x64-v1 is the one level this build honours; list the others when `--cpu` exists.
    try text(&out, ",\"build_targets\":[\"x64-linux\",\"x64-windows\"],\"cpu_levels\":[\"x64-v1\"],\"features\":[]}")
    try flush(&out)
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{}}")
    ret flush(&out)
}

// Section 2's captured bytes: a JSON string when they are valid UTF-8, base64 otherwise.
fn captured(out: *Out, value: str) -> err {
    var at = 0usize
    while at < value.len {
        let width = lex.utf8_width(value, at)
        if width == 0usize { ret base64_object(out, value) }
        at += width
    }
    ret quoted(out, value)
}

// The byte a `line:column` names in `source`, and the column in UTF-16 units: the trap
// record carries the lexer's columns, which count code points.
fn trap_byte_at(source: str, line: usize, column: usize) -> (usize, usize) {
    var at = 0usize
    var current = 1usize
    while current < line && at < source.len {
        if source[at] == 10u8 { current += 1usize }
        at += 1usize
    }
    var seen = 1usize
    var seen_utf16 = 1usize
    while seen < column && at < source.len && source[at] != 10u8 {
        let width = lex.utf8_width(source, at)
        if width == 0usize { ret (at, seen_utf16) }
        seen += 1usize
        seen_utf16 += 1usize
        if width == 4usize { seen_utf16 += 1usize }
        at += width
    }
    ret (at, seen_utf16)
}

fn trap_decimal(digits: str) -> usize {
    var value = 0usize
    var at = 0usize
    while at < digits.len {
        if digits[at] < 48u8 || digits[at] > 57u8 { ret value }
        value = value * 10usize + usize(digits[at] - 48u8)
        at += 1usize
    }
    ret value
}

// `file:line` split at its last colon; `(0, 0)` when there is none.
fn trap_split_line(site: str) -> (usize, usize) {
    var colon = site.len
    var at = 0usize
    while at < site.len {
        if site[at] == 58u8 { colon = at }
        at += 1usize
    }
    if colon == site.len { ret (0usize, 0usize) }
    ret (colon, trap_decimal(site[colon + 1usize..site.len]))
}

fn trap_line_end(bytes: str, from: usize) -> usize {
    var at = from
    while at < bytes.len && bytes[at] != 10u8 { at += 1usize }
    if at > from && bytes[at - 1usize] == 13u8 { ret at - 1usize }
    ret at
}

// A frame's source: the operand, when the frame's file is the operand as the child
// spells it and the line lies inside the operand's own text; null otherwise, since the
// printed path does not say which root another module lies under.
fn trap_source(out: *Out, path: str, file: str, spelled: str, line: usize, line_offset: usize, line_count: usize) -> err {
    if graph.same(file, spelled) && line > line_offset && line - line_offset <= line_count {
        try text(out, "{\"root\":\"operand\",\"path\":")
        try quoted(out, path)
        ret byte(out, 125u8)
    }
    ret text(out, "null")
}

// `module.function` with the child's module name -- the runner's, under `test` --
// replaced by the operand's when the frame lies in the operand's text.
// The module name a file is printed under: its stem, section 2's naming rule.
fn trap_stem(spelled: str) -> str {
    var start = 0usize
    var at = 0usize
    while at < spelled.len {
        if spelled[at] == 47u8 || spelled[at] == 92u8 { start = at + 1usize }
        at += 1usize
    }
    var end = spelled.len
    if end >= start + 2usize && spelled[end - 2usize] == 46u8 && spelled[end - 1usize] == 101u8 { end = end - 2usize }
    ret spelled[start..end]
}

fn trap_function(out: *Out, function: str, module_name: str, spelled: str, file: str, line: usize, line_offset: usize, line_count: usize) -> err {
    var dot = 0usize
    while dot < function.len && function[dot] != 46u8 { dot += 1usize }
    let spelled_module = trap_stem(spelled)
    if dot < function.len && graph.same(function[0usize..dot], spelled_module) && graph.same(file, spelled) && line > line_offset && line - line_offset <= line_count {
        try byte(out, 34u8)
        try quoted_body(out, module_name)
        try quoted_body(out, function[dot..function.len])
        ret byte(out, 34u8)
    }
    ret quoted(out, function)
}

fn trap_line_count(source: str) -> usize {
    var count = 1usize
    var at = 0usize
    while at < source.len {
        if source[at] == 10u8 { count += 1usize }
        at += 1usize
    }
    ret count
}

// Section 11's trap record read back into section 7's `trap` payload (D253). The
// record is `file:line:col: trap[kind]: values`, then one `  at module.function
// (file:line)` frame per line. The operand's own file -- spelled `spelled` by the
// child, its text beginning `line_offset` lines down -- gets a byte-precise span and
// the `operand` source. `values` is the record's text after the kind, as one entry:
// the operands are in there, and which words are operands is the check's business.
// Without a record the payload is null.
fn trap_json(out: *Out, stderr_bytes: str, module_name: str, path: str, source: str, spelled: str, line_offset: usize) -> err {
    var at = 0usize
    var found = stderr_bytes.len
    while at + 7usize <= stderr_bytes.len && found == stderr_bytes.len {
        if graph.same(stderr_bytes[at..at + 7usize], ": trap[") { found = at }
        at += 1usize
    }
    if found == stderr_bytes.len { ret text(out, "null") }
    let line_count = trap_line_count(source)
    var record_start = found
    while record_start > 0usize && stderr_bytes[record_start - 1usize] != 10u8 { record_start = record_start - 1usize }
    // `file:line:col`, split from the right.
    let (column_colon, column) = trap_split_line(stderr_bytes[record_start..found])
    let (line_colon, line) = trap_split_line(stderr_bytes[record_start..record_start + column_colon])
    let file = stderr_bytes[record_start..record_start + line_colon]
    var kind_end = found + 7usize
    while kind_end < stderr_bytes.len && stderr_bytes[kind_end] != 93u8 { kind_end += 1usize }
    try text(out, "{\"kind\":")
    try quoted(out, stderr_bytes[found + 7usize..kind_end])
    try text(out, ",\"span\":")
    if graph.same(file, spelled) && line > line_offset && line - line_offset <= line_count {
        let (offset, column_utf16) = trap_byte_at(source, line - line_offset, column)
        try span(out, "operand", path, offset, offset, line - line_offset, column, line - line_offset, column, column_utf16, column_utf16)
    } else {
        try text(out, "null")
    }
    var values_start = kind_end + 1usize
    if values_start < stderr_bytes.len && stderr_bytes[values_start] == 58u8 { values_start += 1usize }
    if values_start < stderr_bytes.len && stderr_bytes[values_start] == 32u8 { values_start += 1usize }
    let values_end = trap_line_end(stderr_bytes, kind_end)
    try text(out, ",\"values\":[")
    if values_start < values_end { try quoted(out, stderr_bytes[values_start..values_end]) }
    try text(out, "],\"backtrace\":[")
    var frames = 0usize
    var cursor = trap_line_end(stderr_bytes, kind_end)
    while cursor < stderr_bytes.len {
        if stderr_bytes[cursor] == 13u8 || stderr_bytes[cursor] == 10u8 { cursor += 1usize }
        let end = trap_line_end(stderr_bytes, cursor)
        if end < cursor + 5usize || !graph.same(stderr_bytes[cursor..cursor + 5usize], "  at ") { ret text(out, "]}") }
        // `  at module.function (file:line)`
        var open = cursor + 5usize
        while open < end && stderr_bytes[open] != 40u8 { open += 1usize }
        var function_end = open
        if function_end > cursor + 5usize && stderr_bytes[function_end - 1usize] == 32u8 { function_end = function_end - 1usize }
        var close = end
        if close > open && stderr_bytes[close - 1usize] == 41u8 { close = close - 1usize }
        var site_start = open
        if site_start < close { site_start += 1usize }
        let (frame_colon, frame_line) = trap_split_line(stderr_bytes[site_start..close])
        let frame_file = stderr_bytes[site_start..site_start + frame_colon]
        if frames != 0usize { try byte(out, 44u8) }
        try text(out, "{\"function\":")
        try trap_function(out, stderr_bytes[cursor + 5usize..function_end], module_name, spelled, frame_file, frame_line, line_offset, line_count)
        try text(out, ",\"source\":")
        try trap_source(out, path, frame_file, spelled, frame_line, line_offset, line_count)
        try text(out, ",\"line\":")
        if frame_line == 0usize {
            try text(out, "null")
        } else {
            if graph.same(frame_file, spelled) && frame_line > line_offset && frame_line - line_offset <= line_count { try decimal(out, frame_line - line_offset) } else { try decimal(out, frame_line) }
        }
        try byte(out, 125u8)
        frames += 1usize
        cursor = end
    }
    ret text(out, "]}")
}

// A failed test's `error`: the qualified name after `error: `, the runner's module
// replaced by the operand's the way a frame's is.
fn test_error_name(out: *Out, stderr_bytes: str, module_name: str, spelled: str) -> err {
    if stderr_bytes.len < 7usize || !graph.same(stderr_bytes[0usize..7usize], "error: ") { ret text(out, "null") }
    let end = trap_line_end(stderr_bytes, 7usize)
    let name = stderr_bytes[7usize..end]
    let spelled_module = trap_stem(spelled)
    var dot = 0usize
    while dot < name.len && name[dot] != 46u8 { dot += 1usize }
    if dot < name.len && graph.same(name[0usize..dot], spelled_module) {
        try byte(out, 34u8)
        try quoted_body(out, module_name)
        try quoted_body(out, name[dot..name.len])
        ret byte(out, 34u8)
    }
    ret quoted(out, name)
}

// `run --json` (D231): the program's exit status and its whole stdout and stderr as one
// record, with section 11's trap record read back as the `trap` payload (D253).
// `spelled` is the operand as the compiler was given it, which is how the child prints
// it; `path` is section 2's operand identity, the basename.
fn run_record(a: *mem.Arena, status: i32, stdout_bytes: str, stderr_bytes: str, module_name: str, path: str, source: str, spelled: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, (stdout_bytes.len + stderr_bytes.len) * 6usize + 256usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize }
    try text(&out, "{\"record\":\"run\",\"process_exit_code\":")
    if status < 0i32 {
        try byte(&out, 45u8)
        try decimal(&out, usize(0i32 - status))
    } else {
        try decimal(&out, usize(status))
    }
    try text(&out, ",\"stdout\":")
    try captured(&out, stdout_bytes)
    try text(&out, ",\"stderr\":")
    try captured(&out, stderr_bytes)
    try text(&out, ",\"trap\":")
    try trap_json(&out, stderr_bytes, module_name, path, source, spelled, 0usize)
    try byte(&out, 125u8)
    ret flush(&out)
}

// docs/tooling.md section 5's `kind` for a module-scope declaration; the resolver's
// own kinds map onto the closed set one to one (D232).
fn index_kind_name(kind: resolve.Kind) -> str {
    if kind == .Type { ret "type" }
    if kind == .Const { ret "const" }
    if kind == .Var { ret "module_var" }
    if kind == .Error { ret "error" }
    if kind == .Function { ret "fn" }
    if kind == .Extern { ret "extern" }
    ret "intrinsic"
}

// A JSON string of `module.name`; both halves are identifiers or a dotted module path,
// so no escape is ever needed.
fn index_qualified(out: *Out, module_name: str, name: str) -> err {
    try byte(out, 34u8)
    try text(out, module_name)
    try byte(out, 46u8)
    try text(out, name)
    ret byte(out, 34u8)
}

// Where a comment line's text begins. A comment is the leading trivia of the `Newline`
// token that ends its line, and that trivia runs to the newline byte itself, so the
// line is the trivia with its indentation skipped.
fn index_comment_start(source: str, token: lex.Token) -> usize {
    var at = token.leading_start
    while at < token.start && (source[at] == 32u8 || source[at] == 9u8) { at += 1usize }
    ret at
}

// Whether the token at `at` ends one of spec section 3's `///` documentation lines. The
// comment must start the line -- a trailing `/// x` after code is trivia of the same
// `Newline`, so the token before one that qualifies is itself a newline.
fn index_is_doc_line(source: str, tokens: []const lex.Token, at: usize) -> bool {
    let token = tokens[at]
    if token.kind != .Newline { ret false }
    if at != 0usize && tokens[at - 1usize].kind != .Newline { ret false }
    let start = index_comment_start(source, token)
    if token.start < start + 3usize { ret false }
    if source[start] != 47u8 { ret false }
    if source[start + 1usize] != 47u8 { ret false }
    if source[start + 2usize] != 47u8 { ret false }
    ret true
}

// The token a declaration's attributes begin at. Section 12 requires them adjacent, so
// only newlines sit between one and the next; `@name` and `@name(...)` are both walked.
// ponytail: 64 attributes on one declaration is the cap, raise it if anything needs more.
fn index_attribute_start(tokens: []const lex.Token, opener: usize) -> usize {
    var at = opener
    var guard = 0usize
    while guard < 64usize {
        guard += 1usize
        var probe = at
        while probe > 0usize && tokens[probe - 1usize].kind == .Newline { probe = probe - 1usize }
        if probe < 2usize { ret at }
        var back = probe - 1usize
        if tokens[back].kind == .PunctRParen {
            var depth = 0usize
            var closed = false
            while closed == false {
                if tokens[back].kind == .PunctRParen { depth += 1usize }
                if tokens[back].kind == .PunctLParen {
                    depth = depth - 1usize
                    if depth == 0usize { closed = true }
                }
                if closed == false {
                    if back == 0usize { ret at }
                    back = back - 1usize
                }
            }
            if back == 0usize { ret at }
            back = back - 1usize
        }
        if tokens[back].kind != .Identifier { ret at }
        if back == 0usize { ret at }
        if tokens[back - 1usize].kind != .PunctAt { ret at }
        at = back - 1usize
    }
    ret at
}

// `[...]` of the attribute names written on a declaration, in source order.
fn index_attributes(out: *Out, source: str, tokens: []const lex.Token, from: usize, opener: usize) -> err {
    try byte(out, 91u8)
    var at = from
    var written = 0usize
    while at < opener {
        if tokens[at].kind == .PunctAt && at + 1usize < opener && tokens[at + 1usize].kind == .Identifier {
            if written != 0usize { try byte(out, 44u8) }
            let name = tokens[at + 1usize]
            try quoted(out, source[name.start..name.end])
            written += 1usize
        }
        at += 1usize
    }
    ret byte(out, 93u8)
}

// Spec section 3's documentation: the run of `///` lines immediately above, one optional
// space after the slashes removed and the lines joined with LF. A blank line or an
// ordinary `//` ends the run, because neither is a documentation line.
fn index_documentation(out: *Out, source: str, tokens: []const lex.Token, from: usize) -> err {
    var first = from
    while first > 0usize && index_is_doc_line(source, tokens, first - 1usize) { first = first - 1usize }
    if first == from { ret text(out, "null") }
    try byte(out, 34u8)
    var at = first
    while at < from {
        if at != first { try text(out, "\\n") }
        var start = index_comment_start(source, tokens[at]) + 3usize
        if start < tokens[at].start && source[start] == 32u8 { start += 1usize }
        try quoted_body(out, source[start..tokens[at].start])
        at += 1usize
    }
    ret byte(out, 34u8)
}

// A declaration's signature is its header: everything up to the body a reader does not
// need in order to call it. The body opens at the first `{` outside any bracket, so a
// declaration without one -- a `const`, a `var`, an `extern fn` -- is its own signature.
fn index_signature(out: *Out, source: str, tokens: []const lex.Token, opener: usize, closer: usize) -> err {
    var depth = 0usize
    var at = opener
    var last = closer
    while at <= closer {
        let kind = tokens[at].kind
        if kind == .PunctLParen || kind == .PunctLBracket { depth += 1usize }
        if (kind == .PunctRParen || kind == .PunctRBracket) && depth != 0usize { depth = depth - 1usize }
        if kind == .PunctLBrace && depth == 0usize && at != opener {
            last = at - 1usize
            at = closer
        }
        at += 1usize
    }
    ret quoted(out, source[tokens[opener].start..tokens[last].end])
}

// `index --json` (D232): a `symbol` record for the module and each of its module-scope
// declarations, each carrying its signature, its attributes and its `///` documentation
// (D251). Locals, parameters, fields, members and every reference are the gap -- the
// resolver does not carry them, so this names only what it does.
fn index_json(a: *mem.Arena, root: str, path: str, source: str, module_name: str, module_index: usize, symbols: []const resolve.Symbol, count: usize) -> (usize, err) {
    let (tokens, token_count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 8192usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let header_error = header(&out, "index")
    if header_error != ok { ret (2usize, header_error) }
    // The module itself is the first symbol, so every declaration's container is id 0.
    let module_error = index_module_record(&out, module_name)
    if module_error != ok { ret (2usize, module_error) }
    var emitted = 1usize
    var at = 0usize
    while at < count {
        let symbol = symbols[at]
        if symbol.module_index == module_index && symbol.kind != .Qualifier && symbol.kind != .Intrinsic {
            var name_index = symbol.token_start + 1usize
            if symbol.kind == .Extern { name_index += 1usize }
            if symbol.token_end == 0usize || symbol.token_end > token_count || name_index >= token_count { ret (2usize, parse.InvalidSyntax) }
            let record_error = index_symbol_record(&out, root, path, source, module_name, emitted, symbol, tokens[0usize..token_count], symbol.token_start, symbol.token_end - 1usize, name_index)
            if record_error != ok { ret (2usize, record_error) }
            emitted += 1usize
        }
        at += 1usize
    }
    let result_error = index_result(&out, emitted)
    if result_error != ok { ret (2usize, result_error) }
    ret (0usize, ok)
}

fn index_module_record(out: *Out, module_name: str) -> err {
    try text(out, "{\"record\":\"symbol\",\"id\":0,\"kind\":\"module\",\"name\":")
    try quoted(out, module_name)
    try text(out, ",\"qualified_name\":")
    try quoted(out, module_name)
    try text(out, ",\"module\":")
    try quoted(out, module_name)
    try text(out, ",\"signature\":null,\"span\":null,\"selection_span\":null,\"container_id\":null,\"attributes\":[],\"documentation\":null}")
    ret flush(out)
}

fn index_symbol_record(out: *Out, root: str, path: str, source: str, module_name: str, id: usize, symbol: resolve.Symbol, tokens: []const lex.Token, first: usize, last: usize, name_index: usize) -> err {
    let opener = tokens[first]
    let closer = tokens[last]
    let name_token = tokens[name_index]
    let attribute_start = index_attribute_start(tokens, first)
    try text(out, "{\"record\":\"symbol\",\"id\":")
    try decimal(out, id)
    try text(out, ",\"kind\":")
    try quoted(out, index_kind_name(symbol.kind))
    try text(out, ",\"name\":")
    try quoted(out, symbol.name)
    try text(out, ",\"qualified_name\":")
    try index_qualified(out, module_name, symbol.name)
    try text(out, ",\"module\":")
    try quoted(out, module_name)
    try text(out, ",\"signature\":")
    try index_signature(out, source, tokens, first, last)
    try text(out, ",\"span\":")
    try span(out, root, path, opener.start, closer.end, opener.line, opener.column, closer.end_line, closer.end_column, opener.column_utf16, closer.end_column_utf16)
    try text(out, ",\"selection_span\":")
    try span(out, root, path, name_token.start, name_token.end, name_token.line, name_token.column, name_token.end_line, name_token.end_column, name_token.column_utf16, name_token.end_column_utf16)
    try text(out, ",\"container_id\":0,\"attributes\":")
    try index_attributes(out, source, tokens, attribute_start, first)
    try text(out, ",\"documentation\":")
    try index_documentation(out, source, tokens, attribute_start)
    try byte(out, 125u8)
    ret flush(out)
}

fn index_result(out: *Out, symbols: usize) -> err {
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"symbols\":")
    try decimal(out, symbols)
    try text(out, ",\"references\":0}}")
    ret flush(out)
}

// `dis --json` (D233): one `disassembly` record per function. The `text` is the
// function's machine bytes as space-separated lowercase hex -- a faithful listing of
// what code selection produced. Mnemonic (AT&T/Intel) disassembly is the gap.
fn disassembly_json(a: *mem.Arena, arch: str, os_name: str, builder: *nir.Builder, offsets: []const usize, machine: []const usize, machine_count: usize) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, machine_count * 3usize + 8192usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize }
    try header(&out, "dis")
    var at = 0usize
    while at < builder.function_count {
        let start = offsets[at]
        var stop = machine_count
        if at + 1usize < builder.function_count { stop = offsets[at + 1usize] }
        try text(&out, "{\"record\":\"disassembly\",\"symbol\":")
        let function = builder.functions[at]
        // module.function, the name a backtrace and the symbol table use (D206).
        if function.module_name.len != 0usize {
            try byte(&out, 34u8)
            try text(&out, function.module_name)
            try byte(&out, 46u8)
            try text(&out, function.name)
            try byte(&out, 34u8)
        } else {
            try quoted(&out, function.name)
        }
        try text(&out, ",\"target\":\"")
        try text(&out, arch)
        try byte(&out, 45u8)
        try text(&out, os_name)
        try text(&out, "\",\"text\":\"")
        var byte_at = start
        while byte_at < stop {
            if byte_at != start { try byte(&out, 32u8) }
            let value = machine[byte_at] & 255usize
            try byte(&out, hex_digit(value / 16usize))
            try byte(&out, hex_digit(value % 16usize))
            byte_at += 1usize
        }
        try text(&out, "\"}")
        try flush(&out)
        at += 1usize
    }
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"functions\":")
    try decimal(&out, builder.function_count)
    try text(&out, "}}")
    ret flush(&out)
}

// docs/tooling.md section 6's canonical layout, the deterministic local rules (D234):
// four-space indent by brace depth, one space around binary and assignment operators and
// after comma and colon, no space inside delimiters or around `.` and `..` or before a
// call/index list, prefix operators glued to their operand, comments preserved, blank
// runs collapsed to one and none at a block edge, a single final newline. Not yet:
// >100-column list wrapping, sorting `use` and attributes, and raw-string minimization.

fn fmt_is_open(kind: lex.Kind) -> bool {
    ret kind == .PunctLParen || kind == .PunctLBracket || kind == .PunctLBrace
}

fn fmt_is_close(kind: lex.Kind) -> bool {
    ret kind == .PunctRParen || kind == .PunctRBracket || kind == .PunctRBrace
}

// A token that ends a value, so a following `(`/`[` is a call or index and a following
// `-`/`*`/`&` is a binary operator rather than a prefix.
fn fmt_value_end(kind: lex.Kind) -> bool {
    if kind == .Identifier || kind == .Integer || kind == .Float || kind == .String { ret true }
    if kind == .RawString || kind == .Character || kind == .PunctUnderscore { ret true }
    if kind == .KwTrue || kind == .KwFalse || kind == .KwNil || kind == .KwOk { ret true }
    if kind == .KwZero || kind == .KwUndef { ret true }
    if kind == .PunctRParen || kind == .PunctRBracket { ret true }
    ret false
}

fn fmt_prefixable(kind: lex.Kind) -> bool {
    ret kind == .PunctMinus || kind == .PunctPlus || kind == .PunctAmp || kind == .PunctStar || kind == .PunctBang || kind == .PunctTilde
}

// Whether one space separates the previous token from this one, on the same line.
// `prev_unary` is set when the previous token was a prefix operator, so this one glues.
fn fmt_space_before(prev: lex.Kind, prev_unary: bool, cur: lex.Kind) -> bool {
    if prev_unary { ret false }
    // One space inside a brace pair on one line -- `{ ret ok }`, `struct { a: i32 }` -- and
    // none inside an empty `{}` (D255); `(` and `[` hug their contents.
    if prev == .PunctLBrace { ret cur != .PunctRBrace }
    if cur == .PunctRBrace { ret prev != .PunctLBrace }
    if fmt_is_open(prev) { ret false }
    if fmt_is_close(cur) { ret false }
    if cur == .PunctComma { ret false }
    if cur == .PunctColon { ret false }
    if cur == .PunctDot || prev == .PunctDot { ret false }
    if cur == .PunctRange || prev == .PunctRange { ret false }
    if prev == .PunctAt { ret false }
    if cur == .PunctLParen || cur == .PunctLBracket {
        if fmt_value_end(prev) { ret false }
        ret true
    }
    // A slice or array type glues its element to the `]`: `[]str`, `[]const u8`, `[4]u8`.
    if prev == .PunctRBracket && (cur == .Identifier || cur == .KwConst) { ret false }
    ret true
}

// A prefix (unary) use of `-`/`+`/`&`/`*`/`!`/`~`: the previous token does not end a value.
fn fmt_is_unary(prev: lex.Kind, cur: lex.Kind) -> bool {
    if !fmt_prefixable(cur) { ret false }
    ret !fmt_value_end(prev)
}

// A run of one or more blank lines collapses to one, and none survives right after a line
// that ends in `{` or right before a line that is `}`; the file ends in exactly one newline.
// A single pass over the raw bytes, into the same order in a second buffer.
fn fmt_collapse(raw: []const u8, out: []u8) -> usize {
    var written = 0usize
    var at = 0usize
    // Skip leading blank lines.
    while at < raw.len && raw[at] == 10u8 { at += 1usize }
    while at < raw.len {
        // Copy one line including its trailing newline (if any).
        let line_start = at
        while at < raw.len && raw[at] != 10u8 { at += 1usize }
        var line_end = at
        if at < raw.len { at += 1usize }
        // A blank line is empty between newlines.
        if line_end == line_start {
            // Look ahead past a run of blanks to the next non-blank line's first byte.
            var probe = at
            while probe < raw.len && raw[probe] == 10u8 { probe += 1usize }
            // Drop the blank(s) at end of file or before a `}` line, and after a `{` line.
            let after_open = written >= 2usize && out[written - 2usize] == 123u8 && out[written - 1usize] == 10u8
            var before_close = false
            if probe < raw.len {
                var scan = probe
                while scan < raw.len && raw[scan] == 32u8 { scan += 1usize }
                if scan < raw.len && raw[scan] == 125u8 { before_close = true }
            }
            if probe >= raw.len || before_close || after_open {
                at = probe
            } else {
                out[written] = 10u8
                written += 1usize
                at = probe
            }
        } else {
            var copy = line_start
            while copy < line_end {
                out[written] = raw[copy]
                written += 1usize
                copy += 1usize
            }
            out[written] = 10u8
            written += 1usize
        }
    }
    ret written
}

// The canonical layout of a source, or an error if it does not tokenize.
fn format_source(a: *mem.Arena, source: str) -> (str, err) {
    if lex.validate(source) != ok { ret ("", InvalidSource) }
    let (raw_storage, raw_error) = mem.alloc[u8](a, source.len * 2usize + 4096usize)
    if raw_error != ok { ret ("", raw_error) }
    var raw = Out { bytes: raw_storage, count: 0usize }
    let build_error = format_into(&raw, source)
    if build_error != ok { ret ("", build_error) }
    let (clean_storage, clean_error) = mem.alloc[u8](a, raw.count + 16usize)
    if clean_error != ok { ret ("", clean_error) }
    let clean_count = fmt_collapse(raw.bytes[0usize..raw.count], clean_storage)
    ret (clean_storage[0usize..clean_count], ok)
}

// The layout pass, in an err-returning function so `try` may propagate a buffer overflow.
fn format_into(raw: *Out, source: str) -> err {
    var depth = 0usize
    var line_has_content = false
    var prev: lex.Kind = .Newline
    var prev_unary = false
    var scanner = lex.init(source)
    while true {
        let token = lex.next(&scanner)
        if token.kind == .Eof { break }
        if token.kind == .Newline {
            // A comment in this newline's leading trivia is a trailing comment when the line
            // already has content, otherwise a standalone comment line at the current indent.
            var trivia = lex.trivia_init(source, token)
            var comment_start = 0usize
            var comment_end = 0usize
            var has_comment = false
            while true {
                let item = lex.next_trivia(&trivia)
                if item.kind == .End { break }
                if item.kind == .Comment {
                    comment_start = item.start
                    comment_end = item.end
                    has_comment = true
                }
            }
            if line_has_content {
                if has_comment {
                    try byte(raw, 32u8)
                    try text(raw, source[comment_start..comment_end])
                }
                try byte(raw, 10u8)
                line_has_content = false
                prev = .Newline
                prev_unary = false
            } else {
                if has_comment {
                    var indent = 0usize
                    while indent < depth * 4usize {
                try byte(raw, 32u8)
                indent += 1usize
            }
                    try text(raw, source[comment_start..comment_end])
                    try byte(raw, 10u8)
                } else {
                    try byte(raw, 10u8)
                }
            }
        } else {
            let at_line_start = !line_has_content
            if token.kind == .PunctRBrace && depth > 0usize && at_line_start { depth = depth - 1usize }
            if at_line_start {
                var indent = 0usize
                while indent < depth * 4usize {
                try byte(raw, 32u8)
                indent += 1usize
            }
                line_has_content = true
            } else {
                if fmt_space_before(prev, prev_unary, token.kind) { try byte(raw, 32u8) }
            }
            try text(raw, source[token.start..token.end])
            if token.kind == .PunctLBrace { depth += 1usize }
            // A close brace mid-line (e.g. `{}` or `} else {`) still lowers the depth.
            if token.kind == .PunctRBrace && !at_line_start && depth > 0usize { depth = depth - 1usize }
            prev_unary = fmt_is_unary(prev, token.kind)
            prev = token.kind
        }
    }
    ret ok
}

// `fmt --check --json` (D242+): the canonical-layout check. Emits E-FORMAT-0001 pointing at
// the first byte that differs from canonical and exits 1 when the source is not already
// canonical, and just the header and a passing result when it is.
fn fmt_check_json(a: *mem.Arena, source: str, path: str) -> (usize, err) {
    let (formatted, format_error) = format_source(a, source)
    if format_error != ok { ret (1usize, format_error) }
    let (storage, storage_error) = mem.alloc[u8](a, source.len + formatted.len + 4096usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let header_error = header(&out, "fmt")
    if header_error != ok { ret (2usize, header_error) }
    var canonical = formatted.len == source.len
    var diff_at = 0usize
    if canonical {
        while diff_at < source.len {
            if source[diff_at] != formatted[diff_at] {
                canonical = false
                diff_at = source.len
            } else {
                diff_at += 1usize
            }
        }
    }
    if canonical {
        let result_error = fmt_check_result(&out, true)
        if result_error != ok { ret (2usize, result_error) }
        ret (0usize, ok)
    }
    // The first differing byte, and its one-based line and column by a scan of the original.
    var first = 0usize
    while first < source.len && first < formatted.len && source[first] == formatted[first] { first += 1usize }
    var line = 1usize
    var column = 1usize
    var scan = 0usize
    while scan < first {
        if source[scan] == 10u8 {
            line += 1usize
            column = 1usize
        } else {
            column += 1usize
        }
        scan += 1usize
    }
    let diag_error = fmt_check_diagnostic(&out, path, first, line, column)
    if diag_error != ok { ret (2usize, diag_error) }
    let result_error = fmt_check_result(&out, false)
    if result_error != ok { ret (2usize, result_error) }
    ret (1usize, ok)
}

fn fmt_check_diagnostic(out: *Out, path: str, byte_at: usize, line: usize, column: usize) -> err {
    try text(out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-FORMAT-0001\",\"message\":\"source is not in canonical layout\",\"span\":{\"source\":{\"root\":\"operand\",\"path\":")
    try quoted(out, path)
    try text(out, "},\"byte_start\":")
    try decimal(out, byte_at)
    try text(out, ",\"byte_end\":")
    try decimal(out, byte_at)
    try text(out, ",\"line\":")
    try decimal(out, line)
    try text(out, ",\"column\":")
    try decimal(out, column)
    try text(out, ",\"end_line\":")
    try decimal(out, line)
    try text(out, ",\"end_column\":")
    try decimal(out, column)
    try text(out, ",\"column_utf16\":")
    try decimal(out, column)
    try text(out, ",\"end_column_utf16\":")
    try decimal(out, column)
    try text(out, "},\"parent\":null,\"related\":[],\"fixes\":[]}")
    ret flush(out)
}

fn fmt_check_result(out: *Out, canonical: bool) -> err {
    if canonical { try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"diagnostics\":0}}") } else { try text(out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":1,\"data\":{\"diagnostics\":1}}") }
    ret flush(out)
}

// `fmt --json` (D234): one `formatted` record whose `text` is the canonical layout.
// `fmt-file PATH` without `--json` (D255): the canonical text itself, for a diff or a pipe.
fn fmt_plain(a: *mem.Arena, source: str) -> err {
    let (formatted, format_error) = format_source(a, source)
    if format_error != ok { ret format_error }
    let stdout = os.stdout()
    var at = 0usize
    while at < formatted.len {
        let (written, write_error) = os.write(stdout, formatted[at..formatted.len])
        if write_error != ok { ret write_error }
        if written == 0usize { ret Capacity }
        at += written
    }
    ret ok
}

fn fmt_json(a: *mem.Arena, source: str) -> (usize, err) {
    let (formatted, format_error) = format_source(a, source)
    if format_error != ok { ret (1usize, format_error) }
    let (storage, storage_error) = mem.alloc[u8](a, formatted.len * 2usize + 4096usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let header_error = header(&out, "fmt")
    if header_error != ok { ret (2usize, header_error) }
    let record_error = fmt_record(&out, formatted)
    if record_error != ok { ret (2usize, record_error) }
    let result_error = fmt_result(&out)
    if result_error != ok { ret (2usize, result_error) }
    ret (0usize, ok)
}

fn fmt_record(out: *Out, formatted: str) -> err {
    try text(out, "{\"record\":\"formatted\",\"text\":")
    try quoted(out, formatted)
    try text(out, "}")
    ret flush(out)
}

fn fmt_result(out: *Out) -> err {
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{}}")
    ret flush(out)
}

// The last path segment, the basename a source identifier uses for a file operand.
fn manifest_basename(path: str) -> str {
    var start = 0usize
    var at = 0usize
    while at < path.len {
        if path[at] == 47u8 || path[at] == 92u8 { start = at + 1usize }
        at += 1usize
    }
    ret path[start..path.len]
}

// The SHA-256 of a module's source bytes, widened one byte per slot for the hasher.
fn manifest_sha256(a: *mem.Arena, content: str) -> (str, err) {
    let (digest, digest_error) = artifact_hash.sha256_hex(a, content)
    ret (digest, digest_error)
}

// `build-manifest --json` (D238): the canonical `neper-build-manifest` object of section 7 --
// versions, target, mode, root module and one input per source module with its SHA-256.
// This command runs no build, so its mode is debug and its artifacts are empty; a build
// writes the same object with its artifact to `.neper/<mode>/build-manifest.json` (D254).
// Not yet: the dependency interface/body split, libraries, assets and non-empty options.
fn manifest_json(a: *mem.Arena, arch: str, os_name: str, g: *graph.Graph) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, 65536usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let build_error = manifest_write(a, &out, arch, os_name, g, "debug", "", "")
    if build_error != ok { ret (2usize, build_error) }
    let flush_error = flush(&out)
    if flush_error != ok { ret (2usize, flush_error) }
    ret (0usize, ok)
}

// The object, into `out`, without a newline: the command flushes it as a record and a
// build saves it as a file. An empty `artifact_path` is no artifact.
fn manifest_write(a: *mem.Arena, out: *Out, arch: str, os_name: str, g: *graph.Graph, mode: str, artifact_path: str, artifact_sha256: str) -> err {
    try text(out, "{\"schema\":\"neper-build-manifest\",\"version\":1,\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":1,\"target\":\"")
    try text(out, arch)
    try byte(out, 45u8)
    try text(out, os_name)
    try text(out, "\",\"mode\":\"")
    try text(out, mode)
    try text(out, "\",\"root_module\":")
    if g.count == 0usize {
        try text(out, "null")
    } else {
        try quoted(out, g.modules[0usize].name)
    }
    try text(out, ",\"inputs\":[")
    var at = 0usize
    while at < g.count {
        if at != 0usize { try byte(out, 44u8) }
        try text(out, "{\"source\":{\"root\":\"operand\",\"path\":")
        try quoted(out, manifest_basename(g.modules[at].path))
        try text(out, "},\"sha256\":")
        let (digest, digest_error) = manifest_sha256(a, g.modules[at].text)
        if digest_error != ok { ret digest_error }
        try quoted(out, digest)
        try byte(out, 125u8)
        at += 1usize
    }
    try text(out, "],\"dependencies\":[],\"libraries\":[],\"assets\":[],\"artifacts\":[")
    if artifact_path.len != 0usize {
        try text(out, "{\"path\":")
        try quoted(out, artifact_path)
        try text(out, ",\"kind\":\"executable\",\"target\":\"")
        try text(out, arch)
        try byte(out, 45u8)
        try text(out, os_name)
        try text(out, "\",\"sha256\":")
        try quoted(out, artifact_sha256)
        try byte(out, 125u8)
    }
    ret text(out, "],\"options\":{}}")
}

fn manifest_join(a: *mem.Arena, dir: str, name: str) -> (str, err) {
    var separator = 1usize
    if dir.len != 0usize && (dir[dir.len - 1usize] == 47u8 || dir[dir.len - 1usize] == 92u8) { separator = 0usize }
    let (buffer, buffer_error) = mem.alloc[u8](a, dir.len + separator + name.len)
    if buffer_error != ok { ret ("", buffer_error) }
    var at = 0usize
    while at < dir.len {
        buffer[at] = dir[at]
        at += 1usize
    }
    if separator == 1usize {
        buffer[at] = 47u8
        at += 1usize
    }
    var from = 0usize
    while from < name.len {
        buffer[at] = name[from]
        at += 1usize
        from += 1usize
    }
    ret (buffer[0usize..at], ok)
}

// Every build writes `.neper/<mode>/build-manifest.json` under the project root (section 7,
// D254) when that directory exists, the executable it just wrote as the one artifact with
// its SHA-256. `main` sits at the bootstrap's local cap, so the mode is settled here.
fn manifest_file(a: *mem.Arena, g: *graph.Graph, arch: str, os_name: str, release_mode: bool, artifact_path: str, packed: []const u8) -> err {
    var mode = "debug"
    if release_mode { mode = "release" }
    let (dot_dir, dot_error) = manifest_join(a, g.project.root, ".neper")
    if dot_error != ok { ret dot_error }
    let (mode_dir, mode_error) = manifest_join(a, dot_dir, mode)
    if mode_error != ok { ret mode_error }
    let (manifest_path, path_error) = manifest_join(a, mode_dir, "build-manifest.json")
    if path_error != ok { ret path_error }
    let (digest, digest_error) = manifest_sha256(a, packed)
    if digest_error != ok { ret digest_error }
    let (storage, storage_error) = mem.alloc[u8](a, 65536usize + g.count * 512usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize }
    try manifest_write(a, &out, arch, os_name, g, mode, artifact_path, digest)
    try byte(&out, 10u8)
    let flags = os.OpenFlags { read: false, write: true, create: true, truncate: true, append: false }
    // The fixed os surface has no mkdir, so `.neper/<mode>/` is the project's to make,
    // once; until it exists the build has nowhere to put the manifest and writes none.
    // ponytail: add os.mkdir to the fixed surface (bootstrap and both runtimes) and make
    // the directory here when a consumer needs the manifest without that step.
    let (file, open_error) = os.open(a, manifest_path, flags)
    if open_error == os.NotFound { ret ok }
    if open_error != ok { ret open_error }
    var at = 0usize
    var write_error = ok
    while at < out.count && write_error == ok {
        let (written, chunk_error) = os.write(file, out.bytes[at..out.count])
        write_error = chunk_error
        if written == 0usize && chunk_error == ok { write_error = Capacity }
        at += written
    }
    let close_error = os.close(file)
    if write_error != ok { ret write_error }
    ret close_error
}

// The section 7 name of a test outcome: 0 passed, 1 failed, 2 crashed.
fn test_outcome_name(outcome: usize) -> str {
    if outcome == 0usize { ret "passed" }
    if outcome == 1usize { ret "failed" }
    if outcome == 2usize { ret "crashed" }
    ret "timeout"
}

// `test --json` (D240): the header, one buffered `test` record per @test function in source
// order, a `test_summary`, and the result -- each with its real wall time (D242), its deadline
// (D246), its error name and a crash's structured trap payload (D253).
fn test_json(a: *mem.Arena, module_name: str, root: str, path: str, source: str, spelled: str, names: []const str, lines: []const usize, outcomes: []const usize, statuses: []const i32, durations: []const usize, stdouts: []const str, stderrs: []const str, count: usize, summary_duration: usize, timeout_s: usize) -> err {
    var capacity = 8192usize
    var at = 0usize
    while at < count {
        capacity += names[at].len + stdouts[at].len * 6usize + stderrs[at].len * 6usize + 512usize
        at += 1usize
    }
    let (storage, storage_error) = mem.alloc[u8](a, capacity)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize }
    try header(&out, "test")
    var passed = 0usize
    var failed = 0usize
    var crashed = 0usize
    var timedout = 0usize
    at = 0usize
    while at < count {
        if outcomes[at] == 0usize {
            passed += 1usize
        } else {
            if outcomes[at] == 1usize {
                failed += 1usize
            } else {
                if outcomes[at] == 2usize { crashed += 1usize } else { timedout += 1usize }
            }
        }
        try test_record(&out, module_name, root, path, source, spelled, names[at], lines[at], outcomes[at], statuses[at], durations[at], timeout_s, stdouts[at], stderrs[at])
        at += 1usize
    }
    try text(&out, "{\"record\":\"test_summary\",\"passed\":")
    try decimal(&out, passed)
    try text(&out, ",\"failed\":")
    try decimal(&out, failed)
    try text(&out, ",\"crashed\":")
    try decimal(&out, crashed)
    try text(&out, ",\"timeout\":")
    try decimal(&out, timedout)
    try text(&out, ",\"total\":")
    try decimal(&out, count)
    try text(&out, ",\"duration_ms\":")
    try decimal(&out, summary_duration)
    try byte(&out, 125u8)
    try flush(&out)
    var succeeded = failed == 0usize && crashed == 0usize && timedout == 0usize
    if succeeded { try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"tests\":") } else { try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":1,\"data\":{\"tests\":") }
    try decimal(&out, count)
    try text(&out, "}}")
    ret flush(&out)
}

// The runner is the operand's text two `use` lines down (D240), and `spelled` is its
// path as the child prints it; a trap or an error name in it maps back onto the operand.
fn test_record(out: *Out, module_name: str, root: str, path: str, source: str, spelled: str, name: str, line: usize, outcome: usize, status: i32, duration_ms: usize, timeout_s: usize, stdout_bytes: str, stderr_bytes: str) -> err {
    try text(out, "{\"record\":\"test\",\"name\":")
    try quoted(out, name)
    try text(out, ",\"module\":")
    try quoted(out, module_name)
    try text(out, ",\"file\":{\"root\":")
    try quoted(out, root)
    try text(out, ",\"path\":")
    try quoted(out, path)
    try text(out, "},\"line\":")
    try decimal(out, line)
    try text(out, ",\"outcome\":")
    try quoted(out, test_outcome_name(outcome))
    try text(out, ",\"error\":")
    if outcome == 0usize {
        try text(out, "\"ok\"")
    } else {
        if outcome == 1usize { try test_error_name(out, stderr_bytes, module_name, "nptest-runner.e") } else { try text(out, "null") }
    }
    try text(out, ",\"message\":null,\"duration_ms\":")
    try decimal(out, duration_ms)
    try text(out, ",\"timeout_s\":")
    try decimal(out, timeout_s)
    try text(out, ",\"stdout\":")
    try captured(out, stdout_bytes)
    try text(out, ",\"stderr\":")
    try captured(out, stderr_bytes)
    try text(out, ",\"trap\":")
    // A crash with no trap record is section 7's `exit` kind, its values the status.
    if outcome == 2usize && stderr_bytes.len >= 7usize && graph.same(stderr_bytes[0usize..7usize], "error: ") == false {
        var probe = 0usize
        var recorded = false
        while probe + 7usize <= stderr_bytes.len && recorded == false {
            if graph.same(stderr_bytes[probe..probe + 7usize], ": trap[") { recorded = true }
            probe += 1usize
        }
        if recorded {
            try trap_json(out, stderr_bytes, module_name, path, source, spelled, 2usize)
        } else {
            try text(out, "{\"kind\":\"exit\",\"span\":null,\"values\":[\"")
            if status < 0i32 {
                try byte(out, 45u8)
                try decimal(out, usize(0i32 - status))
            } else {
                try decimal(out, usize(status))
            }
            try text(out, "\"],\"backtrace\":[]}")
        }
    } else {
        try trap_json(out, stderr_bytes, module_name, path, source, spelled, 2usize)
    }
    try byte(out, 125u8)
    ret flush(out)
}

// The public name of a token kind, the registry of docs/grammar.ebnf.
fn kind_name(kind: lex.Kind) -> str {
    if kind == .Invalid { ret "INVALID" }
    if kind == .Eof { ret "EOF" }
    if kind == .Newline { ret "NEWLINE" }
    if kind == .Identifier { ret "IDENTIFIER" }
    if kind == .Integer { ret "INTEGER" }
    if kind == .Float { ret "FLOAT" }
    if kind == .String { ret "STRING" }
    if kind == .RawString { ret "RAW_STRING" }
    if kind == .Character { ret "CHARACTER" }
    if kind == .KwUse { ret "KW_USE" }
    if kind == .KwType { ret "KW_TYPE" }
    if kind == .KwConst { ret "KW_CONST" }
    if kind == .KwVar { ret "KW_VAR" }
    if kind == .KwLet { ret "KW_LET" }
    if kind == .KwFn { ret "KW_FN" }
    if kind == .KwRet { ret "KW_RET" }
    if kind == .KwIf { ret "KW_IF" }
    if kind == .KwElse { ret "KW_ELSE" }
    if kind == .KwWhile { ret "KW_WHILE" }
    if kind == .KwFor { ret "KW_FOR" }
    if kind == .KwIn { ret "KW_IN" }
    if kind == .KwSwitch { ret "KW_SWITCH" }
    if kind == .KwCase { ret "KW_CASE" }
    if kind == .KwDefault { ret "KW_DEFAULT" }
    if kind == .KwBreak { ret "KW_BREAK" }
    if kind == .KwContinue { ret "KW_CONTINUE" }
    if kind == .KwDefer { ret "KW_DEFER" }
    if kind == .KwTry { ret "KW_TRY" }
    if kind == .KwStruct { ret "KW_STRUCT" }
    if kind == .KwUnion { ret "KW_UNION" }
    if kind == .KwEnum { ret "KW_ENUM" }
    if kind == .KwError { ret "KW_ERROR" }
    if kind == .KwWhen { ret "KW_WHEN" }
    if kind == .KwTrue { ret "KW_TRUE" }
    if kind == .KwFalse { ret "KW_FALSE" }
    if kind == .KwNil { ret "KW_NIL" }
    if kind == .KwOk { ret "KW_OK" }
    if kind == .KwAs { ret "KW_AS" }
    if kind == .KwZero { ret "KW_ZERO" }
    if kind == .KwUndef { ret "KW_UNDEF" }
    if kind == .KwExtern { ret "KW_EXTERN" }
    if kind == .KwUnreachable { ret "KW_UNREACHABLE" }
    if kind == .KwShared { ret "KW_SHARED" }
    if kind == .PunctEllipsis { ret "PUNCT_ELLIPSIS" }
    if kind == .PunctRange { ret "PUNCT_RANGE" }
    if kind == .PunctArrow { ret "PUNCT_ARROW" }
    if kind == .PunctEqEq { ret "PUNCT_EQ_EQ" }
    if kind == .PunctBangEq { ret "PUNCT_BANG_EQ" }
    if kind == .PunctLtEq { ret "PUNCT_LT_EQ" }
    if kind == .PunctGtEq { ret "PUNCT_GT_EQ" }
    if kind == .PunctShiftLeft { ret "PUNCT_SHIFT_LEFT" }
    if kind == .PunctShiftRight { ret "PUNCT_SHIFT_RIGHT" }
    if kind == .PunctAddWrap { ret "PUNCT_ADD_WRAP" }
    if kind == .PunctSubWrap { ret "PUNCT_SUB_WRAP" }
    if kind == .PunctMulWrap { ret "PUNCT_MUL_WRAP" }
    if kind == .PunctAddAssign { ret "PUNCT_ADD_ASSIGN" }
    if kind == .PunctSubAssign { ret "PUNCT_SUB_ASSIGN" }
    if kind == .PunctMulAssign { ret "PUNCT_MUL_ASSIGN" }
    if kind == .PunctDivAssign { ret "PUNCT_DIV_ASSIGN" }
    if kind == .PunctRemAssign { ret "PUNCT_REM_ASSIGN" }
    if kind == .PunctAddWrapAssign { ret "PUNCT_ADD_WRAP_ASSIGN" }
    if kind == .PunctSubWrapAssign { ret "PUNCT_SUB_WRAP_ASSIGN" }
    if kind == .PunctMulWrapAssign { ret "PUNCT_MUL_WRAP_ASSIGN" }
    if kind == .PunctShiftLeftAssign { ret "PUNCT_SHIFT_LEFT_ASSIGN" }
    if kind == .PunctShiftRightAssign { ret "PUNCT_SHIFT_RIGHT_ASSIGN" }
    if kind == .PunctBitAndAssign { ret "PUNCT_BIT_AND_ASSIGN" }
    if kind == .PunctBitXorAssign { ret "PUNCT_BIT_XOR_ASSIGN" }
    if kind == .PunctBitOrAssign { ret "PUNCT_BIT_OR_ASSIGN" }
    if kind == .PunctAndAnd { ret "PUNCT_AND_AND" }
    if kind == .PunctOrOr { ret "PUNCT_OR_OR" }
    if kind == .PunctAt { ret "PUNCT_AT" }
    if kind == .PunctDot { ret "PUNCT_DOT" }
    if kind == .PunctComma { ret "PUNCT_COMMA" }
    if kind == .PunctColon { ret "PUNCT_COLON" }
    if kind == .PunctAssign { ret "PUNCT_ASSIGN" }
    if kind == .PunctLParen { ret "PUNCT_LPAREN" }
    if kind == .PunctRParen { ret "PUNCT_RPAREN" }
    if kind == .PunctLBracket { ret "PUNCT_LBRACKET" }
    if kind == .PunctRBracket { ret "PUNCT_RBRACKET" }
    if kind == .PunctLBrace { ret "PUNCT_LBRACE" }
    if kind == .PunctRBrace { ret "PUNCT_RBRACE" }
    if kind == .PunctStar { ret "PUNCT_STAR" }
    if kind == .PunctSlash { ret "PUNCT_SLASH" }
    if kind == .PunctPercent { ret "PUNCT_PERCENT" }
    if kind == .PunctPlus { ret "PUNCT_PLUS" }
    if kind == .PunctMinus { ret "PUNCT_MINUS" }
    if kind == .PunctLt { ret "PUNCT_LT" }
    if kind == .PunctGt { ret "PUNCT_GT" }
    if kind == .PunctAmp { ret "PUNCT_AMP" }
    if kind == .PunctCaret { ret "PUNCT_CARET" }
    if kind == .PunctPipe { ret "PUNCT_PIPE" }
    if kind == .PunctBang { ret "PUNCT_BANG" }
    if kind == .PunctTilde { ret "PUNCT_TILDE" }
    ret "PUNCT_UNDERSCORE"
}

fn trivia_name(kind: lex.TriviaKind) -> str {
    if kind == .Bom { ret "bom" }
    if kind == .Space { ret "space" }
    ret "comment"
}

// The `diagnostic` and `token` records of a token list: a diagnostic before each
// `INVALID` token, and a token record per token through `EOF`. The trivia text and
// the lexemes concatenate back to every original byte. Returns the exit code.
fn token_records(out: *Out, root: str, path: str, source: str, tokens: []const lex.Token) -> (usize, err) {
    var index = 0usize
    var diagnostics = 0usize
    while index < tokens.len {
        let token = tokens[index]
        if token.kind == .Invalid {
            let d1 = text(out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":")
            if d1 != ok { ret (2usize, d1) }
            let d2 = quoted(out, lex.invalid_code(source, token))
            if d2 != ok { ret (2usize, d2) }
            let d3 = text(out, ",\"message\":\"invalid token\",\"span\":")
            if d3 != ok { ret (2usize, d3) }
            let d4 = span(out, root, path, token.start, token.end, token.line, token.column, token.end_line, token.end_column, token.column_utf16, token.end_column_utf16)
            if d4 != ok { ret (2usize, d4) }
            let d5 = text(out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
            if d5 != ok { ret (2usize, d5) }
            let d6 = flush(out)
            if d6 != ok { ret (2usize, d6) }
            diagnostics += 1usize
        }
        let record_error = token_record(out, root, path, source, token, index)
        if record_error != ok { ret (2usize, record_error) }
        index += 1usize
    }
    if diagnostics != 0usize { ret (1usize, ok) }
    ret (0usize, ok)
}

fn token_record(out: *Out, root: str, path: str, source: str, token: lex.Token, index: usize) -> err {
    try text(out, "{\"record\":\"token\",\"index\":")
    try decimal(out, index)
    try text(out, ",\"kind\":")
    try quoted(out, kind_name(token.kind))
    try text(out, ",\"lexeme\":")
    if token.kind == .Invalid {
        try base64_object(out, source[token.start..token.end])
    } else {
        try quoted(out, source[token.start..token.end])
    }
    try text(out, ",\"span\":")
    try span(out, root, path, token.start, token.end, token.line, token.column, token.end_line, token.end_column, token.column_utf16, token.end_column_utf16)
    try text(out, ",\"leading_trivia\":[")
    var trivia_scanner = lex.trivia_init(source, token)
    var first_trivia = true
    while true {
        let item = lex.next_trivia(&trivia_scanner)
        if item.kind == .End { break }
        if !first_trivia { try byte(out, 44u8) }
        first_trivia = false
        try text(out, "{\"kind\":")
        try quoted(out, trivia_name(item.kind))
        try text(out, ",\"text\":")
        try quoted(out, source[item.start..item.end])
        try text(out, ",\"span\":")
        try span(out, root, path, item.start, item.end, item.line, item.column, item.end_line, item.end_column, item.column_utf16, item.end_column_utf16)
        try byte(out, 125u8)
    }
    try text(out, "]}")
    ret flush(out)
}

// Every token of the source, `EOF` last.
fn scan_all(a: *mem.Arena, source: str) -> ([]lex.Token, usize, usize, err) {
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, source.len + 2usize)
    if tokens_error != ok { ret (tokens, 0usize, 0usize, tokens_error) }
    var count = 0usize
    var invalid = 0usize
    var scanner = lex.init(source)
    while true {
        let token = lex.next(&scanner)
        if count == tokens.len { ret (tokens, 0usize, 0usize, Capacity) }
        tokens[count] = token
        count += 1usize
        if token.kind == .Invalid { invalid += 1usize }
        if token.kind == .Eof { break }
    }
    ret (tokens, count, invalid, ok)
}

// `tokens --json`: the header, the token records, the result.
fn tokens_json(a: *mem.Arena, root: str, path: str, source: str) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 4096usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let header_error = header(&out, "tokens")
    if header_error != ok { ret (2usize, header_error) }
    let (tokens, count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    let (exit_code, records_error) = token_records(&out, root, path, source, tokens[..count])
    if records_error != ok { ret (2usize, records_error) }
    let result_error = result(&out, invalid == 0usize, exit_code, count, invalid)
    if result_error != ok { ret (2usize, result_error) }
    ret (exit_code, ok)
}

// The public name of a syntax-node kind: the registry names the enum's own.
fn node_kind_name(kind: syntax.Kind) -> str {
    if kind == .File { ret "File" }
    if kind == .UseDecl { ret "UseDecl" }
    if kind == .Attribute { ret "Attribute" }
    if kind == .TypeDecl { ret "TypeDecl" }
    if kind == .ConstDecl { ret "ConstDecl" }
    if kind == .VarDecl { ret "VarDecl" }
    if kind == .ErrorDecl { ret "ErrorDecl" }
    if kind == .FnDecl { ret "FnDecl" }
    if kind == .ExternDecl { ret "ExternDecl" }
    if kind == .ComptimeParam { ret "ComptimeParam" }
    if kind == .Parameter { ret "Parameter" }
    if kind == .ReturnSpec { ret "ReturnSpec" }
    if kind == .StructType { ret "StructType" }
    if kind == .UnionType { ret "UnionType" }
    if kind == .EnumType { ret "EnumType" }
    if kind == .UnionEnumType { ret "UnionEnumType" }
    if kind == .FieldDecl { ret "FieldDecl" }
    if kind == .EnumMember { ret "EnumMember" }
    if kind == .UnionMember { ret "UnionMember" }
    if kind == .PointerType { ret "PointerType" }
    if kind == .SliceType { ret "SliceType" }
    if kind == .ArrayType { ret "ArrayType" }
    if kind == .FunctionType { ret "FunctionType" }
    if kind == .NamedType { ret "NamedType" }
    if kind == .Block { ret "Block" }
    if kind == .Binding { ret "Binding" }
    if kind == .BindingStmt { ret "BindingStmt" }
    if kind == .AssignmentStmt { ret "AssignmentStmt" }
    if kind == .CallStmt { ret "CallStmt" }
    if kind == .TryStmt { ret "TryStmt" }
    if kind == .ReturnStmt { ret "ReturnStmt" }
    if kind == .DeferStmt { ret "DeferStmt" }
    if kind == .NocheckStmt { ret "NocheckStmt" }
    if kind == .SharedVarStmt { ret "SharedVarStmt" }
    if kind == .BreakStmt { ret "BreakStmt" }
    if kind == .ContinueStmt { ret "ContinueStmt" }
    if kind == .IfStmt { ret "IfStmt" }
    if kind == .WhileStmt { ret "WhileStmt" }
    if kind == .ForStmt { ret "ForStmt" }
    if kind == .WhenStmt { ret "WhenStmt" }
    if kind == .SwitchStmt { ret "SwitchStmt" }
    if kind == .SwitchArm { ret "SwitchArm" }
    if kind == .UnaryExpr { ret "UnaryExpr" }
    if kind == .BinaryExpr { ret "BinaryExpr" }
    if kind == .FieldExpr { ret "FieldExpr" }
    if kind == .BracketPostfix { ret "BracketPostfix" }
    if kind == .CallExpr { ret "CallExpr" }
    if kind == .NameExpr { ret "NameExpr" }
    if kind == .MemberExpr { ret "MemberExpr" }
    if kind == .GroupExpr { ret "GroupExpr" }
    if kind == .AggregateLiteral { ret "AggregateLiteral" }
    if kind == .LiteralItem { ret "LiteralItem" }
    if kind == .LiteralExpr { ret "LiteralExpr" }
    ret "ErrorNode"
}

// One node of the syntax record: its kind, its span from its first token's start to
// its last token's end, its token range, and its children in order.
fn syntax_node(out: *Out, tree: *parse.Tree, tokens: []const lex.Token, node_index: usize, root: str, path: str, depth: usize) -> err {
    if depth > 512usize { ret Capacity }
    let node = tree.nodes[node_index]
    try text(out, "{\"kind\":")
    try quoted(out, node_kind_name(node.kind))
    try text(out, ",\"span\":")
    if node.token_end > node.token_start && node.token_end <= tokens.len {
        let first = tokens[node.token_start]
        let last = tokens[node.token_end - 1usize]
        try span(out, root, path, first.start, last.end, first.line, first.column, last.end_line, last.end_column, first.column_utf16, last.end_column_utf16)
    } else {
        var at_token = node.token_start
        if at_token >= tokens.len { at_token = tokens.len - 1usize }
        let here = tokens[at_token]
        try span(out, root, path, here.start, here.start, here.line, here.column, here.line, here.column, here.column_utf16, here.column_utf16)
    }
    try text(out, ",\"token_start\":")
    try decimal(out, node.token_start)
    try text(out, ",\"token_end\":")
    try decimal(out, node.token_end)
    try text(out, ",\"children\":[")
    var first_child = true
    if node.kind == .File && node_index == 0usize {
        // The root lists no children of its own: the top-level nodes are its, in order.
        var top = 1usize
        while top < tree.count {
            if tree.nodes[top].top_level {
                if !first_child { try byte(out, 44u8) }
                first_child = false
                try text(out, "{\"node\":")
                try syntax_node(out, tree, tokens, top, root, path, depth + 1usize)
                try byte(out, 125u8)
            }
            top += 1usize
        }
    } else {
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if !first_child { try byte(out, 44u8) }
            first_child = false
            let child = tree.children[at]
            if child.node {
                try text(out, "{\"node\":")
                try syntax_node(out, tree, tokens, child.index, root, path, depth + 1usize)
                try byte(out, 125u8)
            } else {
                try text(out, "{\"token\":")
                try decimal(out, child.index)
                try byte(out, 125u8)
            }
            at += 1usize
        }
    }
    ret text(out, "]}")
}

// `parse --json`: the token records as `tokens` gives them, a syntax diagnostic where
// the parser stopped, one `syntax` record for the tree that exists, and the result.
fn parse_json(a: *mem.Arena, root: str, path: str, source: str) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 4096usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let header_error = header(&out, "parse")
    if header_error != ok { ret (2usize, header_error) }
    let (tokens, count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    var diagnostics = invalid
    let (token_exit, token_records_error) = token_records(&out, root, path, source, tokens[..count])
    if token_records_error != ok { ret (2usize, token_records_error) }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, count + 16usize)
    if nodes_error != ok { ret (2usize, nodes_error) }
    let (children, children_error) = mem.alloc[syntax.Child](a, count * 2usize + 16usize)
    if children_error != ok { ret (2usize, children_error) }
    var tree: parse.Tree = zero
    let init_error = parse.init_tree(&tree, nodes, children)
    if init_error != ok { ret (2usize, init_error) }
    let parse_error = parse.parse(&tree, source)
    if parse_error != ok {
        diagnostics += 1usize
        var at = tree.failure_token
        if !tree.has_failure { at = tokens[count - 1usize] }
        let d1 = text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-SYNTAX-9999\",\"message\":\"unexpected token\",\"span\":")
        if d1 != ok { ret (2usize, d1) }
        let d2 = span(&out, root, path, at.start, at.end, at.line, at.column, at.end_line, at.end_column, at.column_utf16, at.end_column_utf16)
        if d2 != ok { ret (2usize, d2) }
        let d3 = text(&out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
        if d3 != ok { ret (2usize, d3) }
        let d4 = flush(&out)
        if d4 != ok { ret (2usize, d4) }
    }
    // The tree can outgrow the record buffer the tokens used: one sized to it.
    let (tree_storage, tree_storage_error) = mem.alloc[u8](a, tree.count * 512usize + tree.child_count * 32usize + 4096usize)
    if tree_storage_error != ok { ret (2usize, tree_storage_error) }
    var tree_out = Out { bytes: tree_storage, count: 0usize }
    let s1 = text(&tree_out, "{\"record\":\"syntax\",\"root\":")
    if s1 != ok { ret (2usize, s1) }
    let s2 = syntax_node(&tree_out, &tree, tokens[..count], 0usize, root, path, 0usize)
    if s2 != ok { ret (2usize, s2) }
    let s3 = text(&tree_out, "}")
    if s3 != ok { ret (2usize, s3) }
    let s4 = flush(&tree_out)
    if s4 != ok { ret (2usize, s4) }
    var exit_code = 0usize
    if diagnostics != 0usize { exit_code = 1usize }
    let result_error = result(&out, diagnostics == 0usize, exit_code, count, diagnostics)
    if result_error != ok { ret (2usize, result_error) }
    ret (exit_code, ok)
}
