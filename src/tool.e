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
use project
use codegen_x64
use artifact_hash
use disasm_x64

error Capacity
error InvalidSource

// One record at a time: built here, printed whole, so a line is never split.
type Out = struct {
    bytes: []u8,
    count: usize,
    // `--absolute-paths` (section 2, D290): the operand's absolute spelling, written as
    // `absolute_path` beside every source identity when it is not empty.
    absolute: str,
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
    if out.absolute.len != 0usize {
        try text(out, ",\"absolute_path\":")
        try quoted(out, out.absolute)
    }
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
    var out = Out { bytes: storage, count: 0usize, absolute: "" }
    try header(&out, "info")
    try text(&out, "{\"record\":\"info\",\"tool_version\":\"0.1.0\",\"language_profiles\":[{\"language_version\":\"0.1\",\"grammar_revision\":1,\"stream_version\":1,\"experimental\":false}],\"commands\":[\"build\",\"check\",\"dis\",\"fmt\",\"index\",\"info\",\"parse\",\"run\",\"test\",\"tokens\"],\"host_target\":")
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
    var out = Out { bytes: storage, count: 0usize, absolute: "" }
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
// (D251), and under a function or type its parameters, fields and members from the parse
// tree (D258). Locals and every reference are the gap.
fn index_json(a: *mem.Arena, root: str, path: str, source: str, module_name: str, module_index: usize, symbols: []const resolve.Symbol, count: usize, absolute: str) -> (usize, err) {
    let (tokens, token_count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, source.len + 1024usize)
    if nodes_error != ok { ret (2usize, nodes_error) }
    let (children, children_error) = mem.alloc[syntax.Child](a, source.len + 1024usize)
    if children_error != ok { ret (2usize, children_error) }
    var tree: parse.Tree = zero
    let init_error = parse.init_tree(&tree, nodes, children)
    if init_error != ok { ret (2usize, init_error) }
    let parse_error = parse.parse(&tree, source)
    if parse_error != ok { ret (2usize, parse_error) }
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 8192usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize, absolute: absolute }
    let header_error = header(&out, "index")
    if header_error != ok { ret (2usize, header_error) }
    // The module itself is the first symbol, so every declaration's container is id 0.
    let module_error = index_module_record(&out, module_name)
    if module_error != ok { ret (2usize, module_error) }
    // Every module-scope name and its id, for the references (D271).
    let (known_names, known_names_error) = mem.alloc[str](a, count + 1usize)
    if known_names_error != ok { ret (2usize, known_names_error) }
    let (known_ids, known_ids_error) = mem.alloc[usize](a, count + 1usize)
    if known_ids_error != ok { ret (2usize, known_ids_error) }
    let (known_types, known_types_error) = mem.alloc[bool](a, count + 1usize)
    if known_types_error != ok { ret (2usize, known_types_error) }
    var known = 0usize
    // The references are collected first and put out in span order between the symbols
    // (D280): every reference before a declaration's start goes before that symbol.
    var known_pass = 0usize
    var running = 1usize
    while known_pass < count {
        let known_symbol = symbols[known_pass]
        if known_symbol.module_index == module_index && known_symbol.kind != .Qualifier && known_symbol.kind != .Intrinsic {
            known_names[known] = known_symbol.name
            known_ids[known] = running
            known_types[known] = known_symbol.kind == .Type
            known += 1usize
            running += 1usize
            // The ids a declaration's nested symbols will take (D258).
            if known_symbol.kind == .Function || known_symbol.kind == .Type || known_symbol.kind == .Extern { running += index_nested_count(&tree, known_symbol.token_start, known_symbol.token_end - 1usize) }
        }
        known_pass += 1usize
    }
    let known_total = known
    let (collected, collect_error) = index_collect_references(a, source, &tree, tokens[0usize..token_count])
    if collect_error != ok { ret (2usize, collect_error) }
    var refs = collected
    refs.known_names = known_names[0usize..known_total]
    refs.known_ids = known_ids[0usize..known_total]
    refs.known_types = known_types[0usize..known_total]
    known = 0usize
    var emitted = 1usize
    var at = 0usize
    while at < count {
        let symbol = symbols[at]
        if symbol.module_index == module_index && symbol.kind != .Qualifier && symbol.kind != .Intrinsic {
            let interleave_error = index_emit_references(&refs, &out, root, path, source, module_name, &tree, tokens[0usize..token_count], tokens[symbol.token_start].start)
            if interleave_error != ok { ret (2usize, interleave_error) }
            if known_ids[known] != emitted { ret (2usize, parse.InvalidSyntax) }
            known += 1usize
            var name_index = symbol.token_start + 1usize
            if symbol.kind == .Extern { name_index += 1usize }
            if symbol.token_end == 0usize || symbol.token_end > token_count || name_index >= token_count { ret (2usize, parse.InvalidSyntax) }
            let record_error = index_symbol_record(&out, root, path, source, module_name, emitted, symbol, tokens[0usize..token_count], symbol.token_start, symbol.token_end - 1usize, name_index)
            if record_error != ok { ret (2usize, record_error) }
            emitted += 1usize
            if symbol.kind == .Function || symbol.kind == .Type || symbol.kind == .Extern {
                let (owner_storage, owner_error) = mem.alloc[u8](a, module_name.len + 1usize + symbol.name.len)
                if owner_error != ok { ret (2usize, owner_error) }
                var owner_at = 0usize
                while owner_at < module_name.len {
                    owner_storage[owner_at] = module_name[owner_at]
                    owner_at += 1usize
                }
                owner_storage[owner_at] = 46u8
                owner_at += 1usize
                var name_at = 0usize
                while name_at < symbol.name.len {
                    owner_storage[owner_at] = symbol.name[name_at]
                    owner_at += 1usize
                    name_at += 1usize
                }
                let (nested, nested_error) = index_nested(a, &out, root, path, source, module_name, owner_storage[0usize..owner_at], &tree, tokens[0usize..token_count], symbol.token_start, symbol.token_end - 1usize, emitted - 1usize, emitted, &refs)
                if nested_error != ok { ret (2usize, nested_error) }
                emitted += nested
            }
        }
        at += 1usize
    }
    let drain_error = index_emit_references(&refs, &out, root, path, source, module_name, &tree, tokens[0usize..token_count], source.len + 1usize)
    if drain_error != ok { ret (2usize, drain_error) }
    let result_error = index_result(&out, emitted, refs.written)
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
    ret index_record(out, root, path, source, module_name, id, index_kind_name(symbol.kind), symbol.name, module_name, tokens, first, last, name_index, 0usize)
}

// One symbol record: `owner` is the qualified name this one nests under -- the module for
// a declaration, `module.Type` for a field or member, `module.fn` for a parameter (D258).
fn index_record(out: *Out, root: str, path: str, source: str, module_name: str, id: usize, kind: str, name: str, owner: str, tokens: []const lex.Token, first: usize, last: usize, name_index: usize, container_id: usize) -> err {
    let opener = tokens[first]
    let closer = tokens[last]
    let name_token = tokens[name_index]
    let attribute_start = index_attribute_start(tokens, first)
    try text(out, "{\"record\":\"symbol\",\"id\":")
    try decimal(out, id)
    try text(out, ",\"kind\":")
    try quoted(out, kind)
    try text(out, ",\"name\":")
    try quoted(out, name)
    try text(out, ",\"qualified_name\":")
    try index_qualified(out, owner, name)
    try text(out, ",\"module\":")
    try quoted(out, module_name)
    try text(out, ",\"signature\":")
    try index_signature(out, source, tokens, first, last)
    try text(out, ",\"span\":")
    try span(out, root, path, opener.start, closer.end, opener.line, opener.column, closer.end_line, closer.end_column, opener.column_utf16, closer.end_column_utf16)
    try text(out, ",\"selection_span\":")
    try span(out, root, path, name_token.start, name_token.end, name_token.line, name_token.column, name_token.end_line, name_token.end_column, name_token.column_utf16, name_token.end_column_utf16)
    try text(out, ",\"container_id\":")
    try decimal(out, container_id)
    try text(out, ",\"attributes\":")
    try index_attributes(out, source, tokens, attribute_start, first)
    try text(out, ",\"documentation\":")
    try index_documentation(out, source, tokens, attribute_start)
    try byte(out, 125u8)
    ret flush(out)
}

