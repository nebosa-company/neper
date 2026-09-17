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
use em
use check
use layout

error Capacity
error InvalidSource
// A plan's site whose list could not be found at the tokens (D406).
error InvalidPlan
// A query answered with a refusal (D406, D409): its stream has been written, with a
// result of exit code 2; the caller decides whether the process ends with it.
error Refused

// One record at a time: built here, printed whole, so a line is never split.
type Out = struct {
    bytes: []u8,
    count: usize,
    // Every byte flushed so far (D400): what a byte budget is measured against, and
    // what a result reports as `bytes`.
    flushed: usize,
    // The operand's line table (D315), built once per command for the spans its
    // records carry; empty means a span counts lines from the start of the source.
    lines: []usize,
    // `--absolute-paths` (section 2, D290): the operand's absolute spelling, written as
    // `absolute_path` beside every source identity when it is not empty.
    absolute: str,
    // The module's unsafe inventory (D513, H27), the manifest's records as bytes,
    // while its index is written: each symbol names the boundaries it holds.
    inventory: str,
    // Captured (D515): a flush keeps the records in `bytes` instead of writing
    // them, for a command that reads another command's records.
    capture: bool,
}

fn byte(out: *Out, value: u8) -> err {
    if out.count == out.bytes.len { ret Capacity }
    out.bytes[out.count] = value
    out.count += 1usize
    ret ok
}

fn text(out: *Out, value: str) -> err {
    let end = out.count + value.len
    if end > out.bytes.len { ret Capacity }
    os.copy_bytes(out.bytes[out.count..end], value)
    out.count = end
    ret ok
}

fn decimal(out: *Out, value: usize) -> err {
    if value >= 10usize { try decimal(out, value / 10usize) }
    ret byte(out, u8(48usize + value % 10usize))
}

