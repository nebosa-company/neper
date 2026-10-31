// `e.dist.snapshot`: four processes pass 400 tokens around over an LCG
// schedule that sends more often than it delivers; process 1 starts a
// Chandy-Lamport snapshot at step 20 while messages are in flight, every
// process sees three markers, the recorded states and channel contents are
// the ones a Python replica records, and they add up to the 400 tokens the
// live system still holds after the pool drains. Each check exits with its
// own code.

use e.dist.snapshot as snap
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 99u64
    var pool: [256]snap.Message = zero
    var out = snap.sent(pool[..])
    var procs: [4]snap.Proc = zero
    var channels: [16]snap.Channel = zero
    let initial = [4]u64 { 100u64, 100u64, 100u64, 100u64 }
    let (s0, e0) = snap.snapshot(procs[..], channels[..], initial[..])
    if e0 != ok { os.exit(1i32) }
    var s = s0

    // 1: the schedule, with the snapshot started mid-flight.
    var head = 0usize
    var sends = 0usize
    var t = 0usize
    while t < 200usize {
        if t == 20usize {
            if out.count != 12usize || s.procs[0usize].state != 13u64 || s.procs[1usize].state != 105u64 || s.procs[2usize].state != 0u64 { os.exit(1i32) }
            if snap.snapshot_initiate(&s, 1usize, &out) != ok || snap.snapshot_complete(&s) { os.exit(1i32) }
            if snap.snapshot_initiate(&s, 1usize, &out) != snap.Invalid || out.count != 15usize { os.exit(1i32) }
        }
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r = state >> 33u32
        if r % 3u64 == 0u64 && head < out.count {
            let (_, step_error0) = snap.snapshot_step(&s, out.out[head], &out)
            if step_error0 != ok { os.exit(1i32) }
            head += 1usize
        } else {
            let f = usize(r % 4u64)
            var to = usize((r >> 4u32) % 4u64)
            if to == f { to = (to + 1usize) % 4usize }
            let amount = (r >> 8u32) % (s.procs[f].state + 1u64)
            if snap.snapshot_send(&s, f, to, amount, &out) != ok { os.exit(1i32) }
            sends += 1usize
        }
        t += 1usize
    }
    if sends != 145usize || out.count != 157usize || !snap.snapshot_complete(&s) { os.exit(1i32) }

    // 2: the recorded global state agrees with the replica and is consistent.
    let want_snap = [4]u64 { 224u64, 105u64, 0u64, 4u64 }
    var i = 0usize
    while i < 4usize {
        if s.procs[i].snapshot != want_snap[i] || s.procs[i].markers != 3usize || !s.procs[i].recorded { os.exit(2i32) }
        i += 1usize
    }
    let want_total = [16]u64 { 0u64, 6u64, 12u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 47u64, 2u64, 0u64 }
    let want_count = [16]usize { 0usize, 3usize, 3usize, 1usize, 0usize, 0usize, 0usize, 0usize, 1usize, 1usize, 0usize, 3usize, 3usize, 2usize, 3usize, 0usize }
    i = 0usize
    while i < 16usize {
        if s.channels[i].total != want_total[i] || s.channels[i].count != want_count[i] || s.channels[i].recording { os.exit(2i32) }
        i += 1usize
    }
    if snap.snapshot_total(&s) != 400u64 { os.exit(2i32) }

    // 3: draining the pool conserves the tokens; markers were consumed.
    var markers = 0usize
    while head < out.count {
        let (was_marker, step_error1) = snap.snapshot_step(&s, out.out[head], &out)
        if step_error1 != ok { os.exit(3i32) }
        if was_marker { markers += 1usize }
        head += 1usize
    }
    if snap.snapshot_live(&s) != 400u64 || out.count != 157usize { os.exit(3i32) }
    i = 0usize
    markers = 0usize
    while i < out.count {
        if out.out[i].marker { markers += 1usize }
        i += 1usize
    }
    if markers != 12usize { os.exit(3i32) }

    // 4: bad sends and shapes.
    if snap.snapshot_send(&s, 0usize, 0usize, 1u64, &out) != snap.Invalid { os.exit(4i32) }
    if snap.snapshot_send(&s, 2usize, 0usize, s.procs[2usize].state + 1u64, &out) != snap.Invalid { os.exit(4i32) }
    if snap.snapshot_send(&s, 4usize, 0usize, 0u64, &out) != snap.Invalid { os.exit(4i32) }
    if snap.snapshot_initiate(&s, 4usize, &out) != snap.Invalid { os.exit(4i32) }
    let (_, e1) = snap.snapshot(procs[..], channels[..9usize], initial[..])
    if e1 != snap.TooSmall { os.exit(4i32) }
    let (fresh, e2) = snap.snapshot(procs[..], channels[..], initial[..])
    if e2 != ok || snap.snapshot_live(&fresh) != 400u64 || snap.snapshot_complete(&fresh) { os.exit(4i32) }

    // 5: a full output pool refuses a send before moving the process state.
    var send_pool: [1]snap.Message = zero
    var send_out = snap.sent(send_pool[..])
    var send_procs: [2]snap.Proc = zero
    var send_channels: [4]snap.Channel = zero
    let send_initial = [2]u64 { 10u64, 20u64 }
    let (send_s0, send_setup_error) = snap.snapshot(send_procs[..], send_channels[..], send_initial[..])
    if send_setup_error != ok { os.exit(5i32) }
    var send_s = send_s0
    if snap.snapshot_send(&send_s, 0usize, 1usize, 3u64, &send_out) != ok { os.exit(5i32) }
    let full_send_error = snap.snapshot_send(&send_s, 0usize, 1usize, 2u64, &send_out)
    if full_send_error != snap.TooSmall || send_out.count != 1usize || send_s.procs[0usize].state != 7u64 || send_s.procs[1usize].state != 20u64 || send_out.out[0usize].amount != 3u64 { os.exit(5i32) }

    // 6: recording fails before setting snapshots or channel flags.
    var rec_pool: [1]snap.Message = zero
    var rec_out = snap.sent(rec_pool[..])
    var rec_procs: [3]snap.Proc = zero
    var rec_channels: [9]snap.Channel = zero
    let rec_initial = [3]u64 { 10u64, 20u64, 30u64 }
    let (rec_s0, rec_setup_error) = snap.snapshot(rec_procs[..], rec_channels[..], rec_initial[..])
    if rec_setup_error != ok { os.exit(6i32) }
    var rec_s = rec_s0
    let rec_error = snap.snapshot_initiate(&rec_s, 0usize, &rec_out)
    if rec_error != snap.TooSmall || rec_out.count != 0usize || rec_s.procs[0usize].recorded || rec_s.procs[0usize].snapshot != 0u64 || rec_s.channels[3usize].recording || rec_s.channels[6usize].recording { os.exit(6i32) }

    // A first marker has the same all-or-nothing recording behavior.
    var step_pool: [2]snap.Message = zero
    var step_out = snap.sent(step_pool[..])
    var step_procs: [3]snap.Proc = zero
    var step_channels: [9]snap.Channel = zero
    let step_initial = [3]u64 { 10u64, 20u64, 30u64 }
    let (step_s0, step_setup_error) = snap.snapshot(step_procs[..], step_channels[..], step_initial[..])
    if step_setup_error != ok { os.exit(7i32) }
    var step_s = step_s0
    if snap.snapshot_initiate(&step_s, 0usize, &step_out) != ok || step_out.count != 2usize { os.exit(7i32) }
    let (was_marker, step_error2) = snap.snapshot_step(&step_s, step_out.out[0usize], &step_out)
    if !was_marker || step_error2 != snap.TooSmall || step_out.count != 2usize || step_s.procs[1usize].recorded || step_s.procs[1usize].snapshot != 0u64 || step_s.procs[1usize].state != 20u64 || step_s.procs[1usize].markers != 0usize || step_s.channels[1usize].recording || step_s.channels[7usize].recording { os.exit(7i32) }

    // 7: the scripted API returns the capacity error from first-marker recording.
    var script_pool: [1]snap.Message = zero
    var script_out = snap.sent(script_pool[..])
    var script_procs: [3]snap.Proc = zero
    var script_channels: [9]snap.Channel = zero
    let script_initial = [3]u64 { 10u64, 20u64, 30u64 }
    let script = [1]snap.Op { snap.Op { kind: .Initiate, from: 0u32, to: 0u32, amount: 0u64 } }
    let (_, _, script_error) = snap.chandy_lamport(script_procs[..], script_channels[..], script_initial[..], script[..], &script_out)
    if script_error != snap.TooSmall || script_out.count != 0usize || script_procs[0usize].recorded || script_procs[0usize].snapshot != 0u64 || script_channels[3usize].recording || script_channels[6usize].recording { os.exit(8i32) }

    try io.print("dist snapshot ok\n")
    ret ok
}