// How many nested symbols index_nested will emit for the declaration at [first, last].
fn index_nested_count(tree: *parse.Tree, first: usize, last: usize) -> usize {
    var found = 0usize
    var node_index = 1usize
    while node_index < tree.count && found < 256usize {
        let node = tree.nodes[node_index]
        if !node.top_level && node.token_start >= first && node.token_start <= last && node.token_end > node.token_start && index_nested_kind(node.kind).len != 0usize { found += 1usize }
        node_index += 1usize
    }
    ret found
}

// The section 7 kind of a nested declaration node, or "" for a node that is not one.
fn index_nested_kind(kind: syntax.Kind) -> str {
    if kind == .Parameter { ret "parameter" }
    if kind == .FieldDecl { ret "field" }
    if kind == .EnumMember || kind == .UnionMember { ret "member" }
    ret ""
}

// The parameters, fields and members declared inside the top-level declaration whose
// tokens are [first, last]: each nested node starts at its name token, so one pass over
// the tree keeps the ones whose start lies in that range, and they go out in token
// order, since the parser appends a child before its parent (D258). Returns how many
// records were written; `owner` is the declaration's qualified name.
// ponytail: 256 nested declarations per top-level one is the cap; raise it if a struct needs more.
fn index_nested(a: *mem.Arena, out: *Out, root: str, path: str, source: str, module_name: str, owner: str, tree: *parse.Tree, tokens: []const lex.Token, first: usize, last: usize, container_id: usize, next_id: usize, refs: *IndexRefs) -> (usize, err) {
    var picked: [256]usize = zero
    var picked_count = 0usize
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if !node.top_level && node.token_start >= first && node.token_start <= last && node.token_end > node.token_start && index_nested_kind(node.kind).len != 0usize && picked_count < 256usize {
            // Insertion by token position keeps the list ordered as it grows.
            var slot = picked_count
            while slot > 0usize && tree.nodes[picked[slot - 1usize]].token_start > node.token_start {
                picked[slot] = picked[slot - 1usize]
                slot = slot - 1usize
            }
            picked[slot] = node_index
            picked_count += 1usize
        }
        node_index += 1usize
    }
    var written = 0usize
    while written < picked_count {
        let node = tree.nodes[picked[written]]
        let name_token = tokens[node.token_start]
        // References inside the signature so far come before this symbol (D280).
        let interleave_error = index_emit_references(refs, out, root, path, source, module_name, tree, tokens, name_token.start)
        if interleave_error != ok { ret (0usize, interleave_error) }
        let nested_error = index_record(out, root, path, source, module_name, next_id + written, index_nested_kind(node.kind), source[name_token.start..name_token.end], owner, tokens, node.token_start, node.token_end - 1usize, node.token_start, container_id)
        if nested_error != ok { ret (0usize, nested_error) }
        written += 1usize
    }
    ret (written, ok)
}

// The `reference` records (D271): every use of a module-scope name of the operand, and
// every use of a name through a `use` qualifier, classified by the tokens around it --
// `f(` is a call, `f[` an instantiation, `= x` a write, `&x` an address, a type position
// a type, a `use` an import, anything else a read. A bare name is one of the operand's
// own symbols or nothing: spec section 5 lets no local shadow a module-scope name, so
// the match is the resolution. Records go out sorted by span start.
// ponytail: 4096 references per module is the cap; raise it when a module has more.
type IndexRefs = struct {
    known_names: []const str,
    known_ids: []const usize,
    known_types: []const bool,
    qualifiers: []str,
    paths: []str,
    imports: usize,
    nodes: []usize,
    roles: []usize,
    picked: usize,
    next: usize,
    written: usize,
}

// The collection half: every candidate node, sorted by span start (D280).
fn index_collect_references(a: *mem.Arena, source: str, tree: *parse.Tree, tokens: []const lex.Token) -> (IndexRefs, err) {
    var state: IndexRefs = zero
    // The imports: qualifier and module path, from every `use`.
    let (qualifiers, qualifiers_error) = mem.alloc[str](a, 256usize)
    if qualifiers_error != ok { ret (state, qualifiers_error) }
    let (paths, paths_error) = mem.alloc[str](a, 256usize)
    if paths_error != ok { ret (state, paths_error) }
    var imports = 0usize
    let (starts, starts_error) = mem.alloc[usize](a, 4096usize)
    if starts_error != ok { ret (state, starts_error) }
    let (nodes, nodes_error) = mem.alloc[usize](a, 4096usize)
    if nodes_error != ok { ret (state, nodes_error) }
    let (roles, roles_error) = mem.alloc[usize](a, 4096usize)
    if roles_error != ok { ret (state, roles_error) }
    var picked = 0usize
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        var role = 99usize
        if node.kind == .UseDecl {
            role = 0usize
            if imports < 256usize {
                // `use a.b.c [as q]`: the qualifier is the alias or the last segment.
                var last = node.token_start + 1usize
                var path_end = last
                while path_end + 1usize < node.token_end && (tokens[path_end + 1usize].kind == .PunctDot || tokens[path_end + 1usize].kind == .Identifier) && tokens[path_end + 1usize].kind != .KwAs {
                    path_end += 1usize
                    if tokens[path_end].kind == .Identifier { last = path_end }
                }
                var qualifier = tokens[last]
                if path_end + 2usize < node.token_end && tokens[path_end + 1usize].kind == .KwAs { qualifier = tokens[path_end + 2usize] }
                qualifiers[imports] = source[qualifier.start..qualifier.end]
                paths[imports] = source[tokens[node.token_start + 1usize].start..tokens[path_end].end]
                imports += 1usize
            }
        }
        if node.kind == .NameExpr || node.kind == .NamedType { role = 1usize }
        var wanted = role == 0usize
        if role == 1usize && node.token_end > node.token_start && tokens[node.token_start].kind == .Identifier { wanted = true }
        if wanted && picked < 4096usize {
            var slot = picked
            while slot > 0usize && tree.nodes[nodes[slot - 1usize]].token_start > node.token_start {
                nodes[slot] = nodes[slot - 1usize]
                roles[slot] = roles[slot - 1usize]
                slot = slot - 1usize
            }
            nodes[slot] = node_index
            roles[slot] = role
            picked += 1usize
        }
        node_index += 1usize
    }
    state.qualifiers = qualifiers
    state.paths = paths
    state.imports = imports
    state.nodes = nodes
    state.roles = roles
    state.picked = picked
    ret (state, ok)
}

