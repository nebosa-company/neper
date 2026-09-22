// `e.net.reliable`: Go-Back-N over a 20-packet transfer with packets 3 and 9
// lost once retransmits the whole window twice; Selective Repeat over the
// same losses retransmits only 3 and 9 with the replica's per-receive
// delivery counts; RFC 1982 comparison around a 16-bit wrap and the
// half-space window rule; the Jacobson estimator matches the replica at
// every step and clamps tiny samples; Karn's rule holds a backed-off RTO
// until a fresh sample; AIMD slow start and congestion avoidance. Each
// check exits with its own code.

use e.io
use e.mem
use e.net.reliable as rel
use e.os

fn fnv(h: u64, v: u64) -> u64 { ret (h ^ v) *% 1099511628211u64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let bits = 16u32
    let n = 20u64
    var out: [16]u64 = zero

    // 1: Go-Back-N, window 4, timeout 3 ticks, packets 3 and 9 lost once.
    var sent_at: [8]u64 = zero
    var s = rel.sender(4usize, 3u64, sent_at[..], bits)
    var expected = 0u64
    var lost3 = false
    var lost9 = false
    var retrans: [16]u64 = zero
    var retrans_count = 0usize
    var h = 14695981039346656037u64
    var final_ack = 0u64
    var now = 0u64
    while s.base < n {
        let expired = rel.sender_timeouts(&s, now, out[..])
        var i = 0usize
        while i < expired {
            if retrans_count < 16usize { retrans[retrans_count] = out[i] }
            retrans_count += 1usize
            let (accepted, ack) = rel.receiver_go_back_n(&expected, out[i], bits)
            var acc = 0u64
            if accepted { acc = 1u64 }
            h = fnv(fnv(h, acc), ack)
            let _ = rel.sender_ack(&s, ack)
            final_ack = ack
            i += 1usize
        }
        while rel.sender_can_send(&s) && s.next_seq < n {
            let (seq, send_error) = rel.sender_send(&s, now)
            if send_error != ok { os.exit(1i32) }
            if seq == 3u64 && !lost3 {
                lost3 = true
                continue
            }
            if seq == 9u64 && !lost9 {
                lost9 = true
                continue
            }
            let (accepted, ack) = rel.receiver_go_back_n(&expected, seq, bits)
            var acc = 0u64
            if accepted { acc = 1u64 }
            h = fnv(fnv(h, acc), ack)
            let _ = rel.sender_ack(&s, ack)
            final_ack = ack
        }
        now += 1u64
    }
    if retrans_count != 8usize || final_ack != 20u64 || now != 7u64 { os.exit(1i32) }
    let want_retrans = [8]u64{ 3u64, 4u64, 5u64, 6u64, 9u64, 10u64, 11u64, 12u64 }
    var k = 0usize
    while k < 8usize {
        if retrans[k] != want_retrans[k] { os.exit(1i32) }
        k += 1usize
    }
    if h != 0x8147d110e43913cbu64 { os.exit(1i32) }
    var one_slot: [1]u64 = zero
    var narrow = rel.sender(4usize, 3u64, one_slot[..], bits)
    let (_, first_ok) = rel.sender_send(&narrow, now)
    let (_, full) = rel.sender_send(&narrow, now)
    if first_ok != ok || full != rel.Full || rel.sender_can_send(&narrow) { os.exit(1i32) }

    // 2: Selective Repeat over the same losses.
    var sr_sent: [8]u64 = zero
    var sr_acked: [8]u8 = zero
    var present: [8]u8 = zero
    let (sr0, sr_error) = rel.sr_sender(4usize, 3u64, sr_sent[..], sr_acked[..], bits)
    if sr_error != ok { os.exit(2i32) }
    var sr = sr0
    let (rcv0, rcv_error) = rel.sr_receiver(4usize, present[..], bits)
    if rcv_error != ok { os.exit(2i32) }
    var rcv = rcv0
    lost3 = false
    lost9 = false
    retrans_count = 0usize
    var total = 0usize
    h = 14695981039346656037u64
    now = 0u64
    while sr.base < n {
        let expired = rel.sr_timeouts(&sr, now, out[..])
        var i = 0usize
        while i < expired {
            if retrans_count < 16usize { retrans[retrans_count] = out[i] }
            retrans_count += 1usize
            let (deliverable, ack) = rel.sr_receive(&rcv, out[i])
            total += deliverable
            var acc = 0u64
            if ack { acc = 1u64 }
            h = fnv(fnv(h, u64(deliverable)), acc)
            if ack { let _ = rel.sr_ack(&sr, out[i]) }
            i += 1usize
        }
        while rel.sr_can_send(&sr) && sr.next_seq < n {
            let (seq, send_error) = rel.sr_send(&sr, now)
            if send_error != ok { os.exit(2i32) }
            if seq == 3u64 && !lost3 {
                lost3 = true
                continue
            }
            if seq == 9u64 && !lost9 {
                lost9 = true
                continue
            }
            let (deliverable, ack) = rel.sr_receive(&rcv, seq)
            total += deliverable
            var acc = 0u64
            if ack { acc = 1u64 }
            h = fnv(fnv(h, u64(deliverable)), acc)
            if ack { let _ = rel.sr_ack(&sr, seq) }
        }
        now += 1u64
    }
    if retrans_count != 2usize || retrans[0] != 3u64 || retrans[1] != 9u64 { os.exit(2i32) }
    if total != 20usize || now != 7u64 || rcv.rcv_base != 20u64 { os.exit(2i32) }
    if h != 0xe57f83582d9cd7c5u64 { os.exit(2i32) }
    // a duplicate just below the window is re-acked without delivery
    let (dup_n, dup_ack) = rel.sr_receive(&rcv, 19u64)
    if dup_n != 0usize || !dup_ack { os.exit(2i32) }
    let (far_n, far_ack) = rel.sr_receive(&rcv, 100u64)
    if far_n != 0usize || far_ack { os.exit(2i32) }

    // 3: RFC 1982 around the 16-bit wrap; window over half the space refused.
    if !rel.seq_less(65535u64, 0u64, bits) || rel.seq_less(0u64, 65535u64, bits) { os.exit(3i32) }
    if rel.seq_less(1u64, 32769u64, bits) || rel.seq_less(1u64, 32770u64, bits) { os.exit(3i32) }
    if !rel.seq_less(32770u64, 1u64, bits) || rel.seq_less(5u64, 5u64, bits) { os.exit(3i32) }
    if rel.seq_wrap(65536u64 + 7u64, bits) != 7u64 { os.exit(3i32) }
    var big_sent: [4]u64 = zero
    var big_acked: [4]u8 = zero
    let (_, half_error) = rel.sr_sender(3usize, 1u64, big_sent[..], big_acked[..], 2u32)
    if half_error != rel.Invalid { os.exit(3i32) }
    let (_, two_ok) = rel.sr_sender(2usize, 1u64, big_sent[..], big_acked[..], 2u32)
    if two_ok != ok { os.exit(3i32) }
    let (_, small_error) = rel.sr_receiver(8usize, present[..4usize], bits)
    if small_error != rel.TooSmall { os.exit(3i32) }

    // 4: Jacobson estimate over a fixed sample list; tiny samples clamp at min_rto.
    var e = rel.rtt(200000u64, 60000000u64)
    if rel.rtt_rto(&e) != 1000000u64 { os.exit(4i32) }
    let samples = [8]u64{ 120000u64, 130000u64, 90000u64, 400000u64, 110000u64, 115000u64, 2000000u64, 100000u64 }
    h = fnv(14695981039346656037u64, e.rto)
    k = 0usize
    while k < 8usize {
        rel.rtt_estimate(&e, samples[k])
        h = fnv(fnv(fnv(h, e.srtt), e.rttvar), e.rto)
        k += 1usize
    }
    if h != 16247551582668393991u64 { os.exit(4i32) }
    if e.srtt != 340961u64 || e.rttvar != 458692u64 || e.rto != 2175729u64 { os.exit(4i32) }
    var tiny = rel.rtt(200000u64, 60000000u64)
    rel.rtt_estimate(&tiny, 1000u64)
    rel.rtt_estimate(&tiny, 1200u64)
    if rel.rtt_rto(&tiny) != 200000u64 || tiny.srtt != 1025u64 { os.exit(4i32) }

    // 5: Karn's rule.
    var ke = rel.rtt(200000u64, 60000000u64)
    rel.rtt_estimate(&ke, 100000u64)
    if rel.rtt_rto(&ke) != 300000u64 { os.exit(5i32) }
    rel.rtt_backoff(&ke)
    if rel.rtt_rto(&ke) != 600000u64 || !ke.backed_off { os.exit(5i32) }
    if rel.rtt_karn(&ke, 500000u64, true) { os.exit(5i32) }
    if ke.srtt != 100000u64 || rel.rtt_rto(&ke) != 600000u64 || !ke.backed_off { os.exit(5i32) }
    rel.rtt_backoff(&ke)
    if rel.rtt_rto(&ke) != 1200000u64 { os.exit(5i32) }
    if !rel.rtt_karn(&ke, 100000u64, false) { os.exit(5i32) }
    if ke.backed_off || rel.rtt_rto(&ke) != 250000u64 || ke.srtt != 100000u64 { os.exit(5i32) }
    var capped = rel.rtt(200000u64, 700000u64)
    rel.rtt_backoff(&capped)
    if rel.rtt_rto(&capped) != 700000u64 { os.exit(5i32) }

    // 6: AIMD trace.
    var cwnd = 1460u64
    var ssthresh = 65535u64
    h = 14695981039346656037u64
    k = 0usize
    while k < 60usize {
        cwnd = rel.aimd_ack(cwnd, ssthresh, 1460u64)
        if k == 20usize {
            let (c, t) = rel.aimd_loss(cwnd, 1460u64, false)
            cwnd = c
            ssthresh = t
        }
        if k == 40usize {
            let (c, t) = rel.aimd_loss(cwnd, 1460u64, true)
            cwnd = c
            ssthresh = t
        }
        h = fnv(fnv(h, cwnd), ssthresh)
        k += 1usize
    }
    if cwnd != 12655u64 || ssthresh != 9261u64 || h != 13872147700439305785u64 { os.exit(6i32) }

    try io.print("net reliable ok\n")
    ret ok
}
