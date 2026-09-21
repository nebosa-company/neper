// Event-time stream processing over the caller's clocks. `Watermark`
// tracks a bounded out-of-orderness bound: after each observed event time
// the watermark is `max seen - lateness`, never decreasing, and an event
// below the current watermark is late (`watermark_observe`,
// `watermark_is_late`). `Merge` combines per-source watermarks into their
// minimum, skipping sources that have not reported for `idle` ticks of the
// caller's processing clock, and keeps that combined value monotone.
// `WindowBuffer` assigns events to tumbling (`slide == size`) or sliding
// windows keyed by their start, holds one count and sum per open window
// in caller storage, and `window_fire` emits (in start order) and drops the
// windows whose end has passed the watermark; an event whose window has
// already passed is counted in `late` and dropped.

type Watermark = struct { lateness: u64, max_seen: u64, mark: u64, seen: bool, late: u64 }
type Merge = struct { marks: []u64, last: []u64, idle: u64, mark: u64 }
type Window = struct { start: u64, count: u64, sum: u64 }
type WindowBuffer = struct { size: u64, slide: u64, windows: []Window, used: usize, late: u64 }
error TooSmall
error Invalid

fn watermark(lateness: u64) -> Watermark {
    ret Watermark { lateness: lateness, max_seen: 0u64, mark: 0u64, seen: false, late: 0u64 }
}

// An event time below the watermark is late.
fn watermark_is_late(w: *const Watermark, event_time: u64) -> bool {
    ret w.seen && event_time < w.mark
}

// Account `event_time` and answer the (monotone) watermark; a late event is counted.
fn watermark_observe(w: *Watermark, event_time: u64) -> u64 {
    if watermark_is_late(w, event_time) { w.late += 1u64 }
    if !w.seen || event_time > w.max_seen { w.max_seen = event_time }
    w.seen = true
    var candidate = 0u64
    if w.max_seen > w.lateness { candidate = w.max_seen - w.lateness }
    if candidate > w.mark { w.mark = candidate }
    ret w.mark
}

fn watermark_current(w: *const Watermark) -> u64 { ret w.mark }

// Per-source watermarks in `marks`, each source's last report time in
// `last` (both sized to the source count); a source silent for `idle`
// ticks of the processing clock is ignored by the minimum. Every source
// starts unreported at time 0, so it holds the merged value at 0 until it
// reports or `idle` ticks pass.
fn merge(marks: []u64, last: []u64, idle: u64) -> (Merge, err) {
    if marks.len == 0usize || last.len < marks.len || idle == 0u64 { ret (Merge { marks: marks, last: last, idle: 1u64, mark: 0u64 }, Invalid) }
    var i = 0usize
    while i < marks.len {
        marks[i] = 0u64
        last[i] = 0u64
        i += 1usize
    }
    ret (Merge { marks: marks, last: last, idle: idle, mark: 0u64 }, ok)
}

// Source `source` reports watermark `mark` at processing time `now`;
// answers the merged watermark.
fn merge_update(m: *Merge, source: usize, mark: u64, now: u64) -> (u64, err) {
    if source >= m.marks.len { ret (m.mark, Invalid) }
    if mark > m.marks[source] { m.marks[source] = mark }
    m.last[source] = now
    ret (merge_at(m, now), ok)
}

// The merged watermark as of processing time `now` (idle sources dropped).
fn merge_at(m: *Merge, now: u64) -> u64 {
    var lowest = 0u64
    var any = false
    var i = 0usize
    while i < m.marks.len {
        if m.last[i] +% m.idle > now {
            if !any || m.marks[i] < lowest { lowest = m.marks[i] }
            any = true
        }
        i += 1usize
    }
    if any && lowest > m.mark { m.mark = lowest }
    ret m.mark
}

// The start of the tumbling window of `size` holding `event_time`.
fn window_start(event_time: u64, size: u64) -> u64 { ret event_time - event_time % size }

// The starts of the sliding windows (`size` wide, every `slide`) holding
// `event_time`, latest first, into `out`; answers the count.
fn sliding_windows(event_time: u64, size: u64, slide: u64, out: []u64) -> (usize, err) {
    if size == 0u64 || slide == 0u64 { ret (0usize, Invalid) }
    var start = event_time - event_time % slide
    var n = 0usize
    while start +% size > event_time {
        if n >= out.len { ret (n, TooSmall) }
        out[n] = start
        n += 1usize
        if start < slide { break }
        start -= slide
    }
    ret (n, ok)
}

// Windows of `size` every `slide` (tumbling when equal) over caller storage.
fn window_buffer(size: u64, slide: u64, windows: []Window) -> (WindowBuffer, err) {
    if size == 0u64 || slide == 0u64 || slide > size { ret (WindowBuffer { size: 1u64, slide: 1u64, windows: windows, used: 0usize, late: 0u64 }, Invalid) }
    ret (WindowBuffer { size: size, slide: slide, windows: windows, used: 0usize, late: 0u64 }, ok)
}

// Add `value` at `event_time` to every window holding it that has not yet
// passed `mark` (the current watermark); windows already past count as late.
fn window_add(b: *WindowBuffer, event_time: u64, value: u64, mark: u64) -> err {
    var start = event_time - event_time % b.slide
    while start +% b.size > event_time {
        if start +% b.size <= mark {
            b.late += 1u64
        } else {
            // ponytail: linear scan over open windows; a map by start if thousands stay open.
            var i = 0usize
            while i < b.used && b.windows[i].start != start { i += 1usize }
            if i == b.used {
                if b.used >= b.windows.len { ret TooSmall }
                b.windows[i] = Window { start: start, count: 0u64, sum: 0u64 }
                b.used += 1usize
            }
            b.windows[i].count += 1u64
            b.windows[i].sum +%= value
        }
        if start < b.slide { break }
        start -= b.slide
    }
    ret ok
}

// Emit into `out`, in start order, every window whose end is at or below
// `mark`, removing it from the buffer; answers the count emitted.
fn window_fire(b: *WindowBuffer, mark: u64, out: []Window) -> (usize, err) {
    var n = 0usize
    var i = 0usize
    while i < b.used {
        if b.windows[i].start +% b.size <= mark {
            if n >= out.len { ret (n, TooSmall) }
            // Insertion by start keeps the emission ordered.
            var j = n
            while j > 0usize && out[j - 1usize].start > b.windows[i].start {
                out[j] = out[j - 1usize]
                j -= 1usize
            }
            out[j] = b.windows[i]
            n += 1usize
            b.used -= 1usize
            b.windows[i] = b.windows[b.used]
        } else {
            i += 1usize
        }
    }
    ret (n, ok)
}
