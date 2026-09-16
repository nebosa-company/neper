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
    // debug answers what it has: no frames, the address kept.
    var scratch: [8]debug.Frame = zero
    let frames = debug.backtrace(scratch[0..])
    if frames.len != 0usize { os.exit(19) }
    let frame = debug.symbolize(4096usize)
    if frame.address != 4096usize || frame.function.len != 0usize || frame.file.len != 0usize || frame.line != 0u32 { os.exit(20) }
    ret ok
}
