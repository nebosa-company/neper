// The half a single thread cannot check: that a full channel blocks its sender, an
// empty one blocks its receiver, nothing is lost or duplicated across the handoff, and
// a close releases everyone who is waiting.

use e.mem
use e.os
use e.sync
use e.atomic
use e.channel

error Failed

type Traffic = struct {
    pipe: channel.Channel[i64],
    sent: Atomic[u32],
    received: Atomic[u32],
    total: Atomic[u64],
    failures: Atomic[u32],
}

// Four producers send 500 each through a channel that holds four, so every one of
// them blocks repeatedly and the capacity is the thing under test.
fn produce(t: *Traffic) {
    var at = 0i64
    while at < 500i64 {
        let send_error = channel.send[i64](&t.pipe, at + 1i64)
        if send_error != ok { let bad = atomic.add(&t.failures, 1u32, .Release) }
        let counted = atomic.add(&t.sent, 1u32, .Release)
        at += 1i64
    }
}

// Consumers stop on `Closed`. They are also the close test: by the time the producers
// have finished every consumer is blocked on an empty channel, so the close below is
// what releases them and a close that failed to wake would hang here.
fn consume(t: *Traffic) {
    while true {
        let (value, receive_error) = channel.receive[i64](&t.pipe)
        if receive_error != ok { ret }
        let summed = atomic.add(&t.total, u64(value), .Release)
        let counted = atomic.add(&t.received, 1u32, .Release)
    }
}

fn join_all(workers: []os.Thread, count: usize) -> err {
    var at = 0usize
    while at < count {
        let join_error = os.thread_join(workers[at])
        if join_error != ok { ret join_error }
        at += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena) -> err {
    var t: Traffic = zero
    let (pipe, init_error) = channel.init[i64](a, 4usize)
    if init_error != ok { ret init_error }
    t.pipe = pipe

    var producers: [4]os.Thread = zero
    var started = 0usize
    while started < 4usize {
        let (worker, create_error) = os.thread_create[Traffic](produce, &t, 1048576usize)
        if create_error == os.Unsupported { ret ok }
        if create_error != ok { ret create_error }
        producers[started] = worker
        started += 1usize
    }
    var consumers: [3]os.Thread = zero
    started = 0usize
    while started < 3usize {
        let (worker, create_error) = os.thread_create[Traffic](consume, &t, 1048576usize)
        if create_error != ok { ret create_error }
        consumers[started] = worker
        started += 1usize
    }

    try join_all(producers[..], 4usize)
    if atomic.load(&t.sent, .Acquire) != 2000u32 { ret Failed }
    if atomic.load(&t.failures, .Acquire) != 0u32 { ret Failed }

    // Closing is what lets the consumers finish: they drain what is left and stop.
    if channel.close[i64](&t.pipe) != ok { ret Failed }
    try join_all(consumers[..], 3usize)

    // Nothing lost and nothing duplicated: 4 x (1 + 2 + ... + 500).
    if atomic.load(&t.received, .Acquire) != 2000u32 { ret Failed }
    if atomic.load(&t.total, .Acquire) != 501000u64 { ret Failed }
    if channel.len[i64](&t.pipe) != 0usize { ret Failed }
    ret ok
}
