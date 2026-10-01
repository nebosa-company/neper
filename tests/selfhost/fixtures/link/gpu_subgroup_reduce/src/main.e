// Arithmetic and bitwise subgroup reductions over a full and partial subgroup.
use e.gpu
use e.io
use e.mem
use e.os

const LANES: usize = 40usize
const INTEGER_STRIDE: usize = 13usize
const SIGNED_STRIDE: usize = 7usize
const FLOAT_STRIDE: usize = 3usize

fn supports(caps: []const gpu.Cap, wanted: gpu.Cap) -> bool {
    for capability in caps {
        if capability == wanted { ret true }
    }
    ret false
}

@gpu(40, caps(.Subgroup, .Int64))
fn reduce_integer(values: []u64) {
    let at = usize(gpu.lid.x) * INTEGER_STRIDE
    let width = gpu.subgroup_size()
    let narrow = gpu.sid + 1u32
    let add32 = gpu.subgroup_add(narrow)
    let min32 = gpu.subgroup_min(narrow)
    let max32 = gpu.subgroup_max(narrow)
    let and32 = gpu.subgroup_and(narrow)
    let or32 = gpu.subgroup_or(narrow)
    let xor32 = gpu.subgroup_xor(narrow)
    let wide = u64(gpu.sid) + 4294967296u64
    let add64 = gpu.subgroup_add(wide)
    let min64 = gpu.subgroup_min(wide)
    let max64 = gpu.subgroup_max(wide)
    let and64 = gpu.subgroup_and(wide)
    let or64 = gpu.subgroup_or(wide)
    let xor64 = gpu.subgroup_xor(wide)
    values[at] = u64(width)
    values[at + 1usize] = u64(add32)
    values[at + 2usize] = u64(min32)
    values[at + 3usize] = u64(max32)
    values[at + 4usize] = u64(and32)
    values[at + 5usize] = u64(or32)
    values[at + 6usize] = u64(xor32)
    values[at + 7usize] = add64
    values[at + 8usize] = min64
    values[at + 9usize] = max64
    values[at + 10usize] = and64
    values[at + 11usize] = or64
    values[at + 12usize] = xor64
}

@gpu(40, caps(.Subgroup))
fn reduce_scalars(signed_values: []i32, float_values: []f32) {
    let signed_at = usize(gpu.lid.x) * SIGNED_STRIDE
    let width = gpu.subgroup_size()
    let signed = i32(gpu.sid) - 16i32
    let signed_add = gpu.subgroup_add(signed)
    let signed_min = gpu.subgroup_min(signed)
    let signed_max = gpu.subgroup_max(signed)
    let signed_and = gpu.subgroup_and(signed)
    let signed_or = gpu.subgroup_or(signed)
    let signed_xor = gpu.subgroup_xor(signed)
    let float_at = usize(gpu.lid.x) * FLOAT_STRIDE
    let floating = f32(gpu.sid) + 0.5f32
    let float_add = gpu.subgroup_add(floating)
    let float_min = gpu.subgroup_min(floating)
    let float_max = gpu.subgroup_max(floating)
    signed_values[signed_at] = i32(width)
    signed_values[signed_at + 1usize] = signed_add
    signed_values[signed_at + 2usize] = signed_min
    signed_values[signed_at + 3usize] = signed_max
    signed_values[signed_at + 4usize] = signed_and
    signed_values[signed_at + 5usize] = signed_or
    signed_values[signed_at + 6usize] = signed_xor
    float_values[float_at] = float_add
    float_values[float_at + 1usize] = float_min
    float_values[float_at + 2usize] = float_max
}

fn run_integer(a: *mem.Arena, backend: gpu.Backend, index: u32, values: []u64) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (buffer, buffer_error) = gpu.alloc[u64](q, values.len)
    if buffer_error != ok { ret buffer_error }
    defer let _ = gpu.release(q, buffer)
    try gpu.launch[reduce_integer](q, gpu.grid1(LANES), buffer)
    ret gpu.download(q, buffer, values)
}

fn run_scalars(a: *mem.Arena, backend: gpu.Backend, index: u32, signed_values: []i32, float_values: []f32) -> err {
    let (device, device_error) = gpu.open(a, backend, index)
    if device_error != ok { ret device_error }
    defer let _ = gpu.close(device)
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (signed_buffer, signed_error) = gpu.alloc[i32](q, signed_values.len)
    if signed_error != ok { ret signed_error }
    defer let _ = gpu.release(q, signed_buffer)
    let (float_buffer, float_error) = gpu.alloc[f32](q, float_values.len)
    if float_error != ok { ret float_error }
    defer let _ = gpu.release(q, float_buffer)
    try gpu.launch[reduce_scalars](q, gpu.grid1(LANES), signed_buffer, float_buffer)
    try gpu.download(q, signed_buffer, signed_values)
    ret gpu.download(q, float_buffer, float_values)
}

