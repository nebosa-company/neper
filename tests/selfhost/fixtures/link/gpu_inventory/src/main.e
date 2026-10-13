// The mock inventory and the enumeration retry of `e.gpu` device selection (C093): run as
// `neper run ... --gpu-inventory inventory.txt` the Vulkan and CUDA enumeration is the file's
// records (duplicate keys, a record without a key, open by index); run without it the
// fixture checks the retry decision alone.

use e.gpu
use e.gpu.vulkan
use e.io
use e.mem
use e.os

fn key_of(byte: u8, backend: gpu.Backend) -> gpu.DeviceKey {
    var uuid: [16]u8 = zero
    uuid[0usize] = byte
    uuid[15usize] = byte
    ret gpu.DeviceKey { backend: backend, uuid: uuid }
}

fn is_name(record: gpu.DeviceInfo, want: str) -> bool {
    if record.name.len != want.len { ret false }
    var at = 0usize
    while at < want.len {
        if record.name[at] != want[at] { ret false }
        at += 1usize
    }
    ret true
}

// VK_INCOMPLETE retries until the third attempt; anything else non-zero fails at once.
fn check_retry() -> i32 {
    if vulkan.enumeration_step(0i32, 0u32) != 0u32 { ret 1i32 }
    if vulkan.enumeration_step(0i32, 2u32) != 0u32 { ret 2i32 }
    if vulkan.enumeration_step(5i32, 0u32) != 1u32 { ret 3i32 }
    if vulkan.enumeration_step(5i32, 1u32) != 1u32 { ret 4i32 }
    if vulkan.enumeration_step(5i32, 2u32) != 2u32 { ret 5i32 }
    if vulkan.enumeration_step(-3i32, 0u32) != 2u32 { ret 6i32 }
    if vulkan.enumeration_step(1i32, 0u32) != 2u32 { ret 7i32 }
    ret 0i32
}

fn check_inventory(a: *mem.Arena) -> i32 {
    let (found, found_error) = gpu.devices(a, .Vulkan, 16usize)
    if found_error != ok || found.len != 4usize { ret 10i32 }
    if !is_name(found[0usize], "Mock A") || !is_name(found[3usize], "Mock without a key") { ret 11i32 }
    if found[2usize].index != 2u32 || found[3usize].key_valid || !found[0usize].key_valid { ret 12i32 }
    if found[0usize].key.uuid[0usize] != 1u8 || found[0usize].key.uuid[15usize] != 1u8 { ret 13i32 }
    if !found[1usize].supported || found[1usize].memory_known { ret 14i32 }
    let (_, bound_error) = gpu.devices(a, .Vulkan, 3usize)
    if bound_error != gpu.TooLarge { ret 15i32 }
    let (cuda, cuda_error) = gpu.devices(a, .Cuda, 4usize)
    if cuda_error != ok || cuda.len != 1usize || !is_name(cuda[0usize], "Mock CUDA") { ret 16i32 }
    if cuda[0usize].key.backend != .Cuda || cuda[0usize].key.uuid[0usize] != 10u8 { ret 17i32 }
    // The CPU is not the inventory's to replace.
    let (cpu, cpu_error) = gpu.devices(a, .Cpu, 4usize)
    if cpu_error != ok || cpu.len != 1usize || !is_name(cpu[0usize], "Neper CPU") { ret 18i32 }
    // A unique key opens, and `info` is the record; the CPU device is untouched afterwards.
    let (one, one_error) = gpu.open_id(a, key_of(1u8, .Vulkan))
    if one_error != ok { ret 20i32 }
    let (one_info, one_info_error) = gpu.info(a, one)
    if one_info_error != ok || !is_name(one_info, "Mock A") || one_info.index != 0u32 { ret 21i32 }
    if gpu.close(one) != ok { ret 22i32 }
    // A duplicated key is ambiguous; the same records open by index.
    let (_, dup_error) = gpu.open_id(a, key_of(2u8, .Vulkan))
    if dup_error != gpu.AmbiguousDevice { ret 23i32 }
    let (second, second_error) = gpu.open(a, .Vulkan, 2u32)
    if second_error != ok { ret 24i32 }
    let (second_info, second_info_error) = gpu.info(a, second)
    if second_info_error != ok || !is_name(second_info, "Mock B second") || second_info.index != 2u32 { ret 25i32 }
    if gpu.close(second) != ok { ret 26i32 }
    // A record without a key never matches, even on its zero bytes; it opens by index.
    var zero_key: [16]u8 = zero
    let (_, invalid_error) = gpu.open_id(a, gpu.DeviceKey { backend: .Vulkan, uuid: zero_key })
    if invalid_error != gpu.NoDevice { ret 27i32 }
    let (keyless, keyless_error) = gpu.open(a, .Vulkan, 3u32)
    if keyless_error != ok { ret 28i32 }
    if gpu.close(keyless) != ok { ret 29i32 }
    let (_, past_error) = gpu.open(a, .Vulkan, 4u32)
    if past_error != gpu.NoDevice { ret 30i32 }
    let (_, missing_error) = gpu.open_id(a, key_of(9u8, .Vulkan))
    if missing_error != gpu.NoDevice { ret 31i32 }
    // CUDA by key opens the mock; the key's backend is part of the identity.
    let (cuda_device, cuda_open_error) = gpu.open_id(a, key_of(10u8, .Cuda))
    if cuda_open_error != ok { ret 32i32 }
    let (cuda_info, cuda_info_error) = gpu.info(a, cuda_device)
    if cuda_info_error != ok || cuda_info.key.backend != .Cuda { ret 33i32 }
    if gpu.close(cuda_device) != ok { ret 34i32 }
    let (_, cross_error) = gpu.open_id(a, key_of(10u8, .Vulkan))
    if cross_error != gpu.NoDevice { ret 35i32 }
    // The CPU still opens as itself.
    let (cpu_device, cpu_open_error) = gpu.open(a, .Cpu, 0u32)
    if cpu_open_error != ok { ret 36i32 }
    let (cpu_info, cpu_info_error) = gpu.info(a, cpu_device)
    if cpu_info_error != ok || !is_name(cpu_info, "Neper CPU") { ret 37i32 }
    if gpu.close(cpu_device) != ok { ret 38i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let retry = check_retry()
    if retry != 0i32 { os.exit(retry) }
    let (path, env_error) = os.env(a, "NEPER_GPU_INVENTORY")
    if env_error != ok || path.len == 0usize {
        try io.print("gpu inventory unconfigured ok\n")
        ret ok
    }
    let mocked = check_inventory(a)
    if mocked != 0i32 { os.exit(mocked) }
    try io.print("gpu inventory ok\n")
    ret ok
}