fn flush(out: *Out) -> err {
    try byte(out, 10u8)
    if out.capture { ret ok }
    let stdout = os.stdout()
    var at = 0usize
    while at < out.count {
        let (written, write_error) = os.write(stdout, out.bytes[at..out.count])
        if write_error != ok { ret write_error }
        if written == 0usize { ret Capacity }
        at += written
    }
    out.flushed += out.count
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

// Eight hex digits of a 32-bit value, most significant first.
fn hex32(out: *Out, value: usize) -> err {
    var shift = 32usize
    while shift > 0usize {
        shift = shift - 4usize
        try byte(out, hex_digit((value >> shift) & 15usize))
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

// A span from `first`'s start to `last`'s end, the positions derived from the source
// (D315), and one that is a point at `here`'s start.
fn token_span(out: *Out, root: str, path: str, source: str, first: lex.Token, last: lex.Token) -> err {
    let head = lex.span_of(source, out.lines, first)
    let tail = lex.span_of(source, out.lines, last)
    ret span(out, root, path, head.start, tail.end, head.line, head.column, tail.end_line, tail.end_column, head.column_utf16, tail.end_column_utf16)
}

fn point_span(out: *Out, root: str, path: str, source: str, here: lex.Token) -> err {
    let at = lex.span_of(source, out.lines, here)
    ret span(out, root, path, at.start, at.start, at.line, at.column, at.line, at.column, at.column_utf16, at.column_utf16)
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
    try text(out, ",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":3}")
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
    var out: Out = zero
    out.bytes = storage
    try header(&out, "info")
    try text(&out, "{\"record\":\"info\",\"tool_version\":\"0.1.0\",\"language_profiles\":[{\"language_version\":\"0.1\",\"grammar_revision\":3,\"stream_version\":1,\"experimental\":false}],\"commands\":[\"build\",\"check\",\"dis\",\"fmt\",\"index\",\"info\",\"parse\",\"run\",\"test\",\"tokens\"],\"host_target\":")
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
fn trap_source(out: *Out, g: *graph.Graph, path: str, file: str, spelled: str, line: usize, line_offset: usize, line_count: usize) -> err {
    if graph.same(file, spelled) && line > line_offset && line - line_offset <= line_count {
        // The operand under its identity (D519) when the graph is there.
        if g.count != 0usize { ret manifest_source(out, g, g.modules[0usize].path) }
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
// A frame or a trap in a module other than the operand (D503): the file the child
// printed is that module's reproducible spelling (D337), so the graph finds it, its
// source is named under its own root as the manifest names it (D427), and its text
// gives the span. A graph of no modules -- the test runner's path without one --
// leaves such a frame's source null as before.
fn trap_module(g: *graph.Graph, file: str) -> (usize, bool) {
    var at = 1usize
    while at < g.count {
        if graph.same(g.modules[at].spelling, file) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// A frame whose file is a module other than its function's (D519, H19): the body
// was inlined there, so the frame names, as `inlined_from`, the function of that
// module whose source holds the line -- the one the runtime's frame cannot name,
// its code lying inside the caller's. The functions are the checker's, empty for
// the test runner's path.
fn frame_origin(out: *Out, functions: []const check.Function, g: *graph.Graph, frame_module: usize, line: usize) -> err {
    if frame_module >= g.count || line == 0usize { ret ok }
    let module = g.modules[frame_module]
    if line > module.lines.len { ret ok }
    let offset = module.lines[line - 1usize]
    var at = 0usize
    while at < functions.len {
        let function = functions[at]
        if function.module_index == frame_module && offset >= function.source_start && offset < function.source_end {
            try text(out, ",\"inlined_from\":\"")
            try quoted_body(out, module.name)
            try byte(out, 46u8)
            try quoted_body(out, function.name)
            ret byte(out, 34u8)
        }
        at += 1usize
    }
    ret ok
}

// The module part of a frame's `module.function`.
fn frame_module_name(function: str) -> str {
    var dot = 0usize
    while dot < function.len && function[dot] != 46u8 { dot += 1usize }
    ret function[0usize..dot]
}

fn trap_json(out: *Out, g: *graph.Graph, functions: []const check.Function, stderr_bytes: str, module_name: str, path: str, source: str, spelled: str, line_offset: usize) -> err {
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
        // The operand under its own identity (D519): the project's when it has one,
        // as every other record names it; the test runner's path has no graph.
        var operand_root = "operand"
        var operand_path = path
        if g.count != 0usize {
            let (identity_root, identity_relative) = source_identity_of(g, g.modules[0usize].path)
            operand_root = identity_root
            operand_path = identity_relative
        }
        try span(out, operand_root, operand_path, offset, offset, line - line_offset, column, line - line_offset, column, column_utf16, column_utf16)
    } else {
        let (trap_module_index, in_module) = trap_module(g, file)
        if in_module && line > 0usize && line <= trap_line_count(g.modules[trap_module_index].text) {
            let (root, relative) = source_identity_of(g, g.modules[trap_module_index].path)
            let (offset, column_utf16) = trap_byte_at(g.modules[trap_module_index].text, line, column)
            try span(out, root, relative, offset, offset, line, column, line, column, column_utf16, column_utf16)
        } else {
            try text(out, "null")
        }
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
        let (frame_module, frame_in_module) = trap_module(g, frame_file)
        if frame_in_module {
            try manifest_source(out, g, g.modules[frame_module].path)
        } else {
            try trap_source(out, g, path, frame_file, spelled, frame_line, line_offset, line_count)
        }
        try text(out, ",\"line\":")
        if frame_line == 0usize {
            try text(out, "null")
        } else {
            if graph.same(frame_file, spelled) && frame_line > line_offset && frame_line - line_offset <= line_count { try decimal(out, frame_line - line_offset) } else { try decimal(out, frame_line) }
        }
        // Inlined (D519): the frame's function is of one module, its line of another.
        if frame_in_module && !graph.same(frame_module_name(stderr_bytes[cursor + 5usize..function_end]), g.modules[frame_module].name) {
            try frame_origin(out, functions, g, frame_module, frame_line)
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
// `spelled` is the operand as the child prints it -- its reproducible spelling (D337),
// it; `path` is section 2's operand identity, the basename.
fn run_record(a: *mem.Arena, g: *graph.Graph, functions: []const check.Function, status: i32, stdout_bytes: str, stderr_bytes: str, module_name: str, path: str, source: str, spelled: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, (stdout_bytes.len + stderr_bytes.len) * 6usize + 256usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
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
    try trap_json(&out, g, functions, stderr_bytes, module_name, path, source, spelled, 0usize)
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
fn index_comment_start(source: str, tokens: []const lex.Token, index: usize) -> usize {
    let token = tokens[index]
    var at = lex.leading_start(tokens, index)
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
    let start = index_comment_start(source, tokens, at)
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
        var start = index_comment_start(source, tokens, at) + 3usize
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
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 8192usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out: Out = zero
    out.bytes = storage
    let (exit_code, index_error) = index_json_into(a, &out, root, path, source, module_name, module_index, symbols, count, absolute)
    ret (exit_code, index_error)
}

// The index of one module into `out` (D515): the query writes it, a plan over a type
// captures it (`out.capture`) and reads the references back.
fn index_json_into(a: *mem.Arena, out: *Out, root: str, path: str, source: str, module_name: str, module_index: usize, symbols: []const resolve.Symbol, count: usize, absolute: str) -> (usize, err) {
    let (tokens, token_count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, source.len + 1024usize)
    if nodes_error != ok { ret (2usize, nodes_error) }
    let (children, children_error) = mem.alloc[u32](a, source.len + 1024usize)
    if children_error != ok { ret (2usize, children_error) }
    var tree: parse.Tree = zero
    let init_error = parse.init_tree(&tree, nodes, children)
    if init_error != ok { ret (2usize, init_error) }
    let parse_error = parse.parse(&tree, source)
    if parse_error != ok { ret (2usize, parse_error) }
    let (out_lines, out_lines_error) = lex.line_starts(a, source)
    if out_lines_error != ok { ret (0usize, out_lines_error) }
    out.lines = out_lines
    out.absolute = absolute
    // The boundaries each declaration holds (D513): the manifest's scan of the module.
    let (inventory, inventory_count, inventory_error) = module_inventory(a, module_name, source, out_lines)
    if inventory_error != ok { ret (2usize, inventory_error) }
    out.inventory = inventory
    let header_error = header(out, "index")
    if header_error != ok { ret (2usize, header_error) }
    // The module itself is the first symbol, so every declaration's container is id 0.
    let module_error = index_module_record(out, module_name)
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
        // A seeded symbol has no tokens (D515): `e.mem`'s intrinsics stand in the
        // table as functions and types with no source, and are not indexed.
        if known_symbol.module_index == module_index && known_symbol.kind != .Qualifier && known_symbol.kind != .Intrinsic && usize(known_symbol.token_end) != 0usize {
            known_names[known] = known_symbol.name
            known_ids[known] = running
            known_types[known] = known_symbol.kind == .Type
            known += 1usize
            running += 1usize
            // The ids a declaration's nested symbols will take (D258).
            if known_symbol.kind == .Function || known_symbol.kind == .Type || known_symbol.kind == .Extern { running += index_nested_count(&tree, tokens[0usize..token_count], usize(known_symbol.token_start), usize(known_symbol.token_end) - 1usize) }
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
        if symbol.module_index == module_index && symbol.kind != .Qualifier && symbol.kind != .Intrinsic && usize(symbol.token_end) != 0usize {
            let interleave_error = index_emit_references(&refs, out, root, path, source, module_name, &tree, tokens[0usize..token_count], tokens[usize(symbol.token_start)].start)
            if interleave_error != ok { ret (2usize, interleave_error) }
            if known_ids[known] != emitted { ret (2usize, parse.InvalidSyntax) }
            known += 1usize
            var name_index = usize(symbol.token_start) + 1usize
            if symbol.kind == .Extern { name_index += 1usize }
            if usize(symbol.token_end) == 0usize || usize(symbol.token_end) > token_count || name_index >= token_count { ret (2usize, parse.InvalidSyntax) }
            let record_error = index_symbol_record(out, root, path, source, module_name, emitted, symbol, tokens[0usize..token_count], usize(symbol.token_start), usize(symbol.token_end) - 1usize, name_index)
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
                let (nested, nested_error) = index_nested(a, out, root, path, source, module_name, owner_storage[0usize..owner_at], &tree, tokens[0usize..token_count], usize(symbol.token_start), usize(symbol.token_end) - 1usize, emitted - 1usize, emitted, &refs)
                if nested_error != ok { ret (2usize, nested_error) }
                emitted += nested
            }
        }
        at += 1usize
    }
    let drain_error = index_emit_references(&refs, out, root, path, source, module_name, &tree, tokens[0usize..token_count], source.len + 1usize)
    if drain_error != ok { ret (2usize, drain_error) }
    let result_error = index_result(out, emitted, refs.written)
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
    try text(out, ",\"signature\":null,\"span\":null,\"selection_span\":null,\"container_id\":null,\"attributes\":[],\"unsafe\":[],\"documentation\":null}")
    ret flush(out)
}

// The unsafe boundaries a declaration holds (D513, H27): the kinds of the manifest's
// inventory records that name it -- `unsafe`, `nocheck`, `deref`, `extern`, `union`,
// `bitcast`, `cast` -- each once, for a function, an extern or a type; every other
// symbol's list is empty. The inventory is read as the manifest writes it.
fn index_unsafe_kinds(out: *Out, kind: str, name: str) -> err {
    try byte(out, 91u8)
    if graph.same(kind, "fn") || graph.same(kind, "extern") || graph.same(kind, "type") || graph.same(kind, "kernel") || graph.same(kind, "test") {
        let inventory = out.inventory
        var seen: [8]str = zero
        var seen_count = 0usize
        var at = 0usize
        while at < inventory.len {
            let (record_kind, kind_end, has_kind) = inventory_value(inventory, at, "\"kind\":\"")
            if !has_kind { break }
            let (function, function_end, has_function) = inventory_value(inventory, kind_end, "\"function\":\"")
            if !has_function { break }
            at = function_end
            if !graph.same(function, name) { continue }
            var repeated = false
            var seen_at = 0usize
            while seen_at < seen_count {
                if graph.same(seen[seen_at], record_kind) { repeated = true }
                seen_at += 1usize
            }
            if repeated || seen_count == seen.len { continue }
            if seen_count != 0usize { try byte(out, 44u8) }
            try quoted(out, record_kind)
            seen[seen_count] = record_kind
            seen_count += 1usize
        }
    }
    ret byte(out, 93u8)
}

// The value of a string key at or after `from` in the inventory's bytes: the value,
// where it ends, and whether the key was there.
fn inventory_value(inventory: str, from: usize, key: str) -> (str, usize, bool) {
    var at = from
    while at + key.len <= inventory.len {
        if graph.same(inventory[at..at + key.len], key) {
            var end = at + key.len
            while end < inventory.len && inventory[end] != 34u8 { end += 1usize }
            ret (inventory[at + key.len..end], end, true)
        }
        at += 1usize
    }
    ret ("", inventory.len, false)
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
    try token_span(out, root, path, source, opener, closer)
    try text(out, ",\"selection_span\":")
    try token_span(out, root, path, source, name_token, name_token)
    try text(out, ",\"container_id\":")
    try decimal(out, container_id)
    try text(out, ",\"attributes\":")
    try index_attributes(out, source, tokens, attribute_start, first)
    try text(out, ",\"unsafe\":")
    try index_unsafe_kinds(out, kind, name)
    try text(out, ",\"documentation\":")
    try index_documentation(out, source, tokens, attribute_start)
    try byte(out, 125u8)
    ret flush(out)
}

// How many nested symbols index_nested will emit for the declaration at [first, last].
fn index_nested_count(tree: *parse.Tree, tokens: []const lex.Token, first: usize, last: usize) -> usize {
    var found = 0usize
    var node_index = 1usize
    while node_index < tree.count && found < 256usize {
        let node = tree.nodes[node_index]
        if !node.top_level && usize(node.token_start) >= first && usize(node.token_start) <= last && usize(node.token_end) > usize(node.token_start) && index_nested_kind(node.kind).len != 0usize && index_nested_named(node, tokens) { found += index_nested_names(node, tokens) }
        node_index += 1usize
    }
    ret found
}

// The section 7 kind of a nested declaration node, or "" for a node that is not one.
fn index_nested_kind(kind: syntax.Kind) -> str {
    if kind == .Parameter { ret "parameter" }
    if kind == .FieldDecl { ret "field" }
    if kind == .EnumMember || kind == .UnionMember { ret "member" }
    // A `let`/`var` binding and a `for` variable are `local` symbols (D483, H17).
    if kind == .Binding || kind == .ForStmt { ret "local" }
    ret ""
}

// How many symbols a nested node is: a tuple binding `let (a, b)` is one per name,
// a `for` one, anything else one.
fn index_nested_names(node: syntax.Node, tokens: []const lex.Token) -> usize {
    if node.kind == .ForStmt { ret 1usize }
    if node.kind != .Binding || tokens[usize(node.token_start)].kind != .PunctLParen { ret 1usize }
    var count = 0usize
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        if tokens[at].kind == .Identifier { count += 1usize }
        at += 1usize
    }
    ret count
}

// Whether a nested node declares a name (D550): a `Parameter` of a function type,
// `fn(*void, i64)`, is a type alone, and the index had made a `parameter` symbol
// of `i64` and `os` -- renaming the library's locals renamed the types.
fn index_nested_named(node: syntax.Node, tokens: []const lex.Token) -> bool {
    if node.kind != .Parameter { ret true }
    let name_at = usize(node.token_start)
    ret name_at + 1usize < usize(node.token_end) && tokens[name_at].kind == .Identifier && tokens[name_at + 1usize].kind == .PunctColon
}

// The token index of a nested node's `which`th name: the `for` variable after the
// keyword, the names of a tuple binding in order, else the node's first token.
fn index_nested_name(node: syntax.Node, tokens: []const lex.Token, which: usize) -> usize {
    if node.kind == .ForStmt { ret usize(node.token_start) + 1usize }
    if node.kind != .Binding || tokens[usize(node.token_start)].kind != .PunctLParen { ret usize(node.token_start) }
    var seen = 0usize
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        if tokens[at].kind == .Identifier {
            if seen == which { ret at }
            seen += 1usize
        }
        at += 1usize
    }
    ret usize(node.token_start)
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
    refs.owner = owner
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if !node.top_level && usize(node.token_start) >= first && usize(node.token_start) <= last && usize(node.token_end) > usize(node.token_start) && index_nested_kind(node.kind).len != 0usize && index_nested_named(node, tokens) && picked_count < 256usize {
            // Insertion by token position keeps the list ordered as it grows.
            var slot = picked_count
            while slot > 0usize && usize(tree.nodes[picked[slot - 1usize]].token_start) > usize(node.token_start) {
                picked[slot] = picked[slot - 1usize]
                slot = slot - 1usize
            }
            picked[slot] = node_index
            picked_count += 1usize
        }
        node_index += 1usize
    }
    // The declaration's locals and parameters, for the references in its body (D483):
    // each name, its id and the token it is declared at, in token order.
    refs.local_count = 0usize
    refs.local_first = first
    refs.local_last = last
    var written = 0usize
    var pick_at = 0usize
    while pick_at < picked_count {
        let node = tree.nodes[picked[pick_at]]
        let names = index_nested_names(node, tokens)
        var which = 0usize
        while which < names {
            let name_index = index_nested_name(node, tokens, which)
            let name_token = tokens[name_index]
            var record_first = usize(node.token_start)
            var record_last = usize(node.token_end) - 1usize
            if node.kind == .Binding || node.kind == .ForStmt {
                record_first = name_index
                record_last = name_index
            }
            let kind = index_nested_kind(node.kind)
            if (node.kind == .Parameter || node.kind == .Binding || node.kind == .ForStmt) && refs.local_count < refs.local_names.len {
                refs.local_names[refs.local_count] = source[name_token.start..name_token.end]
                refs.local_ids[refs.local_count] = next_id + written
                refs.local_starts[refs.local_count] = name_index
                refs.local_count += 1usize
            }
            // References inside the signature so far come before this symbol (D280).
            let interleave_error = index_emit_references(refs, out, root, path, source, module_name, tree, tokens, name_token.start)
            if interleave_error != ok { ret (0usize, interleave_error) }
            let nested_error = index_record(out, root, path, source, module_name, next_id + written, kind, source[name_token.start..name_token.end], owner, tokens, record_first, record_last, name_index, container_id)
            if nested_error != ok { ret (0usize, nested_error) }
            written += 1usize
            which += 1usize
        }
        pick_at += 1usize
    }
    ret (written, ok)
}

// The `reference` records (D271): every use of a module-scope name of the operand, and
// every use of a name through a `use` qualifier, classified by the tokens around it --
// `f(` is a call, `f[` an instantiation, `= x` a write, `&x` an address, a type position
// a type, a `use` an import, anything else a read. A bare name is one of the operand's
// own symbols or nothing: spec section 5 lets no local shadow a module-scope name, so
// the match is the resolution. Records go out sorted by span start. The tables are
// sized by the tree (D528): a cap of four thousand had dropped every later reference
// of a large module without a word, which renaming the compiler's locals found.
type IndexRefs = struct {
    known_names: []const str,
    known_ids: []const usize,
    known_types: []const bool,
    qualifiers: []str,
    paths: []str,
    imports: usize,
    starts: []usize,
    nodes: []usize,
    roles: []usize,
    picked: usize,
    next: usize,
    written: usize,
    // The current declaration's locals and parameters (D483): a bare name in its
    // body that is one of them, declared before the use -- the latest such, so a
    // shadowing binding wins -- is a reference to that symbol.
    local_names: []str,
    local_ids: []usize,
    local_starts: []usize,
    local_count: usize,
    local_first: usize,
    local_last: usize,
    // The owner's qualified name, for a local's `target_qualified_name`.
    owner: str,
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
    let candidates = tree.count + 16usize
    let (starts, starts_error) = mem.alloc[usize](a, candidates)
    if starts_error != ok { ret (state, starts_error) }
    let (nodes, nodes_error) = mem.alloc[usize](a, candidates)
    if nodes_error != ok { ret (state, nodes_error) }
    let (roles, roles_error) = mem.alloc[usize](a, candidates)
    if roles_error != ok { ret (state, roles_error) }
    let (local_names, local_names_error) = mem.alloc[str](a, 4096usize)
    if local_names_error != ok { ret (state, local_names_error) }
    let (local_ids, local_ids_error) = mem.alloc[usize](a, 4096usize)
    if local_ids_error != ok { ret (state, local_ids_error) }
    let (local_starts, local_starts_error) = mem.alloc[usize](a, 4096usize)
    if local_starts_error != ok { ret (state, local_starts_error) }
    state.local_names = local_names
    state.local_ids = local_ids
    state.local_starts = local_starts
    var picked = 0usize
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        var role = 99usize
        var candidate_start = usize(node.token_start)
        if node.kind == .UseDecl {
            role = 0usize
            if imports < 256usize {
                // `use a.b.c [as q]`: the qualifier is the alias or the last segment.
                var last = usize(node.token_start) + 1usize
                var path_end = last
                while path_end + 1usize < usize(node.token_end) && (tokens[path_end + 1usize].kind == .PunctDot || tokens[path_end + 1usize].kind == .Identifier) && tokens[path_end + 1usize].kind != .KwAs {
                    path_end += 1usize
                    if tokens[path_end].kind == .Identifier { last = path_end }
                }
                var qualifier = tokens[last]
                if path_end + 2usize < usize(node.token_end) && tokens[path_end + 1usize].kind == .KwAs { qualifier = tokens[path_end + 2usize] }
                qualifiers[imports] = source[qualifier.start..qualifier.end]
                paths[imports] = source[tokens[usize(node.token_start) + 1usize].start..tokens[path_end].end]
                imports += 1usize
            }
        }
        if node.kind == .NameExpr || node.kind == .NamedType { role = 1usize }
        // `resource(cleanup)` is a resolved reference to the consuming function
        // even though it is contextual syntax rather than an expression (D560).
        if node.kind == .TypeDecl {
            var token_at = usize(node.token_start)
            while token_at + 3usize < usize(node.token_end) && token_at + 3usize < tokens.len {
                if tokens[token_at].kind == .Identifier && graph.same(source[tokens[token_at].start..tokens[token_at].end], "resource") && tokens[token_at + 1usize].kind == .PunctLParen && tokens[token_at + 2usize].kind == .Identifier && tokens[token_at + 3usize].kind == .PunctRParen {
                    role = 2usize
                    candidate_start = token_at + 2usize
                    token_at = usize(node.token_end)
                }
                token_at += 1usize
            }
        }
        var wanted = role == 0usize
        if (role == 1usize && usize(node.token_end) > usize(node.token_start) && tokens[usize(node.token_start)].kind == .Identifier) || role == 2usize { wanted = true }
        if wanted && picked < nodes.len {
            var slot = picked
            while slot > 0usize && starts[slot - 1usize] > candidate_start {
                starts[slot] = starts[slot - 1usize]
                nodes[slot] = nodes[slot - 1usize]
                roles[slot] = roles[slot - 1usize]
                slot = slot - 1usize
            }
            starts[slot] = candidate_start
            nodes[slot] = node_index
            roles[slot] = role
            picked += 1usize
        }
        node_index += 1usize
    }
    state.qualifiers = qualifiers
    state.paths = paths
    state.imports = imports
    state.starts = starts
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
    let starts = state.starts
    let roles = state.roles
    var at = state.next
    while at < state.picked && tokens[starts[at]].start < before {
        let node = tree.nodes[nodes[at]]
        if roles[at] == 0usize {
            // The import: spelled as the path, its found the module.
            let path_start = tokens[usize(node.token_start) + 1usize]
            var path_end = usize(node.token_start) + 1usize
            while path_end + 1usize < usize(node.token_end) && tokens[path_end + 1usize].kind != .KwAs { path_end += 1usize }
            let spelling = source[path_start.start..tokens[path_end].end]
            let import_error = reference_record(out, root, path, source, path_start, tokens[path_end], "import", spelling, 0usize, false, spelling)
            if import_error != ok { ret import_error }
            state.written += 1usize
        } else {
            var first = usize(node.token_start)
            if roles[at] == 2usize { first = starts[at] }
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
            if roles[at] == 2usize && found < known_ids.len {
                var cleanup_scratch: [512]u8 = zero
                var cleanup_at = nptest_copy(cleanup_scratch[..], 0usize, module_name)
                cleanup_scratch[cleanup_at] = 46u8
                cleanup_at += 1usize
                cleanup_at = nptest_copy(cleanup_scratch[..], cleanup_at, name)
                let cleanup_error = reference_record(out, root, path, source, name_token, name_token, "protocol", name, known_ids[found], true, cleanup_scratch[0usize..cleanup_at])
                if cleanup_error != ok { ret cleanup_error }
                state.written += 1usize
            }
            // A local of the current declaration (D483): the latest of its name
            // declared before this use, inside the declaration; spec section 5 lets
            // no local shadow a module-scope name, so a known name is never one.
            var local_found = state.local_count
            if qualified_import == 256usize && found == known_ids.len && node.kind == .NameExpr && first >= state.local_first && first <= state.local_last {
                var local_at = 0usize
                while local_at < state.local_count {
                    if state.local_starts[local_at] < first && graph.same(state.local_names[local_at], name) { local_found = local_at }
                    local_at += 1usize
                }
            }
            if roles[at] != 2usize && local_found < state.local_count {
                var local_role = "read"
                let after = first + 1usize
                if after < tokens.len {
                    if tokens[after].kind == .PunctLParen { local_role = "call" }
                    if parse.is_assignment_op(tokens[after].kind) { local_role = "write" }
                }
                if first > 0usize && tokens[first - 1usize].kind == .PunctAmp && !graph.same(local_role, "write") { local_role = "address" }
                var local_scratch: [512]u8 = zero
                var local_scratch_at = nptest_copy(local_scratch[..], 0usize, state.owner)
                local_scratch[local_scratch_at] = 46u8
                local_scratch_at += 1usize
                local_scratch_at = nptest_copy(local_scratch[..], local_scratch_at, name)
                let local_error = reference_record(out, root, path, source, name_token, name_token, local_role, name, state.local_ids[local_found], true, local_scratch[0usize..local_scratch_at])
                if local_error != ok { ret local_error }
                state.written += 1usize
            }
            if roles[at] != 2usize && (qualified_import < 256usize || found < known_ids.len) {
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
                    let record_error = reference_record(out, root, path, source, name_token, tokens[last_index], role_name, spelling, 0usize, false, qualified_name)
                    if record_error != ok { ret record_error }
                } else {
                    var scratch_at = nptest_copy(scratch[..], 0usize, module_name)
                    scratch[scratch_at] = 46u8
                    scratch_at += 1usize
                    scratch_at = nptest_copy(scratch[..], scratch_at, name)
                    let record_error = reference_record(out, root, path, source, name_token, tokens[last_index], role_name, spelling, known_ids[found], true, scratch[0usize..scratch_at])
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

fn reference_record(out: *Out, root: str, path: str, source: str, first: lex.Token, last: lex.Token, role: str, spelling: str, target_id: usize, has_target: bool, qualified: str) -> err {
    try text(out, "{\"record\":\"reference\",\"source_span\":")
    try token_span(out, root, path, source, first, last)
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
// Inlined ranges (D542, H19): `inlined` lists, per function, the runs of its code
// whose line entries fall in another function -- the copy of a callee's body in a
// release build -- as `from`, `start` and `end` (function-relative, `end` exclusive)
// and the callee's `line` the run begins at; empty in a debug build.
fn disassembly_json(a: *mem.Arena, arch: str, os_name: str, builder: *nir.Builder, offsets: []const usize, machine: []const u8, machine_count: usize, relocations: []const codegen_x64.Relocation, relocation_count: usize, functions: []const check.Function, g: *graph.Graph, lines: []const codegen_x64.LineEntry, line_count: usize) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, machine_count * 64usize + 8192usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
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
        // The disassembler reads a byte per word (D307): widen the function's range.
        let (words, words_error) = mem.alloc[usize](a, stop - start + 1usize)
        if words_error != ok { ret words_error }
        var widen_at = 0usize
        while widen_at < stop - start {
            words[widen_at] = usize(machine[start + widen_at])
            widen_at += 1usize
        }
        let (listed, decode_error) = disasm_x64.disassemble(words[0usize..stop - start], listing)
        if decode_error != ok { ret decode_error }
        // A `call` whose target is another function's start is named after its bytes
        // (D278): the displacements were resolved before this, so the target is known.
        try quoted_listing(&out, listing[0usize..listed], start, builder, offsets, relocations, relocation_count)
        mem.reset(a, checkpoint)
        try inlined_ranges(&out, builder, function, start, stop, functions, g, lines, line_count)
        try byte(&out, 125u8)
        try flush(&out)
        at += 1usize
    }
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"functions\":")
    try decimal(&out, builder.function_count)
    try text(&out, "}}")
    ret flush(&out)
}

// The function of a line entry (D542): its module by path, the function of the
// module whose source holds the line, as `frame_origin` finds a frame's (D519).
fn line_function(functions: []const check.Function, g: *graph.Graph, entry: codegen_x64.LineEntry) -> (usize, bool) {
    // The entry's path is the module's reproducible spelling (D337), the root's too.
    var module_at = 0usize
    while module_at < g.count {
        if graph.same(g.modules[module_at].spelling, entry.path) || graph.same(g.modules[module_at].path, entry.path) { break }
        module_at += 1usize
    }
    if module_at >= g.count || entry.line == 0u32 || usize(entry.line) > g.modules[module_at].lines.len { ret (0usize, false) }
    let offset = g.modules[module_at].lines[usize(entry.line) - 1usize]
    var at = 0usize
    while at < functions.len {
        if functions[at].module_index == module_at && offset >= functions[at].source_start && offset < functions[at].source_end { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn inline_chain(builder: *nir.Builder, origin: u32, chain: []usize) -> (usize, bool) {
    var count = 0usize
    var cursor = origin
    let first = builder.inlined.len - builder.inline_origin_count
    while cursor != 0u32 {
        let index = usize(cursor) - 1usize
        if index < first || index >= builder.inlined.len || count == chain.len { ret (0usize, false) }
        chain[count] = index
        count += 1usize
        cursor = u32(builder.inlined[index].caller_function)
    }
    ret (count, count != 0usize)
}

fn inline_origin_range(out: *Out, builder: *nir.Builder, g: *graph.Graph, origin: u32, range_start: usize, range_end: usize, line: usize, written: *usize) -> err {
    if range_start == range_end { ret ok }
    var chain: [8]usize = zero
    let (count, found) = inline_chain(builder, origin, chain[..])
    if !found { ret ok }
    if *written != 0usize { try byte(out, 44u8) }
    *written += 1usize
    let inner = builder.inlined[chain[count - 1usize]]
    try text(out, "{\"from\":\"")
    if inner.callee_module < g.count { try quoted_body(out, g.modules[inner.callee_module].name) }
    try byte(out, 46u8)
    try quoted_body(out, inner.name)
    try byte(out, 34u8)
    if count > 1usize {
        try text(out, ",\"through\":[")
        var through = count - 1usize
        var separated = false
        while through != 0usize {
            through = through - 1usize
            let middle = builder.inlined[chain[through]]
            if separated { try byte(out, 44u8) }
            try byte(out, 34u8)
            if middle.callee_module < g.count { try quoted_body(out, g.modules[middle.callee_module].name) }
            try byte(out, 46u8)
            try quoted_body(out, middle.name)
            try byte(out, 34u8)
            separated = true
        }
        try byte(out, 93u8)
    }
    try text(out, ",\"start\":")
    try decimal(out, range_start)
    try text(out, ",\"end\":")
    try decimal(out, range_end)
    try text(out, ",\"line\":")
    try decimal(out, line)
    ret byte(out, 125u8)
}

fn inlined_ranges(out: *Out, builder: *nir.Builder, function: nir.Function, start: usize, stop: usize, functions: []const check.Function, g: *graph.Graph, lines: []const codegen_x64.LineEntry, line_count: usize) -> err {
    try text(out, ",\"inlined\":[")
    var written = 0usize
    var run_function = functions.len
    var run_origin = 0u32
    var run_start = 0usize
    var run_line = 0usize
    var at = 0usize
    while at < line_count {
        let entry = lines[at]
        at += 1usize
        if entry.offset < start || entry.offset >= stop { continue }
        var next_origin = entry.origin
        var next_function = functions.len
        if next_origin == 0u32 {
            let (owner, found) = line_function(functions, g, entry)
            // Artifact-linked rows predate the transient origin chain, so retain the
            // D542 source lookup as their single-level fallback.
            var own = !found
            if found && functions[owner].module_index < g.count && graph.same(g.modules[functions[owner].module_index].name, function.module_name) && graph.same(functions[owner].name, function.name) { own = true }
            if !own { next_function = owner }
        }
        if next_origin == run_origin && next_function == run_function { continue }
        if run_origin != 0u32 {
            try inline_origin_range(out, builder, g, run_origin, run_start - start, entry.offset - start, run_line, &written)
        } else {
        if run_function != functions.len {
            try inlined_range(out, g, functions[run_function], run_start - start, entry.offset - start, run_line, &written)
        }
        }
        run_origin = next_origin
        run_function = next_function
        run_start = entry.offset
        run_line = usize(entry.line)
    }
    if run_origin != 0u32 {
        try inline_origin_range(out, builder, g, run_origin, run_start - start, stop - start, run_line, &written)
    } else {
    if run_function != functions.len {
        try inlined_range(out, g, functions[run_function], run_start - start, stop - start, run_line, &written)
    }
    }
    ret byte(out, 93u8)
}

fn inlined_range(out: *Out, g: *graph.Graph, callee: check.Function, range_start: usize, range_end: usize, line: usize, written: *usize) -> err {
    // A line entry with no code before the next -- a `ret` folded away -- is no run.
    if range_start == range_end { ret ok }
    if *written != 0usize { try byte(out, 44u8) }
    *written += 1usize
    try text(out, "{\"from\":\"")
    if callee.module_index < g.count { try quoted_body(out, g.modules[callee.module_index].name) }
    try byte(out, 46u8)
    try quoted_body(out, callee.name)
    try text(out, "\",\"start\":")
    try decimal(out, range_start)
    try text(out, ",\"end\":")
    try decimal(out, range_end)
    try text(out, ",\"line\":")
    try decimal(out, line)
    ret byte(out, 125u8)
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
    var raw: Out = zero
    raw.bytes = raw_storage
    raw.absolute = ""
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
            var trivia = lex.trivia_kinds_of(source, tokens, at)
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
            var trivia = lex.trivia_kinds_of(source, tokens, at)
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
    try token_span(out, root, path, source, token, token)
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
            let leading = lex.leading_start(tokens, at)
            if after_attribute && line_first && leading < token.start {
                let comment_start = index_comment_start(source, tokens, at)
                if comment_start + 1usize < token.start && source[comment_start] == 47u8 && source[comment_start + 1usize] == 47u8 {
                    // The comment's line is where the previous token ended; the bytes before
                    // it on that line are indentation, one column each.
                    var comment: lex.Span = zero
                    comment.start = comment_start
                    comment.end = token.start
                    comment.line = lex.line_of(source, out.lines, comment_start)
                    comment.column = lex.column_of(source, out.lines, comment_start)
                    comment.column_utf16 = comment.column
                    let ending = lex.span_of(source, out.lines, token)
                    comment.end_line = ending.line
                    comment.end_column = ending.column
                    comment.end_column_utf16 = ending.column_utf16
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
    var out: Out = zero
    let (out_lines, out_lines_error) = lex.line_starts(a, source)
    if out_lines_error != ok { ret (0usize, out_lines_error) }
    out.lines = out_lines
    out.bytes = storage
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
    var probe: Out = zero
    probe.bytes = scratch
    probe.absolute = ""
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
    try decimal(out, lex.line_of(source, out.lines, token.start))
    try byte(out, 58u8)
    try decimal(out, lex.column_of(source, out.lines, token.start))
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
    var out: Out = zero
    let (out_lines, out_lines_error) = lex.line_starts(a, source)
    if out_lines_error != ok { ret (0usize, out_lines_error) }
    out.lines = out_lines
    out.bytes = storage
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
// A path with a suffix appended, in the arena.
fn path_with_suffix(a: *mem.Arena, path: str, suffix: str) -> (str, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, path.len + suffix.len)
    if buffer_error != ok { ret ("", buffer_error) }
    os.copy_bytes(buffer[0usize..path.len], path)
    os.copy_bytes(buffer[path.len..path.len + suffix.len], suffix)
    ret (buffer[0usize..path.len + suffix.len], ok)
}

fn manifest_source(out: *Out, g: *graph.Graph, path: str) -> err {
    let (root, relative) = source_identity_of(g, path)
    ret manifest_identity(out, root, relative)
}

// The root and the path under it, as `manifest_source` writes them, for a caller
// that wants them as strings (separators still as the host spells them).
fn source_identity_of(g: *graph.Graph, path: str) -> (str, str) {
    let (src_relative, under_src) = project.relative_under(path, g.project.root, "src")
    if under_src && g.project.has_sources { ret ("project-src", src_relative) }
    let (lib_relative, under_lib) = project.relative_under(path, g.project.root, "lib")
    if under_lib && g.project.has_sources { ret ("project-lib", lib_relative) }
    let (toolchain_relative, under_toolchain) = project.relative_under(path, g.toolchain_root, "lib")
    if under_toolchain { ret ("toolchain-lib", toolchain_relative) }
    ret ("operand", manifest_basename(path))
}

// `explain-file PATH ROOT ARCH OS --json` (D359, H06): what the checker decided
// across the program, one record per protocol dispatch and per generic
// instantiation, by module then byte offset: `dispatch` carries the protocol, the
// receiver type, and the choice -- the declared function, the supplied rule, or
// none -- and `instance` the template and its arguments. Records the checker made
// twice for one site (a re-check of the same call) are written once.
// `failed` (D430): the program did not check; the records the checker made before it
// stopped are written -- a dispatch that found nothing among them, with why -- and the
// caller adds the diagnostic and the result.
fn explain_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, failed: bool) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, c.explain_count * 512usize + 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    let header_error = header(&out, "explain")
    if header_error != ok { ret header_error }
    var written = 0usize
    var last = c.explains[0usize]
    var first = true
    let (order, order_error) = explain_order(a, c)
    if order_error != ok { ret order_error }
    var ordered_at = 0usize
    while ordered_at < order.len {
        // In `explain_before`'s order (D539); two records that order equal are one
        // site decided twice, and the second is not after the first.
        let e = c.explains[order[ordered_at]]
        ordered_at += 1usize
        if !first && !explain_before(last, e) { continue }
        first = false
        last = e
        // Calls, values and field accesses (D420) are `uses-file`'s and `context-file`'s.
        if e.module_index >= g.count || e.kind == 4u8 || e.kind == 5u8 || e.kind == 6u8 || e.kind == 7u8 || e.kind == 9u8 || e.kind == 10u8 || e.kind == 11u8 { continue }
        let module = g.modules[e.module_index]
        let (root, relative) = source_identity_of(g, module.path)
        let (path, path_error) = manifest_slashes(a, relative)
        if path_error != ok { ret path_error }
        out.lines = module.lines
        var here: lex.Token = zero
        here.start = e.offset
        here.end = e.offset
        if e.kind == 1u8 {
            let write_error = text(&out, "{\"record\":\"dispatch\",\"protocol\":")
            if write_error != ok { ret write_error }
            try quoted(&out, e.protocol)
            try text(&out, ",\"receiver\":")
            try quoted_type(&out, c, g, e.receiver)
            try text(&out, ",\"selected\":")
            if e.found {
                try text(&out, "{\"kind\":\"declared\",\"function\":")
                try quoted_function(&out, c, g, e.function_index)
                try byte(&out, 125u8)
            } else {
                if e.builtin == .None {
                    // Why (D430, H06): the component the supplied rule refused, and a
                    // function of the name declared where rule 4 does not look.
                    try text(&out, "{\"kind\":\"none\",\"reason\":")
                    if e.reason_kind == 1u8 { try text(&out, "\"a struct has no supplied rule\"") }
                    if e.reason_kind == 2u8 {
                        try text(&out, "\"the arm `")
                        try text(&out, e.reason_name)
                        try text(&out, "` of type ")
                        try quoted_type_inner(&out, c, g, e.reason_type)
                        try text(&out, " has no `")
                        try text(&out, e.protocol)
                        try text(&out, "`\"")
                    }
                    if e.reason_kind == 3u8 {
                        try text(&out, "\"the element type ")
                        try quoted_type_inner(&out, c, g, e.reason_type)
                        try text(&out, " has no `")
                        try text(&out, e.protocol)
                        try text(&out, "`\"")
                    }
                    if e.reason_kind == 4u8 {
                        try text(&out, "\"the rule does not cover ")
                        try quoted_type_inner(&out, c, g, e.reason_type)
                        try byte(&out, 34u8)
                    }
                    if e.reason_kind == 0u8 { try text(&out, "null") }
                    try text(&out, ",\"candidates\":[")
                    if e.candidate_index < c.function_count {
                        try text(&out, "{\"function\":")
                        try quoted_function(&out, c, g, e.candidate_index)
                        try text(&out, ",\"reason\":\"declared outside the receiver's module\"}")
                    }
                    try text(&out, "]}")
                } else {
                    try text(&out, "{\"kind\":\"supplied\",\"rule\":")
                    if e.builtin == .Cmp { try text(&out, "\"cmp\"") }
                    if e.builtin == .Hash { try text(&out, "\"hash\"") }
                    if e.builtin == .Eq { try text(&out, "\"eq\"") }
                    try byte(&out, 125u8)
                }
            }
        } else {
            if e.kind == 3u8 {
                try text(&out, "{\"record\":\"discard\",\"function\":")
                try quoted_function(&out, c, g, e.function_index)
                try text(&out, ",\"deferred\":")
                if e.found { try text(&out, "true") } else { try text(&out, "false") }
            } else {
            if e.kind == 8u8 {
                // The phase (D463, H06): an `if` settled at compile time.
                try text(&out, "{\"record\":\"phase\",\"construct\":\"if\",\"phase\":\"comptime\",\"taken\":")
                if e.found { try text(&out, "true") } else { try text(&out, "false") }
            } else {
            try text(&out, "{\"record\":\"instance\",\"template\":")
            try quoted_function(&out, c, g, e.template_index)
            try text(&out, ",\"arguments\":[")
            var argument_at = 0usize
            while argument_at < e.argument_count {
                if argument_at != 0usize { try byte(&out, 44u8) }
                let argument = c.generic_arguments[e.first_argument + argument_at]
                if argument.kind == .Type {
                    try quoted_type(&out, c, g, argument.ty)
                } else {
                    if argument.kind == .Integer {
                        try byte(&out, 34u8)
                        try decimal(&out, argument.value)
                        try byte(&out, 34u8)
                    } else {
                        try quoted(&out, argument.text)
                    }
                }
                argument_at += 1usize
            }
            try byte(&out, 93u8)
            }
            }
        }
        try text(&out, ",\"span\":")
        try point_span(&out, root, path, module.text, here)
        try byte(&out, 125u8)
        try flush(&out)
        written += 1usize
    }
    if failed { ret ok }
    // The constants' phase (D468, H06): every `const` the operand declares that the
    // checker settled before the program runs, with its type and value -- what a
    // reader of the source cannot see without evaluating it.
    var constant_at = 0usize
    while constant_at < c.constant_count {
        let constant = c.constants[constant_at]
        if constant.module_index == 0usize && constant.token.end != 0usize && constant.state == 2u8 {
            try text(&out, "{\"record\":\"phase\",\"construct\":\"const\",\"phase\":\"comptime\",\"symbol\":")
            try byte(&out, 34u8)
            try text(&out, g.modules[0usize].name)
            try byte(&out, 46u8)
            try text(&out, constant.name)
            try byte(&out, 34u8)
            try text(&out, ",\"type\":")
            try quoted_type(&out, c, g, constant.ty)
            try text(&out, ",\"value\":\"")
            if constant.ty.kind == .Bool {
                if constant.value.magnitude != 0usize { try text(&out, "true") } else { try text(&out, "false") }
            } else {
                if constant.value.negative { try byte(&out, 45u8) }
                try decimal(&out, constant.value.magnitude)
            }
            try text(&out, "\",\"span\":")
            let (constant_root, constant_relative) = source_identity_of(g, g.modules[0usize].path)
            let (constant_path, constant_path_error) = manifest_slashes(a, constant_relative)
            if constant_path_error != ok { ret constant_path_error }
            out.lines = g.modules[0usize].lines
            try point_span(&out, constant_root, constant_path, g.modules[0usize].text, constant.token)
            try byte(&out, 125u8)
            try flush(&out)
            written += 1usize
        }
        constant_at += 1usize
    }
    // The layouts (D463, H06): every aggregate the operand declares, and every
    // instance of one, as the target lays it out -- size, alignment and each
    // field's offset and size; an enum's members with their values.
    var aggregate_at = 0usize
    while aggregate_at < c.aggregate_count {
        let aggregate = c.aggregates[aggregate_at]
        // The seeded `target` enums have no token and are nobody's declaration.
        if aggregate.module_index == 0usize && aggregate.token.end != 0usize && !(aggregate.generic && !aggregate.instance) {
            try layout_json(a, &out, c, g, aggregate_at)
            written += 1usize
        }
        aggregate_at += 1usize
    }
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"records\":")
    try decimal(&out, written)
    if c.explain_overflow { try text(&out, ",\"truncated\":true") }
    try text(&out, "}}")
    try flush(&out)
    ret ok
}

// One aggregate's layout record (D463): the type, its kind, size and alignment,
// and its fields with their offsets and sizes (an enum's with their values).
fn layout_json(a: *mem.Arena, out: *Out, c: *check.Checker, g: *graph.Graph, aggregate_at: usize) -> err {
    let aggregate = c.aggregates[aggregate_at]
    var ty = check.make_type(.Named, aggregate.name, aggregate.module_index)
    ty.has_element = true
    ty.element = aggregate_at
    try text(out, "{\"record\":\"layout\",\"type\":")
    try quoted_type(out, c, g, ty)
    try text(out, ",\"kind\":")
    if aggregate.kind == .Struct { try text(out, "\"struct\"") }
    if aggregate.kind == .Union { try text(out, "\"union\"") }
    if aggregate.kind == .TaggedUnion { try text(out, "\"tagged-union\"") }
    if aggregate.kind == .Enum { try text(out, "\"enum\"") }
    let (info, info_error) = layout.type_info(c, ty)
    if info_error != ok { ret info_error }
    try text(out, ",\"size\":")
    try decimal(out, info.size)
    try text(out, ",\"align\":")
    try decimal(out, info.alignment)
    try text(out, ",\"fields\":[")
    var field_at = 0usize
    while field_at < aggregate.field_count {
        if field_at != 0usize { try byte(out, 44u8) }
        let member = c.aggregate_fields[aggregate.first_field + field_at]
        try text(out, "{\"name\":")
        try quoted(out, member.name)
        if aggregate.kind == .Enum {
            if member.has_enum_value {
                try text(out, ",\"value\":")
                if member.enum_negative { try byte(out, 45u8) }
                try decimal(out, member.enum_value)
            }
        } else {
        // A tagged union's arm without a payload has no bytes of its own.
        if member.ty.kind == .Void || member.ty.kind == .Invalid {
            try text(out, ",\"offset\":0,\"size\":0")
        } else {
            let (placed, placed_error) = layout.field(c, ty, member.name)
            if placed_error != ok { ret placed_error }
            let (field_info, field_info_error) = layout.type_info(c, member.ty)
            if field_info_error != ok { ret field_info_error }
            try text(out, ",\"type\":")
            try quoted_type(out, c, g, member.ty)
            try text(out, ",\"offset\":")
            try decimal(out, placed.offset)
            try text(out, ",\"size\":")
            try decimal(out, field_info.size)
        }
        }
        try byte(out, 125u8)
        field_at += 1usize
    }
    try text(out, "],\"span\":")
    let module = g.modules[aggregate.module_index]
    let (root, relative) = source_identity_of(g, module.path)
    let (path, path_error) = manifest_slashes(a, relative)
    if path_error != ok { ret path_error }
    out.lines = module.lines
    try point_span(out, root, path, module.text, aggregate.token)
    try byte(out, 125u8)
    ret flush(out)
}

// A total order over the records: module, offset, kind, then what was decided --
// the receiver, the function or rule, the instance's arguments -- so a site decided
// twice the same way is one record and a template's site decided per instance is one
// per instance.
// `context-file PATH ROOT ARCH OS --json --symbol module.name [--budget N] [--cursor N]`
// (D361, H08): what the compiler knows about one function, as facts with their
// provenance, under a record budget. The subject's declaration comes from the
// checker's tables; what its body decided comes from the explain records inside
// its source range -- calls, dispatches, instantiations, discards; the unsafe
// boundaries from the same byte scan the manifest uses. Every fact says how it
// is known: `declared-and-checked` for what the source says and the checker
// accepted, `compiler-proved` for what the checker established on its own,
// `unknown` for a call whose target is a value. The result says how many records
// were written, how many the budget left out, whether the answer is complete, and
// the cursor that continues it.
// A page of facts (D397): the cursor and the budget, and what a writer has
// counted, written and left out against them.
type Page = struct {
    cursor: usize,
    budget: usize,
    // `--bytes N` (D400, H08): the serialized bytes a page may reach before the rest
    // is omitted; zero is no byte budget.
    byte_budget: usize,
    total: usize,
    written: usize,
    omitted: usize,
}

// Whether the page takes another record: under its record budget, and under its
// byte budget when it has one.
fn page_open(page: *Page, out: *Out) -> bool {
    if page.written >= page.budget { ret false }
    ret page.byte_budget == 0usize || out.flushed < page.byte_budget
}

// The subject's module's dependencies (D498, H08): one fact per imported module,
// naming it and its interface hash -- what the manifest's `dependencies` record
// as `interface_sha256` -- so a harness holding an answer knows which interfaces
// it rests on and sees one change without the whole snapshot. Counted against the
// page like the contract facts, after them and before the body's decisions.
fn dependency_facts(a: *mem.Arena, out: *Out, g: *graph.Graph, module_index: usize, page: *Page) -> err {
    if module_index >= g.count { ret ok }
    let module = g.modules[module_index]
    var import_at = module.first_import
    let import_end = module.first_import + module.import_count
    while import_at < import_end {
        let imported = g.imports[import_at].target
        if imported < g.count {
            page.total += 1usize
            if page.total > page.cursor && page_open(page, out) {
                let (digest, digest_error) = manifest_interface_sha256(a, g, imported)
                if digest_error != ok { ret digest_error }
                try text(out, "{\"record\":\"fact\",\"kind\":\"dependency\",\"provenance\":\"compiler-proved\",\"value\":\"")
                try text(out, g.modules[imported].name)
                try text(out, " interface ")
                try text(out, digest)
                try text(out, "\"}")
                try flush(out)
                page.written += 1usize
            } else {
                if page.total > page.cursor { page.omitted += 1usize }
            }
        }
        import_at += 1usize
    }
    ret ok
}

// A generic declaration's whole header, from `fn` to its body. Its checker types
// deliberately do not retain dependent spellings such as `[N]u8`; the checked token
// range does, and `quoted` makes even a multiline signature one JSON string (D573).
fn generic_signature(c: *check.Checker, g: *graph.Graph, function_index: usize) -> (str, err) {
    if function_index >= c.function_count || c.function_generics[function_index].comptime_count == 0usize { ret ("", parse.InvalidSyntax) }
    let function = c.functions[function_index]
    if function.module_index >= g.count { ret ("", parse.InvalidSyntax) }
    let module = g.modules[function.module_index]
    var token_at = 0usize
    while token_at < module.tokens.len && module.tokens[token_at].end <= function.source_start { token_at += 1usize }
    var start = function.source_start
    var found_fn = false
    while token_at < module.tokens.len && module.tokens[token_at].start < function.source_end {
        let token = module.tokens[token_at]
        if !found_fn {
            if token.kind == .KwFn {
                start = token.start
                found_fn = true
            }
        } else {
            if token.kind == .PunctLBrace {
                var end = token.start
                while end > start && (module.text[end - 1usize] == 32u8 || module.text[end - 1usize] == 9u8 || module.text[end - 1usize] == 10u8 || module.text[end - 1usize] == 13u8) { end = end - 1usize }
                ret (module.text[start..end], ok)
            }
        }
        token_at += 1usize
    }
    ret ("", parse.InvalidSyntax)
}

// One function's contract facts (D361, D396), in their fixed order, counted
// against the page: the signature, an ownership fact per `own` parameter, the
// caller's contract per pointer parameter, the errors, the thread start, then the
// body's resource verdict or its `@unsafe` boundary, then the whole-image boundary
// when its checks are off. `context-file --symbol` follows them with the body's
// decisions; `--module` writes them per function.
fn contract_facts(out: *Out, c: *check.Checker, g: *graph.Graph, function_index: usize, page: *Page, checks: str) -> err {
    let function = c.functions[function_index]
    // Signature.
    page.total += 1usize
    if page.total > page.cursor && page_open(page, out) {
        try text(out, "{\"record\":\"fact\",\"kind\":\"signature\",\"provenance\":\"declared-and-checked\",\"value\":")
        if c.function_generics[function_index].comptime_count != 0usize {
            let (signature, signature_error) = generic_signature(c, g, function_index)
            if signature_error != ok { ret signature_error }
            try quoted(out, signature)
        } else {
            try text(out, "\"fn ")
            try text(out, function.name)
            try byte(out, 40u8)
            var parameter_at = 0usize
            while parameter_at < function.parameter_count {
                if parameter_at != 0usize { try text(out, ", ") }
                let parameter = c.parameters[function.first_parameter + parameter_at]
                try text(out, parameter.name)
                try text(out, ": ")
                if parameter.own { try text(out, "own ") }
                try type_text(out, c, g, parameter.ty, 0usize)
                parameter_at += 1usize
            }
            try byte(out, 41u8)
            if function.return_count != 0usize {
                try text(out, " -> ")
                if function.return_count > 1usize { try byte(out, 40u8) }
                var return_at = 0usize
                while return_at < function.return_count {
                    if return_at != 0usize { try text(out, ", ") }
                    try type_text(out, c, g, c.return_types[function.first_return + return_at], 0usize)
                    return_at += 1usize
                }
                if function.return_count > 1usize { try byte(out, 41u8) }
            }
            try byte(out, 34u8)
        }
        try byte(out, 125u8)
        try flush(out)
        page.written += 1usize
    } else {
        if page.total > page.cursor { page.omitted += 1usize }
    }
    // Ownership: each `own` parameter is a transfer the caller makes.
    var own_at = 0usize
    while own_at < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + own_at]
        if parameter.own {
            page.total += 1usize
            if page.total > page.cursor && page_open(page, out) {
                try text(out, "{\"record\":\"fact\",\"kind\":\"ownership\",\"provenance\":\"declared-and-checked\",\"value\":\"takes ")
                try text(out, parameter.name)
                try text(out, ": the caller's value moves in and this function owes its cleanup on every exit\"}")
                try flush(out)
                page.written += 1usize
            } else {
                if page.total > page.cursor { page.omitted += 1usize }
            }
        }
        own_at += 1usize
    }
    // The contract the signature declares and the checker applies at every caller
    // (D396, H11): an arena parameter is an allocation, whose pointer-holding
    // results belong to the caller's region; a `*T` parameter is a borrow when
    // something holding a pointer comes back (a view of the argument) and a
    // mutation otherwise (the caller's views of the argument dangle, D354); a
    // `*const T` parameter is read alone; an `err` result is fallible, and partial
    // when other results ride with it (D353).
    var returns_pointer = false
    var returns_err = false
    var return_scan = 0usize
    while return_scan < function.return_count {
        let return_index = function.first_return + return_scan
        if return_index < c.return_type_count {
            if check.holds_pointer(c, c.return_types[return_index], 0usize) { returns_pointer = true }
            if c.return_types[return_index].kind == .Err { returns_err = true }
        }
        return_scan += 1usize
    }
    var contract_at = 0usize
    while contract_at < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + contract_at]
        if parameter.ty.kind == .Pointer && parameter.ty.has_element && parameter.ty.element < c.type_count {
            let pointee = c.types[parameter.ty.element]
            page.total += 1usize
            if page.total > page.cursor && page_open(page, out) {
                if check.seeded_arena(c, pointee) {
                    try text(out, "{\"record\":\"fact\",\"kind\":\"allocation\",\"provenance\":\"declared-and-checked\",\"value\":\"allocates from ")
                    try text(out, parameter.name)
                    if returns_pointer {
                        try text(out, ": what it returns that can hold a pointer belongs to the caller's region of the arena, and dangles at a reset to a mark taken before the call\"}")
                    } else {
                        try text(out, ": nothing it returns holds a pointer\"}")
                    }
                } else {
                    if parameter.ty.is_const {
                        try text(out, "{\"record\":\"fact\",\"kind\":\"borrow\",\"provenance\":\"declared-and-checked\",\"value\":\"reads ")
                        try text(out, parameter.name)
                        try text(out, ": a const pointer; the argument is not written and the caller's views of it stand\"}")
                    } else {
                        if returns_pointer {
                            try text(out, "{\"record\":\"fact\",\"kind\":\"borrow\",\"provenance\":\"declared-and-checked\",\"value\":\"borrows ")
                            try text(out, parameter.name)
                            try text(out, ": what it returns that can hold a pointer is a view of the argument, dangling when the argument is next mutated\"}")
                        } else {
                            try text(out, "{\"record\":\"fact\",\"kind\":\"mutation\",\"provenance\":\"declared-and-checked\",\"value\":\"mutates ")
                            try text(out, parameter.name)
                            try text(out, ": the caller's views of the argument dangle after this call (E-SAFETY-0014 at their next use)\"}")
                        }
                    }
                }
                try flush(out)
                page.written += 1usize
            } else {
                if page.total > page.cursor { page.omitted += 1usize }
            }
        }
        contract_at += 1usize
    }
    if returns_err {
        page.total += 1usize
        if page.total > page.cursor && page_open(page, out) {
            if function.return_count > 1usize {
                try text(out, "{\"record\":\"fact\",\"kind\":\"errors\",\"provenance\":\"declared-and-checked\",\"value\":\"partial: returns err beside its other results, which stand only when the err is ok; the caller tests it before using them\"}")
            } else {
                try text(out, "{\"record\":\"fact\",\"kind\":\"errors\",\"provenance\":\"declared-and-checked\",\"value\":\"fallible: returns err; the caller tests it or propagates it with try\"}")
            }
            try flush(out)
            page.written += 1usize
        } else {
            if page.total > page.cursor { page.omitted += 1usize }
        }
    }
    // A thread started in the body (D365): what the call is given by address is
    // that thread's until the join.
    var starts_thread = false
    var thread_scan = 0usize
    while thread_scan < c.explain_count {
        let e = c.explains[thread_scan]
        if e.kind == 4u8 && !e.found && e.module_index == function.module_index && e.offset >= function.source_start && e.offset < function.source_end {
            if e.function_index >= c.function_count && e.template_index < g.count && graph.same(g.modules[e.template_index].name, "e.os") && check.same(e.protocol, "thread_create") { starts_thread = true }
            if e.function_index < c.function_count {
                let callee = c.functions[e.function_index]
                if callee.return_count != 0usize && callee.first_return < c.return_type_count {
                    let handle = c.return_types[callee.first_return]
                    if check.seeded_handle(c, handle) && check.same(handle.name, "Thread") { starts_thread = true }
                }
            }
        }
        thread_scan += 1usize
    }
    if starts_thread {
        page.total += 1usize
        if page.total > page.cursor && page_open(page, out) {
            try text(out, "{\"record\":\"fact\",\"kind\":\"threads\",\"provenance\":\"compiler-proved\",\"value\":\"starts a thread: what the start is given by address is that thread's until the join (E-SAFETY-0016 at any other use); the handle is joined or detached on every exit\"}")
            try flush(out)
            page.written += 1usize
        } else {
            if page.total > page.cursor { page.omitted += 1usize }
        }
    }
    // What the checker established for the body: the resource and region rules
    // ran over it, or did not (an `@unsafe` function).
    page.total += 1usize
    if page.total > page.cursor && page_open(page, out) {
        if manifest_is_unsafe(g.modules[function.module_index].text, function.source_start) {
            try text(out, "{\"record\":\"fact\",\"kind\":\"boundary\",\"provenance\":\"declared-and-checked\",\"value\":\"@unsafe: the resource and region rules are not applied inside this function\"}")
        } else {
            try text(out, "{\"record\":\"fact\",\"kind\":\"resources\",\"provenance\":\"compiler-proved\",\"value\":\"every resource this function owns is consumed on every exit; no view outlives its region or its container's change\"}")
        }
        try flush(out)
        page.written += 1usize
    } else {
        if page.total > page.cursor { page.omitted += 1usize }
    }
    ret unchecked_boundary(out, page, checks)
}

// `--unchecked` is one whole-image unsafe boundary (D555, H27), independent of
// the declaration a context query names. It is a fact of every subject so a
// consumer cannot retain the subject and lose the policy that made its values
// trusted. Like every other fact it participates in record and byte pagination.
fn unchecked_boundary(out: *Out, page: *Page, checks: str) -> err {
    if !graph.same(checks, "off") { ret ok }
    page.total += 1usize
    if page.total > page.cursor && page_open(page, out) {
        try text(out, "{\"record\":\"fact\",\"kind\":\"boundary\",\"provenance\":\"declared-and-checked\",\"value\":\"--unchecked: runtime safety checks are omitted from the whole image; values produced by it cross a trusted boundary\"}")
        try flush(out)
        page.written += 1usize
    } else {
        if page.total > page.cursor { page.omitted += 1usize }
    }
    ret ok
}

// The program's snapshot identity (D407, H15/H18): every module's source hash folded
// in graph order, as sixteen hex digits. An edit to any module of the program changes
// it, so a cursor, a plan or a fact that carries it is known stale when it differs --
// where `source_sha256` names one module's text, this names the program the answer
// was computed against.
fn program_snapshot(out: *Out, g: *graph.Graph) -> err {
    var folded = 2870177450012600261usize
    var module_at = 0usize
    while module_at < g.count {
        let (module_hash, hash_error) = artifact_hash.xxhash64(g.modules[module_at].text)
        if hash_error != ok { ret hash_error }
        folded = artifact_hash.round(folded, module_hash)
        module_at += 1usize
    }
    folded = artifact_hash.round(folded, g.count)
    try byte(out, 34u8)
    var shift = 64usize
    while shift > 0usize {
        shift = shift - 4usize
        try byte(out, hex_digit((folded >> shift) & 15usize))
    }
    ret byte(out, 34u8)
}

// The declared aggregate `module.Name` names (D419), not an instance of a generic.
fn context_aggregate(c: *check.Checker, g: *graph.Graph, module_name: str, name: str) -> (usize, bool) {
    var at = 0usize
    while at < c.aggregate_count {
        let aggregate = c.aggregates[at]
        if !aggregate.instance && aggregate.module_index < g.count && graph.same(g.modules[aggregate.module_index].name, module_name) && graph.same(aggregate.name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn context_module(g: *graph.Graph, module_name: str) -> (usize, bool) {
    var at = 0usize
    while at < g.count {
        if graph.same(g.modules[at].name, module_name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// The context of a constant or a module-scope variable (D437, H08): the subject
// with `kind` `const` or `global`, then the `signature` (the declaration's head),
// the `value` -- a constant's, as the interpreter settled it, `compiler-proved`; a
// global's initialiser or its zero, `declared-and-checked` -- and, for a global,
// `threads`: every thread of the program shares it and no rule tracks it.
fn value_context_json(a: *mem.Arena, out: *Out, c: *check.Checker, g: *graph.Graph, subject: str, is_constant: bool, index: usize, budget: usize, byte_budget: usize, cursor: usize, target_name: str, checks: str) -> err {
    var module_index = 0usize
    var name = ""
    var ty: check.Type = zero
    var token: lex.Token = zero
    if is_constant {
        let constant = c.constants[index]
        module_index = constant.module_index
        name = constant.name
        ty = constant.ty
        token = constant.token
    } else {
        let global = c.globals[index]
        module_index = global.module_index
        name = global.name
        ty = global.ty
        token = global.token
    }
    let module = g.modules[module_index]
    let (root, relative) = source_identity_of(g, module.path)
    let (path, path_error) = manifest_slashes(a, relative)
    if path_error != ok { ret path_error }
    let (digest, digest_error) = manifest_sha256(a, module.text)
    if digest_error != ok { ret digest_error }
    out.lines = module.lines
    try text(out, "{\"record\":\"subject\",\"subject\":")
    try quoted(out, subject)
    if is_constant { try text(out, ",\"kind\":\"const\",\"source\":") } else { try text(out, ",\"kind\":\"global\",\"source\":") }
    try manifest_identity(out, root, relative)
    try text(out, ",\"source_sha256\":")
    try quoted(out, digest)
    try text(out, ",\"snapshot\":")
    try program_snapshot(out, g)
    try text(out, ",\"target\":")
    try quoted(out, target_name)
    try text(out, ",\"checks\":")
    try quoted(out, checks)
    try text(out, ",\"grammar_revision\":3,\"span\":")
    try point_span(out, root, path, module.text, token)
    try byte(out, 125u8)
    try flush(out)
    var page: Page = zero
    page.cursor = cursor
    page.budget = budget
    page.byte_budget = byte_budget
    // The declaration.
    page.total += 1usize
    if page.total > page.cursor && page_open(&page, out) {
        if is_constant { try text(out, "{\"record\":\"fact\",\"kind\":\"signature\",\"provenance\":\"declared-and-checked\",\"value\":\"const ") } else { try text(out, "{\"record\":\"fact\",\"kind\":\"signature\",\"provenance\":\"declared-and-checked\",\"value\":\"var ") }
        try text(out, name)
        try text(out, ": ")
        try type_text(out, c, g, ty, 0usize)
        try text(out, "\"}")
        try flush(out)
        page.written += 1usize
    } else {
        if page.total > page.cursor { page.omitted += 1usize }
    }
    // The value.
    page.total += 1usize
    if page.total > page.cursor && page_open(&page, out) {
        if is_constant {
            let constant = c.constants[index]
            if constant.state == 2u8 {
                try text(out, "{\"record\":\"fact\",\"kind\":\"value\",\"provenance\":\"compiler-proved\",\"value\":\"")
                if constant.value.negative { try byte(out, 45u8) }
                try decimal(out, constant.value.magnitude)
                try text(out, "\"}")
            } else {
                try text(out, "{\"record\":\"fact\",\"kind\":\"value\",\"provenance\":\"unknown\",\"value\":\"not an integer the interpreter settled\"}")
            }
        } else {
            if c.globals[index].has_expression {
                try text(out, "{\"record\":\"fact\",\"kind\":\"value\",\"provenance\":\"declared-and-checked\",\"value\":\"initialised by its expression before main runs\"}")
            } else {
                try text(out, "{\"record\":\"fact\",\"kind\":\"value\",\"provenance\":\"declared-and-checked\",\"value\":\"zero-initialised\"}")
            }
        }
        try flush(out)
        page.written += 1usize
    } else {
        if page.total > page.cursor { page.omitted += 1usize }
    }
    // A global is every thread's.
    if !is_constant {
        page.total += 1usize
        if page.total > page.cursor && page_open(&page, out) {
            try text(out, "{\"record\":\"fact\",\"kind\":\"threads\",\"provenance\":\"declared-and-checked\",\"value\":\"shared by every thread of the program: no rule tracks it, so an atomic or a lock is the program's to hold\"}")
            try flush(out)
            page.written += 1usize
        } else {
            if page.total > page.cursor { page.omitted += 1usize }
        }
    }
    try unchecked_boundary(out, &page, checks)
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"records\":")
    try decimal(out, page.written)
    try text(out, ",\"omitted\":")
    try decimal(out, page.omitted)
    try text(out, ",\"complete\":")
    if page.omitted == 0usize { try text(out, "true") } else { try text(out, "false") }
    try text(out, ",\"cursor\":")
    try decimal(out, page.cursor + page.written)
    try text(out, ",\"bytes\":")
    try decimal(out, out.flushed)
    try text(out, "}}")
    ret flush(out)
}

// The context of a type (D419, H08): the subject, then the facts in a fixed order --
// the declaration as a signature, one `field` per field or member with its type
// (a member's value for an enum), the `layout` (size and alignment on the target),
// then what the rules make of a value: `resource` when the type is a resource with
// its cleanup, `borrow` when a value holds a pointer and so views something, else
// `copy` -- every one `declared-and-checked` but the layout, which is compiler-proved.
fn type_context_json(a: *mem.Arena, out: *Out, c: *check.Checker, g: *graph.Graph, subject: str, aggregate_index: usize, budget: usize, byte_budget: usize, cursor: usize, target_name: str, checks: str) -> err {
    let aggregate = c.aggregates[aggregate_index]
    let module = g.modules[aggregate.module_index]
    let (root, relative) = source_identity_of(g, module.path)
    let (path, path_error) = manifest_slashes(a, relative)
    if path_error != ok { ret path_error }
    let (digest, digest_error) = manifest_sha256(a, module.text)
    if digest_error != ok { ret digest_error }
    out.lines = module.lines
    try text(out, "{\"record\":\"subject\",\"subject\":")
    try quoted(out, subject)
    try text(out, ",\"kind\":\"type\",\"source\":")
    try manifest_identity(out, root, relative)
    try text(out, ",\"source_sha256\":")
    try quoted(out, digest)
    try text(out, ",\"snapshot\":")
    try program_snapshot(out, g)
    try text(out, ",\"target\":")
    try quoted(out, target_name)
    try text(out, ",\"checks\":")
    try quoted(out, checks)
    try text(out, ",\"grammar_revision\":3,\"span\":")
    try point_span(out, root, path, module.text, aggregate.token)
    try byte(out, 125u8)
    try flush(out)
    var page: Page = zero
    page.cursor = cursor
    page.budget = budget
    page.byte_budget = byte_budget
    var ty = check.make_type(.Named, aggregate.name, aggregate.module_index)
    ty.has_element = true
    ty.element = aggregate_index
    // The declaration.
    page.total += 1usize
    if page.total > page.cursor && page_open(&page, out) {
        try text(out, "{\"record\":\"fact\",\"kind\":\"signature\",\"provenance\":\"declared-and-checked\",\"value\":\"type ")
        try text(out, aggregate.name)
        if aggregate.kind == .Struct { try text(out, " = struct") }
        if aggregate.kind == .Union { try text(out, " = union") }
        if aggregate.kind == .TaggedUnion { try text(out, " = union enum") }
        if aggregate.kind == .Enum {
            try text(out, " = enum ")
            try type_text(out, c, g, aggregate.backing_type, 0usize)
        }
        if aggregate.resource {
            try text(out, " (resource, cleanup ")
            try text(out, aggregate.cleanup)
            try byte(out, 41u8)
        }
        try text(out, "\"}")
        try flush(out)
        page.written += 1usize
    } else {
        if page.total > page.cursor { page.omitted += 1usize }
    }
    // The fields, or the members.
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field_index = aggregate.first_field + field_at
        page.total += 1usize
        if page.total > page.cursor && page_open(&page, out) {
            let field = c.aggregate_fields[field_index]
            try text(out, "{\"record\":\"fact\",\"kind\":\"field\",\"provenance\":\"declared-and-checked\",\"value\":\"")
            try text(out, field.name)
            if aggregate.kind == .Enum {
                if field.has_enum_value {
                    try text(out, " = ")
                    if field.enum_negative { try byte(out, 45u8) }
                    try decimal(out, field.enum_value)
                }
            } else {
                try text(out, ": ")
                try type_text(out, c, g, field.ty, 0usize)
            }
            try text(out, "\"}")
            try flush(out)
            page.written += 1usize
        } else {
            if page.total > page.cursor { page.omitted += 1usize }
        }
        field_at += 1usize
    }
    // The layout on the target.
    page.total += 1usize
    if page.total > page.cursor && page_open(&page, out) {
        let (info, info_error) = layout.type_info(c, ty)
        if info_error == ok {
            try text(out, "{\"record\":\"fact\",\"kind\":\"layout\",\"provenance\":\"compiler-proved\",\"value\":\"")
            try decimal(out, info.size)
            try text(out, " bytes, aligned to ")
            try decimal(out, info.alignment)
            try text(out, "\"}")
        } else {
            try text(out, "{\"record\":\"fact\",\"kind\":\"layout\",\"provenance\":\"unknown\",\"value\":\"no layout: the type is generic or its size is not settled\"}")
        }
        try flush(out)
        page.written += 1usize
    } else {
        if page.total > page.cursor { page.omitted += 1usize }
    }
    // What the rules make of a value of the type.
    page.total += 1usize
    if page.total > page.cursor && page_open(&page, out) {
        if aggregate.resource {
            try text(out, "{\"record\":\"fact\",\"kind\":\"resource\",\"provenance\":\"declared-and-checked\",\"value\":\"a resource: a value is owed its cleanup `")
            try text(out, aggregate.cleanup)
            try text(out, "` on every exit and moves at most once; its fields are read in its module alone\"}")
        } else {
            if check.holds_pointer(c, ty, 0usize) {
                try text(out, "{\"record\":\"fact\",\"kind\":\"borrow\",\"provenance\":\"declared-and-checked\",\"value\":\"holds a pointer: a value views what it points at, and a store of `&x` into it aliases `x` through that field\"}")
            } else {
                try text(out, "{\"record\":\"fact\",\"kind\":\"copy\",\"provenance\":\"declared-and-checked\",\"value\":\"plain data: copied by value, no cleanup owed, no pointer held\"}")
            }
        }
        try flush(out)
        page.written += 1usize
    } else {
        if page.total > page.cursor { page.omitted += 1usize }
    }
    try unchecked_boundary(out, &page, checks)
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"records\":")
    try decimal(out, page.written)
    try text(out, ",\"omitted\":")
    try decimal(out, page.omitted)
    try text(out, ",\"complete\":")
    if page.omitted == 0usize { try text(out, "true") } else { try text(out, "false") }
    try text(out, ",\"cursor\":")
    try decimal(out, page.cursor + page.written)
    try text(out, ",\"bytes\":")
    try decimal(out, out.flushed)
    try text(out, "}}")
    ret flush(out)
}

// The subject record of a context answer (D361): the snapshot's identity and the
// function's declaration point.
fn subject_record(out: *Out, g: *graph.Graph, subject: str, root: str, relative: str, path: str, source: str, digest: str, target_name: str, checks: str, standing: str, declared_at: usize) -> err {
    try text(out, "{\"record\":\"subject\",\"subject\":")
    try quoted(out, subject)
    try text(out, ",\"kind\":\"fn\",\"source\":")
    try manifest_identity(out, root, relative)
    try text(out, ",\"source_sha256\":")
    try quoted(out, digest)
    try text(out, ",\"snapshot\":")
    try program_snapshot(out, g)
    try text(out, ",\"target\":")
    try quoted(out, target_name)
    try text(out, ",\"checks\":")
    try quoted(out, checks)
    if standing.len != 0usize {
        try text(out, ",\"standing\":")
        try quoted(out, standing)
    }
    try text(out, ",\"grammar_revision\":3,\"span\":")
    var declaration: lex.Token = zero
    declaration.start = declared_at
    declaration.end = declared_at
    try point_span(out, root, path, source, declaration)
    try byte(out, 125u8)
    ret flush(out)
}

// The `memory` line of a batch (D410, D558, H16): live versus reserved arena
// bytes, the checked snapshot below the batch input, the session baseline after
// that input, and the largest completed request before its storage was reclaimed.
fn batch_memory(a: *mem.Arena, snapshot_used: usize, session_used: usize, request_peak: usize, queries_completed: usize) -> err {
    let stats = mem.stats(a)
    var storage: [1024]u8 = zero
    var out: Out = zero
    out.bytes = storage[..]
    try header(&out, "context")
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"arena_used\":")
    try decimal(&out, stats.used)
    try text(&out, ",\"arena_capacity\":")
    try decimal(&out, stats.capacity)
    try text(&out, ",\"snapshot_used\":")
    try decimal(&out, snapshot_used)
    try text(&out, ",\"session_used\":")
    try decimal(&out, session_used)
    try text(&out, ",\"request_peak\":")
    try decimal(&out, request_peak)
    try text(&out, ",\"queries_completed\":")
    try decimal(&out, queries_completed)
    try text(&out, "}}")
    ret flush(&out)
}

// `plan-replace-expression-file PATH ROOT ARCH OS --json --span START:END --with EXPR`
// (D414, H29): the last of the four plan shapes. The bytes START..END of the operand
// must be exactly one expression node of its tree -- found at the tokens, the node
// whose first token starts at START and whose last token ends at END, of an
// expression kind -- else the plan is refused naming what the span holds; the plan
// is one `edit` (`replace-expression`, site `use`) with the file's hash as its
// precondition and the postcondition that re-checking passes with the expression's
// type unchanged, which the checker at apply time decides.
// An edit inside regeneration-owned text (D512, H19): the operand's map says the
// range is the generator's, so the edit record names the owner and where in the
// generator's input its bytes begin; `apply-plan` refuses such an edit.
fn owned_note(out: *Out, g: *graph.Graph, module_index: usize, offset: usize) -> err {
    if module_index >= g.count { ret ok }
    let module = g.modules[module_index]
    var at = 0usize
    while at < module.owned_count {
        if offset >= module.owned_starts[at] && offset < module.owned_ends[at] {
            try text(out, ",\"owner\":\"generator\",\"original\":{\"source\":{\"root\":")
            try quoted(out, module.owned_original_roots[at])
            try text(out, ",\"path\":")
            try quoted(out, module.owned_original_paths[at])
            try text(out, "},\"byte_start\":")
            try decimal(out, module.owned_original_starts[at] + (offset - module.owned_starts[at]))
            ret byte(out, 125u8)
        }
        at += 1usize
    }
    ret ok
}

fn plan_replace_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, span_text: str, replacement: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "plan-replace-expression")
    // The operand is module 0 (D289): the span is its bytes.
    var colon = span_text.len
    var scan = 0usize
    while scan < span_text.len {
        if span_text[scan] == 58u8 { colon = scan }
        scan += 1usize
    }
    var span_ok = colon != span_text.len && colon != 0usize && colon + 1usize != span_text.len
    var byte_start = 0usize
    var byte_end = 0usize
    if span_ok {
        let (start_value, start_ok) = plan_decimal(span_text[0usize..colon])
        let (end_value, end_ok) = plan_decimal(span_text[colon + 1usize..span_text.len])
        span_ok = start_ok && end_ok
        byte_start = start_value
        byte_end = end_value
    }
    let module = g.modules[0usize]
    if !span_ok || byte_start >= byte_end || byte_end > module.text.len { ret plan_refused(&out, "the span is not START:END within the operand") }
    var operand_tree = module.tree
    let (node_index, has_node) = expression_at(module.tokens, &operand_tree, byte_start, byte_end)
    if !has_node { ret plan_refused(&out, "the span is not one expression of the operand") }
    let (root, relative) = source_identity_of(g, module.path)
    let (path, path_error) = manifest_slashes(a, relative)
    if path_error != ok { ret path_error }
    let (digest, digest_error) = manifest_sha256(a, module.text)
    if digest_error != ok { ret digest_error }
    try text(&out, "{\"record\":\"precondition\",\"source\":{\"root\":")
    try quoted(&out, root)
    try text(&out, ",\"path\":")
    try quoted(&out, path)
    try text(&out, "},\"sha256\":")
    try quoted(&out, digest)
    try byte(&out, 125u8)
    try flush(&out)
    out.lines = module.lines
    var first: lex.Token = zero
    first.start = byte_start
    first.end = byte_start
    var last: lex.Token = zero
    last.start = byte_end
    last.end = byte_end
    try text(&out, "{\"record\":\"edit\",\"op\":\"replace-expression\",\"symbol\":")
    try quoted(&out, module.text[byte_start..byte_end])
    try text(&out, ",\"site\":\"use\",\"span\":")
    try token_span(&out, root, path, module.text, first, last)
    try text(&out, ",\"replacement\":")
    try quoted(&out, replacement)
    try owned_note(&out, g, 0usize, byte_start)
    try byte(&out, 125u8)
    try flush(&out)
    try text(&out, "{\"record\":\"postcondition\",\"check\":\"check-file passes; the expression at the span has the type the replaced one had\"}")
    try flush(&out)
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"edits\":1,\"files\":1,\"complete\":true,\"snapshot\":")
    try program_snapshot(&out, g)
    try text(&out, "}}")
    ret flush(&out)
}

// A decimal of a plan's arguments: digits alone, at most eighteen.
fn plan_decimal(text_bytes: str) -> (usize, bool) {
    if text_bytes.len == 0usize || text_bytes.len > 18usize { ret (0usize, false) }
    var value = 0usize
    var at = 0usize
    while at < text_bytes.len {
        if text_bytes[at] < 48u8 || text_bytes[at] > 57u8 { ret (0usize, false) }
        value = value * 10usize + usize(text_bytes[at] - 48u8)
        at += 1usize
    }
    ret (value, true)
}

fn plan_refused(out: *Out, message: str) -> err {
    try text(out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":")
    try quoted(out, message)
    try text(out, ",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}")
    try flush(out)
    try text(out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"edits\":0,\"files\":0,\"complete\":true}}")
    try flush(out)
    ret Refused
}

// The expression node whose tokens span exactly START..END (D414): the outermost
// such node, since a name inside a call and the call itself can begin at one byte.
fn expression_at(tokens: []const lex.Token, tree: *parse.Tree, byte_start: usize, byte_end: usize) -> (usize, bool) {
    var node_index = 0usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        let kind = node.kind
        let expression = kind == .UnaryExpr || kind == .BinaryExpr || kind == .FieldExpr || kind == .BracketPostfix || kind == .CallExpr || kind == .NameExpr || kind == .MemberExpr || kind == .GroupExpr || kind == .AggregateLiteral || kind == .LiteralExpr
        if expression && usize(node.token_start) < tokens.len && usize(node.token_end) <= tokens.len && usize(node.token_end) > usize(node.token_start) {
            if tokens[usize(node.token_start)].start == byte_start && tokens[usize(node.token_end) - 1usize].end == byte_end { ret (node_index, true) }
        }
        node_index += 1usize
    }
    ret (0usize, false)
}

// The checked call graph used by test impact and API verification. Instances point
// at their templates, exactly as the public queries name them.
fn function_edges(a: *mem.Arena, c: *check.Checker, g: *graph.Graph) -> ([]usize, []usize, usize, err) {
    let (edge_from, from_error) = mem.alloc[usize](a, c.explain_count + 1usize)
    let (edge_to, to_error) = mem.alloc[usize](a, c.explain_count + 1usize)
    if from_error != ok { ret (edge_from, edge_to, 0usize, from_error) }
    if to_error != ok { ret (edge_from, edge_to, 0usize, to_error) }
    var edge_count = 0usize
    var scan = 0usize
    while scan < c.explain_count {
        let e = c.explains[scan]
        var callee = c.function_count
        if e.kind == 4u8 && !e.found { callee = e.function_index }
        if e.kind == 1u8 && e.found { callee = e.function_index }
        if e.kind == 2u8 { callee = e.template_index }
        if e.kind == 5u8 { callee = e.function_index }
        if callee < c.function_count && e.module_index < g.count {
            if c.function_generics[callee].instance && c.function_generics[callee].template_index < c.function_count { callee = c.function_generics[callee].template_index }
            let caller = enclosing_function(c, e.module_index, e.offset)
            if caller < c.function_count {
                edge_from[edge_count] = caller
                edge_to[edge_count] = callee
                edge_count += 1usize
            }
        }
        scan += 1usize
    }
    ret (edge_from, edge_to, edge_count, ok)
}

fn reachable_functions(c: *check.Checker, edge_from: []const usize, edge_to: []const usize, edge_count: usize, start: usize, reached: []bool, stack: []usize) {
    var clear = 0usize
    while clear < c.function_count {
        reached[clear] = false
        clear += 1usize
    }
    if start >= c.function_count { ret }
    var depth = 0usize
    stack[depth] = start
    depth += 1usize
    reached[start] = true
    while depth > 0usize {
        depth = depth - 1usize
        let here = stack[depth]
        var edge_at = 0usize
        while edge_at < edge_count {
            if edge_from[edge_at] == here {
                let next = edge_to[edge_at]
                if !reached[next] {
                    reached[next] = true
                    stack[depth] = next
                    depth += 1usize
                }
            }
            edge_at += 1usize
        }
    }
}

// The first executable test, in declaration order, that reaches each non-test API.
// This is coverage evidence; test functions do not verify themselves.
fn verification_tests(a: *mem.Arena, c: *check.Checker, g: *graph.Graph) -> ([]usize, err) {
    let (verified_by, verified_error) = mem.alloc[usize](a, c.function_count + 1usize)
    if verified_error != ok { ret (verified_by, verified_error) }
    var at = 0usize
    while at < c.function_count {
        verified_by[at] = c.function_count
        at += 1usize
    }
    let (edge_from, edge_to, edge_count, edge_error) = function_edges(a, c, g)
    if edge_error != ok { ret (verified_by, edge_error) }
    let (reached, reached_error) = mem.alloc[bool](a, c.function_count + 1usize)
    if reached_error != ok { ret (verified_by, reached_error) }
    let (stack, stack_error) = mem.alloc[usize](a, c.function_count + 1usize)
    if stack_error != ok { ret (verified_by, stack_error) }
    var test_at = 0usize
    while test_at < c.signature_function_count {
        let test_function = c.functions[test_at]
        if test_function.module_index < g.count && manifest_has_attribute(g.modules[test_function.module_index].text, test_function.source_start, "test") {
            reachable_functions(c, edge_from, edge_to, edge_count, test_at, reached, stack)
            var candidate_at = 0usize
            while candidate_at < c.signature_function_count {
                let target_function = c.functions[candidate_at]
                let target_is_test = target_function.module_index < g.count && manifest_has_attribute(g.modules[target_function.module_index].text, target_function.source_start, "test")
                if reached[candidate_at] && !target_is_test && verified_by[candidate_at] == c.function_count { verified_by[candidate_at] = test_at }
                candidate_at += 1usize
            }
        }
        test_at += 1usize
    }
    ret (verified_by, ok)
}

// `test-impact-file PATH ROOT ARCH OS --json --changed m1,m2,...` (D423, H10): which
// `@test` functions of the program an edit to the named modules can reach. The
// program is checked with the explain table open; the calls, dispatches,
// instantiations and function values it recorded are the edges, an instance's the
// template's; from each test, everything reachable over them is walked, and a test
// that lies in a changed module or reaches a function in one is `affected`. A
// module named that the program has not is a diagnostic and exit 2. One `impact`
// record per test in module then declaration order, the result counting both.
fn impact_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, changed_text: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, c.signature_function_count * 256usize + 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "test-impact")
    let (changed, changed_error) = mem.alloc[bool](a, g.count + 1usize)
    if changed_error != ok { ret changed_error }
    var module_at = 0usize
    while module_at < g.count {
        changed[module_at] = false
        module_at += 1usize
    }
    var name_start = 0usize
    var at = 0usize
    while at <= changed_text.len {
        if at == changed_text.len || changed_text[at] == 44u8 {
            let name = changed_text[name_start..at]
            var found = false
            module_at = 0usize
            while module_at < g.count {
                if graph.same(g.modules[module_at].name, name) {
                    changed[module_at] = true
                    found = true
                }
                module_at += 1usize
            }
            if !found {
                var message_storage: [512]u8 = zero
                var message_at = nptest_copy(message_storage[..], 0usize, "the program has no module named ")
                message_at = nptest_copy(message_storage[..], message_at, name)
                try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":")
                try quoted(&out, message_storage[0usize..message_at])
                try text(&out, ",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}")
                try flush(&out)
                try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"tests\":0,\"affected\":0,\"complete\":true}}")
                try flush(&out)
                ret Refused
            }
            name_start = at + 1usize
        }
        at += 1usize
    }
    let (edge_from, edge_to, edge_count, edge_error) = function_edges(a, c, g)
    if edge_error != ok { ret edge_error }
    let (reached, reached_error) = mem.alloc[bool](a, c.function_count + 1usize)
    if reached_error != ok { ret reached_error }
    let (stack, stack_error) = mem.alloc[usize](a, c.function_count + 1usize)
    if stack_error != ok { ret stack_error }
    var tests = 0usize
    var affected_count = 0usize
    var function_at = 0usize
    while function_at < c.signature_function_count {
        let function = c.functions[function_at]
        if function.module_index < g.count && manifest_has_attribute(g.modules[function.module_index].text, function.source_start, "test") {
            reachable_functions(c, edge_from, edge_to, edge_count, function_at, reached, stack)
            var affected = false
            var reached_at = 0usize
            while reached_at < c.function_count && !affected {
                if reached[reached_at] && c.functions[reached_at].module_index < g.count && changed[c.functions[reached_at].module_index] { affected = true }
                reached_at += 1usize
            }
            let module = g.modules[function.module_index]
            let (root, relative) = source_identity_of(g, module.path)
            let (path, path_error) = manifest_slashes(a, relative)
            if path_error != ok { ret path_error }
            out.lines = module.lines
            var declaration: lex.Token = zero
            declaration.start = function.source_start
            declaration.end = function.source_start
            try text(&out, "{\"record\":\"impact\",\"test\":")
            try quoted_function(&out, c, g, function_at)
            try text(&out, ",\"affected\":")
            if affected { try text(&out, "true") } else { try text(&out, "false") }
            try text(&out, ",\"span\":")
            try point_span(&out, root, path, module.text, declaration)
            try byte(&out, 125u8)
            try flush(&out)
            tests += 1usize
            if affected { affected_count += 1usize }
        }
        function_at += 1usize
    }
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"tests\":")
    try decimal(&out, tests)
    try text(&out, ",\"affected\":")
    try decimal(&out, affected_count)
    try text(&out, ",\"complete\":")
    if !c.explain_overflow { try text(&out, "true") } else { try text(&out, "false") }
    try text(&out, "}}")
    ret flush(&out)
}