fn valid_integer(values: []const u64) -> bool {
    var lane = 0usize
    while lane < LANES {
        let at = lane * INTEGER_STRIDE
        let width = usize(values[at])
        if width < 4usize || width > 64usize { ret false }
        let first = lane / width * width
        var active = width
        if first + active > LANES { active = LANES - first }
        var add32 = 0u64
        var min32 = 4294967295u64
        var max32 = 0u64
        var and32 = 4294967295u64
        var or32 = 0u64
        var xor32 = 0u64
        var add64 = 0u64
        var min64 = 18446744073709551615u64
        var max64 = 0u64
        var and64 = 18446744073709551615u64
        var or64 = 0u64
        var xor64 = 0u64
        var source = 0usize
        while source < active {
            let narrow = u64(source + 1usize)
            let wide = u64(source) + 4294967296u64
            add32 += narrow
            if narrow < min32 { min32 = narrow }
            if narrow > max32 { max32 = narrow }
            and32 = and32 & narrow
            or32 = or32 | narrow
            xor32 = xor32 ^ narrow
            add64 += wide
            if wide < min64 { min64 = wide }
            if wide > max64 { max64 = wide }
            and64 = and64 & wide
            or64 = or64 | wide
            xor64 = xor64 ^ wide
            source += 1usize
        }
        if values[at + 1usize] != add32 || values[at + 2usize] != min32 || values[at + 3usize] != max32 { ret false }
        if values[at + 4usize] != and32 || values[at + 5usize] != or32 || values[at + 6usize] != xor32 { ret false }
        if values[at + 7usize] != add64 || values[at + 8usize] != min64 || values[at + 9usize] != max64 { ret false }
        if values[at + 10usize] != and64 || values[at + 11usize] != or64 || values[at + 12usize] != xor64 { ret false }
        lane += 1usize
    }
    ret true
}

fn valid_scalars(signed_values: []const i32, float_values: []const f32) -> bool {
    var lane = 0usize
    while lane < LANES {
        let signed_at = lane * SIGNED_STRIDE
        let width = usize(signed_values[signed_at])
        if width < 4usize || width > 64usize { ret false }
        let first = lane / width * width
        var active = width
        if first + active > LANES { active = LANES - first }
        var add = 0i32
        var minimum = 2147483647i32
        var maximum = -2147483647i32 - 1i32
        var bit_and = -1i32
        var bit_or = 0i32
        var bit_xor = 0i32
        var float_add = 0.0f32
        var source = 0usize
        while source < active {
            let signed = i32(source) - 16i32
            add += signed
            if signed < minimum { minimum = signed }
            if signed > maximum { maximum = signed }
            bit_and = bit_and & signed
            bit_or = bit_or | signed
            bit_xor = bit_xor ^ signed
            float_add += f32(source) + 0.5f32
            source += 1usize
        }
        if signed_values[signed_at + 1usize] != add || signed_values[signed_at + 2usize] != minimum || signed_values[signed_at + 3usize] != maximum { ret false }
        if signed_values[signed_at + 4usize] != bit_and || signed_values[signed_at + 5usize] != bit_or || signed_values[signed_at + 6usize] != bit_xor { ret false }
        let float_at = lane * FLOAT_STRIDE
        if float_values[float_at] != float_add || float_values[float_at + 1usize] != 0.5f32 || float_values[float_at + 2usize] != f32(active - 1usize) + 0.5f32 { ret false }
        lane += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var integers: [520]u64 = zero
    try run_integer(a, .Cpu, 0u32, integers[0..])
    if !valid_integer(integers[0..]) || integers[0usize] != 32u64 { os.exit(1i32) }
    var signed_values: [280]i32 = zero
    var float_values: [120]f32 = zero
    try run_scalars(a, .Cpu, 0u32, signed_values[0..], float_values[0..])
    if !valid_scalars(signed_values[0..], float_values[0..]) { os.exit(2i32) }
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.NoDevice || found_error == gpu.Unsupported {
        try io.print("gpu subgroup reduce cpu only\n")
        ret ok
    }
    if found_error != ok { ret found_error }
    var ran = 0usize
    var device_at = 0usize
    while device_at < found.len {
        if found[device_at].supported && supports(found[device_at].capabilities, .Subgroup) && supports(found[device_at].capabilities, .Int64) {
            var device_integers: [520]u64 = zero
            try run_integer(a, .Vulkan, u32(device_at), device_integers[0..])
            if !valid_integer(device_integers[0..]) { os.exit(4i32) }
            if supports(found[device_at].capabilities, .DenormPreserve) {
                var device_signed: [280]i32 = zero
                var device_float: [120]f32 = zero
                try run_scalars(a, .Vulkan, u32(device_at), device_signed[0..], device_float[0..])
                if !valid_scalars(device_signed[0..], device_float[0..]) { os.exit(5i32) }
            }
            ran += 1usize
        }
        device_at += 1usize
    }
    if ran == 0usize {
        try io.print("gpu subgroup reduce cpu only\n")
        ret ok
    }
    try io.printf["gpu subgroup reduce vulkan ok on {} devices\n"](ran)
    ret ok
}
