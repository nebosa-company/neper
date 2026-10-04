use e.gpu
use e.io
use e.mem
use e.simd

error WrongValue

type View = struct { data: []u32 }
type Packet = struct { value: u32, lane: u32 }
type Iter = struct { next: u32 }
type State = struct { iter: Iter }

fn iter_sync() { gpu.barrier() }

fn iter_next(it: *Iter) -> (u32, bool) {
    gpu.barrier()
    iter_sync()
    let value = it.next
    it.next += 1u32
    ret (value, value < 2u32)
}

fn inner(lane: u32) -> u32 {
    var saved = lane + 41u32
    var round = 0u32
    while round < 3u32 {
        gpu.barrier()
        saved += 1u32
        round += 1u32
    }
    ret saved
}

// Unreached device code must not make the barrier oracle reject the kernel.
fn unused(n: u32) {
    gpu.barrier()
    if n != 0u32 { unused(n - 1u32) }
}

fn combine(view: []u32, left: u32, right: u32) -> u32 { ret right + left - left + u32(view.len) - 8u32 }

fn passthrough[T: type](value: T) -> T {
    gpu.barrier()
    ret value
}

fn packed(lane: u32) -> Packet {
    gpu.barrier()
    ret Packet { value: lane + 44u32, lane: lane }
}

fn pair(lane: u32) -> (u32, u32) {
    gpu.barrier()
    ret (lane + 44u32, lane)
}

fn pair_branch(lane: u32) -> (u32, u32) {
    gpu.barrier()
    if lane % 2u32 == 0u32 { ret (lane + 44u32, lane) }
    ret (lane + 43u32, lane + 1u32)
}

fn duplicate[T: type](value: T) -> (T, T) {
    gpu.barrier()
    ret (value, value)
}

fn triple(lane: u32) -> (u32, u32, u32) {
    gpu.barrier()
    ret (lane + 44u32, lane, lane)
}

fn pair_pending(lane: u32) -> (u32, u32) {
    gpu.barrier()
    ret (lane + 44u32, passthrough(lane))
}

fn packet_pending(lane: u32) -> (Packet, u32) {
    gpu.barrier()
    ret (Packet { value: lane + 44u32, lane: lane }, passthrough(lane))
}

fn triple_pending(lane: u32) -> (u32, u32, u32) {
    gpu.barrier()
    ret (lane + 44u32, passthrough(lane), passthrough(lane))
}

fn deferred_barrier(lane: u32) -> u32 {
    defer gpu.barrier()
    ret lane + 44u32
}

fn deferred_pair(lane: u32) -> (u32, u32) {
    defer gpu.barrier()
    ret (lane + 44u32, lane)
}

fn deferred_packet(lane: u32) -> Packet {
    defer gpu.barrier()
    ret Packet { value: lane + 44u32, lane: lane }
}

fn store_captured(out: []u32, at: usize, value: u32) { out[at] = value }

fn deferred_capture(out: []u32, lane: u32) {
    var value = lane + 44u32
    defer store_captured(out, usize(lane), value)
    value = 0u32
    defer gpu.barrier()
    gpu.barrier()
}