// The emission half: the references whose span starts before `before`, in order, so
// symbols and references interleave in one span order (D280); `before` past the source
// drains the rest.
fn index_emit_references(state: *IndexRefs, out: *Out, root: str, path: str, source: str, module_name: str, tree: *parse.Tree, tokens: []const lex.Token, before: usize) -> err {
    let known_names = state.known_names
    let known_ids = state.known_ids
    let known_types = state.known_types
    let qualifiers = state.qualifiers
    let paths = state.paths
    let imports = state.imports
    let nodes = state.nodes
    let roles = state.roles
    var at = state.next
    while at < state.picked && tokens[tree.nodes[nodes[at]].token_start].start < before {
        let node = tree.nodes[nodes[at]]
        if roles[at] == 0usize {
            // The import: spelled as the path, its found the module.
            let path_start = tokens[node.token_start + 1usize]
            var path_end = node.token_start + 1usize
            while path_end + 1usize < node.token_end && tokens[path_end + 1usize].kind != .KwAs { path_end += 1usize }
            let spelling = source[path_start.start..tokens[path_end].end]
            let import_error = reference_record(out, root, path, path_start, tokens[path_end], "import", spelling, 0usize, false, spelling)
            if import_error != ok { ret import_error }
            state.written += 1usize
        } else {
            let first = node.token_start
            let name_token = tokens[first]
            let name = source[name_token.start..name_token.end]
            var qualified_import = 256usize
            var last_index = first
            // `q.name` through a use qualifier.
            if first + 2usize < tokens.len && tokens[first + 1usize].kind == .PunctDot && tokens[first + 2usize].kind == .Identifier {
                var import_at = 0usize
                while import_at < imports {
                    if graph.same(qualifiers[import_at], name) {
                        qualified_import = import_at
                        import_at = imports
                    }
                    import_at += 1usize
                }
                if qualified_import < 256usize { last_index = first + 2usize }
            }
            var found = known_ids.len
            if qualified_import == 256usize {
                var known_at = 0usize
                while known_at < known_names.len {
                    if graph.same(known_names[known_at], name) {
                        found = known_at
                        known_at = known_names.len
                    }
                    known_at += 1usize
                }
            }
            if qualified_import < 256usize || found < known_ids.len {
                var role_name = "read"
                if node.kind == .NamedType { role_name = "type" }
                // A type's name in a value position -- `Colour.Red` -- names the type.
                if found < known_ids.len && known_types[found] { role_name = "type" }
                let after = last_index + 1usize
                if node.kind == .NameExpr && after < tokens.len {
                    if tokens[after].kind == .PunctLParen { role_name = "call" }
                    if tokens[after].kind == .PunctLBracket { role_name = "instantiate" }
                    if parse.is_assignment_op(tokens[after].kind) { role_name = "write" }
                }
                if node.kind == .NameExpr && first > 0usize && tokens[first - 1usize].kind == .PunctAmp && !graph.same(role_name, "write") { role_name = "address" }
                let spelling = source[name_token.start..tokens[last_index].end]
                var qualified_name = spelling
                var scratch: [512]u8 = zero
                if qualified_import < 256usize {
                    var scratch_at = nptest_copy(scratch[..], 0usize, paths[qualified_import])
                    scratch[scratch_at] = 46u8
                    scratch_at += 1usize
                    scratch_at = nptest_copy(scratch[..], scratch_at, source[tokens[first + 2usize].start..tokens[first + 2usize].end])
                    qualified_name = scratch[0usize..scratch_at]
                    let record_error = reference_record(out, root, path, name_token, tokens[last_index], role_name, spelling, 0usize, false, qualified_name)
                    if record_error != ok { ret record_error }
                } else {
                    var scratch_at = nptest_copy(scratch[..], 0usize, module_name)
                    scratch[scratch_at] = 46u8
                    scratch_at += 1usize
                    scratch_at = nptest_copy(scratch[..], scratch_at, name)
                    let record_error = reference_record(out, root, path, name_token, tokens[last_index], role_name, spelling, known_ids[found], true, scratch[0usize..scratch_at])
                    if record_error != ok { ret record_error }
                }
                state.written += 1usize
            }
        }
        at += 1usize
    }
    state.next = at
    ret ok
}

// A byte copy into a scratch buffer, returning the new length; a `.` is put between a
// module path and a name by the caller.
fn nptest_copy(dst: []u8, at: usize, src: str) -> usize {
    var to = at
    var from = 0usize
    while from < src.len && to < dst.len {
        dst[to] = src[from]
        to += 1usize
        from += 1usize
    }
    ret to
}

fn reference_record(out: *Out, root: str, path: str, first: lex.Token, last: lex.Token, role: str, spelling: str, target_id: usize, has_target: bool, qualified: str) -> err {
    try text(out, "{\"record\":\"reference\",\"source_span\":")
    try span(out, root, path, first.start, last.end, first.line, first.column, last.end_line, last.end_column, first.column_utf16, last.end_column_utf16)
    try text(out, ",\"role\":")
    try quoted(out, role)
    try text(out, ",\"spelling\":")
    try quoted(out, spelling)
    try text(out, ",\"target_id\":")
    if has_target { try decimal(out, target_id) } else { try text(out, "null") }
    try text(out, ",\"target_qualified_name\":")
    try quoted(out, qualified)
    try text(out, ",\"origin\":\"source\"}")
    ret flush(out)
}

fn index_result(out: *Out, symbols: usize, references: usize) -> err {
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"symbols\":")
    try decimal(out, symbols)
    try text(out, ",\"references\":")
    try decimal(out, references)
    try text(out, "}}")
    ret flush(out)
}

// The four-digit hex offset a listing line begins with.
fn fmt_hex_prefix(line: []const u8) -> usize {
    var value = 0usize
    var at = 0usize
    while at < 4usize && at < line.len {
        var digit = usize(line[at]) - 48usize
        if line[at] >= 97u8 { digit = usize(line[at]) - 87usize }
        value = value * 16usize + digit
        at += 1usize
    }
    ret value
}

// The listing as a JSON string, each `call 0x..`/`call -0x..` line whose landing is a
// function's start getting `-> module.function` appended after its bytes (D278).
fn quoted_listing(out: *Out, listing: []const u8, start: usize, builder: *nir.Builder, offsets: []const usize, relocations: []const codegen_x64.Relocation, relocation_count: usize) -> err {
    try byte(out, 34u8)
    var line_start = 0usize
    while line_start < listing.len {
        var line_end = line_start
        while line_end < listing.len && listing[line_end] != 10u8 { line_end += 1usize }
        let line = listing[line_start..line_end]
        try quoted_body(out, line)
        // `NNNN  call 0x..  ; bytes` -- the mnemonic begins at column 6.
        if line.len > 11usize && line[6usize] == 99u8 && line[7usize] == 97u8 && line[8usize] == 108u8 && line[9usize] == 108u8 && line[10usize] == 32u8 {
            var at = 11usize
            var negative = false
            if at < line.len && line[at] == 45u8 {
                negative = true
                at += 1usize
            }
            if at + 2usize < line.len && line[at] == 48u8 && line[at + 1usize] == 120u8 {
                at += 2usize
                var value = 0usize
                var digits = 0usize
                while at < line.len && ((line[at] >= 48u8 && line[at] <= 57u8) || (line[at] >= 97u8 && line[at] <= 102u8)) {
                    var digit = usize(line[at]) - 48usize
                    if line[at] >= 97u8 { digit = usize(line[at]) - 87usize }
                    value = value * 16usize + digit
                    digits += 1usize
                    at += 1usize
                }
                var landing = start + value
                var lands = digits != 0usize
                if negative {
                    if value > start { lands = false } else { landing = start - value }
                }
                var named = false
                if lands {
                    var function = 0usize
                    while function < builder.function_count {
                        if offsets[function] == landing {
                            try text(out, "  -> ")
                            if builder.functions[function].module_name.len != 0usize {
                                try quoted_body(out, builder.functions[function].module_name)
                                try byte(out, 46u8)
                            }
                            try quoted_body(out, builder.functions[function].name)
                            named = true
                            function = builder.function_count
                        }
                        function += 1usize
                    }
                }
                // A displacement the image fills later -- a runtime or imported symbol --
                // is named from its relocation: the rel32 sits one byte after the opcode.
                if !named {
                    let call_at = start + fmt_hex_prefix(line)
                    var relocation = 0usize
                    while relocation < relocation_count {
                        if !relocations[relocation].global && relocations[relocation].displacement_at == call_at + 1usize && relocations[relocation].function_ref < builder.function_ref_count {
                            try text(out, "  -> ")
                            try quoted_body(out, builder.function_refs[relocations[relocation].function_ref].name)
                            relocation = relocation_count
                        }
                        relocation += 1usize
                    }
                }
            }
        }
        if line_end < listing.len {
            try text(out, "\\n")
            line_end += 1usize
        }
        line_start = line_end
    }
    ret byte(out, 34u8)
}

