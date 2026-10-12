// `e.gpu` device selection (C093, D4200): `devices` is a complete bounded snapshot
// (`TooLarge` past the limit, an empty list when the loader finds nothing), a Vulkan
// record's key is the driver's deviceUUID and exists only when the driver reports one,
// `open_id` resolves a key exactly (`NoDevice`, `AmbiguousDevice`, `Unsupported`, never an
// index or a name), and `info` of an opened device carries the opening-time record.

use e.gpu
use e.io
use e.mem
use e.os

fn key_of(byte: u8, backend: gpu.Backend) -> gpu.DeviceKey {
    var uuid: [16]u8 = zero
    uuid[0usize] = byte
    uuid[15usize] = byte
    ret gpu.DeviceKey { backend: backend, uuid: uuid }
}

fn record_of(byte: u8, valid: bool, index: u32) -> gpu.DeviceInfo {
    var record: gpu.DeviceInfo = zero
    record.key = key_of(byte, .Vulkan)
    record.key_valid = valid
    record.index = index
    ret record
}

fn same_key(left: gpu.DeviceKey, right: gpu.DeviceKey) -> bool {
    if left.backend != right.backend { ret false }
    var at = 0usize
    while at < 16usize {
        if left.uuid[at] != right.uuid[at] { ret false }
        at += 1usize
    }
    ret true
}

// The pure resolution over a synthetic inventory: the mock inventory of the contract.
fn check_resolution() -> i32 {
    var records: [4]gpu.DeviceInfo = zero
    records[0usize] = record_of(1u8, true, 0u32)
    records[1usize] = record_of(2u8, true, 1u32)
    records[2usize] = record_of(2u8, true, 2u32)
    records[3usize] = record_of(3u8, false, 3u32)
    let (one, one_error) = gpu.resolve_key(records[..], key_of(1u8, .Vulkan))
    if one_error != ok || one != 0usize { ret 10i32 }
    let (_, dup_error) = gpu.resolve_key(records[..], key_of(2u8, .Vulkan))
    if dup_error != gpu.AmbiguousDevice { ret 11i32 }
    // A record without a valid key is excluded even from an exact byte match.
    let (_, invalid_error) = gpu.resolve_key(records[..], key_of(3u8, .Vulkan))
    if invalid_error != gpu.NoDevice { ret 12i32 }
    let (_, missing_error) = gpu.resolve_key(records[..], key_of(9u8, .Vulkan))
    if missing_error != gpu.NoDevice { ret 13i32 }
    // The same bytes under another backend are another identity.
    let (_, backend_error) = gpu.resolve_key(records[..], key_of(1u8, .Cuda))
    if backend_error != gpu.NoDevice { ret 14i32 }
    // Reordering does not move a key: the match follows the bytes.
    var reversed: [2]gpu.DeviceInfo = zero
    reversed[0usize] = record_of(2u8, true, 0u32)
    reversed[1usize] = record_of(1u8, true, 1u32)
    let (moved, moved_error) = gpu.resolve_key(reversed[..], key_of(1u8, .Vulkan))
    if moved_error != ok || moved != 1usize { ret 15i32 }
    ret 0i32
}

fn check_vulkan(a: *mem.Arena) -> i32 {
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error == gpu.Unsupported {
        // No loader: the key resolves nowhere, and says why.
        let (_, absent_error) = gpu.open_id(a, key_of(1u8, .Vulkan))
        if absent_error != gpu.Unsupported { ret 20i32 }
        ret 0i32
    }
    if found_error != ok { ret 21i32 }
    // The bound is a bound: one less than the count is TooLarge, never a short list.
    if found.len > 0usize {
        let (_, bound_error) = gpu.devices(a, .Vulkan, found.len - 1usize)
        if bound_error != gpu.TooLarge { ret 22i32 }
    }
    let (_, zero_error) = gpu.devices(a, .Vulkan, 0usize)
    if found.len == 0usize && zero_error != ok { ret 23i32 }
    if found.len > 0usize && zero_error != gpu.TooLarge { ret 23i32 }
    // A key the machine does not have names no device.
    let (_, none_error) = gpu.open_id(a, key_of(7u8, .Vulkan))
    if none_error != gpu.NoDevice { ret 24i32 }
    var at = 0usize
    while at < found.len {
        let record = found[at]
        if record.key.backend != .Vulkan || record.index != u32(at) || record.name.len == 0usize { ret 25i32 }
        if !record.key_valid {
            at += 1usize
            continue
        }
        // Two devices with one key are ambiguous; otherwise the key opens that device.
        var twins = 0usize
        var other = 0usize
        while other < found.len {
            if found[other].key_valid && same_key(found[other].key, record.key) { twins += 1usize }
            other += 1usize
        }
        let (device, open_error) = gpu.open_id(a, record.key)
        if twins > 1usize {
            if open_error != gpu.AmbiguousDevice { ret 26i32 }
            at += 1usize
            continue
        }
        if !record.supported {
            if open_error != gpu.Unsupported { ret 27i32 }
            at += 1usize
            continue
        }
        if open_error != ok { ret 28i32 }
        let (opened, info_error) = gpu.info(a, device)
        if info_error != ok { ret 29i32 }
        if !same_key(opened.key, record.key) || !opened.key_valid || opened.index != record.index { ret 30i32 }
        if opened.name.len != record.name.len || opened.memory_bytes != record.memory_bytes || opened.supported != record.supported { ret 31i32 }
        if gpu.close(device) != ok { ret 32i32 }
        at += 1usize
    }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let resolution = check_resolution()
    if resolution != 0i32 { os.exit(resolution) }
    // The CUDA backend is not compiled in: both entry points say so.
    let (_, cuda_error) = gpu.devices(a, .Cuda, 4usize)
    if cuda_error != gpu.Unsupported { os.exit(1i32) }
    let (_, cuda_open_error) = gpu.open_id(a, key_of(1u8, .Cuda))
    if cuda_open_error != gpu.Unsupported { os.exit(2i32) }
    let vulkan = check_vulkan(a)
    if vulkan != 0i32 { os.exit(vulkan) }
    try io.print("gpu devices ok\n")
    ret ok
}
