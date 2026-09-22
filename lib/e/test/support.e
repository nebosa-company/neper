// Deterministic test doubles, caller-owned: a clock that moves only when advanced, a
// reader that plays a script of byte chunks and failures, a writer that accepts at
// most a scripted number of bytes per call into a capture buffer, and a cooperative
// schedule that admits participants in a prescribed order. Steps are copied into the
// arena; the bytes a read step names stay borrowed. A script that runs out answers
// `io.End` (the reader), `io.TooSmall` (the writer's capacity) or `test.Failed` (the
// schedule), and nothing here consults the host.
use e.algo.rand
use e.io
use e.mem
use e.test
use e.text.diff
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

// Golden files, snapshots, fault injection and HTTP replay, all over caller
// storage. `golden` compares bytes and names the first differing offset (the
// shorter length when one is a prefix of the other); `golden_diff` writes a
// line diff (`e.text.diff` Myers: ` `, `-`, `+` prefixes) with the line
// arrays and frontiers in the arena; `golden_update` is the update mode, the
// new golden through the caller writer. `snapshot` serialises through the
// caller function into the arena and compares with `stored` after masking:
// a line beginning with one of `volatile` (a `key:` prefix) keeps the prefix
// and loses the rest on both sides. A `FaultPlan` fails the `n`th call, every
// `k`th, or each with probability `p` from the caller PCG, for a `site` (0 is
// every site); `faulty_reader`/`faulty_writer` wrap a reader or writer to
// fail per plan with the plan's `failure`. A `Cassette` records exchanges
// (borrowing the request and response bytes) and replays by method and path,
// plus the body hash when `match_body` is set. ponytail: cassette lookup is
// linear and the body hash FNV-1a; a real proxy would key on more headers.

type Verdict = enum u8 { Match, Differ }
type FaultKind = enum u8 { Nth, EveryKth, Probability }
type FaultPlan = struct { kind: FaultKind, n: u64, p: f64, r: *rand.Pcg64, site: u64, calls: u64, failure: err }
type FaultyReaderState = struct { inner: io.Reader, plan: *FaultPlan, site: u64 }
type FaultyWriterState = struct { inner: io.Writer, plan: *FaultPlan, site: u64 }
type Exchange = struct { method: []const u8, path: []const u8, body_hash: u64, response: []const u8 }
type Cassette = struct { exchanges: []Exchange, count: usize, match_body: bool }

fn golden(expected: []const u8, actual: []const u8) -> (Verdict, usize) {
    var i = 0usize
    while i < expected.len && i < actual.len && expected[i] == actual[i] { i += 1usize }
    if i == expected.len && i == actual.len { ret (.Match, i) }
    ret (.Differ, i)
}

fn golden_update(w: *io.Writer, actual: []const u8) -> err {
    ret io.write_all(w, actual)
}

fn count_lines(text: []const u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 { n += 1usize }
        i += 1usize
    }
    if text.len > 0usize && text[text.len - 1usize] != 10u8 { n += 1usize }
    ret n
}

fn split_lines(a: *mem.Arena, text: []const u8) -> ([]str, err) {
    let (lines, lines_error) = mem.alloc[str](a, count_lines(text))
    if lines_error != ok { ret (zero, lines_error) }
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            lines[n] = text[start..i]
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    if start < text.len {
        lines[n] = text[start..]
        n += 1usize
    }
    ret (lines[..n], ok)
}

fn golden_diff(a: *mem.Arena, w: *io.Writer, expected: []const u8, actual: []const u8) -> err {
    let (old_lines, old_error) = split_lines(a, expected)
    if old_error != ok { ret old_error }
    let (new_lines, new_error) = split_lines(a, actual)
    if new_error != ok { ret new_error }
    let (edits, edits_error) = mem.alloc[diff.Edit](a, old_lines.len + new_lines.len)
    if edits_error != ok { ret edits_error }
    let (scratch, scratch_error) = mem.alloc[usize](a, diff.myers_scratch(old_lines.len, new_lines.len))
    if scratch_error != ok { ret scratch_error }
    let (count, myers_error) = diff.myers(old_lines, new_lines, edits, scratch)
    if myers_error != ok { ret myers_error }
    var i = 0usize
    while i < count {
        if edits[i].op == .Keep { try io.write_all(w, " ") }
        if edits[i].op == .Delete { try io.write_all(w, "-") }
        if edits[i].op == .Insert { try io.write_all(w, "+") }
        try io.write_all(w, edits[i].line)
        try io.write_all(w, "\n")
        i += 1usize
    }
    ret ok
}