// A batch line no query reads (D409): a stream of its own, refused.
fn batch_line_refused(a: *mem.Arena, line: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, line.len * 2usize + 1024usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "context")
    var message_storage: [1024]u8 = zero
    var message_at = nptest_copy(message_storage[..], 0usize, "the batch line is not a query: ")
    message_at = nptest_copy(message_storage[..], message_at, line)
    try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":")
    try quoted(&out, message_storage[0usize..message_at])
    try text(&out, ",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}")
    try flush(&out)
    try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"records\":0,\"omitted\":0,\"complete\":true}}")
    ret flush(&out)
}

// `context-file PATH ROOT ARCH OS --json --module module.name [--budget N] [--cursor N]`
// (D397, H11): the catalogue -- every declared, non-generic function of one module
// in declaration order, each a `subject` record and its contract facts, under one
// record budget that counts subjects and facts alike. A page may end inside a
// function's facts; the next page continues them, and the last subject written
// before the cut is theirs. The body's decisions are not listed here: `--symbol`
// answers those for one function.
fn catalog_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, module_name: str, budget: usize, byte_budget: usize, cursor: usize, target_name: str, checks: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, c.signature_function_count * 1024usize + 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "context")
    var module_index = g.count
    var scan = 0usize
    while scan < g.count {
        if graph.same(g.modules[scan].name, module_name) {
            module_index = scan
            break
        }
        scan += 1usize
    }
    if module_index == g.count {
        try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":\"the subject names no module of the program\",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}")
        try flush(&out)
        try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"subject\":")
        try quoted(&out, module_name)
        try text(&out, ",\"standing\":\"unavailable\",\"records\":0,\"omitted\":0,\"complete\":true}}")
        try flush(&out)
        // The process status agrees with the record (D406): a refused query is
        // `Refused`, which one query's driver turns into exit 2 and a batch moves past (D409).
        ret Refused
    }
    let module = g.modules[module_index]
    let (root, relative) = source_identity_of(g, module.path)
    let (path, path_error) = manifest_slashes(a, relative)
    if path_error != ok { ret path_error }
    let (digest, digest_error) = manifest_sha256(a, module.text)
    if digest_error != ok { ret digest_error }
    let (verified_by, verified_error) = verification_tests(a, c, g)
    if verified_error != ok { ret verified_error }
    out.lines = module.lines
    var page: Page = zero
    page.cursor = cursor
    page.budget = budget
    page.byte_budget = byte_budget
    let (subject_storage, subject_error) = mem.alloc[u8](a, 4096usize)
    if subject_error != ok { ret subject_error }
    var candidate = 0usize
    while candidate < c.signature_function_count {
        let function = c.functions[candidate]
        if function.module_index == module_index && !function.generic && function.source_end > function.source_start {
            page.total += 1usize
            if page.total > page.cursor && page_open(&page, &out) {
                var subject_at = nptest_copy(subject_storage, 0usize, module_name)
                if subject_at < subject_storage.len { subject_storage[subject_at] = 46u8 }
                subject_at = nptest_copy(subject_storage, subject_at + 1usize, function.name)
                var standing = "supported-on-target"
                if verified_by[candidate] < c.function_count { standing = "verified" }
                try subject_record(&out, g, subject_storage[0usize..subject_at], root, relative, path, module.text, digest, target_name, checks, standing, function.source_start)
                page.written += 1usize
            } else {
                if page.total > page.cursor { page.omitted += 1usize }
            }
            if verified_by[candidate] < c.function_count {
                page.total += 1usize
                if page.total > page.cursor && page_open(&page, &out) {
                    try text(&out, "{\"record\":\"fact\",\"kind\":\"verification\",\"provenance\":\"compiler-proved\",\"value\":")
                    try quoted_function(&out, c, g, verified_by[candidate])
                    try byte(&out, 125u8)
                    try flush(&out)
                    page.written += 1usize
                } else {
                    if page.total > page.cursor { page.omitted += 1usize }
                }
            }
            try contract_facts(&out, c, g, candidate, &page, checks)
        }
        candidate += 1usize
    }
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"records\":")
    try decimal(&out, page.written)
    try text(&out, ",\"omitted\":")
    try decimal(&out, page.omitted)
    try text(&out, ",\"complete\":")
    if page.omitted == 0usize { try text(&out, "true") } else { try text(&out, "false") }
    try text(&out, ",\"cursor\":")
    try decimal(&out, page.cursor + page.written)
    try text(&out, ",\"bytes\":")
    try decimal(&out, out.flushed)
    try text(&out, "}}")
    ret flush(&out)
}