// `dis --json` (D233): one `disassembly` record per function. The `text` is the
// function's listing (D269): one line per instruction -- the function-relative offset,
// the Intel-order mnemonic and operands, then the bytes after `;` -- from a linear sweep
// over the encodings emit_x64 produces; a byte the sweep does not know is a `db` line.
fn disassembly_json(a: *mem.Arena, arch: str, os_name: str, builder: *nir.Builder, offsets: []const usize, machine: []const usize, machine_count: usize, relocations: []const codegen_x64.Relocation, relocation_count: usize) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, machine_count * 64usize + 8192usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize, absolute: "" }
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
        try text(&out, "\",\"text\":")
        let checkpoint = mem.mark(a)
        let (listing, listing_error) = mem.alloc[u8](a, (stop - start) * 48usize + 64usize)
        if listing_error != ok { ret listing_error }
        let (listed, decode_error) = disasm_x64.disassemble(machine[start..stop], listing)
        if decode_error != ok { ret decode_error }
        // A `call` whose target is another function's start is named after its bytes
        // (D278): the displacements were resolved before this, so the target is known.
        try quoted_listing(&out, listing[0usize..listed], start, builder, offsets, relocations, relocation_count)
        mem.reset(a, checkpoint)
        try byte(&out, 125u8)
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
    // `.` glues to a value on its left (a field) and to whatever is on its right; a
    // member literal after a keyword -- `case .Red`, `ret .Red` -- keeps its space (D284).
    if cur == .PunctDot && fmt_value_end(prev) { ret false }
    if prev == .PunctDot { ret false }
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
        var line_start = at
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
            // Section 6: exactly one blank line separates top-level declarations (D273). A
            // line at column 0 that opens one -- or a comment that leads into one -- gets a
            // blank before it unless what precedes is what leads into it: an attribute, a
            // `///` or `//` line, or a `use` before another `use`.
            if written != 0usize && out[written - 1usize] == 10u8 && (written < 2usize || out[written - 2usize] != 10u8) && fmt_opens_declaration(raw, line_start, line_end) {
                var previous_start = written - 1usize
                while previous_start > 0usize && out[previous_start - 1usize] != 10u8 { previous_start = previous_start - 1usize }
                let previous = out[previous_start..written - 1usize]
                var leads = fmt_starts_with(previous, "@") || fmt_starts_with(previous, "//")
                if fmt_starts_with(previous, "use ") && fmt_starts_with(raw[line_start..line_end], "use ") { leads = true }
                if !leads {
                    out[written] = 10u8
                    written += 1usize
                }
            }
            // Section 6: an empty block is `{}`, and `else` follows `}` on the same line
            // (D273); both join this line onto the one before it.
            var content = line_start
            while content < line_end && raw[content] == 32u8 { content += 1usize }
            let joins_close = content + 1usize == line_end && raw[content] == 125u8 && written >= 2usize && out[written - 2usize] == 123u8
            let joins_else = line_end >= content + 4usize && fmt_starts_with(raw[content..line_end], "else") && (line_end == content + 4usize || raw[content + 4usize] == 32u8) && written >= 2usize && out[written - 2usize] == 125u8
            if joins_close || joins_else {
                written = written - 1usize
                if joins_else {
                    out[written] = 32u8
                    written += 1usize
                }
                line_start = content
            }
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

fn fmt_starts_with(line: []const u8, prefix: str) -> bool {
    if line.len < prefix.len { ret false }
    var at = 0usize
    while at < prefix.len {
        if line[at] != prefix[at] { ret false }
        at += 1usize
    }
    ret true
}

// A column-0 line that begins a top-level declaration, its attributes, or the comment
// that leads into one.
fn fmt_opens_declaration(raw: []const u8, line_start: usize, line_end: usize) -> bool {
    let line = raw[line_start..line_end]
    if line.len == 0usize || line[0usize] == 32u8 || line[0usize] == 125u8 { ret false }
    ret fmt_starts_with(line, "fn ") || fmt_starts_with(line, "type ") || fmt_starts_with(line, "const ") || fmt_starts_with(line, "var ") || fmt_starts_with(line, "error ") || fmt_starts_with(line, "extern ") || fmt_starts_with(line, "use ") || fmt_starts_with(line, "@") || fmt_starts_with(line, "//")
}

// The canonical layout of a source, or an error if it does not tokenize.
fn format_source(a: *mem.Arena, source: str) -> (str, err) {
    if lex.validate(source) != ok { ret ("", InvalidSource) }
    let (raw_storage, raw_error) = mem.alloc[u8](a, source.len * 2usize + 4096usize)
    if raw_error != ok { ret ("", raw_error) }
    var raw = Out { bytes: raw_storage, count: 0usize, absolute: "" }
    let (tokens, token_count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret ("", scan_error) }
    let (lists, lists_error) = fmt_list_plan(a, source, tokens[0usize..token_count])
    if lists_error != ok { ret ("", lists_error) }
    let build_error = format_into(&raw, source, tokens[0usize..token_count], lists)
    if build_error != ok { ret ("", build_error) }
    // The line pass inserts a blank before each declaration (D273): room for one per line.
    let (clean_storage, clean_error) = mem.alloc[u8](a, raw.count * 2usize + 16usize)
    if clean_error != ok { ret ("", clean_error) }
    let clean_count = fmt_collapse(raw.bytes[0usize..raw.count], clean_storage)
    let sort_error = fmt_sort_uses(a, clean_storage[0usize..clean_count])
    if sort_error != ok { ret ("", sort_error) }
    let attribute_error = fmt_sort_attributes(a, clean_storage[0usize..clean_count])
    if attribute_error != ok { ret ("", attribute_error) }
    ret (clean_storage[0usize..clean_count], ok)
}

// Section 6: the contiguous comment-free `use` declarations at the start of a file sort
// by module path then alias (D274). The run is the consecutive `use` lines after any
// leading comment lines; a blank line or anything else ends it. Byte order of the whole
// line is path-then-alias order, since the space before `as` sorts before a `.`.
// ponytail: 256 leading imports is the cap; raise it when a module has more.
fn fmt_sort_uses(a: *mem.Arena, page: []u8) -> err {
    var at = 0usize
    while at < page.len && page[at] == 47u8 && at + 1usize < page.len && page[at + 1usize] == 47u8 {
        while at < page.len && page[at] != 10u8 { at += 1usize }
        if at < page.len { at += 1usize }
    }
    var starts: [256]usize = zero
    var ends: [256]usize = zero
    var count = 0usize
    let run_start = at
    while count < 256usize && at + 4usize <= page.len && page[at] == 117u8 && page[at + 1usize] == 115u8 && page[at + 2usize] == 101u8 && page[at + 3usize] == 32u8 {
        starts[count] = at
        while at < page.len && page[at] != 10u8 { at += 1usize }
        ends[count] = at
        if at < page.len { at += 1usize }
        count += 1usize
    }
    if count < 2usize { ret ok }
    // Sort the line indices, then rewrite the run through a copy.
    var order: [256]usize = zero
    var sorted = 0usize
    while sorted < count {
        var slot = sorted
        while slot > 0usize && fmt_line_after(page, starts[order[slot - 1usize]], ends[order[slot - 1usize]], starts[sorted], ends[sorted]) {
            order[slot] = order[slot - 1usize]
            slot = slot - 1usize
        }
        order[slot] = sorted
        sorted += 1usize
    }
    let run_end = at
    let (copy, copy_error) = mem.alloc[u8](a, run_end - run_start)
    if copy_error != ok { ret copy_error }
    var written = 0usize
    var line = 0usize
    while line < count {
        var from = starts[order[line]]
        while from < ends[order[line]] {
            copy[written] = page[from]
            written += 1usize
            from += 1usize
        }
        copy[written] = 10u8
        written += 1usize
        line += 1usize
    }
    var back = 0usize
    while back < written {
        page[run_start + back] = copy[back]
        back += 1usize
    }
    ret ok
}

// Section 6: attribute lines are sorted by attribute name (D286). Each run of
// consecutive lines beginning with `@` at the same indent is sorted in byte order of
// the whole line, which orders by name first; a run is at most 16 attributes.
fn fmt_sort_attributes(a: *mem.Arena, page: []u8) -> err {
    var at = 0usize
    while at < page.len {
        // The next line, and whether it is an attribute line.
        var content = at
        while content < page.len && page[content] == 32u8 { content += 1usize }
        if content < page.len && page[content] == 64u8 {
            var starts: [16]usize = zero
            var ends: [16]usize = zero
            var count = 0usize
            let run_start = at
            let indent = content - at
            var scan = at
            while count < 16usize && scan < page.len {
                var probe = scan
                var spaces = 0usize
                while probe < page.len && page[probe] == 32u8 {
                    probe += 1usize
                    spaces += 1usize
                }
                if !(probe < page.len && page[probe] == 64u8 && spaces == indent) { break }
                starts[count] = scan
                while probe < page.len && page[probe] != 10u8 { probe += 1usize }
                ends[count] = probe
                count += 1usize
                scan = probe
                if scan < page.len { scan += 1usize }
            }
            if count >= 2usize {
                var order: [16]usize = zero
                var sorted = 0usize
                while sorted < count {
                    var slot = sorted
                    while slot > 0usize && fmt_line_after(page, starts[order[slot - 1usize]], ends[order[slot - 1usize]], starts[sorted], ends[sorted]) {
                        order[slot] = order[slot - 1usize]
                        slot = slot - 1usize
                    }
                    order[slot] = sorted
                    sorted += 1usize
                }
                let (copy, copy_error) = mem.alloc[u8](a, scan - run_start)
                if copy_error != ok { ret copy_error }
                var written = 0usize
                var line = 0usize
                while line < count {
                    var from = starts[order[line]]
                    while from < ends[order[line]] {
                        copy[written] = page[from]
                        written += 1usize
                        from += 1usize
                    }
                    copy[written] = 10u8
                    written += 1usize
                    line += 1usize
                }
                var back = 0usize
                while back < written {
                    page[run_start + back] = copy[back]
                    back += 1usize
                }
            }
            at = scan
        } else {
            while at < page.len && page[at] != 10u8 { at += 1usize }
            if at < page.len { at += 1usize }
        }
    }
    ret ok
}

