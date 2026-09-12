// Structured logging: a `Logger` is its sinks and a minimum level, `write` stamps a
// record with the wall clock and hands it to every sink in turn, stopping at the
// first sink that fails. `console_sink` prints one line per record to an `os.File` --
// the ISO 8601 timestamp, the level, the message and `name=value` fields, a
// backtrace's addresses after it -- and `jsonl_sink` one JSON object per line with
// the same content under `time`, `level`, `message`, `fields` and `frames`. An `err`
// field prints as `ok` or `error`, since an error has no name at run time yet. The
// caller owns every string until `write` returns, and there is no global logger.
use e.debug
use e.io
use e.mem
use e.os
use e.str
use e.time

type Level = enum u8 { Trace, Debug, Info, Warn, Error }
type Value = union enum u8 { Bool: bool, I64: i64, U64: u64, F64: f64, String: str, Error: err }
type Field = struct { name: str, value: Value }
type Record = struct { timestamp: time.Timestamp, level: Level, message: str, fields: []const Field, frames: []const debug.Frame }
type Sink = struct { ctx: *void, write: fn(*void, *const Record) -> err }
type Logger = struct { sinks: []const Sink, minimum: Level }

fn logger(sinks: []const Sink, minimum: Level) -> Logger {
    ret Logger { sinks: sinks, minimum: minimum }
}

fn level_rank(level: Level) -> u8 {
    if level == .Trace { ret 0u8 }
    if level == .Debug { ret 1u8 }
    if level == .Info { ret 2u8 }
    if level == .Warn { ret 3u8 }
    ret 4u8
}

fn level_name(level: Level) -> str {
    if level == .Trace { ret "TRACE" }
    if level == .Debug { ret "DEBUG" }
    if level == .Info { ret "INFO" }
    if level == .Warn { ret "WARN" }
    ret "ERROR"
}

fn enabled(l: *const Logger, level: Level) -> bool {
    ret level_rank(level) >= level_rank(l.minimum)
}

fn emit(l: *Logger, record: *const Record) -> err {
    var i = 0usize
    while i < l.sinks.len {
        try l.sinks[i].write(l.sinks[i].ctx, record)
        i += 1usize
    }
    ret ok
}

fn write(l: *Logger, level: Level, message: str, fields: []const Field) -> err {
    if !enabled(l, level) { ret ok }
    let (stamp, clock_error) = time.now()
    if clock_error != ok { ret clock_error }
    var none: [1]debug.Frame = zero
    let record = Record { timestamp: stamp, level: level, message: message, fields: fields, frames: none[0usize..0usize] }
    ret emit(l, &record)
}

fn write_with_backtrace(l: *Logger, level: Level, message: str, fields: []const Field, scratch: []debug.Frame) -> err {
    if !enabled(l, level) { ret ok }
    let (stamp, clock_error) = time.now()
    if clock_error != ok { ret clock_error }
    let frames = debug.backtrace(scratch)
    let record = Record { timestamp: stamp, level: level, message: message, fields: fields, frames: frames }
    ret emit(l, &record)
}

// --- Formatting, through a builder over a stack arena so the sinks allocate nothing.

fn push_value(b: *str.Builder, value: Value, quoted: bool) -> err {
    switch value {
    case .Bool as flag:
        if flag { ret str.push(b, "true") }
        ret str.push(b, "false")
    case .I64 as signed:
        ret str.push_i64(b, signed)
    case .U64 as unsigned:
        ret str.push_u64(b, unsigned)
    case .F64 as number:
        ret str.push_f64(b, number)
    case .String as text:
        if quoted { ret push_json_string(b, text) }
        ret str.push(b, text)
    case .Error as failure:
        var name = "ok"
        if failure != ok { name = "error" }
        if quoted { ret push_json_string(b, name) }
        ret str.push(b, name)
    }
}

fn push_json_string(b: *str.Builder, text: str) -> err {
    try str.push(b, "\"")
    var at = 0usize
    while at < text.len {
        let byte = text[at]
        if byte == 34u8 {
            try str.push(b, "\\\"")
        } else {
        if byte == 92u8 {
            try str.push(b, "\\\\")
        } else {
        if byte == 10u8 {
            try str.push(b, "\\n")
        } else {
        if byte == 13u8 {
            try str.push(b, "\\r")
        } else {
        if byte == 9u8 {
            try str.push(b, "\\t")
        } else {
        if byte < 32u8 {
            try str.push(b, "\\u00")
            try str.push_byte(b, hex_digit(byte >> 4u8))
            try str.push_byte(b, hex_digit(byte & 15u8))
        } else {
            try str.push_byte(b, byte)
        }
        }
        }
        }
        }
        }
        at += 1usize
    }
    ret str.push(b, "\"")
}

