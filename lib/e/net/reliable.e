// Reliable-transfer state machines over caller storage, driven by explicit
// events: no sockets and no clocks, the caller passes `now`. `Sender` is a
// Go-Back-N sender (one timer on the oldest packet, cumulative acks,
// `receiver_go_back_n` accepts only the next in-order packet); `SrSender`
// and `SrReceiver` are Selective Repeat (per-packet acks and timers, a
// presence bitmap on the receiver, window at most half the sequence space);
// `Rtt` is the RFC 6298 / Jacobson-Karels estimator in integer microseconds
// with `rtt_backoff` and Karn's rule in `rtt_karn`; `aimd_ack` / `aimd_loss`
// are RFC 5681 slow start and congestion avoidance.
//
// Sequence numbers on the wire are `bits` wide (`seq_wrap`, `seq_less` is
// RFC 1982 serial comparison); the senders and receivers keep unbounded
// counters (`base`, `next_seq`, `rcv_base`) and slot storage indexed by
// counter modulo its length, so a slot slice of at least `window` entries
// is enough for any transfer length.

type Sender = struct { base: u64, next_seq: u64, window: usize, timeout: u64, sent_at: []u64, bits: u32 }
type SrSender = struct { base: u64, next_seq: u64, window: usize, timeout: u64, sent_at: []u64, acked: []u8, bits: u32 }
type SrReceiver = struct { rcv_base: u64, window: usize, present: []u8, bits: u32 }
type Rtt = struct { srtt: u64, rttvar: u64, rto: u64, min_rto: u64, max_rto: u64, has_sample: bool, backed_off: bool }
error Full
error Invalid
error TooSmall

// ---- sequence numbers -----------------------------------------------------

fn seq_mask(bits: u32) -> u64 {
    if bits >= 64u32 { ret ~0u64 }
    ret (1u64 << bits) - 1u64
}

// `seq` reduced to `bits` on-wire bits.
fn seq_wrap(seq: u64, bits: u32) -> u64 { ret seq & seq_mask(bits) }

// RFC 1982 serial-number comparison: is `a` before `b` in a `bits`-wide
// circular space (`bits` at most 63)? Exactly half apart is neither.
fn seq_less(a: u64, b: u64, bits: u32) -> bool {
    let half = 1u64 << (bits - 1u32)
    let x = seq_wrap(a, bits)
    let y = seq_wrap(b, bits)
    if x < y { ret y - x < half }
    if x > y { ret x - y > half }
    ret false
}

// ---- Go-Back-N ------------------------------------------------------------

// A Go-Back-N sender; `sent_at` needs at least `window` slots (fewer caps the window).
fn sender(window: usize, timeout: u64, sent_at: []u64, bits: u32) -> Sender {
    ret Sender { base: 0u64, next_seq: 0u64, window: window, timeout: timeout, sent_at: sent_at, bits: bits }
}

fn sender_in_flight(s: *const Sender) -> usize { ret usize(s.next_seq - s.base) }

fn sender_can_send(s: *const Sender) -> bool {
    let in_flight = sender_in_flight(s)
    ret in_flight < s.window && in_flight < s.sent_at.len
}

// Stamp and hand out the next sequence number (on the wire); `Full` when the window is closed.
fn sender_send(s: *Sender, now: u64) -> (u64, err) {
    if !sender_can_send(s) { ret (0u64, Full) }
    let seq = s.next_seq
    s.sent_at[usize(seq % u64(s.sent_at.len))] = now
    s.next_seq += 1u64
    ret (seq_wrap(seq, s.bits), ok)
}

// A cumulative ack: `ack_seq` is the receiver's next expected number on the
// wire; everything before it is done. Answers whether the base moved.
fn sender_ack(s: *Sender, ack_seq: u64) -> bool {
    let d = (ack_seq -% seq_wrap(s.base, s.bits)) & seq_mask(s.bits)
    if d == 0u64 || d > s.next_seq - s.base { ret false }
    s.base += d
    ret true
}