fn fmt_line_after(page: []const u8, a_start: usize, a_end: usize, b_start: usize, b_end: usize) -> bool {
    var i = 0usize
    while a_start + i < a_end && b_start + i < b_end {
        if page[a_start + i] != page[b_start + i] { ret page[a_start + i] > page[b_start + i] }
        i += 1usize
    }
    ret a_end - a_start > b_end - b_start
}

// Section 6's bracketed lists (D277). For every soft opener -- `(`, `[`, or the `{` of a
// type body after `struct`, `union` or an enum's element type -- the plan says which
// token closes it and what to do with it: 0 leave as written (a comment lies inside, or
// it is not a list this pass handles), 1 join onto one line, 2 break one element per
// line with a trailing comma. A list joins when its one-line width from the column it
// opens on fits in 100 columns, breaks otherwise; the width is measured with the same
// spacing the pass emits, newlines inside the list being soft.
fn fmt_list_plan(a: *mem.Arena, source: str, tokens: []const lex.Token) -> ([]usize, err) {
    // plan[i] for an opener at i: closer index * 4 + action; 0 for every other token.
    let (plan, plan_error) = mem.alloc[usize](a, tokens.len + 1usize)
    if plan_error != ok { ret (plan, plan_error) }
    var at = 0usize
    while at < tokens.len {
        plan[at] = 0usize
        at += 1usize
    }
    // A stack of open soft delimiters.
    var openers: [64]usize = zero
    var open_count = 0usize
    // Whether an `if`/`while`/`for`/`switch`/`when`/`else` header is open on this line:
    // its `{` is a block, however Pascal the name before it (the parser's own rule).
    var header_open = false
    at = 0usize
    while at < tokens.len {
        let kind = tokens[at].kind
        // A signature's `-> Type {` opens a body too, however Pascal the type.
        if kind == .KwIf || kind == .KwWhile || kind == .KwFor || kind == .KwSwitch || kind == .KwWhen || kind == .KwElse || kind == .PunctArrow { header_open = true }
        if kind == .Newline { header_open = false }
        var opens = kind == .PunctLParen || kind == .PunctLBracket
        if kind == .PunctLBrace && at != 0usize {
            let before = tokens[at - 1usize].kind
            // `struct {`, `union {`, `enum u8 {`, `union enum u8 {`: a type body.
            if before == .KwStruct || before == .KwUnion || before == .KwEnum || (before == .Identifier && at >= 2usize && tokens[at - 2usize].kind == .KwEnum) { opens = true }
            // `Pair {`: an aggregate literal, a PascalCase name before the brace outside a
            // control header (D285) -- the parser's `named_aggregate_follows`.
            if before == .Identifier && !header_open && !opens {
                let first = source[tokens[at - 1usize].start]
                if first >= 65u8 && first <= 90u8 && !(at >= 2usize && tokens[at - 2usize].kind == .KwEnum) { opens = true }
            }
            if kind == .PunctLBrace && opens { header_open = false }
        }
        if kind == .PunctLBrace && open_count == 0usize { header_open = false }
        if opens && open_count < 64usize {
            openers[open_count] = at
            open_count += 1usize
        }
        let closes = kind == .PunctRParen || kind == .PunctRBracket || kind == .PunctRBrace
        if closes && open_count != 0usize {
            let opener = openers[open_count - 1usize]
            let opener_kind = tokens[opener].kind
            let matches = (kind == .PunctRParen && opener_kind == .PunctLParen) || (kind == .PunctRBracket && opener_kind == .PunctLBracket) || (kind == .PunctRBrace && opener_kind == .PunctLBrace)
            if matches {
                open_count = open_count - 1usize
                // A `(` after a callee, `ret` or `fn` is a list that may break; a grouping
                // `(` and every `[` only join -- a trailing comma inside them is not syntax.
                var action = 2usize
                if opener_kind == .PunctLBrace { action = 1usize }
                if opener_kind == .PunctLParen && opener != 0usize {
                    let lead = tokens[opener - 1usize].kind
                    if fmt_value_end(lead) || lead == .KwRet || lead == .KwFn { action = 1usize }
                }
                plan[opener] = at * 4usize + action
            }
        }
        at += 1usize
    }
    ret (plan, ok)
}

// The one-line width of tokens [from, to] with the pass's own spacing, newlines soft,
// in Unicode scalars; `prev` and `prev_unary` are the spacing state before `from`.
fn fmt_inline_width(source: str, tokens: []const lex.Token, from: usize, to: usize, prev_in: lex.Kind, prev_unary_in: bool) -> usize {
    var width = 0usize
    var prev = prev_in
    var prev_unary = prev_unary_in
    var at = from
    while at <= to {
        let token = tokens[at]
        if token.kind != .Newline {
            if at != from && fmt_space_before(prev, prev_unary, token.kind) { width += 1usize }
            var scan = token.start
            while scan < token.end {
                if source[scan] < 128u8 || source[scan] >= 192u8 { width += 1usize }
                scan += 1usize
            }
            prev_unary = fmt_is_unary(prev, token.kind)
            prev = token.kind
        }
        at += 1usize
    }
    ret width
}

// Whether a comment lies within tokens [from, to]: the pass leaves such a list alone.
fn fmt_has_comment(source: str, tokens: []const lex.Token, from: usize, to: usize) -> bool {
    var at = from
    while at <= to {
        if tokens[at].kind == .Newline {
            var trivia = lex.trivia_init(source, tokens[at])
            while true {
                let item = lex.next_trivia(&trivia)
                if item.kind == .End { break }
                if item.kind == .Comment { ret true }
            }
        }
        at += 1usize
    }
    ret false
}

fn fmt_indent(raw: *Out, columns: usize) -> err {
    var at = 0usize
    while at < columns {
        try byte(raw, 32u8)
        at += 1usize
    }
    ret ok
}