fn middle(out: []u32, lane: u32) {
    for pass in 0u32..1u32 {
        // The store address, binary left operand and first call argument precede inner's barriers.
        if gpu.lid.x < 8u32 {
            out[usize(lane)] = lane + combine(out, lane, inner(lane)) - lane
            let view = View { data: out }
            view.data[usize(inner(lane) - 44u32)] = lane + 44u32
            view.data[usize(lane)] += inner(lane) - (lane + 44u32)
            view.data[usize(lane)] = passthrough(lane + 44u32)
            let packet = packed(lane)
            view.data[usize(lane)] = packet.value + packet.lane - lane
            let copied = passthrough(packet)
            view.data[usize(lane)] = copied.value + copied.lane - lane
            let (first, first_lane) = pair(lane)
            view.data[usize(lane)] = first + first_lane - lane
            let (second, second_lane) = pair_branch(lane)
            view.data[usize(lane)] = second + second_lane - lane
            let (third, third_lane) = duplicate(lane)
            view.data[usize(lane)] = third + 44u32 + third_lane - lane
            let (wide, wide_lane, last_lane) = triple(lane)
            view.data[usize(lane)] = wide + wide_lane - lane + last_lane - lane
            let (pending, pending_lane) = pair_pending(lane)
            view.data[usize(lane)] = pending + pending_lane - lane
            let (pending_packet, packet_lane) = packet_pending(lane)
            view.data[usize(lane)] = pending_packet.value + pending_packet.lane - lane + packet_lane - lane
            let (pending_first, pending_second, pending_third) = triple_pending(lane)
            view.data[usize(lane)] = pending_first + pending_second - lane + pending_third - lane
            let part = out[usize(lane)..passthrough(usize(lane) + 1usize)]
            view.data[usize(lane)] = part[0usize]
            let tail = out[passthrough(usize(lane))..]
            view.data[usize(lane)] = tail[0usize]
            let head = out[..passthrough(usize(lane) + 1usize)]
            view.data[usize(lane)] = head[usize(lane)]
            let single = out[passthrough(usize(lane))..passthrough(usize(lane) + 1usize)]
            view.data[usize(lane)] = single[0usize]
            if true && passthrough(true) { view.data[usize(lane)] = lane + 44u32 }
            if false || passthrough(true) { view.data[usize(lane)] = lane + 44u32 }
            var vector: Vec[u32, 4] = zero
            vector.lanes[0usize] = lane + 44u32
            var vectors: [8]Vec[u32, 4] = zero
            vectors[usize(lane)] = vector
            let added = vectors[usize(lane)] +% passthrough(vector)
            view.data[usize(lane)] = added.lanes[0usize] - (lane + 44u32)
            let saved_array = [2]u32 { lane, passthrough(lane + 44u32) }
            view.data[usize(lane)] = saved_array[0usize] + saved_array[1usize] - lane
            var skipped_total = 0u32
            for control_step in 0u32..4u32 {
                defer gpu.barrier()
                if control_step == 1u32 { continue }
                if control_step == 3u32 { break }
                skipped_total += control_step
            }
            view.data[usize(lane)] = lane + skipped_total + 42u32
            for step in lane..passthrough(lane + 1u32) {
                view.data[usize(lane)] = step + 44u32
            }
            view.data[usize(lane)] = deferred_barrier(lane)
            let (after_defer, deferred_lane) = deferred_pair(lane)
            view.data[usize(lane)] = after_defer + deferred_lane - lane
            let deferred_value = deferred_packet(lane)
            view.data[usize(lane)] = deferred_value.value + deferred_value.lane - lane
            deferred_capture(out, lane)
            var assigned_lane = 0u32
            (view.data[usize(lane)], assigned_lane) = pair(lane)
            out[usize(lane)] = view.data[usize(lane)] + assigned_lane - lane
            (view.data[usize(lane)], view.data[usize(passthrough(lane))]) = pair(lane)
            out[usize(lane)] = view.data[usize(lane)] + 44u32
            var condition_round = 0u32
            while passthrough(condition_round < 2u32) {
                out[usize(lane)] = lane + 44u32
                condition_round += 1u32
            }
            for condition_step in passthrough(lane)..passthrough(lane + 1u32) {
                out[usize(lane)] = condition_step + 44u32
            }
            var state = State { iter: Iter { next: 0u32 } }
            var total = 0u32
            for value in state.iter {
                gpu.barrier()
                total += value
            }
            out[usize(lane)] = lane + total + 43u32
            let fields = Packet { value: lane + 44u32, lane: passthrough(lane) }
            switch passthrough(fields.lane) {
            case 0u32:
                out[usize(lane)] = fields.value
            default:
                out[usize(lane)] = fields.value + fields.lane - lane
            }
            if skipped_total != 2u32 { out[usize(lane)] = 0u32 }
        }
    }
}

fn outer(out: []u32, lane: u32) {
    for pass in 0u32..1u32 {
        if gpu.lid.x < 8u32 { middle(out, lane) }
    }
}

fn fourth(out: []u32, lane: u32) {
    if gpu.lid.x < 8u32 { outer(out, lane) }
}

fn fifth(out: []u32, lane: u32) {
    if gpu.lid.x < 8u32 { fourth(out, lane) }
}

@gpu(8)
fn kernel(out: []u32) { fifth(out, gpu.lid.x) }

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { ret open_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (buf, alloc_error) = gpu.alloc[u32](q, 8usize)
    if alloc_error != ok { ret alloc_error }
    defer let _ = gpu.release(q, buf)
    try gpu.launch[kernel](q, gpu.grid1(8usize), buf)
    var output: [8]u32 = zero
    try gpu.download[u32](q, buf, output[0..])
    var at = 0usize
    while at < output.len {
        if output[at] != u32(at) + 44u32 { ret WrongValue }
        at += 1usize
    }
    try io.print("gpu barrier chain ok\n")
    ret ok
}