// When the oldest unacked packet has waited `timeout`, every packet in
// flight is restamped at `now` and listed (on the wire) into `out`;
// answers the count written (capped by `out.len`).
fn sender_timeouts(s: *Sender, now: u64, out: []u64) -> usize {
    if s.base == s.next_seq { ret 0usize }
    if now - s.sent_at[usize(s.base % u64(s.sent_at.len))] < s.timeout { ret 0usize }
    var n = 0usize
    var seq = s.base
    while seq < s.next_seq {
        s.sent_at[usize(seq % u64(s.sent_at.len))] = now
        if n < out.len {
            out[n] = seq_wrap(seq, s.bits)
            n += 1usize
        }
        seq += 1u64
    }
    ret n
}

// The Go-Back-N receiver over one counter: `seq` (on the wire) is accepted
// only when it is the next expected packet; the ack is the next expected
// number afterwards (cumulative).
fn receiver_go_back_n(expected: *u64, seq: u64, bits: u32) -> (bool, u64) {
    if seq == seq_wrap(*expected, bits) {
        *expected += 1u64
        ret (true, seq_wrap(*expected, bits))
    }
    ret (false, seq_wrap(*expected, bits))
}

// ---- Selective Repeat ----------------------------------------------------

fn half_space_ok(window: usize, bits: u32) -> bool {
    if bits >= 64u32 { ret true }
    ret u64(window) <= (1u64 << bits) / 2u64
}

// An SR sender with per-packet timers and acks; `Invalid` when the window
// exceeds half the sequence space, `TooSmall` when the slots are fewer than it.
fn sr_sender(window: usize, timeout: u64, sent_at: []u64, acked: []u8, bits: u32) -> (SrSender, err) {
    let s = SrSender { base: 0u64, next_seq: 0u64, window: window, timeout: timeout, sent_at: sent_at, acked: acked, bits: bits }
    if window == 0usize || !half_space_ok(window, bits) { ret (s, Invalid) }
    if sent_at.len < window || acked.len < window { ret (s, TooSmall) }
    ret (s, ok)
}

fn sr_can_send(s: *const SrSender) -> bool { ret usize(s.next_seq - s.base) < s.window }

fn sr_send(s: *SrSender, now: u64) -> (u64, err) {
    if !sr_can_send(s) { ret (0u64, Full) }
    let seq = s.next_seq
    let slot = usize(seq % u64(s.sent_at.len))
    s.sent_at[slot] = now
    s.acked[slot] = 0u8
    s.next_seq += 1u64
    ret (seq_wrap(seq, s.bits), ok)
}

// A per-packet ack (on the wire); answers whether the base advanced.
fn sr_ack(s: *SrSender, seq: u64) -> bool {
    let d = (seq -% seq_wrap(s.base, s.bits)) & seq_mask(s.bits)
    if d >= s.next_seq - s.base { ret false }
    s.acked[usize((s.base + d) % u64(s.sent_at.len))] = 1u8
    var advanced = false
    while s.base < s.next_seq && s.acked[usize(s.base % u64(s.sent_at.len))] != 0u8 {
        s.base += 1u64
        advanced = true
    }
    ret advanced
}

// Every unacked packet whose timer expired is restamped and listed into `out`.
fn sr_timeouts(s: *SrSender, now: u64, out: []u64) -> usize {
    var n = 0usize
    var seq = s.base
    while seq < s.next_seq {
        let slot = usize(seq % u64(s.sent_at.len))
        if s.acked[slot] == 0u8 && now - s.sent_at[slot] >= s.timeout {
            s.sent_at[slot] = now
            if n < out.len {
                out[n] = seq_wrap(seq, s.bits)
                n += 1usize
            }
        }
        seq += 1u64
    }
    ret n
}

// An SR receiver: `present` marks buffered packets (at least `window` slots, zeroed).
fn sr_receiver(window: usize, present: []u8, bits: u32) -> (SrReceiver, err) {
    let r = SrReceiver { rcv_base: 0u64, window: window, present: present, bits: bits }
    if window == 0usize || !half_space_ok(window, bits) { ret (r, Invalid) }
    if present.len < window { ret (r, TooSmall) }
    ret (r, ok)
}

