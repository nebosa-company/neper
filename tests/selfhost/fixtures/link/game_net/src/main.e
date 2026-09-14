// `e.net.snapshot` and `e.game.netsync` (D296). The quantisation expectations were
// derived independently. Each check returns its own number when it fails; 0 is every
// check passed.

use e.mem
use e.net.snapshot
use e.game.netsync

// Three i32 fields in a twelve-byte state: x and y over a 1000-unit map at 10 bits, and
// a signed velocity over +/-100 at 8.
fn build_schema(fields: []snapshot.Field) -> snapshot.Schema {
    fields[0usize] = snapshot.Field { offset: 0usize, bits: 10u8, signed: false, lo: 0i32, hi: 1000i32 }
    fields[1usize] = snapshot.Field { offset: 4usize, bits: 10u8, signed: false, lo: 0i32, hi: 1000i32 }
    fields[2usize] = snapshot.Field { offset: 8usize, bits: 8u8, signed: true, lo: -100i32, hi: 100i32 }
    ret snapshot.Schema { fields: fields[0usize..3usize], state_bytes: 12usize }
}

fn main() -> i64 {
    var fields: [3]snapshot.Field = zero
    let schema = build_schema(fields[..])

    // --- quantisation ------------------------------------------------------------------
    // Both ends of the range land exactly, which is what makes a clamped value safe.
    if snapshot.quantize(0i32, fields[0usize]) != 0u32 { ret 1i64 }
    if snapshot.quantize(1000i32, fields[0usize]) != 1023u32 { ret 2i64 }
    if snapshot.quantize(500i32, fields[0usize]) != 512u32 { ret 3i64 }
    if snapshot.dequantize(512u32, fields[0usize]) != 500i32 { ret 4i64 }
    if snapshot.dequantize(1023u32, fields[0usize]) != 1000i32 { ret 5i64 }
    // A signed range quantises around its midpoint.
    if snapshot.quantize(0i32, fields[2usize]) != 128u32 { ret 6i64 }
    if snapshot.dequantize(128u32, fields[2usize]) != 0i32 { ret 7i64 }
    if snapshot.quantize(-100i32, fields[2usize]) != 0u32 { ret 8i64 }
    if snapshot.quantize(100i32, fields[2usize]) != 255u32 { ret 9i64 }
    // Out of range is clamped rather than wrapped, which would put a runaway value at the
    // opposite end of the map.
    if snapshot.quantize(5000i32, fields[0usize]) != 1023u32 { ret 10i64 }
    if snapshot.quantize(-5000i32, fields[0usize]) != 0u32 { ret 11i64 }
    // A round trip at 10 bits over 1000 units is exact at every tenth value.
    var probe = 0i32
    while probe <= 1000i32 {
        if snapshot.dequantize(snapshot.quantize(probe, fields[0usize]), fields[0usize]) != probe { ret 12i64 }
        probe = probe + 10i32
    }

    // --- whole snapshots ----------------------------------------------------------------
    var state: [12]u8 = zero
    snapshot.store(state[..], 0usize, 250i32)
    snapshot.store(state[..], 4usize, 750i32)
    snapshot.store(state[..], 8usize, -37i32)
    if snapshot.load(state[..], 0usize) != 250i32 { ret 13i64 }
    if snapshot.load(state[..], 8usize) != -37i32 { ret 14i64 }

    var wire: [16]u8 = zero
    var w = snapshot.writer(wire[..])
    if snapshot.write_full(&w, schema, state[..]) != ok { ret 15i64 }
    // Ten plus ten plus eight bits, and not a byte more.
    if snapshot.bits_written(w) != 28usize { ret 16i64 }

    var restored: [12]u8 = zero
    var r = snapshot.reader(wire[..])
    if snapshot.read_full(&r, schema, restored[..]) != ok { ret 17i64 }
    if snapshot.load(restored[..], 0usize) != 250i32 { ret 18i64 }
    if snapshot.load(restored[..], 4usize) != 750i32 { ret 19i64 }
    if snapshot.load(restored[..], 8usize) != -37i32 { ret 20i64 }

    // --- deltas ---------------------------------------------------------------------------
    // Nothing changed: one presence bit per field and no payload at all. This is the whole
    // reason deltas exist -- a still world costs a bit per field, not a field per field.
    var unchanged: [16]u8 = zero
    var w2 = snapshot.writer(unchanged[..])
    if snapshot.write_delta(&w2, schema, state[..], state[..]) != ok { ret 21i64 }
    if snapshot.bits_written(w2) != 3usize { ret 22i64 }

    // One field moved: three presence bits plus that field's ten.
    var moved: [12]u8 = zero
    var at = 0usize
    while at < 12usize {
        moved[at] = state[at]
        at += 1usize
    }
    snapshot.store(moved[..], 0usize, 260i32)
    var wire3: [16]u8 = zero
    var w3 = snapshot.writer(wire3[..])
    if snapshot.write_delta(&w3, schema, state[..], moved[..]) != ok { ret 23i64 }
    if snapshot.bits_written(w3) != 13usize { ret 24i64 }

    // Reading it against the same baseline reproduces the new state, and the fields that
    // were not sent keep the baseline's values rather than zeroing.
    var applied: [12]u8 = zero
    var r3 = snapshot.reader(wire3[..])
    if snapshot.read_delta(&r3, schema, state[..], applied[..]) != ok { ret 25i64 }
    if snapshot.load(applied[..], 0usize) != 260i32 { ret 26i64 }
    if snapshot.load(applied[..], 4usize) != 750i32 { ret 27i64 }
    if snapshot.load(applied[..], 8usize) != -37i32 { ret 28i64 }

    // A change too small to survive quantisation is not a change and costs nothing.
    var nudged: [12]u8 = zero
    at = 0usize
    while at < 12usize {
        nudged[at] = state[at]
        at += 1usize
    }
    // 250 and 250 quantise alike; the field is not sent.
    snapshot.store(nudged[..], 0usize, 250i32)
    var wire4: [16]u8 = zero
    var w4 = snapshot.writer(wire4[..])
    if snapshot.write_delta(&w4, schema, state[..], nudged[..]) != ok { ret 29i64 }
    if snapshot.bits_written(w4) != 3usize { ret 30i64 }

    // --- prediction -------------------------------------------------------------------------
    var history: [8]netsync.Input = zero
    var predictor: netsync.Predictor = zero
    if netsync.init(&predictor, history[..]) != ok { ret 31i64 }
    if netsync.divergences(predictor) != 0u32 { ret 32i64 }

    if netsync.record(&predictor, netsync.Input { tick: 1u64, bits: 5u32 }) != ok { ret 33i64 }
    if netsync.record(&predictor, netsync.Input { tick: 2u64, bits: 9u32 }) != ok { ret 34i64 }
    // A recorded tick answers itself.
    let (known, known_error) = netsync.predict(predictor, 2u64)
    if known_error != ok || known.bits != 9u32 { ret 35i64 }
    // An unrecorded one repeats the most recent input, because a player holding a
    // direction keeps holding it -- and it is stamped with the tick asked for.
    let (guessed, guessed_error) = netsync.predict(predictor, 3u64)
    if guessed_error != ok { ret 36i64 }
    if guessed.bits != 9u32 { ret 37i64 }
    if guessed.tick != 3u64 { ret 38i64 }

    // --- reconciliation -----------------------------------------------------------------------
    var authoritative: [12]u8 = zero
    var local: [12]u8 = zero
    at = 0usize
    while at < 12usize {
        authoritative[at] = state[at]
        local[at] = state[at]
        at += 1usize
    }
    // The guess held: no rollback, no divergence counted.
    let (rollback, rollback_error) = netsync.confirm(&predictor, 2u64, authoritative[..], local[..])
    if rollback_error != ok { ret 39i64 }
    if rollback { ret 40i64 }
    if netsync.divergences(predictor) != 0u32 { ret 41i64 }
    if netsync.rollback_from(predictor) != 2u64 { ret 42i64 }

    // The guess did not hold: rollback is called for and the divergence is counted.
    snapshot.store(local[..], 0usize, 999i32)
    let (rollback2, rollback2_error) = netsync.confirm(&predictor, 3u64, authoritative[..], local[..])
    if rollback2_error != ok { ret 43i64 }
    if !rollback2 { ret 44i64 }
    if netsync.divergences(predictor) != 1u32 { ret 45i64 }
    if netsync.rollback_from(predictor) != 3u64 { ret 46i64 }

    // A frame older than the one already confirmed is Late: the network reordered it, and
    // acting on it would undo a correction already applied.
    let (stale, stale_error) = netsync.confirm(&predictor, 1u64, authoritative[..], local[..])
    if stale_error != netsync.Late { ret 47i64 }
    if stale { ret 48i64 }
    if netsync.divergences(predictor) != 1u32 { ret 49i64 }

    // A replay inside the ring is recoverable; one that has lapped it is not.
    if netsync.record(&predictor, netsync.Input { tick: 6u64, bits: 1u32 }) != ok { ret 50i64 }
    if netsync.replay_span(predictor) != 3u64 { ret 51i64 }
    if !netsync.recoverable(predictor) { ret 52i64 }
    if netsync.record(&predictor, netsync.Input { tick: 40u64, bits: 1u32 }) != ok { ret 53i64 }
    if netsync.recoverable(predictor) { ret 54i64 }

    // --- replication over a peer ------------------------------------------------------------
    var baseline: [12]u8 = zero
    var peer: netsync.Peer = zero
    if netsync.init_peer(&peer, baseline[..]) != ok { ret 55i64 }

    // The first frame is a delta against an all-zero baseline, so every field is sent.
    var out_wire: [16]u8 = zero
    var ow = snapshot.writer(out_wire[..])
    if netsync.encode(&ow, schema, &peer, 1u64, state[..]) != ok { ret 56i64 }
    if snapshot.bits_written(ow) != 31usize { ret 57i64 }
    if peer.acked != 1u64 { ret 58i64 }

    // Sending the same state again now costs three bits, because the peer's baseline has
    // moved on -- which is the point of adopting it.
    var second_wire: [16]u8 = zero
    var sw = snapshot.writer(second_wire[..])
    if netsync.encode(&sw, schema, &peer, 2u64, state[..]) != ok { ret 59i64 }
    if snapshot.bits_written(sw) != 3usize { ret 60i64 }

    // A receiver tracking its own baseline reproduces the sender's state exactly.
    var receiver_baseline: [12]u8 = zero
    var receiver: netsync.Peer = zero
    if netsync.init_peer(&receiver, receiver_baseline[..]) != ok { ret 61i64 }
    var received: [12]u8 = zero
    var rr = snapshot.reader(out_wire[..])
    if netsync.decode(&rr, schema, &receiver, 1u64, received[..]) != ok { ret 62i64 }
    if snapshot.load(received[..], 0usize) != 250i32 { ret 63i64 }
    if snapshot.load(received[..], 4usize) != 750i32 { ret 64i64 }
    if snapshot.load(received[..], 8usize) != -37i32 { ret 65i64 }
    if receiver.acked != 1u64 { ret 66i64 }

    ret 0i64
}