fn context_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, subject: str, budget: usize, byte_budget: usize, cursor: usize, target_name: str, checks: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, c.explain_count * 512usize + 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "context")
    // The subject: `module.name`, a declared function of the program.
    var dot = subject.len
    var at = 0usize
    while at < subject.len {
        if subject[at] == 46u8 { dot = at }
        at += 1usize
    }
    var function_index = c.function_count
    if dot != subject.len {
        let module_name = subject[0usize..dot]
        let name = subject[dot + 1usize..subject.len]
        var candidate = 0usize
        while candidate < c.signature_function_count {
            let function = c.functions[candidate]
            if function.module_index < g.count && graph.same(g.modules[function.module_index].name, module_name) && graph.same(function.name, name) && !function.generic {
                function_index = candidate
                break
            }
            candidate += 1usize
        }
        if function_index == c.function_count {
            candidate = 0usize
            while candidate < c.signature_function_count {
                let function = c.functions[candidate]
                if function.module_index < g.count && graph.same(g.modules[function.module_index].name, module_name) && graph.same(function.name, name) {
                    function_index = candidate
                    break
                }
                candidate += 1usize
            }
        }
    }
    if function_index == c.function_count {
        // A type (D419, H08): the subject names an aggregate of the program.
        if dot != subject.len {
            let (aggregate_index, has_aggregate) = context_aggregate(c, g, subject[0usize..dot], subject[dot + 1usize..subject.len])
            if has_aggregate { ret type_context_json(a, &out, c, g, subject, aggregate_index, budget, byte_budget, cursor, target_name, checks) }
            // A constant or a module-scope variable (D437, H08).
            let (subject_module, has_module) = context_module(g, subject[0usize..dot])
            if has_module {
                let (constant_index, has_constant) = check.find_constant(c, subject_module, subject[dot + 1usize..subject.len])
                if has_constant { ret value_context_json(a, &out, c, g, subject, true, constant_index, budget, byte_budget, cursor, target_name, checks) }
                let (global_index, has_global) = check.find_global(c, subject_module, subject[dot + 1usize..subject.len])
                if has_global { ret value_context_json(a, &out, c, g, subject, false, global_index, budget, byte_budget, cursor, target_name, checks) }
            }
        }
        try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":\"the subject names no function, type, constant or global of the program\",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}")
        try flush(&out)
        try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"subject\":")
        try quoted(&out, subject)
        try text(&out, ",\"standing\":\"unavailable\",\"records\":0,\"omitted\":0,\"complete\":true}}")
        try flush(&out)
        // The process status agrees with the record (D406): a refused query is
        // `Refused`, which one query's driver turns into exit 2 and a batch moves past (D409).
        ret Refused
    }
    let function = c.functions[function_index]
    let module = g.modules[function.module_index]
    let (root, relative) = source_identity_of(g, module.path)
    let (path, path_error) = manifest_slashes(a, relative)
    if path_error != ok { ret path_error }
    let (digest, digest_error) = manifest_sha256(a, module.text)
    if digest_error != ok { ret digest_error }
    out.lines = module.lines
    // The subject record: identity of the snapshot and the subject, always written.
    try subject_record(&out, g, subject, root, relative, path, module.text, digest, target_name, checks, "", function.source_start)
    var page: Page = zero
    page.cursor = cursor
    page.budget = budget
    page.byte_budget = byte_budget
    try contract_facts(&out, c, g, function_index, &page, checks)
    try dependency_facts(a, &out, g, function.module_index, &page)
    var written = page.written
    var omitted = page.omitted
    var total = page.total
    // The body's decisions, from the explain records inside the source range, in
    // source order; each a fact with its span.
    var last_offset = 0usize
    var last_kind = 0u8
    var last_function = 0usize
    var first = true
    while true {
        var best = c.explain_count
        var scan = 0usize
        while scan < c.explain_count {
            let e = c.explains[scan]
            if e.kind != 6u8 && e.kind != 7u8 && e.module_index == function.module_index && e.offset >= function.source_start && e.offset < function.source_end {
                let after = first || e.offset > last_offset || (e.offset == last_offset && (e.kind > last_kind || (e.kind == last_kind && e.function_index > last_function)))
                if after && (best == c.explain_count || e.offset < c.explains[best].offset || (e.offset == c.explains[best].offset && (e.kind < c.explains[best].kind || (e.kind == c.explains[best].kind && e.function_index < c.explains[best].function_index)))) { best = scan }
            }
            scan += 1usize
        }
        if best == c.explain_count { break }
        let e = c.explains[best]
        first = false
        last_offset = e.offset
        last_kind = e.kind
        last_function = e.function_index
        total += 1usize
        if total <= cursor { continue }
        if written >= budget || (byte_budget != 0usize && out.flushed >= byte_budget) {
            omitted += 1usize
            continue
        }
        var here: lex.Token = zero
        here.start = e.offset
        here.end = e.offset
        try text(&out, "{\"record\":\"fact\",\"kind\":")
        if e.kind == 4u8 {
            if e.found {
                try text(&out, "\"call\",\"provenance\":\"unknown\",\"value\":\"a call through a function value; the target is not known here\"")
            } else {
                try text(&out, "\"call\",\"provenance\":\"declared-and-checked\",\"value\":")
                if e.function_index < c.function_count {
                    try quoted_function(&out, c, g, e.function_index)
                } else {
                    try byte(&out, 34u8)
                    if e.template_index < g.count {
                        try text(&out, g.modules[e.template_index].name)
                        try byte(&out, 46u8)
                    }
                    try text(&out, e.protocol)
                    try byte(&out, 34u8)
                }
            }
        }
        if e.kind == 1u8 {
            try text(&out, "\"dispatch\",\"provenance\":\"compiler-proved\",\"value\":\"")
            try text(&out, e.protocol)
            try text(&out, " on ")
            try type_text(&out, c, g, e.receiver, 0usize)
            if e.found {
                try text(&out, " is ")
                if e.function_index < c.function_count {
                    if c.functions[e.function_index].module_index < g.count {
                        try text(&out, g.modules[c.functions[e.function_index].module_index].name)
                        try byte(&out, 46u8)
                    }
                    try text(&out, c.functions[e.function_index].name)
                }
            } else {
                if e.builtin == .None { try text(&out, " has no declaration and no supplied rule") } else { try text(&out, " is the supplied rule") }
            }
            try byte(&out, 34u8)
        }
        if e.kind == 2u8 {
            try text(&out, "\"instance\",\"provenance\":\"compiler-proved\",\"value\":")
            try quoted_function(&out, c, g, e.template_index)
        }
        if e.kind == 5u8 {
            try text(&out, "\"value\",\"provenance\":\"compiler-proved\",\"value\":")
            try quoted_function(&out, c, g, e.function_index)
        }
        // A folded `if` (D463) as a fact of the body (D486): the record was written
        // with no kind before, which was not a record at all.
        if e.kind == 8u8 {
            if e.found { try text(&out, "\"phase\",\"provenance\":\"compiler-proved\",\"value\":\"an if settled at compile time: the true arm is taken\"") } else { try text(&out, "\"phase\",\"provenance\":\"compiler-proved\",\"value\":\"an if settled at compile time: the false arm is taken\"") }
        }
        // A view ended (D501, H02): the local, and what ended it.
        if e.kind == 11u8 {
            try text(&out, "\"borrow\",\"provenance\":\"compiler-proved\",\"value\":\"")
            try text(&out, e.reason_name)
            if e.reason_kind == 1u8 { try text(&out, " views nothing from here: the region it was taken in is reset\"") } else { try text(&out, " views nothing from here: what it views is given to a call by pointer\"") }
        }
        // A view taken (D487, H17): the local and the local it views.
        if e.kind == 10u8 {
            try text(&out, "\"borrow\",\"provenance\":\"compiler-proved\",\"value\":\"")
            try text(&out, e.reason_name)
            try text(&out, " views ")
            try text(&out, e.protocol)
            try text(&out, " from here: a write to or a reset of what it views ends the view\"")
        }
        // A resource consumed (D486, H17): where the checker moved it out.
        if e.kind == 9u8 {
            try text(&out, "\"move\",\"provenance\":\"compiler-proved\",\"value\":\"")
            try text(&out, e.reason_name)
            try text(&out, " is consumed here: closed, returned, rebound or handed to an own parameter\"")
        }
        if e.kind == 3u8 {
            try text(&out, "\"discard\",\"provenance\":\"declared-and-checked\",\"value\":\"the err of ")
            if e.function_index < c.function_count {
                if c.functions[e.function_index].module_index < g.count {
                    try text(&out, g.modules[c.functions[e.function_index].module_index].name)
                    try byte(&out, 46u8)
                }
                try text(&out, c.functions[e.function_index].name)
            }
            if e.found { try text(&out, " is dropped under defer\"") } else { try text(&out, " is dropped\"") }
        }
        try text(&out, ",\"span\":")
        try point_span(&out, root, path, module.text, here)
        try byte(&out, 125u8)
        try flush(&out)
        written += 1usize
    }
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"records\":")
    try decimal(&out, written)
    try text(&out, ",\"omitted\":")
    try decimal(&out, omitted)
    try text(&out, ",\"complete\":")
    if omitted == 0usize && !c.explain_overflow { try text(&out, "true") } else { try text(&out, "false") }
    try text(&out, ",\"cursor\":")
    try decimal(&out, cursor + written)
    // The serialized bytes before this record (D400, H18): what the harness held.
    try text(&out, ",\"bytes\":")
    try decimal(&out, out.flushed)
    try text(&out, "}}")
    ret flush(&out)
}