fn hex_digit(nibble: u8) -> u8 {
    if nibble < 10u8 { ret 48u8 + nibble }
    ret 87u8 + nibble
}

fn render_console(b: *str.Builder, record: *const Record) -> err {
    var stamp: [30]u8 = zero
    try str.push(b, time.format_iso8601(record.timestamp, stamp[0..]))
    try str.push(b, " ")
    try str.push(b, level_name(record.level))
    try str.push(b, " ")
    try str.push(b, record.message)
    var i = 0usize
    while i < record.fields.len {
        try str.push(b, " ")
        try str.push(b, record.fields[i].name)
        try str.push(b, "=")
        try push_value(b, record.fields[i].value, false)
        i += 1usize
    }
    i = 0usize
    while i < record.frames.len {
        try str.push(b, "\n    at 0x")
        try str.push_hex_u64(b, u64(record.frames[i].address))
        if record.frames[i].function.len > 0usize {
            try str.push(b, " ")
            try str.push(b, record.frames[i].function)
        }
        i += 1usize
    }
    ret str.push(b, "\n")
}

fn render_jsonl(b: *str.Builder, record: *const Record) -> err {
    var stamp: [30]u8 = zero
    try str.push(b, "{\"time\":\"")
    try str.push(b, time.format_iso8601(record.timestamp, stamp[0..]))
    try str.push(b, "\",\"level\":\"")
    try str.push(b, level_name(record.level))
    try str.push(b, "\",\"message\":")
    try push_json_string(b, record.message)
    try str.push(b, ",\"fields\":{")
    var i = 0usize
    while i < record.fields.len {
        if i > 0usize { try str.push(b, ",") }
        try push_json_string(b, record.fields[i].name)
        try str.push(b, ":")
        try push_value(b, record.fields[i].value, true)
        i += 1usize
    }
    try str.push(b, "},\"frames\":[")
    i = 0usize
    while i < record.frames.len {
        if i > 0usize { try str.push(b, ",") }
        try str.push(b, "{\"address\":")
        try str.push_u64(b, u64(record.frames[i].address))
        try str.push(b, ",\"function\":")
        try push_json_string(b, record.frames[i].function)
        try str.push(b, "}")
        i += 1usize
    }
    ret str.push(b, "]}\n")
}

// A record is rendered into a 4 KiB stack line; a longer one is cut at the message.
const LINE: usize = 4096usize

fn console_write(ctx: *void, record: *const Record) -> err {
    var scratch: [4096]u8 = zero
    var arena = mem.arena_from(scratch[0..])
    let (b0, builder_error) = str.builder(&arena, LINE)
    if builder_error != ok { ret builder_error }
    var b = b0
    let render_error = render_console(&b, record)
    if render_error != ok && render_error != mem.Exhausted { ret render_error }
    let file = mem.cast[*os.File](ctx)
    var line = str.done(&b)
    if render_error == mem.Exhausted { line = "" }
    var sent = 0usize
    while sent < line.len {
        let (count, write_error) = os.write(*file, line[sent..])
        if write_error != ok { ret write_error }
        if count == 0usize { ret io.NoProgress }
        sent += count
    }
    ret ok
}

fn console_sink(file: *os.File) -> Sink {
    ret Sink { ctx: mem.cast[*void](file), write: console_write }
}

fn jsonl_write(ctx: *void, record: *const Record) -> err {
    var scratch: [4096]u8 = zero
    var arena = mem.arena_from(scratch[0..])
    let (b0, builder_error) = str.builder(&arena, LINE)
    if builder_error != ok { ret builder_error }
    var b = b0
    try render_jsonl(&b, record)
    let writer = mem.cast[*io.Writer](ctx)
    ret io.write_all(writer, str.done(&b))
}

fn jsonl_sink(writer: *io.Writer) -> Sink {
    ret Sink { ctx: mem.cast[*void](writer), write: jsonl_write }
}
