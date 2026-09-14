// The half of netcode that is not a socket (D249): an input history, prediction ahead of
// the server, and reconciliation when an authoritative frame arrives.
//
// Nothing here opens a connection or knows one exists. What it does is the part that is
// hard and that a transport cannot help with: deciding what a client should simulate
// before it has been told, and detecting that it guessed wrong. A game wires whatever
// carries bytes -- a socket, a pipe, a test harness looping frames back with a delay --
// and this stays the same.
//
// Detection is by comparing the authoritative state against what this peer simulated for
// the same tick, byte for byte. That comparison is only meaningful because the whole
// engine core is integer: with floats, two machines that agreed perfectly would still
// differ in the last bit and every tick would look like a desync.

use e.mem
use e.net.snapshot

type Input = struct {
    tick: u64,
    bits: u32,
}

// What a peer has acknowledged, and the state it acknowledged -- the baseline a delta is
// written against.
type Peer = struct {
    acked: u64,
    baseline: []u8,
}

type Predictor = struct {
    inputs: []Input,
    head: usize,
    confirmed: u64,
    predicted: u64,
    divergences: u32,
}

error Desync
error Late
error Size

const NO_TICK: u64 = 18446744073709551615u64

fn init(p: *Predictor, inputs: []Input) -> err {
    if inputs.len == 0usize { ret Size }
    var at = 0usize
    while at < inputs.len {
        inputs[at] = Input { tick: NO_TICK, bits: 0u32 }
        at += 1usize
    }
    p.inputs = inputs
    p.head = 0usize
    p.confirmed = 0u64
    p.predicted = 0u64
    p.divergences = 0u32
    ret ok
}

// The ring is indexed by tick, so a sample lands in the same slot every lap and an old
// one is overwritten by the tick that laps it rather than by arrival order.
fn slot_of(p: Predictor, tick: u64) -> usize {
    ret usize(tick % u64(p.inputs.len))
}

fn record(p: *Predictor, sample: Input) -> err {
    let slot = slot_of(*p, sample.tick)
    p.inputs[slot] = sample
    if sample.tick > p.predicted { p.predicted = sample.tick }
    ret ok
}

fn known(p: Predictor, tick: u64) -> bool {
    ret p.inputs[slot_of(p, tick)].tick == tick
}

// The input actually recorded for a tick, or -- when it has not arrived -- the most
// recent one that has. Repeating the last input is the standard guess because a player
// holding a direction keeps holding it, so it is right far more often than zero would be.
fn predict(p: Predictor, tick: u64) -> (Input, err) {
    if known(p, tick) { ret (p.inputs[slot_of(p, tick)], ok) }
    var back = tick
    var steps = 0usize
    while steps < p.inputs.len {
        if back == 0u64 { break }
        back = back - 1u64
        steps += 1usize
        if known(p, back) { ret (Input { tick: tick, bits: p.inputs[slot_of(p, back)].bits }, ok) }
    }
    ret (Input { tick: tick, bits: 0u32 }, Late)
}

fn same_bytes(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if a[at] != b[at] { ret false }
        at += 1usize
    }
    ret true
}

// An authoritative frame lands. Answers whether the local simulation has to be rolled
// back and replayed: false when the guess held, true when it did not. A tick older than
// the one already confirmed is `Late` -- the network reordered it, and acting on it would
// undo a correction already applied.
fn confirm(p: *Predictor, tick: u64, authoritative: []const u8, local: []const u8) -> (bool, err) {
    if tick < p.confirmed { ret (false, Late) }
    p.confirmed = tick
    if tick > p.predicted { p.predicted = tick }
    if same_bytes(authoritative, local) { ret (false, ok) }
    p.divergences = p.divergences + 1u32
    ret (true, ok)
}

// Where a replay starts: the authoritative tick, whose state is now known good. Every
// tick after it is resimulated from the inputs still in the ring.
fn rollback_from(p: Predictor) -> u64 {
    ret p.confirmed
}

// How many ticks a replay has to cover. A window wider than the ring means inputs have
// been lapped and the replay cannot be exact, which is a caller's problem to notice.
fn replay_span(p: Predictor) -> u64 {
    if p.predicted <= p.confirmed { ret 0u64 }
    ret p.predicted - p.confirmed
}

fn recoverable(p: Predictor) -> bool {
    ret replay_span(p) <= u64(p.inputs.len)
}

fn divergences(p: Predictor) -> u32 {
    ret p.divergences
}

// --- replication --------------------------------------------------------------------

fn init_peer(peer: *Peer, baseline: []u8) -> err {
    if baseline.len == 0usize { ret Size }
    var at = 0usize
    while at < baseline.len {
        baseline[at] = 0u8
        at += 1usize
    }
    peer.acked = 0u64
    peer.baseline = baseline
    ret ok
}

// Write the state as a delta against what this peer last acknowledged, and adopt it as
// the new baseline. The adoption is deliberate and it is also the risk: the sender is
// assuming the frame arrives. A transport that can drop has to re-acknowledge, which is
// what `Peer.acked` is for.
fn encode(w: *snapshot.Writer, s: snapshot.Schema, peer: *Peer, tick: u64, state: []const u8) -> err {
    try snapshot.write_delta(w, s, peer.baseline, state)
    var at = 0usize
    while at < peer.baseline.len && at < state.len {
        peer.baseline[at] = state[at]
        at += 1usize
    }
    peer.acked = tick
    ret ok
}

fn decode(r: *snapshot.Reader, s: snapshot.Schema, peer: *Peer, tick: u64, out: []u8) -> err {
    try snapshot.read_delta(r, s, peer.baseline, out)
    var at = 0usize
    while at < peer.baseline.len && at < out.len {
        peer.baseline[at] = out[at]
        at += 1usize
    }
    peer.acked = tick
    ret ok
}