// Whether the declaration at `offset` carries `@unsafe`: the attribute line above it.
fn manifest_is_unsafe(text_bytes: str, offset: usize) -> bool {
    var line_start = offset
    while line_start > 0usize && text_bytes[line_start - 1usize] != 10u8 { line_start = line_start - 1usize }
    // The line before, if any, after its own spaces.
    if line_start == 0usize { ret false }
    var previous_end = line_start - 1usize
    var previous_start = previous_end
    while previous_start > 0usize && text_bytes[previous_start - 1usize] != 10u8 { previous_start = previous_start - 1usize }
    var at = previous_start
    while at < previous_end && (text_bytes[at] == 32u8 || text_bytes[at] == 9u8) { at += 1usize }
    if at >= previous_end || text_bytes[at] != 64u8 { ret false }
    let word_end = manifest_word_end(text_bytes, at + 1usize)
    ret graph.same(text_bytes[at + 1usize..word_end], "unsafe")
}

// `uses-file PATH ROOT ARCH OS --json --symbol module.name` (D362, H17): every use
// of one function across the program the checker resolved -- a call, a protocol
// dispatch that chose it, an instantiation of it, its name taken as a value -- by
// module then offset, each with its span and the function it lies in; then the
// roots that keep it alive without a use here (`main`, a test, an export), and
// whether the answer is complete: a call through a function value anywhere in the
// program is a consumer no name can trace, so the answer says so.
fn uses_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, subject: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, c.explain_count * 512usize + 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "uses")
    // A field (D420, H17): `module.Type.field`, every access and every literal naming it.
    let (field_index, is_field) = uses_field_subject(c, g, subject)
    if is_field { ret sites_uses_json(a, &out, c, g, 6u8, field_index, "field") }
    // An error (D451, H17): `module.Name`, every value naming it.
    let (error_symbol, is_error) = uses_error_subject(c, g, subject)
    if is_error { ret sites_uses_json(a, &out, c, g, 7u8, error_symbol, "error") }
    // A type (D516, H17): `module.Name`, every annotation and literal naming it,
    // from the index of every module, as the type's rename plan finds them.
    let (type_symbol, is_type) = uses_type_subject(c, g, subject)
    if is_type { ret type_uses_json(a, &out, c, g, subject, type_symbol) }
    let (function_index, has_function) = uses_subject(c, g, subject)
    if !has_function {
        try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":\"the subject names no function, type, field or error of the program\",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}")
        try flush(&out)
        try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"uses\":0,\"roots\":0,\"complete\":true}}")
        try flush(&out)
        // The process status agrees with the record (D406): a refused query is
        // `Refused`, which one query's driver turns into exit 2 and a batch moves past (D409).
        ret Refused
    }
    let function = c.functions[function_index]
    var written = 0usize
    var indirect_calls = 0usize
    var last = c.explains[0usize]
    var first = true
    let (order, order_error) = explain_order(a, c)
    if order_error != ok { ret order_error }
    var ordered_at = 0usize
    while ordered_at < order.len {
        let e = c.explains[order[ordered_at]]
        ordered_at += 1usize
        // A call of an instance is a call of its template.
        var called = e.function_index == function_index
        if !called && e.function_index < c.function_count && c.function_generics[e.function_index].instance && c.function_generics[e.function_index].template_index == function_index { called = true }
        let targets = (e.kind == 4u8 && !e.found && called) || (e.kind == 1u8 && e.found && e.function_index == function_index) || (e.kind == 2u8 && e.template_index == function_index) || (e.kind == 5u8 && e.function_index == function_index)
        if !targets { continue }
        if !first && !explain_before(last, e) { continue }
        first = false
        last = e
        if e.module_index >= g.count { continue }
        let module = g.modules[e.module_index]
        let (root, relative) = source_identity_of(g, module.path)
        let (path, path_error) = manifest_slashes(a, relative)
        if path_error != ok { ret path_error }
        out.lines = module.lines
        var here: lex.Token = zero
        here.start = e.offset
        here.end = e.offset
        try text(&out, "{\"record\":\"use\",\"relation\":")
        if e.kind == 4u8 { try text(&out, "\"call\"") }
        if e.kind == 1u8 { try text(&out, "\"dispatch\"") }
        if e.kind == 2u8 { try text(&out, "\"instance\"") }
        if e.kind == 5u8 { try text(&out, "\"value\"") }
        try text(&out, ",\"provenance\":\"compiler-proved\",\"in\":")
        try quoted_function(&out, c, g, enclosing_function(c, e.module_index, e.offset))
        try text(&out, ",\"span\":")
        try point_span(&out, root, path, module.text, here)
        try byte(&out, 125u8)
        try flush(&out)
        written += 1usize
    }
    // Roots: what keeps the subject alive without a use above.
    var roots = 0usize
    if function.module_index < g.count && graph.same(function.name, "main") && function.module_index == 0usize {
        try text(&out, "{\"record\":\"root\",\"kind\":\"entry\",\"value\":\"the program's entry point\"}")
        try flush(&out)
        roots += 1usize
    }
    if function.module_index < g.count && manifest_has_attribute(g.modules[function.module_index].text, function.source_start, "test") {
        try text(&out, "{\"record\":\"root\",\"kind\":\"test\",\"value\":\"a @test the runner calls\"}")
        try flush(&out)
        roots += 1usize
    }
    if function.module_index < g.count && manifest_has_attribute(g.modules[function.module_index].text, function.source_start, "export") {
        try text(&out, "{\"record\":\"root\",\"kind\":\"export\",\"value\":\"exported to foreign callers\"}")
        try flush(&out)
        roots += 1usize
    }
    // Completeness: a call through a value anywhere could reach a function whose
    // name was taken as a value; the count says how many such calls the program has.
    var at = 0usize
    while at < c.explain_count {
        if c.explains[at].kind == 4u8 && c.explains[at].found { indirect_calls += 1usize }
        at += 1usize
    }
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"uses\":")
    try decimal(&out, written)
    try text(&out, ",\"roots\":")
    try decimal(&out, roots)
    try text(&out, ",\"indirect_calls\":")
    try decimal(&out, indirect_calls)
    try text(&out, ",\"complete\":")
    if !c.explain_overflow { try text(&out, "true") } else { try text(&out, "false") }
    try text(&out, "}}")
    ret flush(&out)
}

// `plan-rename-file --json --symbol module.name --to new` (D376, H29): the first
// structured edit. One `precondition` record per file the plan touches (its SHA-256
// as read), one `edit` record per site -- the declaration's name token and the name
// token of every resolved use -- each a byte span and its replacement, and one
// `postcondition` record saying what re-checking must find. Nothing is applied: a
// harness applies the edits to files whose hashes still match and re-checks.
// The sites a plan over one function touches (D376, D406): the declaration's name
// and every use's, in (module, offset) order, deduplicated -- an instance record and
// a call record share the offset of one spelling. A use of the name as a value is a
// site of a rename and not of a signature change, which cannot migrate it.
type PlanSites = struct {
    modules: []usize,
    offsets: []usize,
    kinds: []u8,
    count: usize,
}

fn plan_sites(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, function_index: usize, with_values: bool) -> (PlanSites, err) {
    var sites: PlanSites = zero
    let function = c.functions[function_index]
    let (site_modules, modules_error) = mem.alloc[usize](a, c.explain_count + 1usize)
    if modules_error != ok { ret (sites, modules_error) }
    let (site_offsets, offsets_error) = mem.alloc[usize](a, c.explain_count + 1usize)
    if offsets_error != ok { ret (sites, offsets_error) }
    let (site_kinds, kinds_error) = mem.alloc[u8](a, c.explain_count + 1usize)
    if kinds_error != ok { ret (sites, kinds_error) }
    var site_count = 0usize
    if function.module_index < g.count {
        let (declaration, has_declaration) = rename_declaration_offset(g.modules[function.module_index].text, function.source_start, function.name)
        if has_declaration {
            site_modules[0usize] = function.module_index
            site_offsets[0usize] = declaration
            site_kinds[0usize] = 0u8
            site_count = 1usize
        }
    }
    var at = 0usize
    while at < c.explain_count {
        let e = c.explains[at]
        var called = e.function_index == function_index
        if !called && e.function_index < c.function_count && c.function_generics[e.function_index].instance && c.function_generics[e.function_index].template_index == function_index { called = true }
        let targets = (e.kind == 4u8 && !e.found && called) || (e.kind == 2u8 && e.template_index == function_index) || (with_values && e.kind == 5u8 && e.function_index == function_index)
        if targets && e.module_index < g.count {
            let (name_at, has_name) = rename_use_offset(g.modules[e.module_index].text, e.offset, function.name)
            if has_name {
                var seen = false
                var probe = 0usize
                while probe < site_count {
                    if site_modules[probe] == e.module_index && site_offsets[probe] == name_at { seen = true }
                    probe += 1usize
                }
                if !seen {
                    // Insert in order.
                    var slot = site_count
                    while slot > 0usize && (site_modules[slot - 1usize] > e.module_index || (site_modules[slot - 1usize] == e.module_index && site_offsets[slot - 1usize] > name_at)) {
                        site_modules[slot] = site_modules[slot - 1usize]
                        site_offsets[slot] = site_offsets[slot - 1usize]
                        site_kinds[slot] = site_kinds[slot - 1usize]
                        slot = slot - 1usize
                    }
                    site_modules[slot] = e.module_index
                    site_offsets[slot] = name_at
                    site_kinds[slot] = 1u8
                    site_count += 1usize
                }
            }
        }
        at += 1usize
    }
    sites.modules = site_modules
    sites.offsets = site_offsets
    sites.kinds = site_kinds
    sites.count = site_count
    ret (sites, ok)
}

// The preconditions of a plan: each touched file's hash, once, in module order.
fn plan_preconditions(a: *mem.Arena, out: *Out, g: *graph.Graph, sites: PlanSites) -> (usize, err) {
    var files = 0usize
    var site = 0usize
    while site < sites.count {
        if site == 0usize || sites.modules[site] != sites.modules[site - 1usize] {
            let record_error = precondition_record(a, out, g, sites.modules[site])
            if record_error != ok { ret (files, record_error) }
            files += 1usize
        }
        site += 1usize
    }
    ret (files, ok)
}

fn precondition_record(a: *mem.Arena, out: *Out, g: *graph.Graph, module_index: usize) -> err {
    let module = g.modules[module_index]
    let (root, relative) = source_identity_of(g, module.path)
    let (path, path_error) = manifest_slashes(a, relative)
    if path_error != ok { ret path_error }
    let (digest, digest_error) = manifest_sha256(a, module.text)
    if digest_error != ok { ret digest_error }
    try text(out, "{\"record\":\"precondition\",\"source\":{\"root\":")
    try quoted(out, root)
    try text(out, ",\"path\":")
    try quoted(out, path)
    try text(out, "},\"sha256\":")
    try quoted(out, digest)
    try byte(out, 125u8)
    ret flush(out)
}

// The `)` that closes the parameter or argument list after the name at `name_at`
// (D406): the name's token, an optional `[...]` of generic arguments, then `(` and its
// match; and whether the list holds nothing but layout.
fn list_close_offset(tokens: []const lex.Token, name_at: usize) -> (usize, bool, bool) {
    var low = 0usize
    var high = tokens.len
    while low < high {
        let mid = low + (high - low) / 2usize
        if tokens[mid].start < name_at { low = mid + 1usize } else { high = mid }
    }
    if low >= tokens.len || tokens[low].start != name_at { ret (0usize, false, false) }
    var at = low + 1usize
    if at < tokens.len && tokens[at].kind == .PunctLBracket {
        var bracket_depth = 0usize
        while at < tokens.len {
            if tokens[at].kind == .PunctLBracket { bracket_depth += 1usize }
            if tokens[at].kind == .PunctRBracket {
                bracket_depth = bracket_depth - 1usize
                if bracket_depth == 0usize {
                    at += 1usize
                    break
                }
            }
            at += 1usize
        }
    }
    if at >= tokens.len || tokens[at].kind != .PunctLParen { ret (0usize, false, false) }
    let open_at = at
    var depth = 0usize
    var empty = true
    while at < tokens.len {
        if tokens[at].kind == .PunctLParen { depth += 1usize }
        if tokens[at].kind == .PunctRParen {
            depth = depth - 1usize
            if depth == 0usize { ret (tokens[at].start, empty, true) }
        }
        if at != open_at && tokens[at].kind != .Newline { empty = false }
        at += 1usize
    }
    ret (0usize, false, false)
}

// `plan-add-parameter-file PATH ROOT ARCH OS --json --symbol module.name --parameter
// "name: T" --argument EXPR` (D406, H17/H29): the signature-change plan. The
// declaration gains the parameter last, and every call the argument last, with the
// `, ` a non-empty list needs; the preconditions, the edits in (module, offset) order
// and the postcondition are the rename's. A function named as a value or chosen by a
// protocol cannot be migrated -- its type is its signature -- and the plan is refused
// naming the first such site, so no half-migration is ever emitted.
// The items of the list after the name at `name_at` (D415): the byte range of the
// text between `(` and its match, and each item's byte range, split at the commas
// of depth zero (a comma inside `(...)`, `[...]` or `{...}` stays), trimmed of the
// layout around it. At most sixteen items; more is a list the plan refuses.
type ListItems = struct {
    inner_start: usize,
    inner_end: usize,
    item_start: [16]usize,
    item_end: [16]usize,
    count: usize,
    found: bool,
}

fn list_items(tokens: []const lex.Token, name_at: usize) -> ListItems {
    var items: ListItems = zero
    var low = 0usize
    var high = tokens.len
    while low < high {
        let mid = low + (high - low) / 2usize
        if tokens[mid].start < name_at { low = mid + 1usize } else { high = mid }
    }
    if low >= tokens.len || tokens[low].start != name_at { ret items }
    var at = low + 1usize
    if at < tokens.len && tokens[at].kind == .PunctLBracket {
        var bracket_depth = 0usize
        while at < tokens.len {
            if tokens[at].kind == .PunctLBracket { bracket_depth += 1usize }
            if tokens[at].kind == .PunctRBracket {
                bracket_depth = bracket_depth - 1usize
                if bracket_depth == 0usize {
                    at += 1usize
                    break
                }
            }
            at += 1usize
        }
    }
    if at >= tokens.len || tokens[at].kind != .PunctLParen { ret items }
    items.inner_start = tokens[at].end
    at += 1usize
    var depth = 0usize
    var item_from = at
    var has_item = false
    while at < tokens.len {
        let kind = tokens[at].kind
        if kind == .PunctLParen || kind == .PunctLBracket || kind == .PunctLBrace { depth += 1usize }
        if kind == .PunctRParen || kind == .PunctRBracket || kind == .PunctRBrace {
            if depth == 0usize {
                if has_item {
                    if items.count >= 16usize { ret items }
                    items.item_start[items.count] = tokens[item_from].start
                    items.item_end[items.count] = tokens[at - 1usize].end
                    items.count += 1usize
                }
                items.inner_end = tokens[at].start
                items.found = true
                ret items
            }
            depth = depth - 1usize
        }
        if kind == .PunctComma && depth == 0usize {
            if has_item {
                if items.count >= 16usize { ret items }
                items.item_start[items.count] = tokens[item_from].start
                items.item_end[items.count] = tokens[at - 1usize].end
                items.count += 1usize
            }
            has_item = false
            item_from = at + 1usize
        } else {
            if kind != .Newline && !has_item {
                has_item = true
                item_from = at
            }
        }
        at += 1usize
    }
    ret items
}

// `plan-change-signature-file PATH ROOT ARCH OS --json --symbol module.name --order
// I,J,...` (D415, H29): the parameters kept, in the order given, each an index into
// the old list; an index left out removes that parameter, and no index may repeat.
// The declaration's list and every resolved call's argument list are re-rendered
// from the texts of their items -- what was written, in the new order, joined by
// `, ` -- as one edit per site over the text between the parentheses. A function
// named as a value or chosen by a protocol is refused as D406 refuses it; the
// process entry point is fixed too. So is a list with more items than the order
// names or more than sixteen.
// Whether an identifier token spelled `name` lies in a module's text between two
// byte offsets (D439): a function body's use of a parameter, read from the tokens.
fn body_names(module: graph.Module, from: usize, to: usize, name: str) -> bool {
    var at = 0usize
    while at < module.tokens.len {
        let token = module.tokens[at]
        if token.start >= from && token.end <= to && token.kind == .Identifier && graph.same(module.text[token.start..token.end], name) { ret true }
        at += 1usize
    }
    ret false
}

fn plan_signature_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, subject: str, order_text: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, c.explain_count * 1024usize + 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "plan-change-signature")
    let (function_index, has_function) = uses_subject(c, g, subject)
    if !has_function { ret plan_refused(&out, "the subject names no function of the program") }
    let function = c.functions[function_index]
    if function.module_index < g.count && graph.same(function.name, "main") && function.module_index == 0usize {
        ret plan_refused(&out, "the program's entry point has a fixed signature")
    }
    // The order: indices into the old parameter list, none repeated, all in range.
    var order: [16]usize = zero
    var order_count = 0usize
    var field_start = 0usize
    var at = 0usize
    while at <= order_text.len {
        if at == order_text.len || order_text[at] == 44u8 {
            let (value, value_ok) = plan_decimal(order_text[field_start..at])
            if !value_ok || value >= function.parameter_count || order_count >= 16usize { ret plan_refused(&out, "the order is not a list of distinct indices into the parameters") }
            var seen = 0usize
            while seen < order_count {
                if order[seen] == value { ret plan_refused(&out, "the order is not a list of distinct indices into the parameters") }
                seen += 1usize
            }
            order[order_count] = value
            order_count += 1usize
            field_start = at + 1usize
        }
        at += 1usize
    }
    var scan = 0usize
    while scan < c.explain_count {
        let e = c.explains[scan]
        let as_value = e.kind == 5u8 && e.function_index == function_index
        let dispatched = e.kind == 1u8 && e.found && e.function_index == function_index
        if (as_value || dispatched) && e.module_index < g.count {
            let module = g.modules[e.module_index]
            let (root, relative) = source_identity_of(g, module.path)
            let (path, path_error) = manifest_slashes(a, relative)
            if path_error != ok { ret path_error }
            out.lines = module.lines
            try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":\"")
            try text(&out, function.name)
            if as_value { try text(&out, " is named as a value here, and a value of a function type cannot change its signature: no change is planned") } else { try text(&out, " is chosen by a protocol here, whose signature is fixed: no change is planned") }
            try text(&out, "\",\"span\":")
            var here: lex.Token = zero
            here.start = e.offset
            here.end = e.offset
            try point_span(&out, root, path, module.text, here)
            try text(&out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
            try flush(&out)
            try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"edits\":0,\"files\":0,\"complete\":true}}")
            try flush(&out)
            ret Refused
        }
        scan += 1usize
    }
    let (sites, sites_error) = plan_sites(a, c, g, function_index, false)
    if sites_error != ok { ret sites_error }
    // Every site's list must be readable before any edit is written.
    var probe = 0usize
    while probe < sites.count {
        let items = list_items(g.modules[sites.modules[probe]].tokens, sites.offsets[probe])
        if !items.found || items.count != function.parameter_count { ret plan_refused(&out, "a site's list could not be read as the function's parameters or arguments") }
        probe += 1usize
    }
    // A parameter the order leaves out is removed (D439, H17): refused when the body
    // still names it, since the plan would then be an edit the check refuses.
    var removed = 0usize
    while removed < function.parameter_count {
        var kept = false
        var kept_at = 0usize
        while kept_at < order_count {
            if order[kept_at] == removed { kept = true }
            kept_at += 1usize
        }
        if !kept && function.module_index < g.count {
            let parameter_name = c.parameters[function.first_parameter + removed].name
            let declaration = g.modules[function.module_index]
            var declared_at = 0usize
            var declared_found = false
            var site_at = 0usize
            while site_at < sites.count {
                if sites.kinds[site_at] == 0u8 {
                    declared_at = sites.offsets[site_at]
                    declared_found = true
                }
                site_at += 1usize
            }
            let declared = list_items(declaration.tokens, declared_at)
            if declared_found && declared.found && body_names(declaration, declared.inner_end, function.source_end, parameter_name) {
                var message_storage: [256]u8 = zero
                var message_at = nptest_copy(message_storage[..], 0usize, "the parameter `")
                message_at = nptest_copy(message_storage[..], message_at, parameter_name)
                message_at = nptest_copy(message_storage[..], message_at, "` is left out of the order but the body names it: no change is planned")
                ret plan_refused(&out, message_storage[0usize..message_at])
            }
        }
        removed += 1usize
    }
    let (files, preconditions_error) = plan_preconditions(a, &out, g, sites)
    if preconditions_error != ok { ret preconditions_error }
    var site = 0usize
    while site < sites.count {
        let module = g.modules[sites.modules[site]]
        let (root, relative) = source_identity_of(g, module.path)
        let (path, path_error) = manifest_slashes(a, relative)
        if path_error != ok { ret path_error }
        out.lines = module.lines
        let items = list_items(module.tokens, sites.offsets[site])
        var first: lex.Token = zero
        first.start = items.inner_start
        first.end = items.inner_start
        var last: lex.Token = zero
        last.start = items.inner_end
        last.end = items.inner_end
        try text(&out, "{\"record\":\"edit\",\"op\":\"change-signature\",\"symbol\":")
        try quoted_function(&out, c, g, function_index)
        try text(&out, ",\"site\":")
        if sites.kinds[site] == 0u8 { try text(&out, "\"declaration\"") } else { try text(&out, "\"use\"") }
        try text(&out, ",\"span\":")
        try token_span(&out, root, path, module.text, first, last)
        try text(&out, ",\"replacement\":")
        var replacement_storage: [2048]u8 = zero
        var replacement_at = 0usize
        var order_at = 0usize
        while order_at < order_count {
            if order_at != 0usize { replacement_at = nptest_copy(replacement_storage[..], replacement_at, ", ") }
            let item = order[order_at]
            replacement_at = nptest_copy(replacement_storage[..], replacement_at, module.text[items.item_start[item]..items.item_end[item]])
            order_at += 1usize
        }
        try quoted(&out, replacement_storage[0usize..replacement_at])
        try owned_note(&out, g, sites.modules[site], first.start)
        try byte(&out, 125u8)
        try flush(&out)
        site += 1usize
    }
    try text(&out, "{\"record\":\"postcondition\",\"check\":\"check-file passes; context-file --symbol ")
    try text(&out, subject)
    try text(&out, " reports ")
    try decimal(&out, order_count)
    try text(&out, " parameters in the order given, and uses-file --symbol ")
    try text(&out, subject)
    try text(&out, " reports uses at ")
    if sites.count > 0usize { try decimal(&out, sites.count - 1usize) } else { try decimal(&out, 0usize) }
    try text(&out, " sites\"}")
    try flush(&out)
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"edits\":")
    try decimal(&out, sites.count)
    try text(&out, ",\"files\":")
    try decimal(&out, files)
    try text(&out, ",\"complete\":")
    if !c.explain_overflow { try text(&out, "true") } else { try text(&out, "false") }
    try text(&out, ",\"snapshot\":")
    try program_snapshot(&out, g)
    try text(&out, "}}")
    ret flush(&out)
}

// The argument for one call site (D455, H29): the line of `overrides` -- the text
// of `--arguments FILE`, one `LINE:COL EXPR` per line and `* EXPR` for the rest --
// whose position is the call's, else the `*` line, else `argument`; the position is
// the call's name as `uses-file` spells it.
fn site_argument(overrides: str, line: usize, column: usize, argument: str) -> (str, bool) {
    if overrides.len == 0usize { ret (argument, true) }
    var fallback = ""
    var has_fallback = false
    var start = 0usize
    var at = 0usize
    while at <= overrides.len {
        if at == overrides.len || overrides[at] == 10u8 {
            var item = overrides[start..at]
            if item.len != 0usize && item[item.len - 1usize] == 13u8 { item = item[0usize..item.len - 1usize] }
            var space = 0usize
            while space < item.len && item[space] != 32u8 { space += 1usize }
            if space < item.len {
                let key = item[0usize..space]
                let value = item[space + 1usize..item.len]
                if key.len == 1usize && key[0usize] == 42u8 {
                    fallback = value
                    has_fallback = true
                } else {
                    var colon = 0usize
                    while colon < key.len && key[colon] != 58u8 { colon += 1usize }
                    if colon < key.len {
                        let (key_line, line_ok) = plan_decimal(key[0usize..colon])
                        let (key_column, column_ok) = plan_decimal(key[colon + 1usize..key.len])
                        if line_ok && column_ok && key_line == line && key_column == column { ret (value, true) }
                    }
                }
            }
            start = at + 1usize
        }
        at += 1usize
    }
    if has_fallback { ret (fallback, true) }
    ret ("", false)
}

