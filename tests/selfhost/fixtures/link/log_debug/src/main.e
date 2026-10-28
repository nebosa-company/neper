// `e.log` and `e.debug`: a logger over a capturing sink checking the level gate, the
// record's message and fields, a stop at the first failing sink; the JSON lines sink
// over a slice writer with every value kind and an escaped message; the console sink
// over a real file read back; `write_with_backtrace` with the frames `debug` answers
// today (none) and `symbolize` keeping the address. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fs
use e.time
use e.debug
use e.log
use e.text.utf8
use e.fmt.json as json

type Capture = struct { count: u32, last_level: log.Level, last_message: str, last_fields: usize, fail: bool }

fn capture_write(ctx: *void, record: *const log.Record) -> err {
    var c = mem.cast[*Capture](ctx)
    if c.fail { ret io.NoProgress }
    c.count += 1u32
    c.last_level = record.level
    c.last_message = record.message
    c.last_fields = record.fields.len
    ret ok
}

fn log_to_file(handle: *os.File, fields: []log.Field) -> i32 {
    var console_sinks: [1]log.Sink = zero
    console_sinks[0] = log.console_sink(handle)
    var c = log.logger(console_sinks[0..], .Info)
    var scratch: [8]debug.Frame = zero
    if log.write(&c, .Info, "to file", fields) != ok { ret 12i32 }
    if log.write_with_backtrace(&c, .Error, "traced", zero, scratch[0..]) != ok { ret 13i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var first: Capture = zero
    var second: Capture = zero
    var sinks: [2]log.Sink = zero
    sinks[0] = log.Sink { ctx: mem.cast[*void](&first), write: capture_write }
    sinks[1] = log.Sink { ctx: mem.cast[*void](&second), write: capture_write }
    var l = log.logger(sinks[0..], .Info)
    if log.enabled(&l, .Debug) || !log.enabled(&l, .Info) || !log.enabled(&l, .Error) { os.exit(1) }
    var fields: [2]log.Field = zero
    fields[0] = log.Field { name: "count", value: log.Value{ I64: -7i64 } }
    fields[1] = log.Field { name: "who", value: log.Value{ String: "neper" } }
    if log.write(&l, .Debug, "hidden", fields[0..]) != ok { os.exit(2) }
    if first.count != 0u32 || second.count != 0u32 { os.exit(3) }
    if log.write(&l, .Warn, "shown", fields[0..]) != ok { os.exit(4) }
    if first.count != 1u32 || second.count != 1u32 || first.last_level != .Warn || !str.eq(second.last_message, "shown") || second.last_fields != 2usize { os.exit(5) }
    first.fail = true
    if log.write(&l, .Error, "stops", zero) != io.NoProgress { os.exit(6) }
    if second.count != 1u32 { os.exit(7) }
    // JSON lines.
    var buffer: [512]u8 = zero
    var sink_state = io.SliceWriter { data: buffer[..], off: 0usize }
    var writer = io.slice_writer(&sink_state)
    var json_sinks: [1]log.Sink = zero
    json_sinks[0] = log.jsonl_sink(&writer)
    var j = log.logger(json_sinks[0..], .Trace)
    var all: [6]log.Field = zero
    all[0] = log.Field { name: "b", value: log.Value{ Bool: true } }
    all[1] = log.Field { name: "i", value: log.Value{ I64: -1i64 } }
    all[2] = log.Field { name: "u", value: log.Value{ U64: 18446744073709551615u64 } }
    all[3] = log.Field { name: "f", value: log.Value{ F64: 0.5 } }
    all[4] = log.Field { name: "s", value: log.Value{ String: "q\"uote" } }
    all[5] = log.Field { name: "e", value: log.Value{ Error: io.End } }
    if log.write(&j, .Trace, "line\none", all[0..]) != ok { os.exit(8) }
    let line = buffer[..sink_state.off]
    if !str.starts_with(line, "{\"time\":\"") || line.len < 40usize || line[38] != 90u8 { os.exit(9) }
    if !str.ends_with(line, "\",\"level\":\"TRACE\",\"message\":\"line\\none\",\"fields\":{\"b\":true,\"i\":-1,\"u\":18446744073709551615,\"f\":0.5,\"s\":\"q\\\"uote\",\"e\":\"error\"},\"frames\":[]}\n") { os.exit(10) }
    // JSONL refuses malformed UTF-8 before anything reaches the sink, whether it
    // arrives as the message, a field name, or a field string value.
    sink_state.off = 0usize
    if log.write(&j, .Trace, "\xFF", zero) != utf8.Invalid || sink_state.off != 0usize { os.exit(21) }
    var invalid_name: [1]log.Field = zero
    invalid_name[0usize] = log.Field { name: "\xFF", value: log.Value{ String: "ok" } }
    if log.write(&j, .Trace, "line", invalid_name[..]) != utf8.Invalid || sink_state.off != 0usize { os.exit(22) }
    var invalid_value: [1]log.Field = zero
    invalid_value[0usize] = log.Field { name: "value", value: log.Value{ String: "\xFF" } }
    if log.write(&j, .Trace, "line", invalid_value[..]) != utf8.Invalid || sink_state.off != 0usize { os.exit(23) }
    // JSON has no NaN or infinity token, so those field values become null while
    // the console keeps its diagnostic spelling.
    var nonfinite: [3]log.Field = zero
    nonfinite[0usize] = log.Field { name: "nan", value: log.Value{ F64: mem.bitcast[f64](9221120237041090560u64) } }
    nonfinite[1usize] = log.Field { name: "positive", value: log.Value{ F64: mem.bitcast[f64](9218868437227405312u64) } }
    nonfinite[2usize] = log.Field { name: "negative", value: log.Value{ F64: 0.0f64 - mem.bitcast[f64](9218868437227405312u64) } }
    sink_state.off = 0usize
    if log.write(&j, .Trace, "numbers", nonfinite[..]) != ok { os.exit(24) }
    let nonfinite_line = buffer[..sink_state.off]
    if !str.contains(nonfinite_line, "\"nan\":null") || !str.contains(nonfinite_line, "\"positive\":null") || !str.contains(nonfinite_line, "\"negative\":null") { os.exit(25) }
    let (_, nonfinite_json_error) = json.parse(a, nonfinite_line, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
    if nonfinite_json_error != ok { os.exit(26) }
    // Both sinks stream past their 4 KiB stack buffer. JSONL stays a complete,
    // parseable record, while the console record is nonempty and newline-terminated.
    var long_text: [5000]u8 = zero
    var long_at = 0usize
    while long_at < long_text.len {
        long_text[long_at] = 120u8
        long_at += 1usize
    }
    var long_json_bytes: [6000]u8 = zero
    var long_json_state = io.SliceWriter { data: long_json_bytes[..], off: 0usize }
    var long_json_writer = io.slice_writer(&long_json_state)
    var long_json_sinks: [1]log.Sink = zero
    long_json_sinks[0usize] = log.jsonl_sink(&long_json_writer)
    var long_json_logger = log.logger(long_json_sinks[..], .Trace)
    if log.write(&long_json_logger, .Info, long_text[..], zero) != ok || long_json_state.off <= 4096usize { os.exit(27) }
    let long_json_line = long_json_bytes[..long_json_state.off]
    let (_, long_json_error) = json.parse(a, long_json_line, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
    if long_json_error != ok { os.exit(28) }
    // The console sink over a file.
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, "log-fixture.txt", flags)
    if open_error != ok { os.exit(11) }
    var handle = file
    // The sink's pointer lives in its own function (D351), so the close follows it.
    let logged = log_to_file(&handle, fields[0..])
    if logged != 0i32 { os.exit(logged) }
    if os.close(handle) != ok { os.exit(14) }
    let (contents, read_error) = fs.read_file(a, "log-fixture.txt", 4096usize)
    if read_error != ok { os.exit(15) }
    let (first_line, rest, has_break) = str.split_once(contents, "\n")
    if !has_break || !str.ends_with(first_line, " INFO to file count=-7 who=neper") || first_line.len != 62usize { os.exit(16) }
    if !str.ends_with(rest, " ERROR traced\n") || rest.len != 44usize { os.exit(17) }
    if fs.remove_file(a, "log-fixture.txt") != ok { os.exit(18) }
    let (long_file, long_open_error) = os.open(a, "log-long-fixture.txt", flags)
    if long_open_error != ok { os.exit(29) }
    var long_handle = long_file
    var long_console_sinks: [1]log.Sink = zero
    long_console_sinks[0usize] = log.console_sink(&long_handle)
    var long_console = log.logger(long_console_sinks[..], .Trace)
    if log.write(&long_console, .Info, long_text[..], zero) != ok { os.exit(30) }
    if log.write(&long_console, .Info, "nonfinite", nonfinite[..]) != ok { os.exit(31) }
    if os.close(long_handle) != ok { os.exit(32) }
    let (long_contents, long_read_error) = fs.read_file(a, "log-long-fixture.txt", 6000usize)
    if long_read_error != ok || long_contents.len <= 4096usize || long_contents[long_contents.len - 1usize] != 10u8 { os.exit(33) }
    if !str.contains(long_contents, " INFO nonfinite nan=nan positive=inf negative=-inf\n") { os.exit(34) }
    if fs.remove_file(a, "log-long-fixture.txt") != ok { os.exit(35) }
    let (escaped_file, escaped_open_error) = os.open(a, "log-escaped-fixture.txt", flags)
    if escaped_open_error != ok { os.exit(36) }
    var escaped_handle = escaped_file
    var escaped_sinks: [1]log.Sink = zero
    escaped_sinks[0usize] = log.console_sink(&escaped_handle)
    var escaped_logger = log.logger(escaped_sinks[..], .Trace)
    var escaped_fields: [1]log.Field = zero
    escaped_fields[0usize] = log.Field { name: "key\n", value: log.Value{ String: "value\r\t\x01" } }
    if log.write(&escaped_logger, .Info, "message\nnext", escaped_fields[..]) != ok { os.exit(37) }
    if os.close(escaped_handle) != ok { os.exit(38) }
    let (escaped_contents, escaped_read_error) = fs.read_file(a, "log-escaped-fixture.txt", 1024usize)
    if escaped_read_error != ok || !str.ends_with(escaped_contents, " INFO message\\nnext key\\n=value\\r\\t\\x01\n") { os.exit(39) }
    var newlines = 0usize
    var escaped_at = 0usize
    while escaped_at < escaped_contents.len {
        if escaped_contents[escaped_at] == 10u8 { newlines += 1usize }
        escaped_at += 1usize
    }
    if newlines != 1usize { os.exit(40) }
    if fs.remove_file(a, "log-escaped-fixture.txt") != ok { os.exit(41) }
    // debug answers what it has: no frames, the address kept.
    var scratch: [8]debug.Frame = zero
    let frames = debug.backtrace(scratch[0..])
    if frames.len != 0usize { os.exit(19) }
    let frame = debug.symbolize(4096usize)
    if frame.address != 4096usize || frame.function.len != 0usize || frame.file.len != 0usize || frame.line != 0u32 { os.exit(20) }
    ret ok
}