// The layout pass, in an err-returning function so `try` may propagate a buffer overflow.
// Lists (D277): an opener whose list fits is joined -- its newlines dropped, a trailing
// comma before the closer dropped -- and one that does not is broken, one element per
// line four columns in from the line the opener is on, each with a trailing comma, the
// closer back on the opener's line indent.
fn format_into(raw: *Out, source: str, tokens: []const lex.Token, plan: []const usize) -> err {
    var depth = 0usize
    var line_has_content = false
    var line_indent = 0usize
    var column = 0usize
    var prev: lex.Kind = .Newline
    var prev_unary = false
    // The open lists: closer index, element indent, and whether broken.
    var list_closers: [64]usize = zero
    var list_indents: [64]usize = zero
    var list_broken: [64]bool = zero
    var list_count = 0usize
    var at = 0usize
    while at < tokens.len {
        let token = tokens[at]
        if token.kind == .Eof { break }
        // Inside a list this pass joined or broke, a newline is soft.
        let inside_list = list_count != 0usize
        if token.kind == .Newline && inside_list {
            at += 1usize
            continue
        }
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
                column = 0usize
                prev = .Newline
                prev_unary = false
            } else {
                if has_comment {
                    try fmt_indent(raw, depth * 4usize)
                    try text(raw, source[comment_start..comment_end])
                    try byte(raw, 10u8)
                } else {
                    try byte(raw, 10u8)
                }
            }
            at += 1usize
            continue
        }
        // The closer of the innermost list.
        if inside_list && at == list_closers[list_count - 1usize] {
            list_count = list_count - 1usize
            if list_broken[list_count] {
                // The last element's trailing comma, then the closer on the owning indent;
                // after a comma the element line was already begun, and is taken back.
                if prev == .Newline {
                    raw.count = raw.count - list_indents[list_count]
                } else {
                    if prev != .PunctComma { try byte(raw, 44u8) }
                    try byte(raw, 10u8)
                }
                let owning = list_indents[list_count] - 4usize
                try fmt_indent(raw, owning)
                column = owning
                line_indent = owning
                if token.kind == .PunctRBrace && depth > 0usize { depth = depth - 1usize }
                try text(raw, source[token.start..token.end])
                column += token.end - token.start
                line_has_content = true
                prev_unary = false
                prev = token.kind
                at += 1usize
                continue
            }
            // Joined: a trailing comma before the closer is dropped.
            if prev == .PunctComma && raw.count != 0usize && raw.bytes[raw.count - 1usize] == 44u8 {
                raw.count = raw.count - 1usize
                column = column - 1usize
                prev = .Identifier
                prev_unary = false
            }
            if token.kind == .PunctRBrace && depth > 0usize { depth = depth - 1usize }
            if fmt_space_before(prev, prev_unary, token.kind) {
                try byte(raw, 32u8)
                column += 1usize
            }
            try text(raw, source[token.start..token.end])
            column += token.end - token.start
            prev_unary = false
            prev = token.kind
            at += 1usize
            continue
        }
        // A comma at the top level of a broken list ends an element.
        if inside_list && list_broken[list_count - 1usize] && token.kind == .PunctComma {
            try byte(raw, 44u8)
            try byte(raw, 10u8)
            try fmt_indent(raw, list_indents[list_count - 1usize])
            column = list_indents[list_count - 1usize]
            line_indent = column
            prev = .Newline
            prev_unary = false
            at += 1usize
            continue
        }
        let at_line_start = !line_has_content
        if token.kind == .PunctRBrace && depth > 0usize && at_line_start { depth = depth - 1usize }
        if at_line_start {
            // A `case` or `default` label sits at its `switch`'s indent, one level out from
            // the statements under it (D284).
            var indent = depth * 4usize
            if (token.kind == .KwCase || token.kind == .KwDefault) && depth > 0usize { indent = indent - 4usize }
            try fmt_indent(raw, indent)
            column = indent
            line_indent = column
            line_has_content = true
        } else {
            if prev != .Newline && fmt_space_before(prev, prev_unary, token.kind) {
                try byte(raw, 32u8)
                column += 1usize
            }
        }
        try text(raw, source[token.start..token.end])
        column += token.end - token.start
        if token.kind == .PunctLBrace { depth += 1usize }
        // A close brace mid-line (e.g. `{}` or `} else {`) still lowers the depth.
        if token.kind == .PunctRBrace && !at_line_start && depth > 0usize { depth = depth - 1usize }
        // An opener with a plan opens a list: joined when it fits, broken when it does not.
        if plan[at] != 0usize && list_count < 64usize {
            let closer = plan[at] / 4usize
            if !fmt_has_comment(source, tokens, at, closer) {
                let width = fmt_inline_width(source, tokens, at + 1usize, closer, token.kind, false)
                list_closers[list_count] = closer
                list_indents[list_count] = line_indent + 4usize
                // The opener is already on the line: what follows must fit beside it.
                let breaks = column + width > 100usize && closer > at + 1usize && plan[at] % 4usize == 1usize
                list_broken[list_count] = breaks
                list_count += 1usize
                if breaks {
                    try byte(raw, 10u8)
                    try fmt_indent(raw, line_indent + 4usize)
                    column = line_indent + 4usize
                    line_indent = column
                    prev = .Newline
                    prev_unary = false
                    at += 1usize
                    continue
                }
            }
        }
        prev_unary = fmt_is_unary(prev, token.kind)
        prev = token.kind
        at += 1usize
    }
    ret ok
}

// `fmt --check --json` (D242+): the canonical-layout check. Emits E-FORMAT-0001 pointing at
// the first byte that differs from canonical and exits 1 when the source is not already
// canonical, and just the header and a passing result when it is.
// One invalid-token diagnostic, the shape `tokens --json` emits (D227).
fn invalid_token_diagnostic(out: *Out, root: str, path: str, source: str, token: lex.Token) -> err {
    try text(out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":")
    try quoted(out, lex.invalid_code(source, token))
    try text(out, ",\"message\":\"invalid token\",\"span\":")
    try span(out, root, path, token.start, token.end, token.line, token.column, token.end_line, token.end_column, token.column_utf16, token.end_column_utf16)
    try text(out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
    ret flush(out)
}

// What `fmt` refuses, as diagnostics (D257): each invalid token under its lexical code,
// and section 6's one formatter contract a layout pass cannot honour -- a comment
// between an attribute and its declaration, since attributes must stay adjacent --
// as E-FORMAT-9999 at the comment. Returns how many were written; zero means format.
fn fmt_refuse(a: *mem.Arena, out: *Out, source: str, path: str) -> (usize, err) {
    let (tokens, count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (0usize, scan_error) }
    var written = 0usize
    var at = 0usize
    var after_attribute = false
    var line_first = true
    while at < count {
        let token = tokens[at]
        if token.kind == .Invalid {
            let invalid_error = invalid_token_diagnostic(out, "operand", path, source, token)
            if invalid_error != ok { ret (0usize, invalid_error) }
            written += 1usize
        }
        if token.kind == .Newline {
            // A newline whose line holds only a comment, right after an attribute line.
            if after_attribute && line_first && token.leading_start < token.start {
                let comment_start = index_comment_start(source, token)
                if comment_start + 1usize < token.start && source[comment_start] == 47u8 && source[comment_start + 1usize] == 47u8 {
                    var comment: lex.Token = token
                    comment.start = comment_start
                    comment.end = token.start
                    comment.column = token.leading_column + (comment_start - token.leading_start)
                    comment.column_utf16 = token.leading_column_utf16 + (comment_start - token.leading_start)
                    comment.line = token.leading_line
                    comment.end_line = token.line
                    comment.end_column = token.column
                    comment.end_column_utf16 = token.column_utf16
                    let contract_error = text(out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-FORMAT-9999\",\"message\":\"a comment may not separate an attribute from its declaration\",\"span\":")
                    if contract_error != ok { ret (0usize, contract_error) }
                    let span_error = span(out, "operand", path, comment.start, comment.end, comment.line, comment.column, comment.end_line, comment.end_column, comment.column_utf16, comment.end_column_utf16)
                    if span_error != ok { ret (0usize, span_error) }
                    let tail_error = text(out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
                    if tail_error != ok { ret (0usize, tail_error) }
                    let flush_error = flush(out)
                    if flush_error != ok { ret (0usize, flush_error) }
                    written += 1usize
                    after_attribute = false
                }
            }
            line_first = true
        } else {
            if line_first { after_attribute = token.kind == .PunctAt }
            line_first = false
        }
        at += 1usize
    }
    ret (written, ok)
}

fn fmt_refused_result(out: *Out, diagnostics: usize) -> err {
    try text(out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":1,\"data\":{\"diagnostics\":")
    try decimal(out, diagnostics)
    try text(out, "}}")
    ret flush(out)
}

fn fmt_check_json(a: *mem.Arena, source: str, path: str) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 3usize + 8192usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize, absolute: "" }
    let header_error = header(&out, "fmt")
    if header_error != ok { ret (2usize, header_error) }
    let (refused, refuse_error) = fmt_refuse(a, &out, source, path)
    if refuse_error != ok { ret (2usize, refuse_error) }
    if refused != 0usize {
        let refused_error = fmt_refused_result(&out, refused)
        if refused_error != ok { ret (2usize, refused_error) }
        ret (1usize, ok)
    }
    let (formatted, format_error) = format_source(a, source)
    if format_error != ok { ret (1usize, format_error) }
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
// The canonical text and exit 0, or exit 1 after the refusals went to stderr as human
// lines (D295: shared by the printing and the in-place forms).
fn fmt_plain_text(a: *mem.Arena, source: str, path: str) -> (str, usize, err) {
    let (scratch, scratch_error) = mem.alloc[u8](a, source.len * 3usize + 8192usize)
    if scratch_error != ok { ret ("", 2usize, scratch_error) }
    var probe = Out { bytes: scratch, count: 0usize, absolute: "" }
    let (refused, refuse_error) = fmt_refuse_plain(a, &probe, source, path)
    if refuse_error != ok { ret ("", 2usize, refuse_error) }
    if refused != 0usize { ret ("", 1usize, ok) }
    let (formatted, format_error) = format_source(a, source)
    if format_error != ok { ret ("", 1usize, format_error) }
    ret (formatted, 0usize, ok)
}

fn fmt_plain(a: *mem.Arena, source: str, path: str) -> (usize, err) {
    // A refusal goes to stderr as the human lines of the same diagnostics, exit 1.
    let (formatted, exit_code, text_error) = fmt_plain_text(a, source, path)
    if text_error != ok { ret (exit_code, text_error) }
    if exit_code != 0usize { ret (exit_code, ok) }
    let stdout = os.stdout()
    var at = 0usize
    while at < formatted.len {
        let (written, write_error) = os.write(stdout, formatted[at..formatted.len])
        if write_error != ok { ret (2usize, write_error) }
        if written == 0usize { ret (2usize, Capacity) }
        at += written
    }
    ret (0usize, ok)
}

// The plain form's refusals: `path:line:col: error[CODE]: message` on stderr.
fn fmt_plain_line(out: *Out, path: str, source: str, token: lex.Token) -> err {
    try text(out, path)
    try byte(out, 58u8)
    try decimal(out, token.line)
    try byte(out, 58u8)
    try decimal(out, token.column)
    try text(out, ": error[")
    try text(out, lex.invalid_code(source, token))
    try text(out, "]: invalid token\n")
    let stderr = os.stderr()
    var from = 0usize
    while from < out.count {
        let (put, write_error) = os.write(stderr, out.bytes[from..out.count])
        if write_error != ok { ret write_error }
        if put == 0usize { ret Capacity }
        from += put
    }
    out.count = 0usize
    ret ok
}

fn fmt_refuse_plain(a: *mem.Arena, out: *Out, source: str, path: str) -> (usize, err) {
    let (tokens, count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (0usize, scan_error) }
    var written = 0usize
    var at = 0usize
    while at < count {
        if tokens[at].kind == .Invalid {
            let line_error = fmt_plain_line(out, path, source, tokens[at])
            if line_error != ok { ret (0usize, line_error) }
            written += 1usize
        }
        at += 1usize
    }
    ret (written, ok)
}

fn fmt_json(a: *mem.Arena, source: str, path: str) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 3usize + 8192usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize, absolute: "" }
    let header_error = header(&out, "fmt")
    if header_error != ok { ret (2usize, header_error) }
    let (refused, refuse_error) = fmt_refuse(a, &out, source, path)
    if refuse_error != ok { ret (2usize, refuse_error) }
    if refused != 0usize {
        let refused_error = fmt_refused_result(&out, refused)
        if refused_error != ok { ret (2usize, refused_error) }
        ret (1usize, ok)
    }
    let (formatted, format_error) = format_source(a, source)
    if format_error != ok { ret (1usize, format_error) }
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