fn plan_parameter_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, subject: str, parameter: str, argument: str, overrides: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, c.explain_count * 512usize + 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "plan-add-parameter")
    let (function_index, has_function) = uses_subject(c, g, subject)
    if !has_function {
        try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":\"the subject names no function of the program\",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}")
        try flush(&out)
        try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"edits\":0,\"files\":0,\"complete\":true}}")
        try flush(&out)
        // The process status agrees with the record (D406): a refused query is
        // `Refused`, which one query's driver turns into exit 2 and a batch moves past (D409).
        ret Refused
    }
    let function = c.functions[function_index]
    // A site the plan cannot migrate: the name as a value, or a protocol's choice.
    var scan = 0usize
    while scan < c.explain_count {
        let e = c.explains[scan]
        let as_value = e.kind == 5u8 && e.function_index == function_index
        let dispatched = e.kind == 1u8 && e.found && e.function_index == function_index
        if (as_value || dispatched) && e.module_index < g.count {
            let module = g.modules[e.module_index]
            let (root, relative) = source_identity_of(g, module.path)
            let (path, path_error) = manifest_slashes(a, relative)
            if path_error != ok { ret path_error }
            out.lines = module.lines
            try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":\"")
            try text(&out, function.name)
            if as_value { try text(&out, " is named as a value here, and a value of a function type cannot take a new parameter: no signature change is planned") } else { try text(&out, " is chosen by a protocol here, whose signature is fixed: no signature change is planned") }
            try text(&out, "\",\"span\":")
            var here: lex.Token = zero
            here.start = e.offset
            here.end = e.offset
            try point_span(&out, root, path, module.text, here)
            try text(&out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
            try flush(&out)
            try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"edits\":0,\"files\":0,\"complete\":true}}")
            try flush(&out)
            ret Refused
        }
        scan += 1usize
    }
    let (sites, sites_error) = plan_sites(a, c, g, function_index, false)
    if sites_error != ok { ret sites_error }
    let (files, preconditions_error) = plan_preconditions(a, &out, g, sites)
    if preconditions_error != ok { ret preconditions_error }
    var site = 0usize
    while site < sites.count {
        let module = g.modules[sites.modules[site]]
        let (root, relative) = source_identity_of(g, module.path)
        let (path, path_error) = manifest_slashes(a, relative)
        if path_error != ok { ret path_error }
        out.lines = module.lines
        let (close_at, empty, has_list) = list_close_offset(module.tokens, sites.offsets[site])
        if !has_list { ret InvalidPlan }
        var insert: lex.Token = zero
        insert.start = close_at
        insert.end = close_at
        try text(&out, "{\"record\":\"edit\",\"op\":\"add-parameter-and-migrate\",\"symbol\":")
        try quoted_function(&out, c, g, function_index)
        try text(&out, ",\"site\":")
        if sites.kinds[site] == 0u8 { try text(&out, "\"declaration\"") } else { try text(&out, "\"use\"") }
        try text(&out, ",\"span\":")
        try token_span(&out, root, path, module.text, insert, insert)
        try text(&out, ",\"replacement\":")
        var replacement_storage: [512]u8 = zero
        var replacement_at = 0usize
        if !empty { replacement_at = nptest_copy(replacement_storage[..], replacement_at, ", ") }
        if sites.kinds[site] == 0u8 {
            replacement_at = nptest_copy(replacement_storage[..], replacement_at, parameter)
        } else {
            // The call's own argument (D455): by the call's line and column, else the default.
            var name_token: lex.Token = zero
            name_token.start = sites.offsets[site]
            name_token.end = sites.offsets[site]
            let name_at = lex.span_of(module.text, module.lines, name_token)
            let (site_text, has_site_text) = site_argument(overrides, name_at.line, name_at.column, argument)
            if !has_site_text {
                var message_storage: [256]u8 = zero
                var message_at = nptest_copy(message_storage[..], 0usize, "no argument for the call at line ")
                var digits: [24]u8 = zero
                var digit_at = digits.len
                var rest = name_at.line
                if rest == 0usize {
                    digit_at = digit_at - 1usize
                    digits[digit_at] = 48u8
                }
                while rest > 0usize {
                    digit_at = digit_at - 1usize
                    digits[digit_at] = 48u8 + u8(rest % 10usize)
                    rest = rest / 10usize
                }
                message_at = nptest_copy(message_storage[..], message_at, digits[digit_at..digits.len])
                message_at = nptest_copy(message_storage[..], message_at, " and no `*` line: no change is planned")
                ret plan_refused(&out, message_storage[0usize..message_at])
            }
            replacement_at = nptest_copy(replacement_storage[..], replacement_at, site_text)
        }
        try quoted(&out, replacement_storage[0usize..replacement_at])
        try owned_note(&out, g, sites.modules[site], insert.start)
        try byte(&out, 125u8)
        try flush(&out)
        site += 1usize
    }
    try text(&out, "{\"record\":\"postcondition\",\"check\":\"check-file passes; context-file --symbol ")
    try text(&out, subject)
    try text(&out, " reports the signature with `")
    try text(&out, parameter)
    try text(&out, "` last, and uses-file --symbol ")
    try text(&out, subject)
    try text(&out, " reports uses at ")
    if sites.count > 0usize { try decimal(&out, sites.count - 1usize) } else { try decimal(&out, 0usize) }
    try text(&out, " sites\"}")
    try flush(&out)
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"edits\":")
    try decimal(&out, sites.count)
    try text(&out, ",\"files\":")
    try decimal(&out, files)
    try text(&out, ",\"complete\":")
    if !c.explain_overflow { try text(&out, "true") } else { try text(&out, "false") }
    try text(&out, ",\"snapshot\":")
    try program_snapshot(&out, g)
    try text(&out, "}}")
    ret flush(&out)
}

// The uses of a type (D516, H17): one `use` record per site the index resolves to
// it, relation `type`, in the function the site lies in; the declaration is not a use.
fn type_uses_json(a: *mem.Arena, out: *Out, c: *check.Checker, g: *graph.Graph, subject: str, type_symbol: usize) -> err {
    let (sites, sites_error) = type_sites(a, c, g, subject, type_symbol)
    if sites_error != ok { ret sites_error }
    var written = 0usize
    var site = 0usize
    while site < sites.count {
        if sites.kinds[site] != 0u8 {
            let module = g.modules[sites.modules[site]]
            let (root, relative) = source_identity_of(g, module.path)
            let (path, path_error) = manifest_slashes(a, relative)
            if path_error != ok { ret path_error }
            out.lines = module.lines
            var here: lex.Token = zero
            here.start = sites.offsets[site]
            here.end = sites.offsets[site]
            try text(out, "{\"record\":\"use\",\"relation\":\"type\",\"provenance\":\"compiler-proved\",\"in\":")
            try quoted_function(out, c, g, enclosing_function(c, sites.modules[site], sites.offsets[site]))
            try text(out, ",\"span\":")
            try point_span(out, root, path, module.text, here)
            try byte(out, 125u8)
            try flush(out)
            written += 1usize
        }
        site += 1usize
    }
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"uses\":")
    try decimal(out, written)
    try text(out, ",\"roots\":0,\"indirect_calls\":0,\"complete\":true}}")
    ret flush(out)
}

// One of section 12's protocol operations, as a function's suffix (D517, D537).
fn protocol_op_name(op: str) -> bool {
    ret graph.same(op, "eq") || graph.same(op, "cmp") || graph.same(op, "hash") || graph.same(op, "format") || graph.same(op, "next") || graph.same(op, "next_err")
}

// Whether a function is a protocol's by its spelling (D518): `<snake>_<op>` for a
// type declared in its module, `op` one of section 12's -- `eq`, `cmp`, `hash`,
// `format`, `next`, `next_err`; the type's name and the op when it is.
fn protocol_spelling(c: *check.Checker, g: *graph.Graph, function_index: usize) -> (str, str, bool) {
    let function = c.functions[function_index]
    var symbol_index = 0usize
    while symbol_index < c.resolver.count {
        let symbol = c.resolver.symbols[symbol_index]
        if symbol.kind == .Type && symbol.module_index == function.module_index {
            var prefix: [128]u8 = zero
            let prefix_len = em.snake_protocol_name(symbol.name, "", prefix[..])
            if prefix_len != 0usize && function.name.len > prefix_len && graph.same(function.name[0usize..prefix_len], prefix[0usize..prefix_len]) {
                let op = function.name[prefix_len..function.name.len]
                if protocol_op_name(op) { ret (symbol.name, op, true) }
            }
        }
        symbol_index += 1usize
    }
    ret ("", "", false)
}

// The type a subject `module.Name` names (D515): its symbol, when it is one.
fn uses_type_subject(c: *check.Checker, g: *graph.Graph, subject: str) -> (usize, bool) {
    var dot = subject.len
    var at = 0usize
    while at < subject.len {
        if subject[at] == 46u8 { dot = at }
        at += 1usize
    }
    if dot == subject.len { ret (0usize, false) }
    let module_name = subject[0usize..dot]
    let name = subject[dot + 1usize..subject.len]
    var symbol_index = 0usize
    while symbol_index < c.resolver.count {
        let symbol = c.resolver.symbols[symbol_index]
        if symbol.kind == .Type && symbol.module_index < g.count && graph.same(g.modules[symbol.module_index].name, module_name) && graph.same(symbol.name, name) { ret (symbol_index, true) }
        symbol_index += 1usize
    }
    ret (0usize, false)
}

// A number after a key in one captured record, at or after `from`.
fn captured_number(line: str, key: str, from: usize) -> (usize, usize, bool) {
    var at = from
    while at + key.len <= line.len {
        if graph.same(line[at..at + key.len], key) {
            var end = at + key.len
            var value = 0usize
            while end < line.len && line[end] >= 48u8 && line[end] <= 57u8 {
                value = value * 10usize + usize(line[end] - 48u8)
                end += 1usize
            }
            ret (value, end, true)
        }
        at += 1usize
    }
    ret (0usize, line.len, false)
}

// The sites of a type across the program (D515, D516): every module's index is
// taken in memory, and each `reference` record whose `target_qualified_name` is the
// type -- an annotation, a literal, a qualified or a bare spelling -- gives a site,
// its name the last bytes of the reference's span; the type's own `symbol` record
// gives the declaration's, kind 0. In (module, offset) order.
fn type_sites(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, subject: str, type_symbol: usize) -> (PlanSites, err) {
    let symbol = c.resolver.symbols[type_symbol]
    let name = symbol.name
    var sites: PlanSites = zero
    let (site_modules, modules_error) = mem.alloc[usize](a, 4096usize)
    if modules_error != ok { ret (sites, modules_error) }
    let (site_offsets, offsets_error) = mem.alloc[usize](a, 4096usize)
    if offsets_error != ok { ret (sites, offsets_error) }
    let (site_kinds, kinds_error) = mem.alloc[u8](a, 4096usize)
    if kinds_error != ok { ret (sites, kinds_error) }
    var site_count = 0usize
    var module_at = 0usize
    while module_at < g.count {
        let module = g.modules[module_at]
        let checkpoint = mem.mark(a)
        // The whole index at once, where the command flushes it record by record:
        // a module of many short declarations runs to thirty bytes per source byte.
        let (storage, storage_error) = mem.alloc[u8](a, module.text.len * 40usize + 65536usize)
        if storage_error != ok { ret (sites, storage_error) }
        var taken: Out = zero
        taken.bytes = storage
        taken.capture = true
        let (root, relative) = source_identity_of(g, module.path)
        let (index_exit, index_error) = index_json_into(a, &taken, root, relative, module.text, module.name, module_at, c.resolver.symbols[0usize..c.resolver.count], c.resolver.count, "")
        if index_error != ok { ret (sites, index_error) }
        let records = taken.bytes[0usize..taken.count]
        var line_start = 0usize
        while line_start < records.len {
            var line_end = line_start
            while line_end < records.len && records[line_end] != 10u8 { line_end += 1usize }
            let line = records[line_start..line_end]
            line_start = line_end + 1usize
            let (kind, kind_end, has_kind) = inventory_value(line, 0usize, "\"record\":\"")
            if !has_kind { continue }
            var offset = 0usize
            var is_site = false
            var declaration = false
            if graph.same(kind, "reference") {
                let (referenced, referenced_end, has_referenced) = inventory_value(line, kind_end, "\"target_qualified_name\":\"")
                if has_referenced && graph.same(referenced, subject) {
                    let (span_end, end_at, has_end) = captured_number(line, "\"byte_end\":", kind_end)
                    if has_end && span_end >= name.len {
                        offset = span_end - name.len
                        is_site = true
                    }
                }
            }
            if graph.same(kind, "symbol") && module_at == symbol.module_index {
                let (symbol_kind, symbol_kind_end, has_symbol_kind) = inventory_value(line, kind_end, "\"kind\":\"")
                let (qualified, qualified_end, has_qualified) = inventory_value(line, symbol_kind_end, "\"qualified_name\":\"")
                if has_symbol_kind && graph.same(symbol_kind, "type") && has_qualified && graph.same(qualified, subject) {
                    let selection_key = "\"selection_span\":"
                    var selection_at = qualified_end
                    while selection_at + selection_key.len <= line.len && !graph.same(line[selection_at..selection_at + selection_key.len], selection_key) { selection_at += 1usize }
                    let (span_start, start_at, has_start) = captured_number(line, "\"byte_start\":", selection_at)
                    if has_start {
                        offset = span_start
                        is_site = true
                        declaration = true
                    }
                }
            }
            if is_site {
                if site_count == site_modules.len { ret (sites, Capacity) }
                site_modules[site_count] = module_at
                site_offsets[site_count] = offset
                site_kinds[site_count] = 1u8
                if declaration { site_kinds[site_count] = 0u8 }
                site_count += 1usize
            }
        }
        mem.reset(a, checkpoint)
        module_at += 1usize
    }
    sites.modules = site_modules
    sites.offsets = site_offsets
    sites.kinds = site_kinds
    sites.count = site_count
    ret (sites, ok)
}

// The rename of a type (D515, H17, H29): the plan is the same shape as a function's.
fn plan_rename_type_json(a: *mem.Arena, out: *Out, c: *check.Checker, g: *graph.Graph, subject: str, type_symbol: usize, to: str) -> err {
    let symbol = c.resolver.symbols[type_symbol]
    let name = symbol.name
    let (type_only, sites_error) = type_sites(a, c, g, subject, type_symbol)
    if sites_error != ok { ret sites_error }
    // The functions spelled with the type's name (D517, H17): `rec_cmp` for `Rec`,
    // by spec section 12's convention `<t>_<op>`, declared in the type's module;
    // each is renamed with the type, `pair_cmp`, at its declaration and every use,
    // since the lookup that finds it is by the spelling.
    var old_prefix: [128]u8 = zero
    let old_prefix_len = em.snake_protocol_name(name, "", old_prefix[..])
    var new_prefix: [128]u8 = zero
    let new_prefix_len = em.snake_protocol_name(to, "", new_prefix[..])
    var followers: [64]usize = zero
    var follower_count = 0usize
    var function_at = 0usize
    while function_at < c.signature_function_count && old_prefix_len != 0usize && new_prefix_len != 0usize {
        let candidate = c.functions[function_at]
        // Only the protocol's spellings follow (D537): `type_has_undef_value` beside
        // `Type` is a helper named for the type, not a lookup by the spelling.
        if candidate.module_index == symbol.module_index && !c.function_generics[function_at].instance && candidate.name.len > old_prefix_len && graph.same(candidate.name[0usize..old_prefix_len], old_prefix[0usize..old_prefix_len]) && protocol_op_name(candidate.name[old_prefix_len..candidate.name.len]) && follower_count < followers.len {
            followers[follower_count] = function_at
            follower_count += 1usize
        }
        function_at += 1usize
    }
    // Every site, the type's and the followers', in (module, offset) order: `who`
    // is 0 for the type and the follower's number plus one otherwise.
    let (site_modules, modules_error) = mem.alloc[usize](a, type_only.count + follower_count * 256usize + 1usize)
    if modules_error != ok { ret modules_error }
    let (site_offsets, offsets_error) = mem.alloc[usize](a, site_modules.len)
    if offsets_error != ok { ret offsets_error }
    let (site_kinds, kinds_error) = mem.alloc[u8](a, site_modules.len)
    if kinds_error != ok { ret kinds_error }
    let (site_who, who_error) = mem.alloc[usize](a, site_modules.len)
    if who_error != ok { ret who_error }
    var site_count = 0usize
    var copy_at = 0usize
    while copy_at < type_only.count {
        site_modules[site_count] = type_only.modules[copy_at]
        site_offsets[site_count] = type_only.offsets[copy_at]
        site_kinds[site_count] = type_only.kinds[copy_at]
        site_who[site_count] = 0usize
        site_count += 1usize
        copy_at += 1usize
    }
    var follower_at = 0usize
    while follower_at < follower_count {
        let (follower_sites, follower_error) = plan_sites(a, c, g, followers[follower_at], true)
        if follower_error != ok { ret follower_error }
        var follower_site = 0usize
        while follower_site < follower_sites.count {
            if site_count == site_modules.len { ret Capacity }
            site_modules[site_count] = follower_sites.modules[follower_site]
            site_offsets[site_count] = follower_sites.offsets[follower_site]
            site_kinds[site_count] = follower_sites.kinds[follower_site]
            site_who[site_count] = follower_at + 1usize
            site_count += 1usize
            follower_site += 1usize
        }
        follower_at += 1usize
    }
    // Insertion sort by (module, offset): a plan has tens of sites.
    var sorted = 1usize
    while sorted < site_count {
        var back = sorted
        while back > 0usize && (site_modules[back - 1usize] > site_modules[back] || (site_modules[back - 1usize] == site_modules[back] && site_offsets[back - 1usize] > site_offsets[back])) {
            let swap_module = site_modules[back - 1usize]
            site_modules[back - 1usize] = site_modules[back]
            site_modules[back] = swap_module
            let swap_offset = site_offsets[back - 1usize]
            site_offsets[back - 1usize] = site_offsets[back]
            site_offsets[back] = swap_offset
            let swap_kind = site_kinds[back - 1usize]
            site_kinds[back - 1usize] = site_kinds[back]
            site_kinds[back] = swap_kind
            let swap_who = site_who[back - 1usize]
            site_who[back - 1usize] = site_who[back]
            site_who[back] = swap_who
            back = back - 1usize
        }
        sorted += 1usize
    }
    var sites: PlanSites = zero
    sites.modules = site_modules
    sites.offsets = site_offsets
    sites.kinds = site_kinds
    sites.count = site_count
    let (files, preconditions_error) = plan_preconditions(a, out, g, sites)
    if preconditions_error != ok { ret preconditions_error }
    var site = 0usize
    while site < site_count {
        let module = g.modules[site_modules[site]]
        let (root, relative) = source_identity_of(g, module.path)
        let (path, path_error) = manifest_slashes(a, relative)
        if path_error != ok { ret path_error }
        out.lines = module.lines
        var site_name = name
        if site_who[site] != 0usize { site_name = c.functions[followers[site_who[site] - 1usize]].name }
        var name_token: lex.Token = zero
        name_token.start = site_offsets[site]
        name_token.end = site_offsets[site] + site_name.len
        try text(out, "{\"record\":\"edit\",\"op\":\"rename-symbol\",\"symbol\":")
        if site_who[site] == 0usize { try quoted(out, subject) } else { try quoted_function(out, c, g, followers[site_who[site] - 1usize]) }
        try text(out, ",\"site\":")
        if site_kinds[site] == 0u8 { try text(out, "\"declaration\"") } else { try text(out, "\"use\"") }
        try text(out, ",\"span\":")
        try token_span(out, root, path, module.text, name_token, name_token)
        try text(out, ",\"replacement\":")
        if site_who[site] == 0usize {
            try quoted(out, to)
        } else {
            // The follower's new spelling: the new prefix, then what followed the old.
            var renamed: [256]u8 = zero
            var renamed_at = nptest_copy(renamed[..], 0usize, new_prefix[0usize..new_prefix_len])
            renamed_at = nptest_copy(renamed[..], renamed_at, site_name[old_prefix_len..site_name.len])
            try quoted(out, renamed[0usize..renamed_at])
        }
        try owned_note(out, g, site_modules[site], site_offsets[site])
        try byte(out, 125u8)
        try flush(out)
        site += 1usize
    }
    try text(out, "{\"record\":\"postcondition\",\"check\":\"check-file passes; index-file reports ")
    if type_only.count > 0usize { try decimal(out, type_only.count - 1usize) } else { try decimal(out, 0usize) }
    try text(out, " references to ")
    try text(out, subject[0usize..rename_qualifier_len(subject)])
    try text(out, to)
    try text(out, " and ")
    try text(out, subject)
    try text(out, " names no type")
    if follower_count != 0usize {
        try text(out, "; the ")
        try decimal(out, follower_count)
        try text(out, " functions spelled with the type's name are spelled with the new one")
    }
    try text(out, "\"}")
    try flush(out)
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"edits\":")
    try decimal(out, site_count)
    try text(out, ",\"files\":")
    try decimal(out, files)
    try text(out, ",\"complete\":true,\"snapshot\":")
    try program_snapshot(out, g)
    try text(out, "}}")
    ret flush(out)
}

fn plan_rename_json(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, subject: str, to: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, c.explain_count * 512usize + 65536usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try header(&out, "plan-rename")
    // A field's rename (D420): the declaration's token and every access or literal naming it.
    let (field_index, is_field) = uses_field_subject(c, g, subject)
    if is_field {
        let field = c.aggregate_fields[field_index]
        var aggregate_index = 0usize
        var aggregate_at = 0usize
        while aggregate_at < c.aggregate_count {
            let candidate = c.aggregates[aggregate_at]
            if field_index >= candidate.first_field && field_index < candidate.first_field + candidate.field_count && !candidate.instance { aggregate_index = aggregate_at }
            aggregate_at += 1usize
        }
        var declared_at = 0usize
        var has_declaration = false
        if c.aggregates[aggregate_index].module_index < g.count && field.token.end > field.token.start {
            declared_at = field.token.start
            has_declaration = true
        }
        ret plan_rename_sites_json(a, &out, c, g, subject, 6u8, field_index, field.name, c.aggregates[aggregate_index].module_index, declared_at, has_declaration, "field", to)
    }
    // An error's rename (D451, H17): the declaration's name token and every value naming it.
    let (error_symbol, is_error) = uses_error_subject(c, g, subject)
    if is_error {
        let symbol = c.resolver.symbols[error_symbol]
        var declared_at = 0usize
        var has_declaration = false
        if symbol.module_index < g.count && symbol.token_start + 1usize < g.modules[symbol.module_index].tokens.len {
            declared_at = g.modules[symbol.module_index].tokens[symbol.token_start + 1usize].start
            has_declaration = true
        }
        ret plan_rename_sites_json(a, &out, c, g, subject, 7u8, error_symbol, symbol.name, symbol.module_index, declared_at, has_declaration, "error", to)
    }
    // A type's rename (D515, H17, H29): the index of every module names each
    // reference to the type, qualified or bare; the plan is those and the declaration.
    let (type_symbol, is_type) = uses_type_subject(c, g, subject)
    if is_type { ret plan_rename_type_json(a, &out, c, g, subject, type_symbol, to) }
    let (function_index, has_function) = uses_subject(c, g, subject)
    if !has_function {
        try text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-CLI-9999\",\"message\":\"the subject names no function, type, field or error of the program\",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}")
        try flush(&out)
        try text(&out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"edits\":0,\"files\":0,\"complete\":true}}")
        try flush(&out)
        // The process status agrees with the record (D406): a refused query is
        // `Refused`, which one query's driver turns into exit 2 and a batch moves past (D409).
        ret Refused
    }
    let function = c.functions[function_index]
    // A function found by its spelling (D518, H17): `rec_cmp` is `Rec`'s `cmp` by
    // section 12's convention, so a name of its own would leave every lookup behind;
    // the rename is refused and the type named -- the type's rename carries it (D517).
    let (spelled_type, spelled_op, is_spelled) = protocol_spelling(c, g, function_index)
    if is_spelled {
        var message_storage: [512]u8 = zero
        var message_at = nptest_copy(message_storage[..], 0usize, "`")
        message_at = nptest_copy(message_storage[..], message_at, subject)
        message_at = nptest_copy(message_storage[..], message_at, "` is the `")
        message_at = nptest_copy(message_storage[..], message_at, spelled_op)
        message_at = nptest_copy(message_storage[..], message_at, "` of `")
        message_at = nptest_copy(message_storage[..], message_at, spelled_type)
        message_at = nptest_copy(message_storage[..], message_at, "` by its spelling, which every lookup of the protocol is by: rename the type, which carries it, or declare the new spelling beside it")
        ret plan_refused(&out, message_storage[0usize..message_at])
    }
    let (sites, sites_error) = plan_sites(a, c, g, function_index, true)
    if sites_error != ok { ret sites_error }
    let site_modules = sites.modules
    let site_offsets = sites.offsets
    let site_kinds = sites.kinds
    let site_count = sites.count
    let (files, preconditions_error) = plan_preconditions(a, &out, g, sites)
    if preconditions_error != ok { ret preconditions_error }
    var site = 0usize
    while site < site_count {
        let module = g.modules[site_modules[site]]
        let (root, relative) = source_identity_of(g, module.path)
        let (path, path_error) = manifest_slashes(a, relative)
        if path_error != ok { ret path_error }
        out.lines = module.lines
        var name_token: lex.Token = zero
        name_token.start = site_offsets[site]
        name_token.end = site_offsets[site] + function.name.len
        try text(&out, "{\"record\":\"edit\",\"op\":\"rename-symbol\",\"symbol\":")
        try quoted_function(&out, c, g, function_index)
        try text(&out, ",\"site\":")
        if site_kinds[site] == 0u8 { try text(&out, "\"declaration\"") } else { try text(&out, "\"use\"") }
        try text(&out, ",\"span\":")
        try token_span(&out, root, path, module.text, name_token, name_token)
        try text(&out, ",\"replacement\":")
        try quoted(&out, to)
        try owned_note(&out, g, site_modules[site], site_offsets[site])
        try byte(&out, 125u8)
        try flush(&out)
        site += 1usize
    }
    try text(&out, "{\"record\":\"postcondition\",\"check\":\"check-file passes; uses-file --symbol ")
    try text(&out, subject[0usize..rename_qualifier_len(subject)])
    try text(&out, to)
    try text(&out, " reports uses at ")
    if site_count > 0usize { try decimal(&out, site_count - 1usize) } else { try decimal(&out, 0usize) }
    try text(&out, " sites and ")
    try text(&out, subject)
    try text(&out, " names no function\"}")
    try flush(&out)
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"edits\":")
    try decimal(&out, site_count)
    try text(&out, ",\"files\":")
    try decimal(&out, files)
    try text(&out, ",\"complete\":")
    if !c.explain_overflow { try text(&out, "true") } else { try text(&out, "false") }
    try text(&out, ",\"snapshot\":")
    try program_snapshot(&out, g)
    try text(&out, "}}")
    ret flush(&out)
}

