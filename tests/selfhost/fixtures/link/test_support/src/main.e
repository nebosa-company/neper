// `e.test.support`: a clock advanced and refused a negative step and an overflow; a
// scripted reader played through io.read_exact across step edges with a failure
// after its bytes and End after the script; a scripted writer capped per call, its
// failure and its capacity; a schedule that admits only the prescribed participant
// and fails once exhausted. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.time
use e.test
use e.test.support as support

fn main(a: *mem.Arena, args: []str) -> err {
    var c = support.clock(time.Instant { nanos: 100i64 }, time.Timestamp { nanos: 1000i64 })
    if support.advance(&c, time.Duration { nanos: 50i64 }) != ok { os.exit(1) }
    if c.instant.nanos != 150i64 || c.timestamp.nanos != 1050i64 { os.exit(2) }
    if support.advance(&c, time.Duration { nanos: -1i64 }) != test.Failed { os.exit(3) }
    if support.advance(&c, time.Duration { nanos: 9223372036854775807i64 }) != test.Failed { os.exit(4) }
    if c.instant.nanos != 150i64 { os.exit(5) }
    // The reader.
    var steps: [3]support.ReadStep = zero
    steps[0] = support.ReadStep { bytes: "hello ", failure: ok }
    steps[1] = support.ReadStep { bytes: "world", failure: io.NoProgress }
    steps[2] = support.ReadStep { bytes: "", failure: ok }
    let (script0, e1) = support.scripted_reader(a, steps[0..])
    if e1 != ok { os.exit(6) }
    var script = script0
    var r = support.reader(&script)
    var buffer: [8]u8 = zero
    if io.read_exact(&r, buffer[0..8]) != ok { os.exit(7) }
    if !str.eq(buffer[0..8], "hello wo") { os.exit(8) }
    let (n1, e2) = io.read(&r, buffer[0..])
    if n1 != 3usize || e2 != io.NoProgress || !str.eq(buffer[0..3], "rld") { os.exit(9) }
    let (n2, e3) = io.read(&r, buffer[0..])
    if n2 != 0usize || e3 != io.End { os.exit(10) }
    let (n3, e4) = io.read(&r, buffer[0..])
    if n3 != 0usize || e4 != io.End { os.exit(11) }
    // The writer.
    var write_steps: [3]support.WriteStep = zero
    write_steps[0] = support.WriteStep { max_bytes: 4usize, failure: ok }
    write_steps[1] = support.WriteStep { max_bytes: 100usize, failure: io.NoProgress }
    write_steps[2] = support.WriteStep { max_bytes: 100usize, failure: ok }
    let (sink0, e5) = support.scripted_writer(a, write_steps[0..], 12usize)
    if e5 != ok { os.exit(12) }
    var sink = sink0
    var w = support.writer(&sink)
    let (w1, e6) = io.write(&w, "abcdefgh")
    if w1 != 4usize || e6 != ok { os.exit(13) }
    let (w2, e7) = io.write(&w, "efgh")
    if w2 != 4usize || e7 != io.NoProgress { os.exit(14) }
    let (w3, e8) = io.write(&w, "ijklmn")
    if w3 != 0usize || e8 != io.TooSmall { os.exit(15) }
    if !str.eq(support.captured(&sink), "abcdefgh") { os.exit(16) }
    let (w4, e9) = io.write(&w, "x")
    if e9 != io.End { os.exit(17) }
    // The schedule.
    var turns: [4]u64 = [4]u64{ 1, 2, 1, 3 }
    let (sched0, e10) = support.schedule(a, turns[0..])
    if e10 != ok { os.exit(18) }
    var sched = sched0
    let (t1, e11) = support.checkpoint(&sched, 2u64)
    if t1 || e11 != ok { os.exit(19) }
    let (t2, e12) = support.checkpoint(&sched, 1u64)
    if !t2 || e12 != ok { os.exit(20) }
    let (t3, e13) = support.checkpoint(&sched, 2u64)
    if !t3 || e13 != ok { os.exit(21) }
    if support.complete(&sched) { os.exit(22) }
    let (t4, e14) = support.checkpoint(&sched, 1u64)
    let (t5, e15) = support.checkpoint(&sched, 3u64)
    if !t4 || !t5 || e14 != ok || e15 != ok { os.exit(23) }
    if !support.complete(&sched) { os.exit(24) }
    let (t6, e16) = support.checkpoint(&sched, 1u64)
    if t6 || e16 != test.Failed { os.exit(25) }
    ret ok
}
