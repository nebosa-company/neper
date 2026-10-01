// Subgroup identity and collectives on a full and a partial subgroup.
use e.gpu
use e.io
use e.mem
use e.os

fn supports(caps: []const gpu.Cap, wanted: gpu.Cap) -> bool {
    for capability in caps {
        if capability == wanted { ret true }
    }
    ret false
}

@gpu(40, caps(.Subgroup, .Int64))
fn subgroup_collectives(identity: []u32, flags: []u32, ballots: []u64, broadcasts: []u32, shuffles: []u64) {
    var elected = 0u32
    if gpu.subgroup_elect() { elected = 1u32 }
    let at = usize(gpu.lid.x)
    let width = gpu.subgroup_size()
    identity[at] = width * 65536u32 + elected * 256u32 + gpu.sid
    flags[at] = 0u32
    let all = gpu.subgroup_all(gpu.sid < gpu.subgroup_size())
    if all { flags[usize(gpu.lid.x)] = 1u32 }
    let any = gpu.subgroup_any(gpu.sid + 1u32 == gpu.subgroup_size())
    if any { flags[usize(gpu.lid.x)] = flags[usize(gpu.lid.x)] | 2u32 }
    let ballot = gpu.subgroup_ballot(gpu.sid % 3u32 == 0u32)
    ballots[usize(gpu.lid.x)] = ballot
    let broadcast = gpu.subgroup_broadcast(gpu.lid.x + 100u32, 0u32)
    let shuffled = gpu.subgroup_shuffle(u64(gpu.lid.x) * 7u64, gpu.sid ^ 1u32)
    broadcasts[at] = broadcast
    shuffles[at] = shuffled
}

@gpu(40, caps(.Subgroup))
fn subgroup_scalar_exchange(signed_values: []i32, float_values: []f32, widths: []u32) {
    let at = usize(gpu.lid.x)
    let broadcast = gpu.subgroup_broadcast(i32(gpu.lid.x) - 20i32, 0u32)
    let shuffled = gpu.subgroup_shuffle(f32(gpu.lid.x) + 0.25f32, gpu.sid ^ 1u32)
    signed_values[at] = broadcast
    float_values[at] = shuffled
    widths[at] = gpu.subgroup_size()
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, identity: []u32, flags: []u32, ballots: []u64, broadcasts: []u32, shuffles: []u64) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    if backend == .Vulkan && (!gpu.has(device, .Subgroup) || !gpu.has(device, .Int64)) { ret gpu.Unsupported }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (identity_buffer, identity_error) = gpu.alloc[u32](q, identity.len)
    if identity_error != ok { ret identity_error }
    defer let _ = gpu.release(q, identity_buffer)
    let (flags_buffer, flags_error) = gpu.alloc[u32](q, flags.len)
    if flags_error != ok { ret flags_error }
    defer let _ = gpu.release(q, flags_buffer)
    let (ballots_buffer, ballots_error) = gpu.alloc[u64](q, ballots.len)
    if ballots_error != ok { ret ballots_error }
    defer let _ = gpu.release(q, ballots_buffer)
    let (broadcasts_buffer, broadcasts_error) = gpu.alloc[u32](q, broadcasts.len)
    if broadcasts_error != ok { ret broadcasts_error }
    defer let _ = gpu.release(q, broadcasts_buffer)
    let (shuffles_buffer, shuffles_error) = gpu.alloc[u64](q, shuffles.len)
    if shuffles_error != ok { ret shuffles_error }
    defer let _ = gpu.release(q, shuffles_buffer)
    try gpu.launch[subgroup_collectives](q, gpu.grid1(identity.len), identity_buffer, flags_buffer, ballots_buffer, broadcasts_buffer, shuffles_buffer)
    try gpu.download(q, identity_buffer, identity)
    try gpu.download(q, flags_buffer, flags)
    try gpu.download(q, ballots_buffer, ballots)
    try gpu.download(q, broadcasts_buffer, broadcasts)
    ret gpu.download(q, shuffles_buffer, shuffles)
}

fn run_scalars(a: *mem.Arena, backend: gpu.Backend, index: u32, signed_values: []i32, float_values: []f32, widths: []u32) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (signed_buffer, signed_error) = gpu.alloc[i32](q, signed_values.len)
    if signed_error != ok { ret signed_error }
    let (float_buffer, float_error) = gpu.alloc[f32](q, float_values.len)
    if float_error != ok { ret float_error }
    let (width_buffer, width_error) = gpu.alloc[u32](q, widths.len)
    if width_error != ok { ret width_error }
    try gpu.launch[subgroup_scalar_exchange](q, gpu.grid1(signed_values.len), signed_buffer, float_buffer, width_buffer)
    try gpu.download(q, signed_buffer, signed_values)
    try gpu.download(q, float_buffer, float_values)
    ret gpu.download(q, width_buffer, widths)
}