// The rename plan of a field (D420): the same records as a function's, the sites
// being the field's declaration token and every kind-6 record of it.
// A rename over sites the explain table holds (D420, D451): a field (kind 6) or an
// error (kind 7), the declaration's name token first, every use after it.
fn plan_rename_sites_json(a: *mem.Arena, out: *Out, c: *check.Checker, g: *graph.Graph, subject: str, explain_kind: u8, index: usize, name: str, declared_module: usize, declared_at: usize, has_declaration: bool, what: str, to: str) -> err {
    var sites: PlanSites = zero
    let (site_modules, modules_error) = mem.alloc[usize](a, c.explain_count + 1usize)
    if modules_error != ok { ret modules_error }
    let (site_offsets, offsets_error) = mem.alloc[usize](a, c.explain_count + 1usize)
    if offsets_error != ok { ret offsets_error }
    let (site_kinds, kinds_error) = mem.alloc[u8](a, c.explain_count + 1usize)
    if kinds_error != ok { ret kinds_error }
    var site_count = 0usize
    if has_declaration {
        site_modules[0usize] = declared_module
        site_offsets[0usize] = declared_at
        site_kinds[0usize] = 0u8
        site_count = 1usize
    }
    var at = 0usize
    while at < c.explain_count {
        let e = c.explains[at]
        if e.kind == explain_kind && e.function_index == index && e.module_index < g.count {
            var seen = false
            var probe = 0usize
            while probe < site_count {
                if site_modules[probe] == e.module_index && site_offsets[probe] == e.offset { seen = true }
                probe += 1usize
            }
            if !seen {
                var slot = site_count
                while slot > 0usize && (site_modules[slot - 1usize] > e.module_index || (site_modules[slot - 1usize] == e.module_index && site_offsets[slot - 1usize] > e.offset)) {
                    site_modules[slot] = site_modules[slot - 1usize]
                    site_offsets[slot] = site_offsets[slot - 1usize]
                    site_kinds[slot] = site_kinds[slot - 1usize]
                    slot = slot - 1usize
                }
                site_modules[slot] = e.module_index
                site_offsets[slot] = e.offset
                site_kinds[slot] = 1u8
                site_count += 1usize
            }
        }
        at += 1usize
    }
    sites.modules = site_modules
    sites.offsets = site_offsets
    sites.kinds = site_kinds
    sites.count = site_count
    let (files, preconditions_error) = plan_preconditions(a, out, g, sites)
    if preconditions_error != ok { ret preconditions_error }
    var site = 0usize
    while site < sites.count {
        let module = g.modules[sites.modules[site]]
        let (root, relative) = source_identity_of(g, module.path)
        let (path, path_error) = manifest_slashes(a, relative)
        if path_error != ok { ret path_error }
        out.lines = module.lines
        var name_token: lex.Token = zero
        name_token.start = sites.offsets[site]
        name_token.end = sites.offsets[site] + name.len
        try text(out, "{\"record\":\"edit\",\"op\":\"rename-symbol\",\"symbol\":")
        try quoted(out, subject)
        try text(out, ",\"site\":")
        if sites.kinds[site] == 0u8 { try text(out, "\"declaration\"") } else { try text(out, "\"use\"") }
        try text(out, ",\"span\":")
        try token_span(out, root, path, module.text, name_token, name_token)
        try text(out, ",\"replacement\":")
        try quoted(out, to)
        try owned_note(out, g, sites.modules[site], sites.offsets[site])
        try byte(out, 125u8)
        try flush(out)
        site += 1usize
    }
    try text(out, "{\"record\":\"postcondition\",\"check\":\"check-file passes; uses-file --symbol ")
    try text(out, subject[0usize..rename_qualifier_len(subject)])
    try text(out, to)
    try text(out, " reports uses at ")
    if sites.count > 0usize { try decimal(out, sites.count - 1usize) } else { try decimal(out, 0usize) }
    try text(out, " sites and ")
    try text(out, subject)
    try text(out, " names no ")
    try text(out, what)
    try text(out, "\"}")
    try flush(out)
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"edits\":")
    try decimal(out, sites.count)
    try text(out, ",\"files\":")
    try decimal(out, files)
    try text(out, ",\"complete\":")
    if !c.explain_overflow { try text(out, "true") } else { try text(out, "false") }
    try text(out, ",\"snapshot\":")
    try program_snapshot(out, g)
    try text(out, "}}")
    ret flush(out)
}

// `module.` of a subject, or nothing.
fn rename_qualifier_len(subject: str) -> usize {
    var at = subject.len
    while at > 0usize {
        if subject[at - 1usize] == 46u8 { ret at }
        at = at - 1usize
    }
    ret 0usize
}

