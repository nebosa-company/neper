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

// CUDA device selection: the driver's devices are listed with identities and cannot be opened.
fn check_cuda(a: *mem.Arena) -> i32 {
    let (found, found_error) = gpu.devices(a, .Cuda, 16usize)
    if found_error == gpu.Unsupported {
        let (_, absent_error) = gpu.open_id(a, key_of(1u8, .Cuda))
        if absent_error != gpu.Unsupported { ret 2i32 }
        ret 0i32
    }
    if found_error != ok { ret 1i32 }
    let (_, none_error) = gpu.open_id(a, key_of(7u8, .Cuda))
    if found.len > 0usize && none_error != gpu.NoDevice && none_error != gpu.Unsupported { ret 3i32 }
    var at = 0usize
    while at < found.len {
        let record = found[at]
        if record.key.backend != .Cuda || record.index != u32(at) || record.name.len == 0usize { ret 4i32 }
        if record.supported || !record.memory_known || record.memory_bytes == 0u64 { ret 5i32 }
        if record.key_valid {
            var twins = 0usize
            var other = 0usize
            while other < found.len {
                if found[other].key_valid && same_key(found[other].key, record.key) { twins += 1usize }
                other += 1usize
            }
            let (_, open_error) = gpu.open_id(a, record.key)
            if twins > 1usize && open_error != gpu.AmbiguousDevice { ret 6i32 }
            if twins == 1usize && open_error != gpu.Unsupported { ret 7i32 }
        }
        // A Vulkan key is not a CUDA key, whatever the bytes: the other backend's key never matches.
        let (_, cross_error) = gpu.open_id(a, gpu.DeviceKey { backend: .Vulkan, uuid: record.key.uuid })
        if cross_error == gpu.AmbiguousDevice { ret 8i32 }
        at += 1usize
    }
    // The bound is a bound here too.
    if found.len > 0usize {
        let (_, bound_error) = gpu.devices(a, .Cuda, found.len - 1usize)
        if bound_error != gpu.TooLarge { ret 9i32 }
    }
    // An independent oracle: the NVIDIA GPU a Vulkan driver also lists has the same sixteen
    // bytes as its CUDA identity (matched by name, since the backends share nothing else).
    let (vulkan, vulkan_error) = gpu.devices(a, .Vulkan, 16usize)
    if vulkan_error == ok {
        var cuda_at = 0usize
        while cuda_at < found.len {
            var vulkan_at = 0usize
            while vulkan_at < vulkan.len {
                let same_name = vulkan[vulkan_at].name.len == found[cuda_at].name.len && vulkan[vulkan_at].key_valid && found[cuda_at].key_valid
                if same_name {
                    var equal = true
                    var name_at = 0usize
                    while name_at < found[cuda_at].name.len {
                        if vulkan[vulkan_at].name[name_at] != found[cuda_at].name[name_at] { equal = false }
                        name_at += 1usize
                    }
                    if equal && !same_key(gpu.DeviceKey { backend: .Cuda, uuid: vulkan[vulkan_at].key.uuid }, found[cuda_at].key) { ret 10i32 }
                }
                vulkan_at += 1usize
            }
            cuda_at += 1usize
        }
    }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let resolution = check_resolution()
    if resolution != 0i32 { os.exit(resolution) }
    // CUDA is enumerated and never opened (D4705): without a driver both entry points say
    // `Unsupported`; with one, every record is a CUDA identity that is not supported, its own
    // key resolves to `Unsupported` (found, nothing to open it with), and an absent key is
    // `NoDevice`.
    let cuda_check = check_cuda(a)
    if cuda_check != 0i32 { os.exit(cuda_check) }
    let vulkan = check_vulkan(a)
    if vulkan != 0i32 { os.exit(vulkan) }
    try io.print("gpu devices ok\n")
    ret ok
}
