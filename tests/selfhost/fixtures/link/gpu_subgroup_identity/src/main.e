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
fn subgroup_collectives(identity: []u32, flags: []u32, ballots: []u64) {
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
}

fn run(a: *mem.Arena, backend: gpu.Backend, index: u32, identity: []u32, flags: []u32, ballots: []u64) -> err {
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
    try gpu.launch[subgroup_collectives](q, gpu.grid1(identity.len), identity_buffer, flags_buffer, ballots_buffer)
    try gpu.download(q, identity_buffer, identity)
    try gpu.download(q, flags_buffer, flags)
    ret gpu.download(q, ballots_buffer, ballots)
}

fn valid(identity: []const u32, flags: []const u32, ballots: []const u64) -> bool {
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
        at += 1usize
    }
    ret elected == (identity.len + usize(width) - 1usize) / usize(width)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var identity: [40]u32 = zero
    var flags: [40]u32 = zero
    var ballots: [40]u64 = zero
    try run(a, .Cpu, 0u32, identity[0..], flags[0..], ballots[0..])
    if !valid(identity[0..], flags[0..], ballots[0..]) || identity[0usize] / 65536u32 != 32u32 { os.exit(1i32) }
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
            try run(a, .Vulkan, u32(device_at), device_identity[0..], device_flags[0..], device_ballots[0..])
            if !valid(device_identity[0..], device_flags[0..], device_ballots[0..]) { os.exit(2i32) }
            ran += 1usize
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