fn starts_with(text: []const u8, prefix: []const u8) -> bool {
    if text.len < prefix.len { ret false }
    ret mem.eq[u8](text[..prefix.len], prefix)
}

// `src` with every volatile line cut after its key; answers the masked length.
fn mask(src: []const u8, volatile: []const str, out: []u8) -> (usize, err) {
    var n = 0usize
    var i = 0usize
    while i < src.len {
        var end = i
        while end < src.len && src[end] != 10u8 { end += 1usize }
        var keep = end - i
        var v = 0usize
        while v < volatile.len {
            if starts_with(src[i..end], volatile[v]) && volatile[v].len < keep { keep = volatile[v].len }
            v += 1usize
        }
        if n + keep + 1usize > out.len { ret (n, io.TooSmall) }
        mem.copy[u8](out[n..n + keep], src[i..i + keep])
        n += keep
        if end < src.len {
            out[n] = 10u8
            n += 1usize
        }
        i = end + 1usize
    }
    ret (n, ok)
}

fn snapshot[Ctx: type](a: *mem.Arena, ctx: *Ctx, serialise: fn(*Ctx, *io.Writer) -> err, stored: []const u8, volatile: []const str, capacity: usize) -> (Verdict, usize, err) {
    let (memory, unused_sink, memory_error) = io.memory_writer(a, capacity)
    if memory_error != ok { ret (.Differ, 0usize, memory_error) }
    // `memory_writer` answers a sink it never fills in; the writer is wired here.
    var held = memory
    var sink_writer = io.writer(mem.cast[*void](&held), io.memory_write)
    let serialise_error = serialise(ctx, &sink_writer)
    if serialise_error != ok { ret (.Differ, 0usize, serialise_error) }
    let produced = io.memory_bytes(&held)
    let (masked_stored, stored_buffer_error) = mem.alloc[u8](a, stored.len)
    if stored_buffer_error != ok { ret (.Differ, 0usize, stored_buffer_error) }
    let (masked_produced, produced_buffer_error) = mem.alloc[u8](a, produced.len)
    if produced_buffer_error != ok { ret (.Differ, 0usize, produced_buffer_error) }
    let (stored_len, stored_mask_error) = mask(stored, volatile, masked_stored)
    if stored_mask_error != ok { ret (.Differ, 0usize, stored_mask_error) }
    let (produced_len, produced_mask_error) = mask(produced, volatile, masked_produced)
    if produced_mask_error != ok { ret (.Differ, 0usize, produced_mask_error) }
    let (verdict, at) = golden(masked_stored[..stored_len], masked_produced[..produced_len])
    ret (verdict, at, ok)
}

fn fault_nth(n: u64, failure: err) -> FaultPlan { ret FaultPlan { kind: .Nth, n: n, p: 0.0f64, r: zero, site: 0u64, calls: 0u64, failure: failure } }
fn fault_every(k: u64, failure: err) -> FaultPlan { ret FaultPlan { kind: .EveryKth, n: k, p: 0.0f64, r: zero, site: 0u64, calls: 0u64, failure: failure } }
fn fault_probability(p: f64, r: *rand.Pcg64, failure: err) -> FaultPlan { ret FaultPlan { kind: .Probability, n: 0u64, p: p, r: r, site: 0u64, calls: 0u64, failure: failure } }