// Section 2's source identifier of a module (D265): `project-src` or `project-lib` with the
// path under that root, `toolchain-lib` under the toolchain's `lib`, and otherwise the
// operand by its basename; separators come out as `/`.
fn manifest_source(out: *Out, g: *graph.Graph, path: str) -> err {
    let (src_relative, under_src) = project.relative_under(path, g.project.root, "src")
    if under_src && g.project.has_sources { ret manifest_identity(out, "project-src", src_relative) }
    let (lib_relative, under_lib) = project.relative_under(path, g.project.root, "lib")
    if under_lib && g.project.has_sources { ret manifest_identity(out, "project-lib", lib_relative) }
    let (toolchain_relative, under_toolchain) = project.relative_under(path, g.toolchain_root, "lib")
    if under_toolchain { ret manifest_identity(out, "toolchain-lib", toolchain_relative) }
    ret manifest_identity(out, "operand", manifest_basename(path))
}

fn manifest_identity(out: *Out, root: str, relative: str) -> err {
    try text(out, "{\"root\":\"")
    try text(out, root)
    try text(out, "\",\"path\":\"")
    var at = 0usize
    while at < relative.len {
        var c = relative[at]
        if c == 92u8 { c = 47u8 }
        if c == 34u8 || c == 92u8 { try byte(out, 92u8) }
        try byte(out, c)
        at += 1usize
    }
    ret text(out, "\"}")
}

// The interface hash: the source with every function body -- the balanced braces after
// a top-level `fn` header -- left out, hashed. The tokens are streamed off the scanner
// one at a time, never held: a token array is ~100 bytes per source byte, and the
// self-hosted compiler ran out of arena hashing its own thirty modules that way (D265).
fn manifest_interface_sha256(a: *mem.Arena, source: str) -> (str, err) {
    let (kept, kept_error) = mem.alloc[u8](a, source.len)
    if kept_error != ok { ret ("", kept_error) }
    var written = 0usize
    var copied_to = 0usize
    var scanner = lex.init(source)
    var braces = 0usize
    // 0: outside; 1: in a header, `brackets` deep; 2: in a body, `body_depth` braces deep.
    var state = 0usize
    var brackets = 0usize
    var body_depth = 0usize
    var previous = lex.Kind.Newline
    while true {
        let token = lex.next(&scanner)
        if token.kind == .Eof { break }
        if state == 0usize {
            if token.kind == .PunctLBrace { braces += 1usize }
            if token.kind == .PunctRBrace && braces != 0usize { braces = braces - 1usize }
            if token.kind == .KwFn && braces == 0usize {
                state = 1usize
                brackets = 0usize
            }
        } else {
            if state == 1usize {
                if token.kind == .PunctLParen || token.kind == .PunctLBracket { brackets += 1usize }
                if (token.kind == .PunctRParen || token.kind == .PunctRBracket) && brackets != 0usize { brackets = brackets - 1usize }
                if token.kind == .PunctLBrace && brackets == 0usize {
                    // Keep through the `{`; the body starts after it.
                    var from = copied_to
                    while from < token.end {
                        kept[written] = source[from]
                        written += 1usize
                        from += 1usize
                    }
                    copied_to = token.end
                    state = 2usize
                    body_depth = 1usize
                } else {
                    // A header ends at a newline that does not continue one: `extern fn`
                    // has no body, and a function-typed field is not a declaration.
                    if token.kind == .Newline && brackets == 0usize && previous != .PunctArrow && previous != .PunctComma { state = 0usize }
                }
            } else {
                if token.kind == .PunctLBrace { body_depth += 1usize }
                if token.kind == .PunctRBrace {
                    body_depth = body_depth - 1usize
                    if body_depth == 0usize {
                        // The body is dropped; the `}` and what follows are kept.
                        copied_to = token.start
                        state = 0usize
                    }
                }
            }
        }
        previous = token.kind
    }
    while copied_to < source.len {
        kept[written] = source[copied_to]
        written += 1usize
        copied_to += 1usize
    }
    let (digest, digest_error) = manifest_sha256(a, kept[0usize..written])
    ret (digest, digest_error)
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
    var out = Out { bytes: storage, count: 0usize, absolute: "" }
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
        try text(out, "{\"source\":")
        try manifest_source(out, g, g.modules[at].path)
        try text(out, ",\"sha256\":")
        let checkpoint = mem.mark(a)
        let (digest, digest_error) = manifest_sha256(a, g.modules[at].text)
        if digest_error != ok { ret digest_error }
        try quoted(out, digest)
        mem.reset(a, checkpoint)
        try byte(out, 125u8)
        at += 1usize
    }
    // Every module but the root is a dependency (D265): its interface is its source with
    // every function body removed, so an edit inside a body moves `body_sha256` alone.
    try text(out, "],\"dependencies\":[")
    at = 1usize
    while at < g.count {
        if at != 1usize { try byte(out, 44u8) }
        try text(out, "{\"module\":")
        try quoted(out, g.modules[at].name)
        try text(out, ",\"interface_sha256\":")
        // Each module's scratch -- the interface cut and two digests -- is released once
        // written, so a large graph costs one module's worth of arena at a time.
        let checkpoint = mem.mark(a)
        let (interface_digest, interface_error) = manifest_interface_sha256(a, g.modules[at].text)
        if interface_error != ok { ret interface_error }
        try quoted(out, interface_digest)
        try text(out, ",\"body_sha256\":")
        let (body_digest, body_error) = manifest_sha256(a, g.modules[at].text)
        if body_error != ok { ret body_error }
        try quoted(out, body_digest)
        mem.reset(a, checkpoint)
        try byte(out, 125u8)
        at += 1usize
    }
    try text(out, "],\"libraries\":[],\"assets\":[],\"artifacts\":[")
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
// Whether `path` begins with `root` and a separator, either separator standing for the
// other, so a root spelled one way matches a directory spelled the other.
fn manifest_under(path: str, root: str) -> bool {
    if root.len == 0usize || path.len <= root.len { ret false }
    var at = 0usize
    while at < root.len {
        var p = path[at]
        var r = root[at]
        if p == 92u8 { p = 47u8 }
        if r == 92u8 { r = 47u8 }
        if p != r { ret false }
        at += 1usize
    }
    if root[root.len - 1usize] == 47u8 || root[root.len - 1usize] == 92u8 { ret true }
    ret path[root.len] == 47u8 || path[root.len] == 92u8
}

