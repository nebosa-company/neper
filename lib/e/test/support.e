// Deterministic test doubles, caller-owned: a clock that moves only when advanced, a
// reader that plays a script of byte chunks and failures, a writer that accepts at
// most a scripted number of bytes per call into a capture buffer, and a cooperative
// schedule that admits participants in a prescribed order. Steps are copied into the
// arena; the bytes a read step names stay borrowed. A script that runs out answers
// `io.End` (the reader), `io.TooSmall` (the writer's capacity) or `test.Failed` (the
// schedule), and nothing here consults the host.
use e.io
use e.mem
use e.test
use e.time

type Clock = struct { instant: time.Instant, timestamp: time.Timestamp }
type ReadStep = struct { bytes: []const u8, failure: err }
type WriteStep = struct { max_bytes: usize, failure: err }
type ScriptedReader = struct { state: *void }
type ScriptedWriter = struct { state: *void }
type Schedule = struct { state: *void }

type ReaderState = struct { steps: []ReadStep, index: usize, offset: usize }
type WriterState = struct { steps: []WriteStep, index: usize, capture: []u8, used: usize }
type ScheduleState = struct { turns: []u64, index: usize }

fn clock(instant: time.Instant, timestamp: time.Timestamp) -> Clock {
    ret Clock { instant: instant, timestamp: timestamp }
}

fn advance(c: *Clock, elapsed: time.Duration) -> err {
    if elapsed.nanos < 0i64 { ret test.Failed }
    if c.instant.nanos > 9223372036854775807i64 - elapsed.nanos { ret test.Failed }
    if c.timestamp.nanos > 9223372036854775807i64 - elapsed.nanos { ret test.Failed }
    c.instant = time.instant_add(c.instant, elapsed)
    c.timestamp = time.timestamp_add(c.timestamp, elapsed)
    ret ok
}

fn scripted_reader(a: *mem.Arena, steps: []const ReadStep) -> (ScriptedReader, err) {
    let (storage, storage_error) = mem.alloc[ReaderState](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (copy, copy_error) = mem.alloc[ReadStep](a, steps.len)
    if copy_error != ok { ret (zero, copy_error) }
    mem.copy[ReadStep](copy, steps)
    storage[0].steps = copy
    storage[0].index = 0usize
    storage[0].offset = 0usize
    var script: ScriptedReader = zero
    script.state = mem.cast[*void](&storage[0])
    ret (script, ok)
}

// A step's bytes come out over as many calls as `dst` needs; its failure follows the
// last of them, and a step with no bytes is its failure alone.
fn scripted_read(ctx: *void, dst: []u8) -> (usize, err) {
    let s = mem.cast[*ReaderState](ctx)
    if s.index >= s.steps.len { ret (0usize, io.End) }
    let step = s.steps[s.index]
    let left = step.bytes.len - s.offset
    if left == 0usize {
        s.index += 1usize
        s.offset = 0usize
        if step.failure != ok { ret (0usize, step.failure) }
        ret (0usize, io.End)
    }
    var take = dst.len
    if take > left { take = left }
    mem.copy[u8](dst[..take], step.bytes[s.offset..s.offset + take])
    s.offset += take
    if s.offset == step.bytes.len {
        s.index += 1usize
        s.offset = 0usize
        if step.failure != ok { ret (take, step.failure) }
    }
    ret (take, ok)
}

fn reader(script: *ScriptedReader) -> io.Reader {
    ret io.Reader { ctx: script.state, read: scripted_read }
}

fn scripted_writer(a: *mem.Arena, steps: []const WriteStep, capacity: usize) -> (ScriptedWriter, err) {
    let (storage, storage_error) = mem.alloc[WriterState](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (copy, copy_error) = mem.alloc[WriteStep](a, steps.len)
    if copy_error != ok { ret (zero, copy_error) }
    mem.copy[WriteStep](copy, steps)
    let (capture, capture_error) = mem.alloc[u8](a, capacity)
    if capture_error != ok { ret (zero, capture_error) }
    storage[0].steps = copy
    storage[0].index = 0usize
    storage[0].capture = capture
    storage[0].used = 0usize
    var script: ScriptedWriter = zero
    script.state = mem.cast[*void](&storage[0])
    ret (script, ok)
}

// Each call takes one step: up to its byte limit into the capture, then its failure.
fn scripted_write(ctx: *void, src: []const u8) -> (usize, err) {
    let s = mem.cast[*WriterState](ctx)
    if s.index >= s.steps.len { ret (0usize, io.End) }
    let step = s.steps[s.index]
    s.index += 1usize
    var take = src.len
    if take > step.max_bytes { take = step.max_bytes }
    if take > s.capture.len - s.used { ret (0usize, io.TooSmall) }
    mem.copy[u8](s.capture[s.used..s.used + take], src[..take])
    s.used += take
    if step.failure != ok { ret (take, step.failure) }
    ret (take, ok)
}

fn writer(script: *ScriptedWriter) -> io.Writer {
    ret io.Writer { ctx: script.state, write: scripted_write, flush: io.no_flush }
}

fn captured(script: *const ScriptedWriter) -> []const u8 {
    let s = mem.cast[*WriterState](script.state)
    ret s.capture[..s.used]
}

fn schedule(a: *mem.Arena, turns: []const u64) -> (Schedule, err) {
    let (storage, storage_error) = mem.alloc[ScheduleState](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (copy, copy_error) = mem.alloc[u64](a, turns.len)
    if copy_error != ok { ret (zero, copy_error) }
    mem.copy[u64](copy, turns)
    storage[0].turns = copy
    storage[0].index = 0usize
    var s: Schedule = zero
    s.state = mem.cast[*void](&storage[0])
    ret (s, ok)
}

// True and a step forward when it is this participant's turn; false for any other.
fn checkpoint(s: *Schedule, participant: u64) -> (bool, err) {
    let state = mem.cast[*ScheduleState](s.state)
    if state.index >= state.turns.len { ret (false, test.Failed) }
    if state.turns[state.index] != participant { ret (false, ok) }
    state.index += 1usize
    ret (true, ok)
}

fn complete(s: *const Schedule) -> bool {
    let state = mem.cast[*ScheduleState](s.state)
    ret state.index == state.turns.len
}