// Whether this call at `site` fails; a plan for one site ignores the others.
fn inject_fault(plan: *FaultPlan, site: u64) -> bool {
    if plan.site != 0u64 && plan.site != site { ret false }
    plan.calls += 1u64
    if plan.kind == .Nth { ret plan.calls == plan.n }
    if plan.kind == .EveryKth { ret plan.n > 0u64 && plan.calls % plan.n == 0u64 }
    ret rand.pcg64_f64(plan.r) < plan.p
}

fn faulty_read(ctx: *void, dst: []u8) -> (usize, err) {
    let s = mem.cast[*FaultyReaderState](ctx)
    if inject_fault(s.plan, s.site) { ret (0usize, s.plan.failure) }
    let (n, e) = s.inner.read(s.inner.ctx, dst)
    ret (n, e)
}

fn faulty_reader(a: *mem.Arena, inner: io.Reader, plan: *FaultPlan, site: u64) -> (io.Reader, err) {
    let (storage, storage_error) = mem.alloc[FaultyReaderState](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    storage[0] = FaultyReaderState { inner: inner, plan: plan, site: site }
    ret (io.Reader { ctx: mem.cast[*void](&storage[0]), read: faulty_read }, ok)
}

fn faulty_write(ctx: *void, src: []const u8) -> (usize, err) {
    let s = mem.cast[*FaultyWriterState](ctx)
    if inject_fault(s.plan, s.site) { ret (0usize, s.plan.failure) }
    let (n, e) = s.inner.write(s.inner.ctx, src)
    ret (n, e)
}

fn faulty_flush(ctx: *void) -> err {
    let s = mem.cast[*FaultyWriterState](ctx)
    ret s.inner.flush(s.inner.ctx)
}

fn faulty_writer(a: *mem.Arena, inner: io.Writer, plan: *FaultPlan, site: u64) -> (io.Writer, err) {
    let (storage, storage_error) = mem.alloc[FaultyWriterState](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    storage[0] = FaultyWriterState { inner: inner, plan: plan, site: site }
    ret (io.Writer { ctx: mem.cast[*void](&storage[0]), write: faulty_write, flush: faulty_flush }, ok)
}

fn fnv1a(bytes: []const u8) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < bytes.len {
        h = (h ^ u64(bytes[i])) *% 1099511628211u64
        i += 1usize
    }
    ret h
}

// The method, path and body hash of a raw HTTP request (`test.Failed` without a request line).
fn parse_request(request: []const u8) -> (Exchange, err) {
    var space = 0usize
    while space < request.len && request[space] != 32u8 { space += 1usize }
    if space == request.len { ret (zero, test.Failed) }
    var end = space + 1usize
    while end < request.len && request[end] != 32u8 && request[end] != 13u8 && request[end] != 10u8 { end += 1usize }
    var body_at = request.len
    var i = 0usize
    while i + 3usize < request.len && body_at == request.len {
        if request[i] == 13u8 && request[i + 1usize] == 10u8 && request[i + 2usize] == 13u8 && request[i + 3usize] == 10u8 { body_at = i + 4usize }
        i += 1usize
    }
    ret (Exchange { method: request[..space], path: request[space + 1usize..end], body_hash: fnv1a(request[body_at..]), response: zero }, ok)
}

fn http_record(c: *Cassette, request: []const u8, response: []const u8) -> err {
    let (parsed, parse_error) = parse_request(request)
    if parse_error != ok { ret parse_error }
    if c.count >= c.exchanges.len { ret io.TooSmall }
    c.exchanges[c.count] = Exchange { method: parsed.method, path: parsed.path, body_hash: parsed.body_hash, response: response }
    c.count += 1usize
    ret ok
}

fn http_replay(c: *const Cassette, request: []const u8) -> ([]const u8, bool) {
    let (wanted, parse_error) = parse_request(request)
    if parse_error != ok { ret (zero, false) }
    var i = 0usize
    while i < c.count {
        let x = c.exchanges[i]
        if mem.eq[u8](x.method, wanted.method) && mem.eq[u8](x.path, wanted.path) && (!c.match_body || x.body_hash == wanted.body_hash) { ret (x.response, true) }
        i += 1usize
    }
    ret (zero, false)
}