// A path under the current directory unless it is absolute already: a leading
// separator or a drive letter.
fn manifest_absolute(a: *mem.Arena, path: str) -> (str, err) {
    if path.len != 0usize && (path[0usize] == 47u8 || path[0usize] == 92u8 || (path.len >= 2usize && path[1usize] == 58u8)) { ret (path, ok) }
    let (dir, dir_error) = os.current_dir(a)
    if dir_error != ok { ret ("", dir_error) }
    // `.` is the directory itself, as is a trailing `/.` -- what `project.discover`
    // answers for an operand given relative to the project root.
    var trimmed = path
    if graph.same(trimmed, ".") { trimmed = "" }
    if trimmed.len >= 2usize && graph.same(trimmed[trimmed.len - 2usize..trimmed.len], "/.") { trimmed = trimmed[0usize..trimmed.len - 2usize] }
    if trimmed.len == 0usize { ret (dir, ok) }
    let (joined, join_error) = manifest_join(a, dir, trimmed)
    ret (joined, join_error)
}

// Section 7: an artifact's path is project-relative (D293). The path as named is made
// absolute under the current directory unless it already is, and when that lies under
// the project root the rest is the path, with `/` separators; an artifact outside the
// project keeps its absolute spelling, which is at least a spelling that finds it.
// ponytail: `.` and `..` segments are kept, as in `--absolute-paths` (D290).
fn manifest_artifact_path(a: *mem.Arena, project_root: str, named: str) -> (str, err) {
    if named.len == 0usize { ret (named, ok) }
    let (absolute, absolute_error) = manifest_absolute(a, named)
    if absolute_error != ok { ret ("", absolute_error) }
    let (root, root_error) = manifest_absolute(a, project_root)
    if root_error != ok { ret ("", root_error) }
    if !manifest_under(absolute, root) { ret (absolute, ok) }
    var from = root.len
    if !(root[root.len - 1usize] == 47u8 || root[root.len - 1usize] == 92u8) { from += 1usize }
    let (relative, relative_error) = mem.alloc[u8](a, absolute.len - from)
    if relative_error != ok { ret ("", relative_error) }
    var at = 0usize
    while from + at < absolute.len {
        relative[at] = absolute[from + at]
        if relative[at] == 92u8 { relative[at] = 47u8 }
        at += 1usize
    }
    ret (relative[0usize..at], ok)
}

fn manifest_file(a: *mem.Arena, g: *graph.Graph, arch: str, os_name: str, release_mode: bool, artifact_path: str, packed: []const u8) -> err {
    var mode = "debug"
    if release_mode { mode = "release" }
    let (dot_dir, dot_error) = manifest_join(a, g.project.root, ".neper")
    if dot_error != ok { ret dot_error }
    let (mode_dir, mode_error) = manifest_join(a, dot_dir, mode)
    if mode_error != ok { ret mode_error }
    let (manifest_path, path_error) = manifest_join(a, mode_dir, "build-manifest.json")
    if path_error != ok { ret path_error }
    let flags = os.OpenFlags { read: false, write: true, create: true, truncate: true, append: false }
    // `.neper/<mode>/` is made when it is missing (D287): each level once, an `Exists`
    // answer meaning another build got there first. The open comes before hashing, so a
    // root that cannot take the directory costs nothing but the error (D267).
    var (file, open_error) = os.open(a, manifest_path, flags)
    if open_error == os.NotFound {
        let dot_made = os.mkdir(a, dot_dir)
        if dot_made != ok && dot_made != os.Exists { ret dot_made }
        let mode_made = os.mkdir(a, mode_dir)
        if mode_made != ok && mode_made != os.Exists { ret mode_made }
        let (retried, retry_error) = os.open(a, manifest_path, flags)
        file = retried
        open_error = retry_error
    }
    if open_error != ok { ret open_error }
    let (digest, digest_error) = manifest_sha256(a, packed)
    if digest_error != ok { ret digest_error }
    let (storage, storage_error) = mem.alloc[u8](a, 65536usize + g.count * 512usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize, absolute: "" }
    let (relative_path, relative_error) = manifest_artifact_path(a, g.project.root, artifact_path)
    if relative_error != ok { ret relative_error }
    try manifest_write(a, &out, arch, os_name, g, mode, relative_path, digest)
    try byte(&out, 10u8)
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
    var out = Out { bytes: storage, count: 0usize, absolute: "" }
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
fn tokens_json(a: *mem.Arena, root: str, path: str, source: str, absolute: str) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 4096usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize, absolute: absolute }
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
fn parse_json(a: *mem.Arena, root: str, path: str, source: str, absolute: str) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 4096usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize, absolute: absolute }
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
        // Every failure recovery went past, each at its own token (D275); a barrier
        // crossing is E-SYNTAX-0012 at the opener, naming the keyword that ended it.
        var failure = 0usize
        while failure < tree.failure_count || (failure == 0usize && tree.failure_count == 0usize) {
            var at = tokens[count - 1usize]
            var barrier = false
            var keyword = at
            if failure < tree.failure_count {
                at = tree.failures[failure]
                barrier = tree.failure_barriers[failure]
                keyword = tree.failure_keywords[failure]
            }
            diagnostics += 1usize
            if barrier {
                let b1 = text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-SYNTAX-0012\",\"message\":\"`")
                if b1 != ok { ret (2usize, b1) }
                let b2 = text(&out, source[at.start..at.end])
                if b2 != ok { ret (2usize, b2) }
                let b3 = text(&out, "` opened here is still unclosed at `")
                if b3 != ok { ret (2usize, b3) }
                let b4 = text(&out, source[keyword.start..keyword.end])
                if b4 != ok { ret (2usize, b4) }
                let b5 = text(&out, "` on line ")
                if b5 != ok { ret (2usize, b5) }
                let b6 = decimal(&out, keyword.line)
                if b6 != ok { ret (2usize, b6) }
                let b7 = text(&out, "\",\"span\":")
                if b7 != ok { ret (2usize, b7) }
            } else {
                let d1 = text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-SYNTAX-9999\",\"message\":\"unexpected token\",\"span\":")
                if d1 != ok { ret (2usize, d1) }
            }
            let d2 = span(&out, root, path, at.start, at.end, at.line, at.column, at.end_line, at.end_column, at.column_utf16, at.end_column_utf16)
            if d2 != ok { ret (2usize, d2) }
            let d3 = text(&out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
            if d3 != ok { ret (2usize, d3) }
            let d4 = flush(&out)
            if d4 != ok { ret (2usize, d4) }
            failure += 1usize
        }
    }
    // The tree can outgrow the record buffer the tokens used: one sized to it.
    let (tree_storage, tree_storage_error) = mem.alloc[u8](a, tree.count * 512usize + tree.child_count * 32usize + 4096usize)
    if tree_storage_error != ok { ret (2usize, tree_storage_error) }
    var tree_out = Out { bytes: tree_storage, count: 0usize, absolute: absolute }
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