fn valid(identity: []const u32, flags: []const u32, ballots: []const u64, broadcasts: []const u32, shuffles: []const u64) -> bool {
    var elected = 0usize
    var at = 0usize
    var width = 0u32
    while at < identity.len {
        let value = identity[at]
        let lane = value & 255u32
        let chosen = (value / 256u32) & 255u32
        let seen_width = value / 65536u32
        if seen_width < 4u32 || seen_width > 64u32 || lane >= seen_width { ret false }
        if at == 0usize { width = seen_width }
        if seen_width != width || lane != u32(at) % width { ret false }
        if chosen != 0u32 {
            if chosen != 1u32 || lane != 0u32 { ret false }
            elected += 1usize
        }
        let first = at / usize(width) * usize(width)
        var active = usize(width)
        if first + active > identity.len { active = identity.len - first }
        var expected_flags = 1u32
        if active == usize(width) { expected_flags = 3u32 }
        if flags[at] != expected_flags { ret false }
        var expected_ballot = 0u64
        var bit = 0usize
        while bit < active {
            if bit % 3usize == 0usize { expected_ballot = expected_ballot | (1u64 << u32(bit)) }
            bit += 1usize
        }
        if ballots[at] != expected_ballot { ret false }
        if broadcasts[at] != u32(first) + 100u32 { ret false }
        let partner = (at - first) ^ 1usize
        if shuffles[at] != u64(first + partner) * 7u64 { ret false }
        at += 1usize
    }
    ret elected == (identity.len + usize(width) - 1usize) / usize(width)
}

fn valid_scalars(signed_values: []const i32, float_values: []const f32, widths: []const u32) -> bool {
    var at = 0usize
    while at < signed_values.len {
        let width = usize(widths[at])
        if width < 4usize || width > 64usize { ret false }
        let first = at / width * width
        let partner = (at - first) ^ 1usize
        if signed_values[at] != i32(first) - 20i32 { ret false }
        if mem.bitcast[u32](float_values[at]) != mem.bitcast[u32](f32(first + partner) + 0.25f32) { ret false }
        at += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var identity: [40]u32 = zero
    var flags: [40]u32 = zero
    var ballots: [40]u64 = zero
    var broadcasts: [40]u32 = zero
    var shuffles: [40]u64 = zero
    try run(a, .Cpu, 0u32, identity[0..], flags[0..], ballots[0..], broadcasts[0..], shuffles[0..])
    if !valid(identity[0..], flags[0..], ballots[0..], broadcasts[0..], shuffles[0..]) || identity[0usize] / 65536u32 != 32u32 { os.exit(1i32) }
    var signed_values: [40]i32 = zero
    var float_values: [40]f32 = zero
    var widths: [40]u32 = zero
    try run_scalars(a, .Cpu, 0u32, signed_values[0..], float_values[0..], widths[0..])
    if !valid_scalars(signed_values[0..], float_values[0..], widths[0..]) { os.exit(1i32) }
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu subgroup identity cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var device_at = 0usize
    while device_at < found.len {
        if found[device_at].supported && supports(found[device_at].capabilities, .Subgroup) && supports(found[device_at].capabilities, .Int64) {
            var device_identity: [40]u32 = zero
            var device_flags: [40]u32 = zero
            var device_ballots: [40]u64 = zero
            var device_broadcasts: [40]u32 = zero
            var device_shuffles: [40]u64 = zero
            try run(a, .Vulkan, u32(device_at), device_identity[0..], device_flags[0..], device_ballots[0..], device_broadcasts[0..], device_shuffles[0..])
            if !valid(device_identity[0..], device_flags[0..], device_ballots[0..], device_broadcasts[0..], device_shuffles[0..]) { os.exit(2i32) }
            ran += 1usize
        }
        if found[device_at].supported && supports(found[device_at].capabilities, .Subgroup) && supports(found[device_at].capabilities, .DenormPreserve) {
            var device_signed: [40]i32 = zero
            var device_float: [40]f32 = zero
            var device_widths: [40]u32 = zero
            try run_scalars(a, .Vulkan, u32(device_at), device_signed[0..], device_float[0..], device_widths[0..])
            if !valid_scalars(device_signed[0..], device_float[0..], device_widths[0..]) { os.exit(3i32) }
        }
        device_at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu subgroup identity cpu only\n")
        ret ok
    }
    try io.printf["gpu subgroup identity vulkan ok on {} devices\n"](ran)
    ret ok
}