// The offset of the declaration's name: the first `fn NAME` at or after `from`.
fn rename_declaration_offset(source_text: str, from: usize, name: str) -> (usize, bool) {
    var at = from
    while at + 3usize + name.len <= source_text.len {
        if source_text[at] == 102u8 && source_text[at + 1usize] == 110u8 && source_text[at + 2usize] == 32u8 && graph.same(source_text[at + 3usize..at + 3usize + name.len], name) && !rename_word_byte(source_text, at + 3usize + name.len) { ret (at + 3usize, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// The offset of `name` at a use: the spelling at `offset`, or after a qualifier
// (`module.name`, `name[T]` follows either).
fn rename_use_offset(source_text: str, offset: usize, name: str) -> (usize, bool) {
    if offset + name.len <= source_text.len && graph.same(source_text[offset..offset + name.len], name) && !rename_word_byte(source_text, offset + name.len) { ret (offset, true) }
    var at = offset
    while at < source_text.len && (rename_word_byte(source_text, at) || source_text[at] == 46u8) {
        if source_text[at] == 46u8 && at + 1usize + name.len <= source_text.len && graph.same(source_text[at + 1usize..at + 1usize + name.len], name) && !rename_word_byte(source_text, at + 1usize + name.len) { ret (at + 1usize, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn rename_word_byte(source_text: str, at: usize) -> bool {
    if at >= source_text.len { ret false }
    let b = source_text[at]
    let word = (b >= 97u8 && b <= 122u8) || (b >= 65u8 && b <= 90u8) || (b >= 48u8 && b <= 57u8) || b == 95u8
    ret word
}

// The declared field `module.Type.field` names (D420): its global index.
// The error `module.Name` names (D451): the resolver's symbol of kind error.
fn uses_error_subject(c: *check.Checker, g: *graph.Graph, subject: str) -> (usize, bool) {
    var dot = subject.len
    var at = 0usize
    while at < subject.len {
        if subject[at] == 46u8 { dot = at }
        at += 1usize
    }
    if dot == subject.len { ret (0usize, false) }
    let module_name = subject[0usize..dot]
    let name = subject[dot + 1usize..subject.len]
    var symbol_index = 0usize
    while symbol_index < c.resolver.count {
        let symbol = c.resolver.symbols[symbol_index]
        if symbol.kind == .Error && symbol.module_index < g.count && graph.same(g.modules[symbol.module_index].name, module_name) && graph.same(symbol.name, name) { ret (symbol_index, true) }
        symbol_index += 1usize
    }
    ret (0usize, false)
}

fn uses_field_subject(c: *check.Checker, g: *graph.Graph, subject: str) -> (usize, bool) {
    var last_dot = subject.len
    var first_dot = subject.len
    var at = 0usize
    while at < subject.len {
        if subject[at] == 46u8 {
            first_dot = last_dot
            last_dot = at
        }
        at += 1usize
    }
    // Two dots at least: the module may itself be dotted (`e.os.OpenFlags.read`), so
    // the type is between the last two and the module is everything before them.
    if last_dot == subject.len || first_dot == subject.len { ret (0usize, false) }
    let module_name = subject[0usize..first_dot]
    let type_name = subject[first_dot + 1usize..last_dot]
    let field_name = subject[last_dot + 1usize..subject.len]
    let (aggregate_index, has_aggregate) = context_aggregate(c, g, module_name, type_name)
    if !has_aggregate { ret (0usize, false) }
    let aggregate = c.aggregates[aggregate_index]
    var field_at = 0usize
    while field_at < aggregate.field_count {
        if graph.same(c.aggregate_fields[aggregate.first_field + field_at].name, field_name) { ret (aggregate.first_field + field_at, true) }
        field_at += 1usize
    }
    ret (0usize, false)
}

// The uses of a field (D420): every access `x.field` and every literal `{ field: .. }`
// the checker typed, by module then offset, relation `field`.
// The uses the explain table holds of a field (kind 6) or an error (kind 7), by
// module then offset, each a `use` record with the relation named (D420, D451).
fn sites_uses_json(a: *mem.Arena, out: *Out, c: *check.Checker, g: *graph.Graph, explain_kind: u8, index: usize, relation: str) -> err {
    var written = 0usize
    var last = c.explains[0usize]
    var first = true
    let (order, order_error) = explain_order(a, c)
    if order_error != ok { ret order_error }
    var ordered_at = 0usize
    while ordered_at < order.len {
        let e = c.explains[order[ordered_at]]
        ordered_at += 1usize
        if e.kind != explain_kind || e.function_index != index { continue }
        if !first && !explain_before(last, e) { continue }
        first = false
        last = e
        if e.module_index >= g.count { continue }
        let module = g.modules[e.module_index]
        let (root, relative) = source_identity_of(g, module.path)
        let (path, path_error) = manifest_slashes(a, relative)
        if path_error != ok { ret path_error }
        out.lines = module.lines
        var here: lex.Token = zero
        here.start = e.offset
        here.end = e.offset
        try text(out, "{\"record\":\"use\",\"relation\":\"")
        try text(out, relation)
        try text(out, "\",\"provenance\":\"compiler-proved\",\"in\":")
        try quoted_function(out, c, g, enclosing_function(c, e.module_index, e.offset))
        try text(out, ",\"span\":")
        try point_span(out, root, path, module.text, here)
        try byte(out, 125u8)
        try flush(out)
        written += 1usize
    }
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"uses\":")
    try decimal(out, written)
    try text(out, ",\"roots\":0,\"indirect_calls\":0,\"complete\":")
    if !c.explain_overflow { try text(out, "true") } else { try text(out, "false") }
    try text(out, "}}")
    ret flush(out)
}

// The declared function `module.name` names, preferring the concrete one.
fn uses_subject(c: *check.Checker, g: *graph.Graph, subject: str) -> (usize, bool) {
    var dot = subject.len
    var at = 0usize
    while at < subject.len {
        if subject[at] == 46u8 { dot = at }
        at += 1usize
    }
    if dot == subject.len { ret (0usize, false) }
    let module_name = subject[0usize..dot]
    let name = subject[dot + 1usize..subject.len]
    var candidate = 0usize
    while candidate < c.signature_function_count {
        let function = c.functions[candidate]
        if function.module_index < g.count && graph.same(g.modules[function.module_index].name, module_name) && graph.same(function.name, name) { ret (candidate, true) }
        candidate += 1usize
    }
    ret (0usize, false)
}

// The declared function whose source range holds the offset in the module.
fn enclosing_function(c: *check.Checker, module_index: usize, offset: usize) -> usize {
    var at = 0usize
    while at < c.signature_function_count {
        let function = c.functions[at]
        if function.module_index == module_index && offset >= function.source_start && offset < function.source_end { ret at }
        at += 1usize
    }
    ret c.function_count
}

// Whether the declaration at `offset` carries `@name` on the line above it.
fn manifest_has_attribute(text_bytes: str, offset: usize, name: str) -> bool {
    var line_start = offset
    while line_start > 0usize && text_bytes[line_start - 1usize] != 10u8 { line_start = line_start - 1usize }
    if line_start == 0usize { ret false }
    let previous_end = line_start - 1usize
    var previous_start = previous_end
    while previous_start > 0usize && text_bytes[previous_start - 1usize] != 10u8 { previous_start = previous_start - 1usize }
    var at = previous_start
    while at < previous_end && (text_bytes[at] == 32u8 || text_bytes[at] == 9u8) { at += 1usize }
    if at >= previous_end || text_bytes[at] != 64u8 { ret false }
    let word_end = manifest_word_end(text_bytes, at + 1usize)
    ret graph.same(text_bytes[at + 1usize..word_end], name)
}

// The explain table's records in `explain_before`'s order (D539, H16): the indices,
// merge-sorted once, where every writer had scanned the whole table for the record
// after the last written -- quadratic in the sites, fifty-three seconds for the
// compiler's own `explain-file` where the check takes a third of one. Records that
// order equal -- one site decided twice -- are neighbours, and a writer skips a
// record that is not after the one it wrote.
fn explain_order(a: *mem.Arena, c: *check.Checker) -> ([]usize, err) {
    let count = c.explain_count
    let (order, order_error) = mem.alloc[usize](a, count + 1usize)
    if order_error != ok { ret (order, order_error) }
    let (scratch, scratch_error) = mem.alloc[usize](a, count + 1usize)
    if scratch_error != ok { ret (order, scratch_error) }
    var at = 0usize
    while at < count {
        order[at] = at
        at += 1usize
    }
    var width = 1usize
    while width < count {
        var run = 0usize
        while run < count {
            let middle = min_usize(run + width, count)
            let end = min_usize(run + width * 2usize, count)
            var left = run
            var right = middle
            var into = run
            while into < end {
                if left < middle && (right >= end || !explain_index_before(c, order[right], order[left])) {
                    scratch[into] = order[left]
                    left += 1usize
                } else {
                    scratch[into] = order[right]
                    right += 1usize
                }
                into += 1usize
            }
            run = end
        }
        at = 0usize
        while at < count {
            order[at] = scratch[at]
            at += 1usize
        }
        width = width * 2usize
    }
    ret (order[0usize..count], ok)
}

fn min_usize(a: usize, b: usize) -> usize {
    if a < b { ret a }
    ret b
}

// `explain_before` over two records of the table by index, the fields read in
// place: the records are large, and a sort compares millions of pairs.
fn explain_index_before(c: *check.Checker, i: usize, j: usize) -> bool {
    if c.explains[i].module_index != c.explains[j].module_index { ret c.explains[i].module_index < c.explains[j].module_index }
    if c.explains[i].offset != c.explains[j].offset { ret c.explains[i].offset < c.explains[j].offset }
    if c.explains[i].kind != c.explains[j].kind { ret c.explains[i].kind < c.explains[j].kind }
    if c.explains[i].first_argument != c.explains[j].first_argument { ret c.explains[i].first_argument < c.explains[j].first_argument }
    if c.explains[i].template_index != c.explains[j].template_index { ret c.explains[i].template_index < c.explains[j].template_index }
    if c.explains[i].function_index != c.explains[j].function_index { ret c.explains[i].function_index < c.explains[j].function_index }
    if c.explains[i].found != c.explains[j].found { ret !c.explains[i].found }
    if c.explains[i].receiver.module_index != c.explains[j].receiver.module_index { ret c.explains[i].receiver.module_index < c.explains[j].receiver.module_index }
    ret text_before(c.explains[i].receiver.name, c.explains[j].receiver.name)
}

fn explain_before(a: check.Explain, b: check.Explain) -> bool {
    if a.module_index != b.module_index { ret a.module_index < b.module_index }
    if a.offset != b.offset { ret a.offset < b.offset }
    if a.kind != b.kind { ret a.kind < b.kind }
    if a.first_argument != b.first_argument { ret a.first_argument < b.first_argument }
    if a.template_index != b.template_index { ret a.template_index < b.template_index }
    if a.function_index != b.function_index { ret a.function_index < b.function_index }
    // A template's settled `if` may fold each way in different instances (D463).
    if a.found != b.found { ret !a.found }
    if a.receiver.module_index != b.receiver.module_index { ret a.receiver.module_index < b.receiver.module_index }
    ret text_before(a.receiver.name, b.receiver.name)
}

fn text_before(a: str, b: str) -> bool {
    var at = 0usize
    while at < a.len && at < b.len {
        if a[at] != b[at] { ret a[at] < b[at] }
        at += 1usize
    }
    ret a.len < b.len
}

fn manifest_slashes(a: *mem.Arena, relative: str) -> (str, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, relative.len + 1usize)
    if buffer_error != ok { ret ("", buffer_error) }
    var at = 0usize
    while at < relative.len {
        var c = relative[at]
        if c == 92u8 { c = 47u8 }
        buffer[at] = c
        at += 1usize
    }
    ret (buffer[0usize..relative.len], ok)
}

// A type as a program spells it: `module.Name`, `*T`, `[]T`, `[N]T`, or the scalar.
fn quoted_type(out: *Out, c: *check.Checker, g: *graph.Graph, ty: check.Type) -> err {
    try byte(out, 34u8)
    try type_text(out, c, g, ty, 0usize)
    ret byte(out, 34u8)
}

fn type_text(out: *Out, c: *check.Checker, g: *graph.Graph, ty: check.Type, depth: usize) -> err {
    if depth > 8usize { ret text(out, "?") }
    if ty.kind == .Named || ty.kind == .Tag {
        if ty.module_index < g.count {
            try text(out, g.modules[ty.module_index].name)
            try byte(out, 46u8)
        }
        ret text(out, ty.name)
    }
    if ty.kind == .Pointer {
        try byte(out, 42u8)
        if ty.is_const { try text(out, "const ") }
        if ty.has_element && ty.element < c.type_count { ret type_text(out, c, g, c.types[ty.element], depth + 1usize) }
        ret text(out, "?")
    }
    if ty.kind == .Slice {
        try text(out, "[]")
        if ty.is_const { try text(out, "const ") }
        if ty.has_element && ty.element < c.type_count { ret type_text(out, c, g, c.types[ty.element], depth + 1usize) }
        ret text(out, "?")
    }
    if ty.kind == .Array {
        try byte(out, 91u8)
        try decimal(out, ty.array_length)
        try byte(out, 93u8)
        if ty.has_element && ty.element < c.type_count { ret type_text(out, c, g, c.types[ty.element], depth + 1usize) }
        ret text(out, "?")
    }
    if ty.kind == .String { ret text(out, "str") }
    if ty.kind == .Err { ret text(out, "err") }
    if ty.kind == .Bool { ret text(out, "bool") }
    if ty.kind == .Void { ret text(out, "void") }
    if ty.kind == .Function { ret text(out, "fn") }
    if ty.kind == .TypeParameter { ret text(out, "?") }
    ret text(out, ty.name)
}

// A type's name between backquotes inside a JSON string (D430): the spelling
// `quoted_type` gives, without its quotes.
fn quoted_type_inner(out: *Out, c: *check.Checker, g: *graph.Graph, ty: check.Type) -> err {
    try byte(out, 96u8)
    try type_text(out, c, g, ty, 0usize)
    ret byte(out, 96u8)
}

fn quoted_function(out: *Out, c: *check.Checker, g: *graph.Graph, function_index: usize) -> err {
    try byte(out, 34u8)
    if function_index < c.function_count {
        let function = c.functions[function_index]
        if function.module_index < g.count {
            try text(out, g.modules[function.module_index].name)
            try byte(out, 46u8)
        }
        try text(out, function.name)
    }
    ret byte(out, 34u8)
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
// A module's interface digest (D265): from its tokens when it has them, else scanned;
// and a module that already carries its digests -- computed once, or read from its
// artifact (D323) -- answers from them.
fn manifest_interface_sha256(a: *mem.Arena, g: *graph.Graph, module_index: usize) -> (str, err) {
    if g.modules[module_index].interface_sha256.len != 0usize { ret (g.modules[module_index].interface_sha256, ok) }
    if g.modules[module_index].tokens.len != 0usize {
        let (digest, digest_error) = artifact_hash.interface_sha256_hex(a, g.modules[module_index].text, g.modules[module_index].tokens)
        ret (digest, digest_error)
    }
    let (scanned, scanned_error) = artifact_hash.interface_sha256_hex_scanned(a, g.modules[module_index].text)
    ret (scanned, scanned_error)
}

fn manifest_source_sha256(a: *mem.Arena, g: *graph.Graph, module_index: usize) -> (str, err) {
    if g.modules[module_index].sha256.len != 0usize { ret (g.modules[module_index].sha256, ok) }
    let (digest, digest_error) = manifest_sha256(a, g.modules[module_index].text)
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
    var out: Out = zero
    out.bytes = storage
    var no_reasons: []u8 = zero
    let build_error = manifest_write(a, &out, arch, os_name, g, "debug", false, "", "", no_reasons)
    if build_error != ok { ret (2usize, build_error) }
    let flush_error = flush(&out)
    if flush_error != ok { ret (2usize, flush_error) }
    ret (0usize, ok)
}

fn artifact_text(bytes: []const u8, index: usize) -> (str, err) {
    let (start, length, bounds_error) = em.string_bounds(bytes, index)
    if bounds_error != ok { ret ("", bounds_error) }
    ret (bytes[start..start + length], ok)
}

// A canonical build manifest over artifacts alone (D557, H27). An artifact's
// required Inventory section already contains the exact unsafe records a source
// build writes, so this view copies them without source, parsing or checking.
fn artifact_manifest_json(a: *mem.Arena, paths: []str, artifacts: [][]const u8) -> err {
    if artifacts.len == 0usize || paths.len != artifacts.len { ret em.InvalidArtifact }
    let (target_index, target_index_error) = em.artifact_target_index(artifacts[0usize])
    if target_index_error != ok { ret target_index_error }
    let (target_name, target_name_error) = artifact_text(artifacts[0usize], target_index)
    if target_name_error != ok { ret target_name_error }
    let (root_index, root_index_error) = em.interface_module_index(artifacts[0usize])
    if root_index_error != ok { ret root_index_error }
    let (root_name, root_name_error) = artifact_text(artifacts[0usize], root_index)
    if root_name_error != ok { ret root_name_error }
    let (mode, mode_error) = em.artifact_mode(artifacts[0usize])
    if mode_error != ok || mode > 2usize { ret em.InvalidArtifact }
    var capacity = 65536usize + paths.len * 512usize
    var scan = 0usize
    while scan < artifacts.len {
        let (each_target_index, each_target_index_error) = em.artifact_target_index(artifacts[scan])
        if each_target_index_error != ok { ret each_target_index_error }
        let (each_target, each_target_error) = artifact_text(artifacts[scan], each_target_index)
        if each_target_error != ok || !graph.same(each_target, target_name) { ret em.InvalidArtifact }
        let (each_mode, each_mode_error) = em.artifact_mode(artifacts[scan])
        if each_mode_error != ok || each_mode != mode { ret em.InvalidArtifact }
        let (inventory, inventory_count, inventory_found, inventory_error) = em.artifact_inventory(artifacts[scan])
        if inventory_error != ok || !inventory_found { ret em.InvalidArtifact }
        capacity += inventory.len + paths[scan].len * 2usize + inventory_count * 8usize
        scan += 1usize
    }
    let (storage, storage_error) = mem.alloc[u8](a, capacity)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    try text(&out, "{\"schema\":\"neper-build-manifest\",\"version\":1,\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":3,\"target\":")
    try quoted(&out, target_name)
    try text(&out, ",\"mode\":\"")
    if mode == 0usize { try text(&out, "debug") } else { try text(&out, "release") }
    try text(&out, "\",\"root_module\":")
    try quoted(&out, root_name)
    try text(&out, ",\"inputs\":[],\"dependencies\":[],\"libraries\":[],\"assets\":[],\"artifacts\":[")
    var at = 0usize
    while at < artifacts.len {
        if at != 0usize { try byte(&out, 44u8) }
        try text(&out, "{\"path\":")
        try quoted(&out, paths[at])
        try text(&out, ",\"kind\":\"module\",\"target\":")
        try quoted(&out, target_name)
        try text(&out, ",\"sha256\":")
        let checkpoint = mem.mark(a)
        let (digest, digest_error) = artifact_hash.sha256_hex(a, artifacts[at])
        if digest_error != ok { ret digest_error }
        try quoted(&out, digest)
        mem.reset(a, checkpoint)
        try byte(&out, 125u8)
        at += 1usize
    }
    try text(&out, "],\"unsafe\":[")
    var written = 0usize
    at = 0usize
    while at < artifacts.len {
        let (inventory, inventory_count, inventory_found, inventory_error) = em.artifact_inventory(artifacts[at])
        if inventory_error != ok || !inventory_found { ret em.InvalidArtifact }
        if inventory_count != 0usize {
            if written != 0usize { try byte(&out, 44u8) }
            try text(&out, inventory)
            written += inventory_count
        }
        at += 1usize
    }
    try text(&out, "],\"incremental\":[],\"options\":{\"checks\":\"")
    if mode == 2usize { try text(&out, "off") } else { try text(&out, "retained") }
    try text(&out, "\"},\"work\":{\"bodies_checked\":0,\"modules_lowered\":0,\"functions_lowered\":0,\"declarations_checked\":0}}")
    ret flush(&out)
}

// The object, into `out`, without a newline: the command flushes it as a record and a
// build saves it as a file. An empty `artifact_path` is no artifact.
// The unsafe sites of one module (D355, D371, D457): the module's bytes scanned for
// `@unsafe`, `@nocheck`, `extern fn`, `mem.cast`, `mem.bitcast` and a bare `union`,
// each a record of the manifest's `unsafe` array after the `written` ones.
fn manifest_module_sites(out: *Out, written: *usize, module_name: str, text_bytes_in: str, lines_in: []usize, openers: []const u8) -> err {
    // An `@` first on its line (after spaces) opens an attribute or a `@nocheck`
    // statement; one inside a comment or a string has `//` or `"` before it on
    // the line. The bytes are scanned, not the tokens: a lex of every module
    // cost fifty milliseconds on the compiler's own build, this costs two.
    let text_bytes = text_bytes_in
    let lines = lines_in
    // A kept module has no line table (it was never scanned), and `line_of` would
    // count from the start at every site: a cursor counts each byte once (D389).
    var line_cursor_at = 0usize
    var line_cursor = 1usize
    var byte_at = 0usize
    while byte_at < text_bytes.len {
        // One load per byte (D383): the loop is the D356 shape, so it carries no check.
        let opener = text_bytes[byte_at]
        let opener_class = openers[usize(opener)]
        if opener_class == 0u8 {
            byte_at += 1usize
            continue
        }
        if opener_class == 1u8 && manifest_line_opens(text_bytes, byte_at) {
            let word_end = manifest_word_end(text_bytes, byte_at + 1usize)
            let word = text_bytes[byte_at + 1usize..word_end]
            if graph.same(word, "unsafe") || graph.same(word, "nocheck") {
                while line_cursor_at < byte_at {
                    if text_bytes[line_cursor_at] == 10u8 { line_cursor += 1usize }
                    line_cursor_at += 1usize
                }
                let line = line_cursor
                var function = ""
                if graph.same(word, "unsafe") {
                    // The next `fn` after the attribute.
                    let (name, found) = manifest_fn_after(text_bytes, word_end)
                    if found { function = name }
                    try manifest_unsafe_site(out, *written, "unsafe", "declared", module_name, function, line)
                } else {
                    // The last `fn` before the block.
                    let (name, found) = manifest_fn_before(text_bytes, byte_at)
                    if found { function = name }
                    try manifest_unsafe_site(out, *written, "nocheck", "declared", module_name, function, line)
                    *written += 1usize
                    // The block's raw dereferences (D497, H27): every `*p` inside it is
                    // read with no null check, and each is a `deref` site of its own.
                    try manifest_nocheck_derefs(out, written, module_name, function, text_bytes, word_end, line)
                    byte_at = word_end
                    continue
                }
                *written += 1usize
            }
            byte_at = word_end
        } else {
            // The escape hatches the program does not declare (D371, H27): an
            // `extern fn`, a `mem.cast`, a `mem.bitcast`, a bare `union` -- each a
            // site the checker trusts and checks nothing at, listed as `trusted`.
            // Only an `e`, `m` or `u` can open a site: the call per byte cost 115 ms
            // on the 500k-line workload (D383).
            var site_end = 0usize
            var kind = ""
            var function = ""
            var candidate = false
            if opener_class == 2u8 {
                if opener == 101u8 && (byte_at == 0usize || text_bytes[byte_at - 1usize] == 10u8) { candidate = true }
                if opener == 109u8 && byte_at + 1usize < text_bytes.len && text_bytes[byte_at + 1usize] == 101u8 { candidate = true }
                if opener == 117u8 && byte_at >= 2usize && text_bytes[byte_at - 1usize] == 32u8 && text_bytes[byte_at - 2usize] == 61u8 { candidate = true }
            }
            if candidate {
                let (site_kind, site_function, found_end) = manifest_trusted_site(text_bytes, byte_at)
                kind = site_kind
                function = site_function
                site_end = found_end
            }
            if site_end != 0usize {
                while line_cursor_at < byte_at {
                    if text_bytes[line_cursor_at] == 10u8 { line_cursor += 1usize }
                    line_cursor_at += 1usize
                }
                try manifest_unsafe_site(out, *written, kind, "trusted", module_name, function, line_cursor)
                *written += 1usize
                byte_at = site_end
            } else {
                byte_at += 1usize
            }
        }
    }
    ret ok
}

// The raw dereferences of a `@nocheck` block (D497, H27): from the block's `{` to
// its `}`, a `*` that begins a dereference -- one followed by a name or a `(`, and
// not after a `:`, a `[` or a `->`, which begin a pointer type -- is a site with no
// null check, listed as `deref` under the block's function. A `*` with a space
// after it is a product. Strings and comments inside the block are skipped.
// ponytail: a byte scan over the block, as the other sites are (D371); the checker's
// own record of a skipped null check would need the lowering, which
// `build-manifest-file` does not run.
fn manifest_nocheck_derefs(out: *Out, written: *usize, module_name: str, function: str, text_bytes: str, from: usize, line_in: usize) -> err {
    var at = from
    while at < text_bytes.len && text_bytes[at] != 123u8 { at += 1usize }
    if at == text_bytes.len { ret ok }
    var line = line_in
    var line_at = from
    var depth = 0usize
    while at < text_bytes.len {
        let here = text_bytes[at]
        if here == 10u8 {
            at += 1usize
            continue
        }
        if here == 34u8 {
            // A string: to its closing quote, an escaped one skipped.
            at += 1usize
            while at < text_bytes.len && text_bytes[at] != 34u8 && text_bytes[at] != 10u8 {
                if text_bytes[at] == 92u8 { at += 1usize }
                at += 1usize
            }
            at += 1usize
            continue
        }
        if here == 47u8 && at + 1usize < text_bytes.len && text_bytes[at + 1usize] == 47u8 {
            while at < text_bytes.len && text_bytes[at] != 10u8 { at += 1usize }
            continue
        }
        if here == 123u8 { depth += 1usize }
        if here == 125u8 {
            depth = depth - 1usize
            if depth == 0usize { ret ok }
        }
        if here == 42u8 && at + 1usize < text_bytes.len {
            let next = text_bytes[at + 1usize]
            let starts_name = (next >= 97u8 && next <= 122u8) || (next >= 65u8 && next <= 90u8) || next == 95u8 || next == 40u8
            var before = at
            while before > 0usize && text_bytes[before - 1usize] == 32u8 { before = before - 1usize }
            var type_position = false
            if before > 0usize {
                let previous = text_bytes[before - 1usize]
                if previous == 58u8 || previous == 91u8 { type_position = true }
                if previous == 62u8 && before > 1usize && text_bytes[before - 2usize] == 45u8 { type_position = true }
            }
            if starts_name && !type_position {
                while line_at < at {
                    if text_bytes[line_at] == 10u8 { line += 1usize }
                    line_at += 1usize
                }
                try manifest_unsafe_site(out, *written, "deref", "declared", module_name, function, line)
                *written += 1usize
            }
        }
        at += 1usize
    }
    ret ok
}

// The inventory of one module as its artifact carries it (D457): the records the
// manifest would write for it, rendered once when the artifact is written, and
// their count -- so a warm build copies bytes for every kept module and scans only
// what it parsed.
fn module_inventory(a: *mem.Arena, module_name: str, text_bytes: str, lines: []usize) -> ([]u8, usize, err) {
    var none: []u8 = zero
    let (storage, storage_error) = mem.alloc[u8](a, 4096usize + text_bytes.len / 4usize)
    if storage_error != ok { ret (none, 0usize, storage_error) }
    var out: Out = zero
    out.bytes = storage
    var openers: [256]u8 = zero
    openers[64usize] = 1u8
    openers[101usize] = 2u8
    openers[109usize] = 2u8
    openers[117usize] = 2u8
    var written = 0usize
    let sites_error = manifest_module_sites(&out, &written, module_name, text_bytes, lines, openers[..])
    if sites_error != ok { ret (none, 0usize, sites_error) }
    ret (storage[0usize..out.count], written, ok)
}

fn manifest_write(a: *mem.Arena, out: *Out, arch: str, os_name: str, g: *graph.Graph, mode: str, unchecked: bool, artifact_path: str, artifact_sha256: str, reasons: []u8) -> err {
    try text(out, "{\"schema\":\"neper-build-manifest\",\"version\":1,\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":3,\"target\":\"")
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
    // A source's digest is hashed once and named twice (D320): as the input's `sha256`
    // and as the dependency's `body_sha256`, which is the same text.
    let (digests, digests_error) = mem.alloc[str](a, g.count + 1usize)
    if digests_error != ok { ret digests_error }
    var at = 0usize
    while at < g.count {
        if at != 0usize { try byte(out, 44u8) }
        try text(out, "{\"source\":")
        try manifest_source(out, g, g.modules[at].path)
        try text(out, ",\"sha256\":")
        let (digest, digest_error) = manifest_source_sha256(a, g, at)
        if digest_error != ok { ret digest_error }
        digests[at] = digest
        try quoted(out, digest)
        try byte(out, 125u8)
        at += 1usize
    }
    // The operand's source map (D467, H19): an input of the build when it is beside
    // the operand, hashed like the sources, so a map-only change shows in the
    // manifest while the code's identity -- the artifacts', the executable's -- is
    // untouched, which is the H19 rule. The maps of other modules the compiler
    // never reads, and they are not listed.
    if g.count != 0usize {
        let (map_path, map_path_error) = path_with_suffix(a, g.modules[0usize].path, ".map.json")
        if map_path_error != ok { ret map_path_error }
        let (map_text, map_error) = graph.load_file(a, map_path)
        if map_error == ok {
            try text(out, ",{\"source\":")
            try manifest_source(out, g, map_path)
            try text(out, ",\"sha256\":")
            let (map_digest, map_digest_error) = manifest_sha256(a, map_text)
            if map_digest_error != ok { ret map_digest_error }
            try quoted(out, map_digest)
            try text(out, ",\"kind\":\"source-map\"}")
        }
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
        let (interface_digest, interface_error) = manifest_interface_sha256(a, g, at)
        if interface_error != ok { ret interface_error }
        try quoted(out, interface_digest)
        try text(out, ",\"body_sha256\":")
        try quoted(out, digests[at])
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
    // The unsafe boundaries (D355, H03/H27): every `@unsafe` function and `@nocheck`
    // block in every module of the program, read off the tokens -- a warm build
    // checks no body, and the inventory has to be whole either way -- in module
    // then line order; and `checks`, the policy the image was built under: every
    // row of section 11's table retained in both modes.
    try text(out, "],\"unsafe\":[")
    var written = 0usize
    // The bytes that can open a site (D383): `@`, and the `e`, `m`, `u` of `extern`,
    // `mem.` and `union`. One table load per byte, unchecked by the width proof
    // (D384), and every other byte costs the loop alone.
    var openers: [256]u8 = zero
    openers[64usize] = 1u8
    openers[101usize] = 2u8
    openers[109usize] = 2u8
    openers[117usize] = 2u8
    var module_at = 0usize
    while module_at < g.count {
        // A kept module's inventory rides in its artifact (D457): copied, not scanned.
        if g.modules[module_at].inventory_known {
            if g.modules[module_at].inventory_count != 0usize {
                if written != 0usize { try byte(out, 44u8) }
                try text(out, g.modules[module_at].inventory)
                written += g.modules[module_at].inventory_count
            }
        } else {
            try manifest_module_sites(out, &written, g.modules[module_at].name, g.modules[module_at].text, g.modules[module_at].lines, openers[..])
        }
        module_at += 1usize
    }
    // What an incremental build kept and rebuilt, and why (D363, H14): one entry per
    // module in graph order, or none for a build that read no artifact.
    try text(out, "],\"incremental\":[")
    var reason_at = 0usize
    while reason_at < reasons.len && reason_at < g.count {
        if reason_at != 0usize { try byte(out, 44u8) }
        try text(out, "{\"module\":")
        try quoted(out, g.modules[reason_at].name)
        let reason = reasons[reason_at]
        if reason == 3u8 || reason == 4u8 { try text(out, ",\"decision\":\"kept\",\"reason\":") } else { try text(out, ",\"decision\":\"rebuilt\",\"reason\":") }
        if reason == 0u8 { try text(out, "\"no-artifact\"") }
        if reason == 1u8 { try text(out, "\"source-changed\"") }
        if reason == 2u8 { try text(out, "\"mode-changed\"") }
        if reason == 3u8 { try text(out, "\"stable\"") }
        if reason == 4u8 { try text(out, "\"edges-hold\"") }
        if reason == 5u8 { try text(out, "\"edge-changed\"") }
        if reason == 6u8 { try text(out, "\"invalid-artifact\"") }
        if reason == 7u8 { try text(out, "\"compiler-changed\"") }
        if reason == 8u8 { try text(out, "\"options-changed\"") }
        // The artifact's checksum (D473, H24): what the next warm build checks the
        // file against, so a cache is whole as a set or rebuilt.
        if g.modules[reason_at].artifact_hash_known {
            try text(out, ",\"artifact_crc32c\":\"")
            try hex32(out, g.modules[reason_at].artifact_hash)
            try byte(out, 34u8)
        }
        try byte(out, 125u8)
        reason_at += 1usize
    }
    if unchecked { try text(out, "],\"options\":{\"checks\":\"off\"}") } else { try text(out, "],\"options\":{\"checks\":\"retained\"}") }
    // What the build did rather than kept (D405, H14): a warm build over a stable
    // cache checks no body and lowers nothing, and the manifest says so.
    try text(out, ",\"work\":{\"bodies_checked\":")
    try decimal(out, g.work_bodies_checked)
    try text(out, ",\"modules_lowered\":")
    try decimal(out, g.work_modules_lowered)
    try text(out, ",\"functions_lowered\":")
    try decimal(out, g.work_functions_lowered)
    // The declarations rechecked (D446, H14): the seeded surface and the parsed
    // modules' -- a warm build over a stable cache holds the seeds alone.
    try text(out, ",\"declarations_checked\":")
    try decimal(out, g.work_declarations_checked)
    ret text(out, "}}")
}

// Whether only spaces lie between the line's start and `at`.
fn manifest_line_opens(text_bytes: str, at: usize) -> bool {
    var back = at
    while back > 0usize {
        let b = text_bytes[back - 1usize]
        if b == 10u8 { ret true }
        if b != 32u8 && b != 9u8 { ret false }
        back = back - 1usize
    }
    ret true
}

fn manifest_word_end(text_bytes: str, from: usize) -> usize {
    var at = from
    while at < text_bytes.len && ((text_bytes[at] >= 97u8 && text_bytes[at] <= 122u8) || (text_bytes[at] >= 65u8 && text_bytes[at] <= 90u8) || (text_bytes[at] >= 48u8 && text_bytes[at] <= 57u8) || text_bytes[at] == 95u8) { at += 1usize }
    ret at
}

// The name of the first `fn` at a line's start after `from`.
fn manifest_fn_after(text_bytes: str, from: usize) -> (str, bool) {
    var at = from
    while at + 3usize <= text_bytes.len {
        if text_bytes[at] == 102u8 && text_bytes[at + 1usize] == 110u8 && text_bytes[at + 2usize] == 32u8 && (at == 0usize || text_bytes[at - 1usize] == 10u8) {
            ret (text_bytes[at + 3usize..manifest_word_end(text_bytes, at + 3usize)], true)
        }
        at += 1usize
    }
    ret ("", false)
}

// The name of the last `fn` at a line's start before `at`.
fn manifest_fn_before(text_bytes: str, at: usize) -> (str, bool) {
    var back = at
    while back >= 3usize {
        back = back - 1usize
        if text_bytes[back] == 102u8 && back + 2usize < text_bytes.len && text_bytes[back + 1usize] == 110u8 && text_bytes[back + 2usize] == 32u8 && (back == 0usize || text_bytes[back - 1usize] == 10u8) {
            ret (text_bytes[back + 3usize..manifest_word_end(text_bytes, back + 3usize)], true)
        }
    }
    ret ("", false)
}

// An undeclared escape hatch at `at`, or an end of zero: `extern fn NAME` first on its
// line; `mem.cast[` and `mem.bitcast[` in code (not in a comment or a string, not part
// of a longer name), attributed to the last `fn` before; a bare `union {` after `=`
// on a `type` line, attributed to the type. A raw dereference is not a site the bytes
// can find: it is `*` before a name, as a multiplication is.
fn manifest_trusted_site(text_bytes: str, at: usize) -> (str, str, usize) {
    let b = text_bytes[at]
    if b == 101u8 && manifest_starts(text_bytes, at, "extern fn ") && manifest_line_opens(text_bytes, at) {
        let name_end = manifest_word_end(text_bytes, at + 10usize)
        ret ("extern", text_bytes[at + 10usize..name_end], name_end)
    }
    // The prefix tests first (D383): a back-scan of the line for every word-initial
    // `m` cost the manifest 135 ms on the 500k-line workload.
    if b == 109u8 && manifest_starts(text_bytes, at, "mem.") && (at == 0usize || !manifest_word_byte(text_bytes[at - 1usize])) && manifest_in_code(text_bytes, at) {
        if manifest_starts(text_bytes, at, "mem.cast[") {
            let (name, found) = manifest_fn_before(text_bytes, at)
            var function = ""
            if found { function = name }
            ret ("cast", function, at + 9usize)
        }
        if manifest_starts(text_bytes, at, "mem.bitcast[") {
            let (name, found) = manifest_fn_before(text_bytes, at)
            var function = ""
            if found { function = name }
            ret ("bitcast", function, at + 12usize)
        }
    }
    if b == 117u8 && manifest_starts(text_bytes, at, "union {") && at >= 2usize && text_bytes[at - 1usize] == 32u8 && text_bytes[at - 2usize] == 61u8 && manifest_in_code(text_bytes, at) {
        // `type NAME = union {`, or `resource union {` under a `type` line.
        var line_start = at
        while line_start > 0usize && text_bytes[line_start - 1usize] != 10u8 { line_start = line_start - 1usize }
        var name = ""
        if manifest_starts(text_bytes, line_start, "type ") { name = text_bytes[line_start + 5usize..manifest_word_end(text_bytes, line_start + 5usize)] }
        ret ("union", name, at + 7usize)
    }
    ret ("", "", 0usize)
}

fn manifest_starts(text_bytes: str, at: usize, prefix: str) -> bool {
    if at + prefix.len > text_bytes.len { ret false }
    ret graph.same(text_bytes[at..at + prefix.len], prefix)
}

fn manifest_word_byte(b: u8) -> bool {
    let word = (b >= 97u8 && b <= 122u8) || (b >= 65u8 && b <= 90u8) || (b >= 48u8 && b <= 57u8) || b == 95u8 || b == 46u8
    ret word
}

// Whether `at` is in code on its line: not after a `//`, not inside a string literal.
fn manifest_in_code(text_bytes: str, at: usize) -> bool {
    var line_start = at
    while line_start > 0usize && text_bytes[line_start - 1usize] != 10u8 { line_start = line_start - 1usize }
    var scan = line_start
    var in_string = false
    while scan < at {
        let c = text_bytes[scan]
        if in_string {
            if c == 92u8 { scan += 1usize } else {
                if c == 34u8 { in_string = false }
            }
        } else {
            if c == 34u8 { in_string = true }
            if c == 47u8 && scan + 1usize < at && text_bytes[scan + 1usize] == 47u8 { ret false }
        }
        scan += 1usize
    }
    ret !in_string
}

fn manifest_unsafe_site(out: *Out, written: usize, kind: str, provenance: str, module_name: str, function: str, line: usize) -> err {
    if written != 0usize { try byte(out, 44u8) }
    try text(out, "{\"kind\":")
    try quoted(out, kind)
    try text(out, ",\"provenance\":")
    try quoted(out, provenance)
    try text(out, ",\"module\":")
    try quoted(out, module_name)
    try text(out, ",\"function\":")
    try quoted(out, function)
    try text(out, ",\"line\":")
    try decimal(out, line)
    ret byte(out, 125u8)
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

fn manifest_file(a: *mem.Arena, g: *graph.Graph, arch: str, os_name: str, release_mode: bool, unchecked: bool, artifact_path: str, packed: []const u8, reasons: []u8) -> err {
    var mode = "debug"
    if release_mode { mode = "release" }
    let (dot_dir, dot_error) = manifest_join(a, g.project.root, ".neper")
    if dot_error != ok { ret dot_error }
    let (mode_dir, mode_error) = manifest_join(a, dot_dir, mode)
    if mode_error != ok { ret mode_error }
    let (manifest_path, path_error) = manifest_join(a, mode_dir, "build-manifest.json")
    if path_error != ok { ret path_error }
    let flags = os.OpenFlags { read: false, write: true, create: true, truncate: true, append: false }
    let (digest, digest_error) = manifest_sha256(a, packed)
    if digest_error != ok { ret digest_error }
    let (storage, storage_error) = mem.alloc[u8](a, 65536usize + g.count * 512usize)
    if storage_error != ok { ret storage_error }
    var out: Out = zero
    out.bytes = storage
    let (relative_path, relative_error) = manifest_artifact_path(a, g.project.root, artifact_path)
    if relative_error != ok { ret relative_error }
    try manifest_write(a, &out, arch, os_name, g, mode, unchecked, relative_path, digest, reasons)
    try byte(&out, 10u8)
    // The file is opened once the text is ready (D345): every exit before this has
    // nothing to close.
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
    var out: Out = zero
    let (out_lines, out_lines_error) = lex.line_starts(a, source)
    if out_lines_error != ok { ret out_lines_error }
    out.lines = out_lines
    out.bytes = storage
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
            var no_graph: graph.Graph = zero
            var no_functions: []const check.Function = zero
            try trap_json(out, &no_graph, no_functions, stderr_bytes, module_name, path, source, spelled, 2usize)
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
        var no_graph_either: graph.Graph = zero
        var no_functions_either: []const check.Function = zero
        try trap_json(out, &no_graph_either, no_functions_either, stderr_bytes, module_name, path, source, spelled, 2usize)
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
            let d4 = token_span(out, root, path, source, token, token)
            if d4 != ok { ret (2usize, d4) }
            let d5 = text(out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
            if d5 != ok { ret (2usize, d5) }
            let d6 = flush(out)
            if d6 != ok { ret (2usize, d6) }
            diagnostics += 1usize
        }
        let record_error = token_record(out, root, path, source, tokens, token, index)
        if record_error != ok { ret (2usize, record_error) }
        index += 1usize
    }
    if diagnostics != 0usize { ret (1usize, ok) }
    ret (0usize, ok)
}

fn token_record(out: *Out, root: str, path: str, source: str, tokens: []const lex.Token, token: lex.Token, index: usize) -> err {
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
    try token_span(out, root, path, source, token, token)
    try text(out, ",\"leading_trivia\":[")
    var trivia_scanner = lex.trivia_init(source, out.lines, lex.leading_start(tokens, index), token)
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
    var out: Out = zero
    let (out_lines, out_lines_error) = lex.line_starts(a, source)
    if out_lines_error != ok { ret (0usize, out_lines_error) }
    out.lines = out_lines
    out.bytes = storage
    out.absolute = absolute
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
fn syntax_node(out: *Out, tree: *parse.Tree, source: str, tokens: []const lex.Token, node_index: usize, root: str, path: str, depth: usize) -> err {
    if depth > 512usize { ret Capacity }
    let node = tree.nodes[node_index]
    try text(out, "{\"kind\":")
    try quoted(out, node_kind_name(node.kind))
    try text(out, ",\"span\":")
    if usize(node.token_end) > usize(node.token_start) && usize(node.token_end) <= tokens.len {
        let first = tokens[usize(node.token_start)]
        let last = tokens[usize(node.token_end) - 1usize]
        try token_span(out, root, path, source, first, last)
    } else {
        var at_token = usize(node.token_start)
        if at_token >= tokens.len { at_token = tokens.len - 1usize }
        let here = tokens[at_token]
        try point_span(out, root, path, source, here)
    }
    try text(out, ",\"token_start\":")
    try decimal(out, usize(node.token_start))
    try text(out, ",\"token_end\":")
    try decimal(out, usize(node.token_end))
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
                try syntax_node(out, tree, source, tokens, top, root, path, depth + 1usize)
                try byte(out, 125u8)
            }
            top += 1usize
        }
    } else {
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if !first_child { try byte(out, 44u8) }
            first_child = false
            let child = parse.child_at(tree, at)
            if child.node {
                try text(out, "{\"node\":")
                try syntax_node(out, tree, source, tokens, child.index, root, path, depth + 1usize)
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
    var out: Out = zero
    let (out_lines, out_lines_error) = lex.line_starts(a, source)
    if out_lines_error != ok { ret (0usize, out_lines_error) }
    out.lines = out_lines
    out.bytes = storage
    out.absolute = absolute
    let header_error = header(&out, "parse")
    if header_error != ok { ret (2usize, header_error) }
    let (tokens, count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    var diagnostics = invalid
    let (token_exit, token_records_error) = token_records(&out, root, path, source, tokens[..count])
    if token_records_error != ok { ret (2usize, token_records_error) }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, count + 16usize)
    if nodes_error != ok { ret (2usize, nodes_error) }
    let (children, children_error) = mem.alloc[u32](a, count * 2usize + 16usize)
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
                let b6 = decimal(&out, lex.line_of(source, out.lines, keyword.start))
                if b6 != ok { ret (2usize, b6) }
                let b7 = text(&out, "\",\"span\":")
                if b7 != ok { ret (2usize, b7) }
            } else {
                let d1 = text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-SYNTAX-9999\",\"message\":\"unexpected token\",\"span\":")
                if d1 != ok { ret (2usize, d1) }
            }
            let d2 = token_span(&out, root, path, source, at, at)
            if d2 != ok { ret (2usize, d2) }
            let d3 = text(&out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
            if d3 != ok { ret (2usize, d3) }
            let d4 = flush(&out)
            if d4 != ok { ret (2usize, d4) }
            failure += 1usize
        }
    }
    // The tree can outgrow the record buffer the tokens used: one sized to it.
    let (tree_storage, tree_storage_error) = mem.alloc[u8](a, tree.count * 512usize + usize(tree.child_count) * 32usize + 4096usize)
    if tree_storage_error != ok { ret (2usize, tree_storage_error) }
    var tree_out: Out = zero
    let (tree_out_lines, tree_out_lines_error) = lex.line_starts(a, source)
    if tree_out_lines_error != ok { ret (0usize, tree_out_lines_error) }
    tree_out.lines = tree_out_lines
    tree_out.bytes = tree_storage
    tree_out.absolute = absolute
    let s1 = text(&tree_out, "{\"record\":\"syntax\",\"root\":")
    if s1 != ok { ret (2usize, s1) }
    let s2 = syntax_node(&tree_out, &tree, source, tokens[..count], 0usize, root, path, 0usize)
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