// A packet `seq` (on the wire) arrives: answers how many in-order packets
// from `rcv_base` can now be delivered (the base moves past them) and
// whether to ack it (in window, or a duplicate just below it).
fn sr_receive(r: *SrReceiver, seq: u64) -> (usize, bool) {
    let d = (seq -% seq_wrap(r.rcv_base, r.bits)) & seq_mask(r.bits)
    if d < u64(r.window) {
        let slots = u64(r.present.len)
        r.present[usize((r.rcv_base + d) % slots)] = 1u8
        var n = 0usize
        while r.present[usize(r.rcv_base % slots)] != 0u8 {
            r.present[usize(r.rcv_base % slots)] = 0u8
            r.rcv_base += 1u64
            n += 1usize
        }
        ret (n, true)
    }
    if seq_mask(r.bits) - d + 1u64 <= u64(r.window) { ret (0usize, true) }
    ret (0usize, false)
}

// ---- RTT estimation (RFC 6298) -------------------------------------------

fn rtt_clamp(e: *Rtt) {
    if e.rto < e.min_rto { e.rto = e.min_rto }
    if e.rto > e.max_rto { e.rto = e.max_rto }
}

// An estimator in microseconds; the RTO starts at one second, clamped to [min_rto, max_rto].
fn rtt(min_rto: u64, max_rto: u64) -> Rtt {
    var e = Rtt { srtt: 0u64, rttvar: 0u64, rto: 1000000u64, min_rto: min_rto, max_rto: max_rto, has_sample: false, backed_off: false }
    rtt_clamp(&e)
    ret e
}

// Jacobson-Karels update with one sample: first SRTT = R, RTTVAR = R/2;
// then RTTVAR = 3/4 RTTVAR + 1/4 |SRTT - R|, SRTT = 7/8 SRTT + 1/8 R;
// RTO = SRTT + max(1 ms, 4 RTTVAR), clamped. Clears any backoff.
fn rtt_estimate(e: *Rtt, sample_us: u64) {
    if !e.has_sample {
        e.srtt = sample_us
        e.rttvar = sample_us / 2u64
        e.has_sample = true
    } else {
        var diff = 0u64
        if e.srtt > sample_us { diff = e.srtt - sample_us } else { diff = sample_us - e.srtt }
        e.rttvar = (3u64 * e.rttvar + diff) / 4u64
        e.srtt = (7u64 * e.srtt + sample_us) / 8u64
    }
    var spread = 4u64 * e.rttvar
    if spread < 1000u64 { spread = 1000u64 }
    e.rto = e.srtt + spread
    e.backed_off = false
    rtt_clamp(e)
}

// Exponential backoff on a timeout: the RTO doubles (clamped) and stays
// backed off until a fresh sample is taken.
fn rtt_backoff(e: *Rtt) {
    e.rto = e.rto * 2u64
    e.backed_off = true
    rtt_clamp(e)
}

// Karn's rule: a sample from a retransmitted segment is ignored (the
// backed-off RTO stays); a fresh one feeds `rtt_estimate`. Answers whether it was taken.
fn rtt_karn(e: *Rtt, sample_us: u64, was_retransmitted: bool) -> bool {
    if was_retransmitted { ret false }
    rtt_estimate(e, sample_us)
    ret true
}

fn rtt_rto(e: *const Rtt) -> u64 { ret e.rto }

// ---- AIMD (RFC 5681) -----------------------------------------------------

// The congestion window after one ack: slow start below `ssthresh`, else one
// MSS per window (at least one byte per ack).
fn aimd_ack(cwnd: u64, ssthresh: u64, mss: u64) -> u64 {
    if cwnd < ssthresh { ret cwnd + mss }
    var step = mss * mss / cwnd
    if step == 0u64 { step = 1u64 }
    ret cwnd + step
}

// After a loss: ssthresh = max(cwnd/2, 2 MSS); the window drops to one MSS
// on a timeout, to ssthresh on fast retransmit. Answers (cwnd, ssthresh).
fn aimd_loss(cwnd: u64, mss: u64, timeout: bool) -> (u64, u64) {
    var ssthresh = cwnd / 2u64
    if ssthresh < 2u64 * mss { ssthresh = 2u64 * mss }
    if timeout { ret (mss, ssthresh) }
    ret (ssthresh, ssthresh)
}
