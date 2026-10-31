// The Vulkan compute runtime under `e.gpu` (spec section 10, D1610, D1611): the loader opened at run
// time -- `vulkan-1.dll` on Windows, `libvulkan.so.1` on Linux -- so a program that never asks
// for a `.Vulkan` device never needs one installed, and every core entry point looked up by name
// through `os.dlsym`, which the loader exports for Vulkan 1.0 to 1.3.
//
// Vulkan's structures cross as byte records built at their C offsets for x64, where a pointer and
// a non-dispatchable handle are both eight bytes: `record` allocates one zeroed and `put32` and
// `put64` fill it. A handle is a `usize`.

use e.mem
use e.os
use e.sync

error NoLoader
error NoDevice
error Unsupported
error OutOfMemory
error Failed

// Vulkan 1.2, the floor section 10 names.
const API_VERSION: u32 = 4202496u32
const QUEUE_COMPUTE: u32 = 2u32
const MEMORY_HOST_VISIBLE: u32 = 2u32
const MEMORY_HOST_COHERENT: u32 = 4u32
const MEMORY_DEVICE_LOCAL: u32 = 1u32
const MEMORY_HOST_CACHED: u32 = 8u32
// Storage, device-address, and both transfer directions.
const BUFFER_USAGE: u32 = 131107u32

type Api = struct {
    create_instance: fn(*u8, usize, *usize) -> i32,
    destroy_instance: fn(usize, usize),
    enumerate_physical_devices: fn(usize, *u32, *usize) -> i32,
    get_physical_device_properties2: fn(usize, *u8),
    get_physical_device_features2: fn(usize, *u8),
    get_physical_device_memory_properties: fn(usize, *u8),
    get_physical_device_queue_family_properties: fn(usize, *u32, *u8),
    create_device: fn(usize, *u8, usize, *usize) -> i32,
    destroy_device: fn(usize, usize),
    get_device_queue: fn(usize, u32, u32, *usize),
    create_buffer: fn(usize, *u8, usize, *usize) -> i32,
    destroy_buffer: fn(usize, usize, usize),
    get_buffer_memory_requirements: fn(usize, usize, *u8),
    allocate_memory: fn(usize, *u8, usize, *usize) -> i32,
    free_memory: fn(usize, usize, usize),
    bind_buffer_memory: fn(usize, usize, usize, u64) -> i32,
    map_memory: fn(usize, usize, u64, u64, u32, **u8) -> i32,
    unmap_memory: fn(usize, usize),
    get_buffer_device_address: fn(usize, *u8) -> u64,
    device_wait_idle: fn(usize) -> i32,
    create_shader_module: fn(usize, *u8, usize, *usize) -> i32,
    destroy_shader_module: fn(usize, usize, usize),
    create_pipeline_layout: fn(usize, *u8, usize, *usize) -> i32,
    destroy_pipeline_layout: fn(usize, usize, usize),
    create_pipeline_cache: fn(usize, *u8, usize, *usize) -> i32,
    get_pipeline_cache_data: fn(usize, usize, *usize, *u8) -> i32,
    destroy_pipeline_cache: fn(usize, usize, usize),
    create_compute_pipelines: fn(usize, usize, u32, *u8, usize, *usize) -> i32,
    destroy_pipeline: fn(usize, usize, usize),
    create_command_pool: fn(usize, *u8, usize, *usize) -> i32,
    destroy_command_pool: fn(usize, usize, usize),
    allocate_command_buffers: fn(usize, *u8, *usize) -> i32,
    begin_command_buffer: fn(usize, *u8) -> i32,
    end_command_buffer: fn(usize) -> i32,
    cmd_bind_pipeline: fn(usize, u32, usize),
    cmd_push_constants: fn(usize, usize, u32, u32, u32, *u8),
    cmd_dispatch: fn(usize, u32, u32, u32),
    queue_submit: fn(usize, u32, *u8, usize) -> i32,
    queue_wait_idle: fn(usize) -> i32,
    create_fence: fn(usize, *u8, usize, *usize) -> i32,
    destroy_fence: fn(usize, usize, usize),
    wait_for_fences: fn(usize, u32, *usize, u32, u64) -> i32,
    reset_fences: fn(usize, u32, *usize) -> i32,
    reset_command_buffer: fn(usize, u32) -> i32,
}

// A kernel made ready to dispatch (D1611): its shader module, the layout of its one push
// constant -- the argument block's address -- and the compute pipeline.
type Pipeline = struct {
    module: usize,
    layout: usize,
    pipeline: usize,
}

// A physical device as `devices` reports it.
type Physical = struct {
    handle: usize,
    name: str,
    device_type: u32,
    vendor: u32,
    device: u32,
    api_version: u32,
    driver_version: u32,
    memory_bytes: u64,
    // `gpu.Cap`'s members as bits (Int8 Int16 Int64 Float16 Float64 Atomic64 ...).
    caps: usize,
    subgroup_size: u32,
    // Whether the section 10 floor holds: Vulkan 1.2, buffer device addresses, scalar block
    // layout and a compute queue.
    floor: bool,
    compute_family: u32,
    uuid: [16]u8,
    // VkPhysicalDeviceIDProperties.deviceUUID (D4200): the identity `DeviceKey` carries.
    // `uuid` above is the pipeline cache UUID, which names a driver's cache format.
    device_uuid: [16]u8,
    // False when the driver reports no usable identity: below Vulkan 1.1 or all zero.
    device_uuid_valid: bool,
}

// An opened device: its handles, the memory type buffers come from, and the queue.
type Context = struct {
    physical: usize,
    device: usize,
    queue: usize,
    family: u32,
    memory_type: u32,
    // The memory type for buffers the HOST reads back or fills in bulk (frame images, staging):
    // host-visible, coherent and host-CACHED when the driver has one, else `memory_type`.
    // Measured on Intel Iris Xe, whose only device-local host-visible type (flags 7) is uncached
    // write-combined: a CPU read of it ran at ~90 MB/s (a 6.4 MB frame readback 70 ms, the
    // staging read of an upload 106 ms), the cached type (flags 15) at ~4 GB/s (1.5 ms and 3 ms).
    // Kernel buffers keep `memory_type`: on a discrete GPU the cached type is system RAM and a
    // kernel reading it would cross PCIe, so only host-transfer buffers use `host_type`.
    host_type: u32,
    // Persistent submission state (D5927): `dispatch` used to create a command pool, a command buffer and a
    // 24-byte argument buffer (vkCreateBuffer + vkAllocateMemory + vkMapMemory) per launch and end in
    // vkQueueWaitIdle: 0.85 ms (Intel) and 1.38 ms (RTX 3080) for a one-workgroup launch. It now records into
    // one command buffer of a pool made at `open`, submits with a fence and waits on that fence.
    pool: usize,
    command: usize,
    fence: usize,
    // The argument block of the launch in flight (launches wait, so one block serves them all).
    args: Buffer,
    // VK_KHR_swapchain and VK_KHR_incremental_present were enabled on the device (D5928).
    swapchain: bool,
    incremental: bool,
}

// A buffer: its handle and memory, its device address, and its bytes mapped on the host.
type Buffer = struct {
    handle: usize,
    memory: usize,
    address: u64,
    bytes: []u8,
    mapped: bool,
}

var api: Api = zero
// The loader, kept open for the process: its entry points are in `api`.
var loader: os.Lib = zero
var loaded: bool = zero
var instance: usize = zero
// The instance was made with VK_KHR_surface and VK_KHR_win32_surface (D5928).
var surface_ready: bool = zero
// Device enumeration can be called by several application threads.
var loader_locks: [1]sync.Mutex = zero

fn library_name() -> str {
    if os.NATIVE_SEPARATOR == 92u8 { ret "vulkan-1.dll" }
    ret "libvulkan.so.1"
}

fn record(a: *mem.Arena, size: usize) -> ([]u8, err) {
    let (bytes, bytes_error) = mem.alloc[u8](a, size)
    if bytes_error != ok { ret (bytes, bytes_error) }
    var at = 0usize
    while at < size {
        bytes[at] = 0u8
        at += 1usize
    }
    ret (bytes, ok)
}

fn put32(bytes: []u8, at: usize, value: usize) {
    var rest = value
    var k = 0usize
    while k < 4usize {
        bytes[at + k] = u8(rest % 256usize)
        rest = rest / 256usize
        k += 1usize
    }
}

fn put64(bytes: []u8, at: usize, value: usize) {
    var rest = value
    var k = 0usize
    while k < 8usize {
        bytes[at + k] = u8(rest % 256usize)
        rest = rest / 256usize
        k += 1usize
    }
}

fn get32(bytes: []const u8, at: usize) -> usize {
    ret usize(bytes[at]) + usize(bytes[at + 1usize]) * 256usize + usize(bytes[at + 2usize]) * 65536usize + usize(bytes[at + 3usize]) * 16777216usize
}

fn get64(bytes: []const u8, at: usize) -> usize {
    ret get32(bytes, at) + get32(bytes, at + 4usize) * 4294967296usize
}

// A pointer field: the address of a record's first byte, written where the C struct holds it.
fn put_pointer(bytes: []u8, at: usize, pointee: []u8) {
    put64(bytes, at, mem.address_of(&pointee[0usize]))
}

fn put_const_pointer(bytes: []u8, at: usize, pointee: []const u8) {
    put64(bytes, at, mem.address_of(&pointee[0usize]))
}

// The loader and every entry point this runtime calls, once per process.
fn load(a: *mem.Arena) -> err {
    sync.mutex_lock(&loader_locks[0usize])
    defer sync.mutex_unlock(&loader_locks[0usize])
    if loaded { ret ok }
    let (library, library_error) = os.dlopen(a, library_name())
    if library_error != ok { ret NoLoader }
    let (p1, e1) = os.dlsym[fn(*u8, usize, *usize) -> i32](a, library, "vkCreateInstance")
    let (p2, e2) = os.dlsym[fn(usize, usize)](a, library, "vkDestroyInstance")
    let (p3, e3) = os.dlsym[fn(usize, *u32, *usize) -> i32](a, library, "vkEnumeratePhysicalDevices")
    let (p4, e4) = os.dlsym[fn(usize, *u8)](a, library, "vkGetPhysicalDeviceProperties2")
    let (p5, e5) = os.dlsym[fn(usize, *u8)](a, library, "vkGetPhysicalDeviceFeatures2")
    let (p6, e6) = os.dlsym[fn(usize, *u8)](a, library, "vkGetPhysicalDeviceMemoryProperties")
    let (p7, e7) = os.dlsym[fn(usize, *u32, *u8)](a, library, "vkGetPhysicalDeviceQueueFamilyProperties")
    let (p8, e8) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreateDevice")
    let (p9, e9) = os.dlsym[fn(usize, usize)](a, library, "vkDestroyDevice")
    let (p10, e10) = os.dlsym[fn(usize, u32, u32, *usize)](a, library, "vkGetDeviceQueue")
    let (p11, e11) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreateBuffer")
    let (p12, e12) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroyBuffer")
    let (p13, e13) = os.dlsym[fn(usize, usize, *u8)](a, library, "vkGetBufferMemoryRequirements")
    let (p14, e14) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkAllocateMemory")
    let (p15, e15) = os.dlsym[fn(usize, usize, usize)](a, library, "vkFreeMemory")
    let (p16, e16) = os.dlsym[fn(usize, usize, usize, u64) -> i32](a, library, "vkBindBufferMemory")
    let (p17, e17) = os.dlsym[fn(usize, usize, u64, u64, u32, **u8) -> i32](a, library, "vkMapMemory")
    let (p18, e18) = os.dlsym[fn(usize, usize)](a, library, "vkUnmapMemory")
    let (p19, e19) = os.dlsym[fn(usize, *u8) -> u64](a, library, "vkGetBufferDeviceAddress")
    let (p20, e20) = os.dlsym[fn(usize) -> i32](a, library, "vkDeviceWaitIdle")
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok {
        let closed = os.dlclose(library)
        ret NoLoader
    }
    if e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok {
        let closed = os.dlclose(library)
        ret NoLoader
    }
    let dispatch_error = load_dispatch(a, library)
    if dispatch_error != ok {
        let closed = os.dlclose(library)
        ret dispatch_error
    }
    let sync_error = load_sync(a, library)
    if sync_error != ok {
        let closed = os.dlclose(library)
        ret sync_error
    }
    let cache_error = load_pipeline_cache(a, library)
    if cache_error != ok {
        let closed = os.dlclose(library)
        ret cache_error
    }
    api = Api { create_instance: p1, destroy_instance: p2, enumerate_physical_devices: p3, get_physical_device_properties2: p4, get_physical_device_features2: p5, get_physical_device_memory_properties: p6, get_physical_device_queue_family_properties: p7, create_device: p8, destroy_device: p9, get_device_queue: p10, create_buffer: p11, destroy_buffer: p12, get_buffer_memory_requirements: p13, allocate_memory: p14, free_memory: p15, bind_buffer_memory: p16, map_memory: p17, unmap_memory: p18, get_buffer_device_address: p19, device_wait_idle: p20, create_shader_module: api.create_shader_module, destroy_shader_module: api.destroy_shader_module, create_pipeline_layout: api.create_pipeline_layout, destroy_pipeline_layout: api.destroy_pipeline_layout, create_pipeline_cache: api.create_pipeline_cache, get_pipeline_cache_data: api.get_pipeline_cache_data, destroy_pipeline_cache: api.destroy_pipeline_cache, create_compute_pipelines: api.create_compute_pipelines, destroy_pipeline: api.destroy_pipeline, create_command_pool: api.create_command_pool, destroy_command_pool: api.destroy_command_pool, allocate_command_buffers: api.allocate_command_buffers, begin_command_buffer: api.begin_command_buffer, end_command_buffer: api.end_command_buffer, cmd_bind_pipeline: api.cmd_bind_pipeline, cmd_push_constants: api.cmd_push_constants, cmd_dispatch: api.cmd_dispatch, queue_submit: api.queue_submit, queue_wait_idle: api.queue_wait_idle, create_fence: api.create_fence, destroy_fence: api.destroy_fence, wait_for_fences: api.wait_for_fences, reset_fences: api.reset_fences, reset_command_buffer: api.reset_command_buffer }
    // One instance for the process: the application record, then the instance's.
    let (application, application_error) = record(a, 48usize)
    if application_error != ok {
        let closed = os.dlclose(library)
        ret application_error
    }
    put32(application, 44usize, usize(API_VERSION))
    let (create, create_error) = record(a, 64usize)
    if create_error != ok {
        let closed = os.dlclose(library)
        ret create_error
    }
    put32(create, 0usize, 1usize)
    put_pointer(create, 24usize, application)
    // VK_KHR_surface and the host's surface extension, when the loader lists both (D5928): a swapchain needs them at instance creation.
    surface_ready = enable_surface_extensions(a, library, create)
    var made = 0usize
    var created = api.create_instance(&create[0usize], 0usize, &made)
    if created != 0i32 && surface_ready {
        // A loader that lists the surface extensions but refuses them: the compute-only instance of before.
        surface_ready = false
        put32(create, 48usize, 0usize)
        put64(create, 56usize, 0usize)
        made = 0usize
        created = api.create_instance(&create[0usize], 0usize, &made)
    }
    if created != 0i32 {
        let closed = os.dlclose(library)
        ret NoLoader
    }
    loader = library
    instance = made
    loaded = true
    ret ok
}

const ENUMERATE_ATTEMPTS: u32 = 3u32
const VK_INCOMPLETE: i32 = 5i32

// What a list call's status means on attempt `attempt` (from zero): 0 the list is complete,
// 1 ask the count again, 2 give up. Only VK_INCOMPLETE is worth another attempt, and only
// while one is left; any other status is a failure.
fn enumeration_step(status: i32, attempt: u32) -> u32 {
    if status == 0i32 { ret 0u32 }
    if status == VK_INCOMPLETE && attempt + 1u32 < ENUMERATE_ATTEMPTS { ret 1u32 }
    ret 2u32
}

// The physical devices, each with its name, kind, memory, capabilities and whether section 10's
// floor holds on it.
fn devices(a: *mem.Arena, limit: usize) -> ([]Physical, err) {
    var none: []Physical = zero
    let load_error = load(a)
    if load_error != ok { ret (none, load_error) }
    // The count and the list are two calls, so a device can appear between them: the list
    // call then answers VK_INCOMPLETE and the count is asked again, three attempts in all
    // (C093); the snapshot is never a short list presented as complete.
    var count = 0u32
    var no_handles: *usize = zero
    var handles: []usize = zero
    var attempt = 0u32
    var settled = false
    while !settled {
        count = 0u32
        if api.enumerate_physical_devices(instance, &count, no_handles) != 0i32 { ret (none, Failed) }
        if count == 0u32 { ret (none, NoDevice) }
        let checkpoint = mem.mark(a)
        let (listed, handles_error) = mem.alloc[usize](a, usize(count))
        if handles_error != ok { ret (none, handles_error) }
        let status = api.enumerate_physical_devices(instance, &count, &listed[0usize])
        let step = enumeration_step(status, attempt)
        if step == 2u32 { ret (none, Failed) }
        if step == 1u32 {
            mem.reset(a, checkpoint)
            attempt += 1u32
            continue
        }
        handles = listed
        settled = true
    }
    var total = usize(count)
    if total > limit { total = limit }
    let (found, found_error) = mem.alloc[Physical](a, total)
    if found_error != ok { ret (none, found_error) }
    var at = 0usize
    while at < total {
        let (described, described_error) = describe(a, handles[at])
        if described_error != ok { ret (none, described_error) }
        found[at] = described
        at += 1usize
    }
    ret (found, ok)
}

// One physical device read: its properties (name, type, API version, UUID from the
// ID properties), its memory heaps, its features, and a queue family that computes.
fn describe(a: *mem.Arena, handle: usize) -> (Physical, err) {
    var described: Physical = zero
    described.handle = handle
    // Properties2 with the two capability records section 10 consumes.
    let (subgroup, subgroup_error) = record(a, 32usize)
    if subgroup_error != ok { ret (described, subgroup_error) }
    let (floats, floats_error) = record(a, 88usize)
    if floats_error != ok { ret (described, floats_error) }
    let (properties, properties_error) = record(a, 840usize)
    if properties_error != ok { ret (described, properties_error) }
    put32(properties, 0usize, 1000059001usize)
    put_pointer(properties, 8usize, subgroup)
    put32(subgroup, 0usize, 1000094000usize)
    put_pointer(subgroup, 8usize, floats)
    put32(floats, 0usize, 1000197000usize)
    // VkPhysicalDeviceIDProperties: deviceUUID at 16 (D4200).
    let (ids, ids_error) = record(a, 64usize)
    if ids_error != ok { ret (described, ids_error) }
    put_pointer(floats, 8usize, ids)
    put32(ids, 0usize, 1000071004usize)
    api.get_physical_device_properties2(handle, &properties[0usize])
    described.api_version = u32(get32(properties, 16usize))
    described.driver_version = u32(get32(properties, 20usize))
    described.vendor = u32(get32(properties, 24usize))
    described.device = u32(get32(properties, 28usize))
    described.device_type = u32(get32(properties, 32usize))
    var length = 0usize
    while length < 256usize && properties[36usize + length] != 0u8 { length += 1usize }
    described.name = properties[36usize..36usize + length]
    // The pipeline cache UUID stands in for the device's identity (D83's DeviceKey).
    var k = 0usize
    while k < 16usize {
        described.uuid[k] = properties[292usize + k]
        k += 1usize
    }
    var identity_bits = 0usize
    k = 0usize
    while k < 16usize {
        described.device_uuid[k] = ids[16usize + k]
        identity_bits = identity_bits | usize(ids[16usize + k])
        k += 1usize
    }
    // Properties2 is core from 1.1; a zero UUID is a driver that fills nothing in.
    described.device_uuid_valid = identity_bits != 0usize && described.api_version >= 4198400u32
    // Memory: the device-local heaps' total.
    let (memory, memory_error) = record(a, 520usize)
    if memory_error != ok { ret (described, memory_error) }
    api.get_physical_device_memory_properties(handle, &memory[0usize])
    let heaps = get32(memory, 260usize)
    var heap = 0usize
    while heap < heaps && heap < 16usize {
        let at = 264usize + heap * 16usize
        if (get32(memory, at + 8usize) & 1usize) != 0usize { described.memory_bytes = described.memory_bytes + u64(get64(memory, at)) }
        heap += 1usize
    }
    // Features: the core set in VkPhysicalDeviceFeatures2, the 1.2 set chained after it.
    let (features, features_error) = record(a, 240usize)
    if features_error != ok { ret (described, features_error) }
    let (features12, features12_error) = record(a, 208usize)
    if features12_error != ok { ret (described, features12_error) }
    put32(features, 0usize, 1000059000usize)
    put_pointer(features, 8usize, features12)
    put32(features12, 0usize, 51usize)
    if described.api_version >= API_VERSION { api.get_physical_device_features2(handle, &features[0usize]) }
    var caps = 0usize
    if get32(features12, 48usize) != 0usize && get32(features12, 24usize) != 0usize { caps = caps | 1usize }
    if get32(features, 180usize) != 0usize { caps = caps | 2usize }
    if get32(features, 176usize) != 0usize { caps = caps | 4usize }
    if get32(features12, 44usize) != 0usize { caps = caps | 8usize }
    if get32(features, 172usize) != 0usize { caps = caps | 16usize }
    if get32(features12, 36usize) != 0usize { caps = caps | 32usize }
    described.subgroup_size = u32(get32(subgroup, 16usize))
    let subgroup_stages = get32(subgroup, 20usize)
    let subgroup_operations = get32(subgroup, 24usize)
    if described.subgroup_size >= 4u32 && described.subgroup_size <= 64u32 && (subgroup_stages & 32usize) != 0usize && (subgroup_operations & 31usize) == 31usize { caps = caps | 64usize }
    if get32(floats, 52usize) != 0usize { caps = caps | 128usize }
    // `.DenormPreserve` is every float width the device computes in (D4203): a kernel that
    // uses `f64` is written with `DenormPreserve` for 64 as well as 32.
    if get32(floats, 40usize) != 0usize && (get32(features, 172usize) == 0usize || get32(floats, 44usize) != 0usize) { caps = caps | 256usize }
    described.caps = caps
    // A queue family that computes.
    var families = 0u32
    var no_records: *u8 = zero
    api.get_physical_device_queue_family_properties(handle, &families, no_records)
    var has_compute = false
    if families != 0u32 {
        let (family_records, family_error) = record(a, usize(families) * 24usize)
        if family_error != ok { ret (described, family_error) }
        api.get_physical_device_queue_family_properties(handle, &families, &family_records[0usize])
        var family = 0usize
        while family < usize(families) && !has_compute {
            if (get32(family_records, family * 24usize) & usize(QUEUE_COMPUTE)) != 0usize {
                described.compute_family = u32(family)
                has_compute = true
            }
            family += 1usize
        }
    }
    described.floor = described.api_version >= API_VERSION && has_compute && get32(features12, 168usize) != 0usize && get32(features12, 140usize) != 0usize
    ret (described, ok)
}

// A device on a physical one: every feature it supports enabled (the floor among them), one
// compute queue, and the host-visible, host-coherent memory type buffers come from.
fn open(a: *mem.Arena, physical: Physical) -> (Context, err) {
    var context: Context = zero
    if !physical.floor { ret (context, Unsupported) }
    context.physical = physical.handle
    context.family = physical.compute_family
    let (features, features_error) = record(a, 240usize)
    if features_error != ok { ret (context, features_error) }
    let (features12, features12_error) = record(a, 208usize)
    if features12_error != ok { ret (context, features12_error) }
    put32(features, 0usize, 1000059000usize)
    put_pointer(features, 8usize, features12)
    put32(features12, 0usize, 51usize)
    api.get_physical_device_features2(physical.handle, &features[0usize])
    let (priority, priority_error) = record(a, 4usize)
    if priority_error != ok { ret (context, priority_error) }
    // 1.0 as an f32.
    put32(priority, 0usize, 1065353216usize)
    let (queue_create, queue_create_error) = record(a, 40usize)
    if queue_create_error != ok { ret (context, queue_create_error) }
    put32(queue_create, 0usize, 2usize)
    put32(queue_create, 20usize, usize(physical.compute_family))
    put32(queue_create, 24usize, 1usize)
    put_pointer(queue_create, 32usize, priority)
    let (create, create_error) = record(a, 72usize)
    if create_error != ok { ret (context, create_error) }
    put32(create, 0usize, 3usize)
    put_pointer(create, 8usize, features)
    put32(create, 20usize, 1usize)
    put_pointer(create, 24usize, queue_create)
    let (swapchain_enabled, incremental_enabled) = enable_device_extensions(a, physical.handle, create)
    context.swapchain = swapchain_enabled
    context.incremental = incremental_enabled
    var device = 0usize
    if api.create_device(physical.handle, &create[0usize], 0usize, &device) != 0i32 { ret (context, Failed) }
    context.device = device
    var queue = 0usize
    api.get_device_queue(device, physical.compute_family, 0u32, &queue)
    context.queue = queue
    let (memory, memory_error) = record(a, 520usize)
    if memory_error != ok { ret (context, memory_error) }
    api.get_physical_device_memory_properties(physical.handle, &memory[0usize])
    let wanted = usize(MEMORY_HOST_VISIBLE) | usize(MEMORY_HOST_COHERENT)
    let types = get32(memory, 0usize)
    var chosen = 32usize
    var cached = 32usize
    var kind = 0usize
    while kind < types && kind < 32usize {
        let flags = get32(memory, 4usize + kind * 8usize)
        // A host-visible, coherent type, a device-local one first where there is one.
        if (flags & wanted) == wanted {
            if chosen == 32usize || ((flags & usize(MEMORY_DEVICE_LOCAL)) != 0usize && (get32(memory, 4usize + chosen * 8usize) & usize(MEMORY_DEVICE_LOCAL)) == 0usize) { chosen = kind }
            if cached == 32usize && (flags & usize(MEMORY_HOST_CACHED)) != 0usize { cached = kind }
        }
        kind += 1usize
    }
    if chosen == 32usize { ret (context, Unsupported) }
    context.memory_type = u32(chosen)
    context.host_type = u32(chosen)
    if cached != 32usize { context.host_type = u32(cached) }
    let submission_error = make_submission(a, &context)
    if submission_error != ok {
        close(context)
        ret (context, submission_error)
    }
    ret (context, ok)
}

// The entry points a dispatch needs (D1611), in their own function: `load`'s had all the
// locals the bootstrap allows one.
fn load_dispatch(a: *mem.Arena, library: os.Lib) -> err {
    let (q1, r1) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreateShaderModule")
    let (q2, r2) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroyShaderModule")
    let (q3, r3) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreatePipelineLayout")
    let (q4, r4) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroyPipelineLayout")
    let (q5, r5) = os.dlsym[fn(usize, usize, u32, *u8, usize, *usize) -> i32](a, library, "vkCreateComputePipelines")
    let (q6, r6) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroyPipeline")
    let (q7, r7) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreateCommandPool")
    let (q8, r8) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroyCommandPool")
    let (q9, r9) = os.dlsym[fn(usize, *u8, *usize) -> i32](a, library, "vkAllocateCommandBuffers")
    let (q10, r10) = os.dlsym[fn(usize, *u8) -> i32](a, library, "vkBeginCommandBuffer")
    let (q11, r11) = os.dlsym[fn(usize) -> i32](a, library, "vkEndCommandBuffer")
    let (q12, r12) = os.dlsym[fn(usize, u32, usize)](a, library, "vkCmdBindPipeline")
    let (q13, r13) = os.dlsym[fn(usize, usize, u32, u32, u32, *u8)](a, library, "vkCmdPushConstants")
    let (q14, r14) = os.dlsym[fn(usize, u32, u32, u32)](a, library, "vkCmdDispatch")
    let (q15, r15) = os.dlsym[fn(usize, u32, *u8, usize) -> i32](a, library, "vkQueueSubmit")
    let (q16, r16) = os.dlsym[fn(usize) -> i32](a, library, "vkQueueWaitIdle")
    if r1 != ok || r2 != ok || r3 != ok || r4 != ok || r5 != ok || r6 != ok || r7 != ok || r8 != ok { ret NoLoader }
    if r9 != ok || r10 != ok || r11 != ok || r12 != ok || r13 != ok || r14 != ok || r15 != ok || r16 != ok { ret NoLoader }
    api.create_shader_module = q1
    api.destroy_shader_module = q2
    api.create_pipeline_layout = q3
    api.destroy_pipeline_layout = q4
    api.create_compute_pipelines = q5
    api.destroy_pipeline = q6
    api.create_command_pool = q7
    api.destroy_command_pool = q8
    api.allocate_command_buffers = q9
    api.begin_command_buffer = q10
    api.end_command_buffer = q11
    api.cmd_bind_pipeline = q12
    api.cmd_push_constants = q13
    api.cmd_dispatch = q14
    api.queue_submit = q15
    api.queue_wait_idle = q16
    ret ok
}

// Fences and command-buffer reset, for the persistent submission of `dispatch` (D5927).
fn load_sync(a: *mem.Arena, library: os.Lib) -> err {
    let (f1, g1) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreateFence")
    let (f2, g2) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroyFence")
    let (f3, g3) = os.dlsym[fn(usize, u32, *usize, u32, u64) -> i32](a, library, "vkWaitForFences")
    let (f4, g4) = os.dlsym[fn(usize, u32, *usize) -> i32](a, library, "vkResetFences")
    let (f5, g5) = os.dlsym[fn(usize, u32) -> i32](a, library, "vkResetCommandBuffer")
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok { ret NoLoader }
    api.create_fence = f1
    api.destroy_fence = f2
    api.wait_for_fences = f3
    api.reset_fences = f4
    api.reset_command_buffer = f5
    ret ok
}

fn load_pipeline_cache(a: *mem.Arena, library: os.Lib) -> err {
    let (create, create_error) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreatePipelineCache")
    let (data, data_error) = os.dlsym[fn(usize, usize, *usize, *u8) -> i32](a, library, "vkGetPipelineCacheData")
    let (destroy_cache, destroy_error) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroyPipelineCache")
    if create_error != ok || data_error != ok || destroy_error != ok { ret NoLoader }
    api.create_pipeline_cache = create
    api.get_pipeline_cache_data = data
    api.destroy_pipeline_cache = destroy_cache
    ret ok
}

// A SPIR-V module's `entry` made into a compute pipeline, seeded from the driver's
// opaque cache bytes when it accepts them. A bad seed is retried empty; cache support
// itself is only an optimisation and never makes an otherwise valid launch fail.
fn pipeline(a: *mem.Arena, context: Context, code: []const u8, entry: str, cached: []const u8) -> (Pipeline, []u8, err) {
    var none: []u8 = zero
    var empty: []const u8 = zero
    var cache = 0usize
    var seeded = cached.len != 0usize
    let (first, first_error) = make_pipeline_cache(a, context, cached)
    if first_error == ok { cache = first }
    if first_error != ok && seeded {
        seeded = false
        let (fresh, fresh_error) = make_pipeline_cache(a, context, empty)
        if fresh_error == ok { cache = fresh }
    }
    // The cache fixture's one injected driver failure: the valid entry must stay on
    // disk because `e.gpu` publishes only the refreshed bytes returned after success.
    let (failure, failure_error) = os.env(a, "NEPER_GPU_CACHE_FAIL_REBUILD")
    if cached.len != 0usize && failure_error == ok && failure.len == 1usize && failure[0usize] == 49u8 {
        if cache != 0usize { api.destroy_pipeline_cache(context.device, cache, 0usize) }
        var failed: Pipeline = zero
        ret (failed, none, Failed)
    }
    let (made, made_error) = pipeline_with_cache(a, context, code, entry, cache)
    if made_error != ok && seeded {
        api.destroy_pipeline_cache(context.device, cache, 0usize)
        let (fresh, fresh_error) = make_pipeline_cache(a, context, empty)
        var fresh_cache = 0usize
        if fresh_error == ok { fresh_cache = fresh }
        let (retried, retry_error) = pipeline_with_cache(a, context, code, entry, fresh_cache)
        if retry_error != ok {
            if fresh_cache != 0usize { api.destroy_pipeline_cache(context.device, fresh_cache, 0usize) }
            ret (retried, none, retry_error)
        }
        let (refreshed, refresh_error) = pipeline_cache_data(a, context, fresh_cache)
        if fresh_cache != 0usize { api.destroy_pipeline_cache(context.device, fresh_cache, 0usize) }
        if refresh_error != ok { ret (retried, none, ok) }
        ret (retried, refreshed, ok)
    }
    if made_error != ok {
        if cache != 0usize { api.destroy_pipeline_cache(context.device, cache, 0usize) }
        ret (made, none, made_error)
    }
    let (refreshed, refresh_error) = pipeline_cache_data(a, context, cache)
    if cache != 0usize { api.destroy_pipeline_cache(context.device, cache, 0usize) }
    if refresh_error != ok { ret (made, none, ok) }
    ret (made, refreshed, ok)
}

fn make_pipeline_cache(a: *mem.Arena, context: Context, cached: []const u8) -> (usize, err) {
    let (create, create_error) = record(a, 40usize)
    if create_error != ok { ret (0usize, create_error) }
    put32(create, 0usize, 17usize)
    put64(create, 24usize, cached.len)
    if cached.len != 0usize { put_const_pointer(create, 32usize, cached) }
    var cache = 0usize
    if api.create_pipeline_cache(context.device, &create[0usize], 0usize, &cache) != 0i32 { ret (0usize, Failed) }
    ret (cache, ok)
}

fn pipeline_cache_data(a: *mem.Arena, context: Context, cache: usize) -> ([]u8, err) {
    var none: []u8 = zero
    if cache == 0usize { ret (none, Failed) }
    var size = 0usize
    var no_data: *u8 = zero
    if api.get_pipeline_cache_data(context.device, cache, &size, no_data) != 0i32 || size == 0usize { ret (none, Failed) }
    let (bytes, bytes_error) = mem.alloc[u8](a, size)
    if bytes_error != ok { ret (none, bytes_error) }
    var written = size
    if api.get_pipeline_cache_data(context.device, cache, &written, &bytes[0usize]) != 0i32 || written > size { ret (none, Failed) }
    ret (bytes[0usize..written], ok)
}

// The push-constant layout is one eight-byte device address (D1610's launch ABI).
fn pipeline_with_cache(a: *mem.Arena, context: Context, code: []const u8, entry: str, cache: usize) -> (Pipeline, err) {
    var made: Pipeline = zero
    if code.len == 0usize || code.len % 4usize != 0usize { ret (made, Unsupported) }
    let (words, words_error) = record(a, code.len)
    if words_error != ok { ret (made, words_error) }
    var copied = 0usize
    while copied < code.len {
        words[copied] = code[copied]
        copied += 1usize
    }
    let (module_create, module_create_error) = record(a, 40usize)
    if module_create_error != ok { ret (made, module_create_error) }
    put32(module_create, 0usize, 16usize)
    put64(module_create, 24usize, code.len)
    put_pointer(module_create, 32usize, words)
    var module = 0usize
    if api.create_shader_module(context.device, &module_create[0usize], 0usize, &module) != 0i32 { ret (made, Failed) }
    made.module = module
    let (range, range_error) = record(a, 12usize)
    if range_error != ok { ret (made, range_error) }
    put32(range, 0usize, 32usize)
    put32(range, 8usize, 8usize)
    let (layout_create, layout_create_error) = record(a, 48usize)
    if layout_create_error != ok { ret (made, layout_create_error) }
    put32(layout_create, 0usize, 30usize)
    put32(layout_create, 32usize, 1usize)
    put_pointer(layout_create, 40usize, range)
    var layout = 0usize
    if api.create_pipeline_layout(context.device, &layout_create[0usize], 0usize, &layout) != 0i32 {
        destroy(context, made)
        ret (made, Failed)
    }
    made.layout = layout
    // The entry point's name as C reads it: its bytes and a NUL.
    let (name, name_error) = record(a, entry.len + 1usize)
    if name_error != ok { ret (made, name_error) }
    var at = 0usize
    while at < entry.len {
        name[at] = entry[at]
        at += 1usize
    }
    let (pipeline_create, pipeline_create_error) = record(a, 96usize)
    if pipeline_create_error != ok { ret (made, pipeline_create_error) }
    put32(pipeline_create, 0usize, 29usize)
    // The stage, inline at 24: compute, the module, the entry's name.
    put32(pipeline_create, 24usize, 18usize)
    put32(pipeline_create, 44usize, 32usize)
    put64(pipeline_create, 48usize, module)
    put_pointer(pipeline_create, 56usize, name)
    put64(pipeline_create, 72usize, layout)
    put32(pipeline_create, 88usize, 4294967295usize)
    var compute = 0usize
    if api.create_compute_pipelines(context.device, cache, 1u32, &pipeline_create[0usize], 0usize, &compute) != 0i32 {
        destroy(context, made)
        ret (made, Failed)
    }
    made.pipeline = compute
    ret (made, ok)
}

fn destroy(context: Context, made: Pipeline) {
    if made.pipeline != 0usize { api.destroy_pipeline(context.device, made.pipeline, 0usize) }
    if made.layout != 0usize { api.destroy_pipeline_layout(context.device, made.layout, 0usize) }
    if made.module != 0usize { api.destroy_shader_module(context.device, made.module, 0usize) }
}

// One dispatch of `groups` workgroups with the argument block at `block`, waited for: recorded into the context's one
// command buffer, submitted with its fence, and waited on that fence (D5927). The records it builds are returned to
// the arena on exit: a window launching once a frame would otherwise grow the application arena by ~700 bytes a frame.
fn dispatch(a: *mem.Arena, context: Context, made: Pipeline, block: u64, x: u32, y: u32, z: u32) -> err {
    let checkpoint = mem.mark(a)
    defer mem.reset(a, checkpoint)
    let command = context.command
    if command == 0usize || context.fence == 0usize { ret Failed }
    if api.reset_command_buffer(command, 0u32) != 0i32 { ret Failed }
    let (begin, begin_error) = record(a, 32usize)
    if begin_error != ok { ret begin_error }
    put32(begin, 0usize, 42usize)
    put32(begin, 16usize, 1usize)
    if api.begin_command_buffer(command, &begin[0usize]) != 0i32 { ret Failed }
    api.cmd_bind_pipeline(command, 1u32, made.pipeline)
    let (address, address_error) = record(a, 8usize)
    if address_error != ok { ret address_error }
    put64(address, 0usize, usize(block))
    api.cmd_push_constants(command, made.layout, 32u32, 0u32, 8u32, &address[0usize])
    api.cmd_dispatch(command, x, y, z)
    if api.end_command_buffer(command) != 0i32 { ret Failed }
    ret submit_and_wait(a, context, command)
}

// `command` submitted on the context's queue with its fence, and waited for.
fn submit_and_wait(a: *mem.Arena, context: Context, command: usize) -> err {
    let (commands, commands_error) = record(a, 8usize)
    if commands_error != ok { ret commands_error }
    put64(commands, 0usize, command)
    let (submit, submit_error) = record(a, 72usize)
    if submit_error != ok { ret submit_error }
    put32(submit, 0usize, 4usize)
    put32(submit, 40usize, 1usize)
    put_pointer(submit, 48usize, commands)
    if api.queue_submit(context.queue, 1u32, &submit[0usize], context.fence) != 0i32 { ret Failed }
    var fence = context.fence
    if api.wait_for_fences(context.device, 1u32, &fence, 1u32, 18446744073709551615u64) != 0i32 { ret Failed }
    if api.reset_fences(context.device, 1u32, &fence) != 0i32 { ret Failed }
    ret ok
}

// The pool, command buffer, fence and argument block a context keeps for its life.
fn make_submission(a: *mem.Arena, context: *Context) -> err {
    let (pool_create, pool_create_error) = record(a, 24usize)
    if pool_create_error != ok { ret pool_create_error }
    put32(pool_create, 0usize, 39usize)
    // RESET_COMMAND_BUFFER: the one buffer is re-recorded for every launch.
    put32(pool_create, 16usize, 2usize)
    put32(pool_create, 20usize, usize(context.family))
    var pool = 0usize
    if api.create_command_pool(context.device, &pool_create[0usize], 0usize, &pool) != 0i32 { ret Failed }
    context.pool = pool
    let (allocate, allocate_error) = record(a, 32usize)
    if allocate_error != ok { ret allocate_error }
    put32(allocate, 0usize, 40usize)
    put64(allocate, 16usize, pool)
    put32(allocate, 28usize, 1usize)
    var command = 0usize
    if api.allocate_command_buffers(context.device, &allocate[0usize], &command) != 0i32 { ret Failed }
    context.command = command
    let (fence_create, fence_create_error) = record(a, 24usize)
    if fence_create_error != ok { ret fence_create_error }
    put32(fence_create, 0usize, 8usize)
    var fence = 0usize
    if api.create_fence(context.device, &fence_create[0usize], 0usize, &fence) != 0i32 { ret Failed }
    context.fence = fence
    let (block, block_error) = buffer(a, *context, ARGS_BYTES)
    if block_error != ok { ret block_error }
    context.args = block
    ret ok
}

// Room for a launch's argument block: 24 bytes of header and 16 bytes a kernel parameter.
const ARGS_BYTES: usize = 4096usize

fn close(context: Context) {
    if context.device == 0usize { ret }
    let idle = api.device_wait_idle(context.device)
    if context.args.handle != 0usize { free(context, context.args) }
    if context.fence != 0usize { api.destroy_fence(context.device, context.fence, 0usize) }
    if context.pool != 0usize { api.destroy_command_pool(context.device, context.pool, 0usize) }
    api.destroy_device(context.device, 0usize)
}

// A buffer of `size` bytes: storage and device-addressable, its memory host-visible and
// mapped for as long as it lives, so an upload or a download is a copy.
fn buffer(a: *mem.Arena, context: Context, size: usize) -> (Buffer, err) {
    let (made, made_error) = buffer_in(a, context, size, false)
    ret (made, made_error)
}

// The same for a buffer the host reads or fills in bulk (a frame image, a staging block): see `Context.host_type`.
fn host_buffer(a: *mem.Arena, context: Context, size: usize) -> (Buffer, err) {
    let (made, made_error) = buffer_in(a, context, size, true)
    ret (made, made_error)
}

fn buffer_in(a: *mem.Arena, context: Context, size: usize, host: bool) -> (Buffer, err) {
    var memory_type = context.memory_type
    if host { memory_type = context.host_type }
    var made: Buffer = zero
    var bytes_size = size
    if bytes_size == 0usize { bytes_size = 4usize }
    let (create, create_error) = record(a, 56usize)
    if create_error != ok { ret (made, create_error) }
    put32(create, 0usize, 12usize)
    put64(create, 24usize, bytes_size)
    put32(create, 32usize, usize(BUFFER_USAGE))
    var handle = 0usize
    if api.create_buffer(context.device, &create[0usize], 0usize, &handle) != 0i32 { ret (made, OutOfMemory) }
    made.handle = handle
    let (requirements, requirements_error) = record(a, 24usize)
    if requirements_error != ok { ret (rollback_buffer(context, made), requirements_error) }
    api.get_buffer_memory_requirements(context.device, handle, &requirements[0usize])
    // A host type the buffer cannot live in falls back to the default one.
    if host && (get32(requirements, 16usize) & (1usize << usize(memory_type))) == 0usize { memory_type = context.memory_type }
    if (get32(requirements, 16usize) & (1usize << usize(memory_type))) == 0usize {
        ret (rollback_buffer(context, made), Unsupported)
    }
    let (flags, flags_error) = record(a, 24usize)
    if flags_error != ok { ret (rollback_buffer(context, made), flags_error) }
    put32(flags, 0usize, 1000060000usize)
    put32(flags, 16usize, 2usize)
    let (allocate, allocate_error) = record(a, 32usize)
    if allocate_error != ok { ret (rollback_buffer(context, made), allocate_error) }
    put32(allocate, 0usize, 5usize)
    put_pointer(allocate, 8usize, flags)
    put64(allocate, 16usize, get64(requirements, 0usize))
    put32(allocate, 24usize, usize(memory_type))
    var memory = 0usize
    if api.allocate_memory(context.device, &allocate[0usize], 0usize, &memory) != 0i32 {
        ret (rollback_buffer(context, made), OutOfMemory)
    }
    made.memory = memory
    if api.bind_buffer_memory(context.device, handle, memory, 0u64) != 0i32 {
        ret (rollback_buffer(context, made), Failed)
    }
    var mapped: *u8 = zero
    if api.map_memory(context.device, memory, 0u64, u64(bytes_size), 0u32, &mapped) != 0i32 {
        ret (rollback_buffer(context, made), Failed)
    }
    made.mapped = true
    var region: mem.Arena = zero
    region.base = mapped
    region.cap = bytes_size
    region.off = 0usize
    made.bytes = mem.view(&region, 0usize, size)
    let (address_info, address_error) = record(a, 24usize)
    if address_error != ok { ret (rollback_buffer(context, made), address_error) }
    put32(address_info, 0usize, 1000244001usize)
    put64(address_info, 16usize, handle)
    made.address = api.get_buffer_device_address(context.device, &address_info[0usize])
    ret (made, ok)
}

fn free(context: Context, made: Buffer) {
    if made.memory != 0usize && made.mapped { api.unmap_memory(context.device, made.memory) }
    if made.handle != 0usize { api.destroy_buffer(context.device, made.handle, 0usize) }
    if made.memory != 0usize { api.free_memory(context.device, made.memory, 0usize) }
}

// An unsuccessful constructor owns no Vulkan handles. A successfully mapped allocation
// is unmapped before its buffer and memory are released.
fn rollback_buffer(context: Context, made: Buffer) -> Buffer {
    free(context, made)
    ret zero
}

var buffer_test_destroyed: usize = zero

fn buffer_test_create(device: usize, create: *u8, allocator: usize, out: *usize) -> i32 {
    *out = 41usize
    ret 0i32
}

fn buffer_test_destroy(device: usize, handle: usize, allocator: usize) {
    if handle == 41usize { buffer_test_destroyed += 1usize }
}

var buffer_test_release_step: usize = zero

fn buffer_test_unmap(device: usize, memory: usize) {
    if memory == 43usize && buffer_test_release_step == 0usize { buffer_test_release_step = 1usize }
}

fn buffer_test_free(device: usize, memory: usize, allocator: usize) {
    if memory == 43usize && buffer_test_release_step == 1usize { buffer_test_release_step = 2usize }
}

// The first record after `vkCreateBuffer` must tear the handle down when its arena is full.
// This fake API makes the ownership boundary executable on hosts without a Vulkan loader.
@test
fn buffer_rolls_back_after_record_exhaustion(a: *mem.Arena) -> err {
    let saved_api = api
    defer { api = saved_api }
    var fake: Api = zero
    fake.create_buffer = buffer_test_create
    fake.destroy_buffer = buffer_test_destroy
    api = fake
    buffer_test_destroyed = 0usize
    var storage: [56]u8 = zero
    var limited = mem.arena_from(storage[..])
    var context: Context = zero
    context.device = 1usize
    let (made, made_error) = buffer(&limited, context, 32usize)
    if made_error != mem.Exhausted { ret Failed }
    if made.handle != 0usize || made.memory != 0usize || made.address != 0u64 || made.bytes.len != 0usize { ret Failed }
    if buffer_test_destroyed != 1usize { ret Failed }
    ret ok
}

// A mapped allocation must reach vkUnmapMemory before vkFreeMemory. Keep this
// executable with a fake dispatch so hosts without a Vulkan driver cover it.
@test
fn buffer_unmaps_before_memory_free(a: *mem.Arena) -> err {
    let saved_api = api
    defer { api = saved_api }
    var fake: Api = zero
    fake.unmap_memory = buffer_test_unmap
    fake.free_memory = buffer_test_free
    api = fake
    buffer_test_release_step = 0usize
    var made: Buffer = zero
    made.memory = 43usize
    made.mapped = true
    var context: Context = zero
    context.device = 1usize
    free(context, made)
    if buffer_test_release_step != 2usize { ret Failed }
    ret ok
}

// Eight u32 words, to read a Vulkan record by offset in a fake entry point.
type TestWords = struct { w0: u32, w1: u32, w2: u32, w3: u32, w4: u32, w5: u32, w6: u32, w7: u32 }

var memory_test_type: usize = zero

fn memory_test_create(device: usize, create: *u8, allocator: usize, out: *usize) -> i32 {
    *out = 51usize
    ret 0i32
}

fn memory_test_noop_destroy(device: usize, handle: usize, allocator: usize) {
}

// Requirements: 4096 bytes, usable in memory types 0 and 2 only (bits 0b101) -- type 1 is excluded.
fn memory_test_requirements(device: usize, handle: usize, out: *u8) {
    let words = mem.cast[*TestWords](out)
    words.w4 = 5u32
}

fn memory_test_allocate(device: usize, info: *u8, allocator: usize, out: *usize) -> i32 {
    let words = mem.cast[*TestWords](info)
    memory_test_type = usize(words.w6)
    *out = 52usize
    ret 0i32
}

fn memory_test_bind(device: usize, handle: usize, memory: usize, offset: u64) -> i32 {
    ret 0i32
}

// Fails the map so the buffer rolls back after the allocation we want to observe.
fn memory_test_map(device: usize, memory: usize, offset: u64, size: u64, flags: u32, out: **u8) -> i32 {
    ret 1i32
}

// A host-transfer buffer comes from the host-cached type (Context.host_type) and a kernel buffer from
// memory_type; a host type the buffer's requirements exclude falls back to memory_type.
@test
fn host_buffer_prefers_cached_memory_type(a: *mem.Arena) -> err {
    let saved_api = api
    defer { api = saved_api }
    var fake: Api = zero
    fake.create_buffer = memory_test_create
    fake.destroy_buffer = memory_test_noop_destroy
    fake.get_buffer_memory_requirements = memory_test_requirements
    fake.allocate_memory = memory_test_allocate
    fake.free_memory = memory_test_noop_destroy
    fake.bind_buffer_memory = memory_test_bind
    fake.map_memory = memory_test_map
    api = fake
    var context: Context = zero
    context.device = 1usize
    context.memory_type = 0u32
    context.host_type = 2u32
    let mark = mem.mark(a)
    memory_test_type = 99usize
    let (_, plain_error) = buffer(a, context, 64usize)
    if plain_error == ok || memory_test_type != 0usize { ret Failed }
    memory_test_type = 99usize
    let (_, host_error) = host_buffer(a, context, 64usize)
    if host_error == ok || memory_test_type != 2usize { ret Failed }
    context.host_type = 1u32
    memory_test_type = 99usize
    let (_, excluded_error) = host_buffer(a, context, 64usize)
    if excluded_error == ok || memory_test_type != 0usize { ret Failed }
    mem.reset(a, mark)
    ret ok
}

// ------------------------------------------------------------------ window system integration (D5928)
//
// VK_KHR_surface + VK_KHR_win32_surface on the instance, VK_KHR_swapchain (and VK_KHR_incremental_present when listed) on
// the device. A frame image (a host buffer) is copied into the acquired swapchain image by the queue and presented, so
// no pixel returns to the CPU. Win32 only: elsewhere `surface_ready` stays false and every call answers Unsupported.

type Wsi = struct {
    enumerate_instance_extensions: fn(*u8, *u32, *u8) -> i32,
    enumerate_device_extensions: fn(usize, *u8, *u32, *u8) -> i32,
    create_win32_surface: fn(usize, *u8, usize, *usize) -> i32,
    destroy_surface: fn(usize, usize, usize),
    surface_support: fn(usize, u32, usize, *u32) -> i32,
    surface_capabilities: fn(usize, usize, *u8) -> i32,
    surface_formats: fn(usize, usize, *u32, *u8) -> i32,
    surface_present_modes: fn(usize, usize, *u32, *u32) -> i32,
    create_swapchain: fn(usize, *u8, usize, *usize) -> i32,
    destroy_swapchain: fn(usize, usize, usize),
    get_swapchain_images: fn(usize, usize, *u32, *usize) -> i32,
    acquire_next_image: fn(usize, usize, u64, usize, usize, *u32) -> i32,
    queue_present: fn(usize, *u8) -> i32,
    create_semaphore: fn(usize, *u8, usize, *usize) -> i32,
    destroy_semaphore: fn(usize, usize, usize),
    cmd_pipeline_barrier: fn(usize, u32, u32, u32, u32, *u8, u32, *u8, u32, *u8),
    cmd_copy_buffer_to_image: fn(usize, usize, usize, u32, u32, *u8),
}

var wsi: Wsi = zero
var wsi_loaded: bool = zero

const VK_SUCCESS: i32 = 0i32
const VK_SUBOPTIMAL: i32 = 1000001003i32
const VK_OUT_OF_DATE: i32 = -1000001004i32
const VK_DEVICE_LOST: i32 = -4i32
const VK_SURFACE_LOST: i32 = -1000000000i32

// Whether the NUL-padded 256-byte name at `at` in a list of VkExtensionProperties (260 bytes each) is `name`.
fn extension_named(props: []const u8, index: usize, name: str) -> bool {
    let at = index * 260usize
    var k = 0usize
    while k < name.len {
        if props[at + k] != name[k] { ret false }
        k += 1usize
    }
    ret props[at + name.len] == 0u8
}

fn extension_listed(props: []const u8, count: usize, name: str) -> bool {
    var i = 0usize
    while i < count {
        if extension_named(props, i, name) { ret true }
        i += 1usize
    }
    ret false
}

fn load_wsi(a: *mem.Arena, library: os.Lib) -> bool {
    let (w1, h1) = os.dlsym[fn(*u8, *u32, *u8) -> i32](a, library, "vkEnumerateInstanceExtensionProperties")
    let (w2, h2) = os.dlsym[fn(usize, *u8, *u32, *u8) -> i32](a, library, "vkEnumerateDeviceExtensionProperties")
    if h1 != ok || h2 != ok { ret false }
    wsi.enumerate_instance_extensions = w1
    wsi.enumerate_device_extensions = w2
    wsi_loaded = true
    ret true
}

// The names of the instance extensions the loader lists, written into `create` (VkInstanceCreateInfo: enabledExtensionCount
// at 48, ppEnabledExtensionNames at 56) when both surface extensions are there. False when not, `create` untouched.
fn enable_surface_extensions(a: *mem.Arena, library: os.Lib, create: []u8) -> bool {
    if os.NATIVE_SEPARATOR != 92u8 { ret false }
    if !load_wsi(a, library) { ret false }
    var count = 0u32
    var no_layer: *u8 = zero
    var no_props: *u8 = zero
    if wsi.enumerate_instance_extensions(no_layer, &count, no_props) != 0i32 || count == 0u32 { ret false }
    let (props, props_error) = record(a, usize(count) * 260usize)
    if props_error != ok { ret false }
    if wsi.enumerate_instance_extensions(no_layer, &count, &props[0usize]) != 0i32 { ret false }
    if !extension_listed(props, usize(count), "VK_KHR_surface") || !extension_listed(props, usize(count), "VK_KHR_win32_surface") { ret false }
    let (first, first_error) = c_string(a, "VK_KHR_surface")
    if first_error != ok { ret false }
    let (second, second_error) = c_string(a, "VK_KHR_win32_surface")
    if second_error != ok { ret false }
    let (names, names_error) = record(a, 16usize)
    if names_error != ok { ret false }
    put_pointer(names, 0usize, first)
    put_pointer(names, 8usize, second)
    put32(create, 48usize, 2usize)
    put_pointer(create, 56usize, names)
    // The surface functions are the loader's own exports; load them now so a missing one disables the feature, not the instance.
    let (s1, t1) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreateWin32SurfaceKHR")
    let (s2, t2) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroySurfaceKHR")
    let (s3, t3) = os.dlsym[fn(usize, u32, usize, *u32) -> i32](a, library, "vkGetPhysicalDeviceSurfaceSupportKHR")
    let (s4, t4) = os.dlsym[fn(usize, usize, *u8) -> i32](a, library, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR")
    let (s5, t5) = os.dlsym[fn(usize, usize, *u32, *u8) -> i32](a, library, "vkGetPhysicalDeviceSurfaceFormatsKHR")
    let (s6, t6) = os.dlsym[fn(usize, usize, *u32, *u32) -> i32](a, library, "vkGetPhysicalDeviceSurfacePresentModesKHR")
    if t1 != ok || t2 != ok || t3 != ok || t4 != ok || t5 != ok || t6 != ok { ret false }
    wsi.create_win32_surface = s1
    wsi.destroy_surface = s2
    wsi.surface_support = s3
    wsi.surface_capabilities = s4
    wsi.surface_formats = s5
    wsi.surface_present_modes = s6
    let (d1, e1) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreateSwapchainKHR")
    let (d2, e2) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroySwapchainKHR")
    let (d3, e3) = os.dlsym[fn(usize, usize, *u32, *usize) -> i32](a, library, "vkGetSwapchainImagesKHR")
    let (d4, e4) = os.dlsym[fn(usize, usize, u64, usize, usize, *u32) -> i32](a, library, "vkAcquireNextImageKHR")
    let (d5, e5) = os.dlsym[fn(usize, *u8) -> i32](a, library, "vkQueuePresentKHR")
    let (d6, e6) = os.dlsym[fn(usize, *u8, usize, *usize) -> i32](a, library, "vkCreateSemaphore")
    let (d7, e7) = os.dlsym[fn(usize, usize, usize)](a, library, "vkDestroySemaphore")
    let (d8, e8) = os.dlsym[fn(usize, u32, u32, u32, u32, *u8, u32, *u8, u32, *u8)](a, library, "vkCmdPipelineBarrier")
    let (d9, e9) = os.dlsym[fn(usize, usize, usize, u32, u32, *u8)](a, library, "vkCmdCopyBufferToImage")
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret false }
    wsi.create_swapchain = d1
    wsi.destroy_swapchain = d2
    wsi.get_swapchain_images = d3
    wsi.acquire_next_image = d4
    wsi.queue_present = d5
    wsi.create_semaphore = d6
    wsi.destroy_semaphore = d7
    wsi.cmd_pipeline_barrier = d8
    wsi.cmd_copy_buffer_to_image = d9
    ret true
}

// `text` and a NUL, as C reads a name.
fn c_string(a: *mem.Arena, text: str) -> ([]u8, err) {
    let (bytes, bytes_error) = record(a, text.len + 1usize)
    if bytes_error != ok { ret (bytes, bytes_error) }
    var at = 0usize
    while at < text.len {
        bytes[at] = text[at]
        at += 1usize
    }
    ret (bytes, ok)
}

// VK_KHR_swapchain, and VK_KHR_incremental_present when the device lists it, into a VkDeviceCreateInfo record (enabledExtensionCount
// at 48, ppEnabledExtensionNames at 56). (swapchain, incremental) as enabled.
fn enable_device_extensions(a: *mem.Arena, physical: usize, create: []u8) -> (bool, bool) {
    if !surface_ready { ret (false, false) }
    var count = 0u32
    var no_layer: *u8 = zero
    var no_props: *u8 = zero
    if wsi.enumerate_device_extensions(physical, no_layer, &count, no_props) != 0i32 || count == 0u32 { ret (false, false) }
    let (props, props_error) = record(a, usize(count) * 260usize)
    if props_error != ok { ret (false, false) }
    if wsi.enumerate_device_extensions(physical, no_layer, &count, &props[0usize]) != 0i32 { ret (false, false) }
    if !extension_listed(props, usize(count), "VK_KHR_swapchain") { ret (false, false) }
    let incremental = extension_listed(props, usize(count), "VK_KHR_incremental_present")
    let (names, names_error) = record(a, 16usize)
    if names_error != ok { ret (false, false) }
    let (first, first_error) = c_string(a, "VK_KHR_swapchain")
    if first_error != ok { ret (false, false) }
    put_pointer(names, 0usize, first)
    var enabled = 1usize
    if incremental {
        let (second, second_error) = c_string(a, "VK_KHR_incremental_present")
        if second_error != ok { ret (false, false) }
        put_pointer(names, 8usize, second)
        enabled = 2usize
    }
    put32(create, 48usize, enabled)
    put_pointer(create, 56usize, names)
    ret (true, incremental)
}

error Empty

// A window surface and its swapchain. The surface outlives swapchains (a resize makes a new swapchain on the same surface).
type Swapchain = struct {
    surface: usize,
    handle: usize,
    format: u32,
    width: u32,
    height: u32,
    count: u32,
    mode: u32,
    images: [8]usize,
    render_sems: [8]usize,
    // Whether image `i` has been presented before, so its layout is PRESENT_SRC and its pixels are kept (else UNDEFINED).
    used: [8]bool,
    acquire_sem: usize,
    fence: usize,
    fence_pending: bool,
    command: usize,
    incremental: bool,
}

// A Win32 surface for `hwnd` that this context's queue family can present to.
fn surface_open(a: *mem.Arena, context: Context, hwnd: usize, hinstance: usize) -> (usize, err) {
    if !surface_ready || !context.swapchain || hwnd == 0usize { ret (0usize, Unsupported) }
    let (create, create_error) = record(a, 40usize)
    if create_error != ok { ret (0usize, create_error) }
    put32(create, 0usize, 1000009000usize)
    put64(create, 24usize, hinstance)
    put64(create, 32usize, hwnd)
    var surface = 0usize
    if wsi.create_win32_surface(instance, &create[0usize], 0usize, &surface) != 0i32 { ret (0usize, Failed) }
    var supported = 0u32
    if wsi.surface_support(context.physical, context.family, surface, &supported) != 0i32 || supported == 0u32 {
        wsi.destroy_surface(instance, surface, 0usize)
        ret (0usize, Unsupported)
    }
    ret (surface, ok)
}

fn surface_close(surface: usize) {
    if surface != 0usize { wsi.destroy_surface(instance, surface, 0usize) }
}

// The present mode to use: `preferred` when the surface lists it, else the best of MAILBOX (1), IMMEDIATE (0), FIFO (2, which
// every surface has) when `preferred` is 4294967295. Neither of the first two paces a 15 fps interface to the display's refresh.
fn pick_present_mode(modes: []const u8, count: usize, preferred: u32) -> u32 {
    if preferred != 4294967295u32 {
        var i = 0usize
        while i < count {
            if u32(get32(modes, i * 4usize)) == preferred { ret preferred }
            i += 1usize
        }
        ret 2u32
    }
    var mailbox = false
    var immediate = false
    var i = 0usize
    while i < count {
        let mode = get32(modes, i * 4usize)
        if mode == 1usize { mailbox = true }
        if mode == 0usize { immediate = true }
        i += 1usize
    }
    if mailbox { ret 1u32 }
    if immediate { ret 0u32 }
    ret 2u32
}

// A swapchain on `surface` for a window of `want_w` x `want_h` (the surface's current extent wins when it has one), reusing
// `old`'s command buffer, fence and acquire semaphore and chaining `old.handle` as oldSwapchain (the caller retires `old` after).
// `Empty` when the window has no area (minimised); `Unsupported` when no B8G8R8A8_UNORM / TRANSFER_DST / opaque surface exists.
fn swapchain_make(a: *mem.Arena, context: Context, surface: usize, want_w: u32, want_h: u32, mode: u32, old: Swapchain) -> (Swapchain, err) {
    var made: Swapchain = zero
    let checkpoint = mem.mark(a)
    defer mem.reset(a, checkpoint)
    let (caps, caps_error) = record(a, 64usize)
    if caps_error != ok { ret (made, caps_error) }
    if wsi.surface_capabilities(context.physical, surface, &caps[0usize]) != 0i32 { ret (made, Failed) }
    var width = u32(get32(caps, 8usize))
    var height = u32(get32(caps, 12usize))
    if width == 4294967295u32 {
        width = want_w
        height = want_h
    }
    if width == 0u32 || height == 0u32 { ret (made, Empty) }
    if (get32(caps, 48usize) & 2usize) == 0usize || (get32(caps, 44usize) & 1usize) == 0usize { ret (made, Unsupported) }
    var min_images = u32(get32(caps, 0usize)) + 1u32
    if min_images < 3u32 { min_images = 3u32 }
    let max_images = u32(get32(caps, 4usize))
    if max_images != 0u32 && min_images > max_images { min_images = max_images }
    if min_images > 8u32 { min_images = 8u32 }
    var format_count = 0u32
    var no_formats: *u8 = zero
    if wsi.surface_formats(context.physical, surface, &format_count, no_formats) != 0i32 || format_count == 0u32 { ret (made, Failed) }
    let (formats, formats_error) = record(a, usize(format_count) * 8usize)
    if formats_error != ok { ret (made, formats_error) }
    if wsi.surface_formats(context.physical, surface, &format_count, &formats[0usize]) != 0i32 { ret (made, Failed) }
    var format_found = false
    var f = 0usize
    while f < usize(format_count) {
        if get32(formats, f * 8usize) == 44usize && get32(formats, f * 8usize + 4usize) == 0usize { format_found = true }
        f += 1usize
    }
    if !format_found { ret (made, Unsupported) }
    var mode_count = 0u32
    var no_modes: *u32 = zero
    if wsi.surface_present_modes(context.physical, surface, &mode_count, no_modes) != 0i32 || mode_count == 0u32 { ret (made, Failed) }
    let (modes, modes_error) = record(a, usize(mode_count) * 4usize)
    if modes_error != ok { ret (made, modes_error) }
    if wsi.surface_present_modes(context.physical, surface, &mode_count, mem.cast[*u32](&modes[0usize])) != 0i32 { ret (made, Failed) }
    let chosen_mode = pick_present_mode(modes, usize(mode_count), mode)
    let (create, create_error) = record(a, 104usize)
    if create_error != ok { ret (made, create_error) }
    put32(create, 0usize, 1000001000usize)
    put64(create, 24usize, surface)
    put32(create, 32usize, usize(min_images))
    put32(create, 36usize, 44usize)
    put32(create, 40usize, 0usize)
    put32(create, 44usize, usize(width))
    put32(create, 48usize, usize(height))
    put32(create, 52usize, 1usize)
    // TRANSFER_DST: the frame is copied in.
    put32(create, 56usize, 2usize)
    // Exclusive sharing, identity transform (1), opaque (1), clipped.
    put32(create, 80usize, 1usize)
    put32(create, 84usize, 1usize)
    put32(create, 88usize, usize(chosen_mode))
    put32(create, 92usize, 1usize)
    put64(create, 96usize, old.handle)
    var handle = 0usize
    let status = wsi.create_swapchain(context.device, &create[0usize], 0usize, &handle)
    if status != 0i32 { ret (made, Failed) }
    made.surface = surface
    made.handle = handle
    made.format = 44u32
    made.width = width
    made.height = height
    made.mode = chosen_mode
    made.incremental = context.incremental
    var count = 0u32
    var no_images: *usize = zero
    if wsi.get_swapchain_images(context.device, handle, &count, no_images) != 0i32 || count == 0u32 || count > 8u32 {
        wsi.destroy_swapchain(context.device, handle, 0usize)
        ret (zero, Failed)
    }
    var images: [8]usize = zero
    if wsi.get_swapchain_images(context.device, handle, &count, &images[0usize]) != 0i32 {
        wsi.destroy_swapchain(context.device, handle, 0usize)
        ret (zero, Failed)
    }
    made.count = count
    made.images = images
    var i = 0usize
    while i < usize(count) {
        let (semaphore_create, semaphore_create_error) = record(a, 24usize)
        if semaphore_create_error != ok {
            swapchain_retire(context, made)
            ret (zero, semaphore_create_error)
        }
        put32(semaphore_create, 0usize, 9usize)
        var semaphore = 0usize
        if wsi.create_semaphore(context.device, &semaphore_create[0usize], 0usize, &semaphore) != 0i32 {
            swapchain_retire(context, made)
            ret (zero, Failed)
        }
        made.render_sems[i] = semaphore
        i += 1usize
    }
    made.command = old.command
    made.fence = old.fence
    made.acquire_sem = old.acquire_sem
    if made.command == 0usize {
        let (allocate, allocate_error) = record(a, 32usize)
        if allocate_error != ok {
            swapchain_retire(context, made)
            ret (zero, allocate_error)
        }
        put32(allocate, 0usize, 40usize)
        put64(allocate, 16usize, context.pool)
        put32(allocate, 28usize, 1usize)
        var command = 0usize
        if api.allocate_command_buffers(context.device, &allocate[0usize], &command) != 0i32 {
            swapchain_retire(context, made)
            ret (zero, Failed)
        }
        made.command = command
        let (fence_create, fence_create_error) = record(a, 24usize)
        if fence_create_error != ok {
            swapchain_retire(context, made)
            ret (zero, fence_create_error)
        }
        put32(fence_create, 0usize, 8usize)
        var fence = 0usize
        if api.create_fence(context.device, &fence_create[0usize], 0usize, &fence) != 0i32 {
            swapchain_retire(context, made)
            ret (zero, Failed)
        }
        made.fence = fence
        let (acquire_create, acquire_create_error) = record(a, 24usize)
        if acquire_create_error != ok {
            swapchain_free(context, made)
            ret (zero, acquire_create_error)
        }
        put32(acquire_create, 0usize, 9usize)
        var acquire = 0usize
        if wsi.create_semaphore(context.device, &acquire_create[0usize], 0usize, &acquire) != 0i32 {
            swapchain_free(context, made)
            ret (zero, Failed)
        }
        made.acquire_sem = acquire
    }
    ret (made, ok)
}

// An old swapchain's own objects (its handle and render semaphores), once the queue is idle; its command buffer, fence and
// acquire semaphore belong to the new one (`swapchain_make` took them).
fn swapchain_retire(context: Context, old: Swapchain) {
    if old.handle == 0usize { ret }
    let idle = api.device_wait_idle(context.device)
    var i = 0usize
    while i < usize(old.count) {
        if old.render_sems[i] != 0usize { wsi.destroy_semaphore(context.device, old.render_sems[i], 0usize) }
        i += 1usize
    }
    wsi.destroy_swapchain(context.device, old.handle, 0usize)
}

// Everything a swapchain owns, fence and acquire semaphore included: for a close, and a failed `swapchain_make`.
fn swapchain_free(context: Context, sc: Swapchain) {
    if sc.handle == 0usize { ret }
    swapchain_retire(context, sc)
    if sc.fence != 0usize { api.destroy_fence(context.device, sc.fence, 0usize) }
    if sc.acquire_sem != 0usize { wsi.destroy_semaphore(context.device, sc.acquire_sem, 0usize) }
}

// Waits for the copy of the previous present, so its source frame is the CPU's again.
fn swapchain_wait(context: Context, sc: *Swapchain) -> err {
    if !sc.fence_pending { ret ok }
    var fence = sc.fence
    if api.wait_for_fences(context.device, 1u32, &fence, 1u32, 18446744073709551615u64) != 0i32 { ret Failed }
    if api.reset_fences(context.device, 1u32, &fence) != 0i32 { ret Failed }
    sc.fence_pending = false
    ret ok
}

// The next image to draw into: (index, status) with the raw VkResult (0 ok, 1000001003 suboptimal, -1000001004 out of date,
// 2 timeout, 1 not ready). Waits up to 250 ms, so a window that is not being shown does not hang the program.
fn swapchain_acquire(context: Context, sc: *Swapchain) -> (u32, i32) {
    var index = 0u32
    let status = wsi.acquire_next_image(context.device, sc.handle, 250000000u64, sc.acquire_sem, 0usize, &index)
    ret (index, status)
}

// Copies the rectangle (x, y, w, h) of `source` (a buffer of `source_width` pixel rows, B8G8R8A8) into acquired image `index`,
// and presents it, telling the compositor the same rectangle when VK_KHR_incremental_present is on. The raw VkResult of the
// present (VK_DEVICE_LOST when recording or the submit failed).
fn swapchain_present(a: *mem.Arena, context: Context, sc: *Swapchain, index: u32, source: usize, source_width: u32, x: u32, y: u32, w: u32, h: u32) -> i32 {
    let checkpoint = mem.mark(a)
    defer mem.reset(a, checkpoint)
    let image = sc.images[usize(index)]
    let command = sc.command
    if api.reset_command_buffer(command, 0u32) != 0i32 { ret VK_DEVICE_LOST }
    let (begin, begin_error) = record(a, 32usize)
    if begin_error != ok { ret VK_DEVICE_LOST }
    put32(begin, 0usize, 42usize)
    put32(begin, 16usize, 1usize)
    if api.begin_command_buffer(command, &begin[0usize]) != 0i32 { ret VK_DEVICE_LOST }
    let (barrier, barrier_error) = record(a, 72usize)
    if barrier_error != ok { ret VK_DEVICE_LOST }
    put32(barrier, 0usize, 45usize)
    // Before the copy: nothing waits on the image but the copy; a presented image keeps its pixels (PRESENT_SRC), a new one has none.
    put32(barrier, 20usize, 4096usize)
    if sc.used[usize(index)] { put32(barrier, 24usize, 1000001002usize) } else { put32(barrier, 24usize, 0usize) }
    put32(barrier, 28usize, 7usize)
    put32(barrier, 32usize, 4294967295usize)
    put32(barrier, 36usize, 4294967295usize)
    put64(barrier, 40usize, image)
    put32(barrier, 48usize, 1usize)
    put32(barrier, 56usize, 1usize)
    put32(barrier, 64usize, 1usize)
    var no_barriers: *u8 = zero
    wsi.cmd_pipeline_barrier(command, 1u32, 4096u32, 0u32, 0u32, no_barriers, 0u32, no_barriers, 1u32, &barrier[0usize])
    let (region, region_error) = record(a, 56usize)
    if region_error != ok { ret VK_DEVICE_LOST }
    put64(region, 0usize, (usize(y) * usize(source_width) + usize(x)) * 4usize)
    put32(region, 8usize, usize(source_width))
    put32(region, 16usize, 1usize)
    put32(region, 28usize, 1usize)
    put32(region, 32usize, usize(x))
    put32(region, 36usize, usize(y))
    put32(region, 44usize, usize(w))
    put32(region, 48usize, usize(h))
    put32(region, 52usize, 1usize)
    wsi.cmd_copy_buffer_to_image(command, source, image, 7u32, 1u32, &region[0usize])
    // After it: the image becomes the presentation engine's.
    put32(barrier, 16usize, 4096usize)
    put32(barrier, 20usize, 0usize)
    put32(barrier, 24usize, 7usize)
    put32(barrier, 28usize, 1000001002usize)
    wsi.cmd_pipeline_barrier(command, 4096u32, 8192u32, 0u32, 0u32, no_barriers, 0u32, no_barriers, 1u32, &barrier[0usize])
    if api.end_command_buffer(command) != 0i32 { ret VK_DEVICE_LOST }
    let (commands, commands_error) = record(a, 8usize)
    if commands_error != ok { ret VK_DEVICE_LOST }
    put64(commands, 0usize, command)
    let (wait_semaphores, wait_error) = record(a, 8usize)
    if wait_error != ok { ret VK_DEVICE_LOST }
    put64(wait_semaphores, 0usize, sc.acquire_sem)
    let (wait_stages, stages_error) = record(a, 4usize)
    if stages_error != ok { ret VK_DEVICE_LOST }
    put32(wait_stages, 0usize, 4096usize)
    let (signal_semaphores, signal_error) = record(a, 8usize)
    if signal_error != ok { ret VK_DEVICE_LOST }
    put64(signal_semaphores, 0usize, sc.render_sems[usize(index)])
    let (submit, submit_error) = record(a, 72usize)
    if submit_error != ok { ret VK_DEVICE_LOST }
    put32(submit, 0usize, 4usize)
    put32(submit, 16usize, 1usize)
    put_pointer(submit, 24usize, wait_semaphores)
    put_pointer(submit, 32usize, wait_stages)
    put32(submit, 40usize, 1usize)
    put_pointer(submit, 48usize, commands)
    put32(submit, 56usize, 1usize)
    put_pointer(submit, 64usize, signal_semaphores)
    if api.queue_submit(context.queue, 1u32, &submit[0usize], sc.fence) != 0i32 { ret VK_DEVICE_LOST }
    sc.fence_pending = true
    sc.used[usize(index)] = true
    let (present, present_error) = record(a, 64usize)
    if present_error != ok { ret VK_DEVICE_LOST }
    put32(present, 0usize, 1000001001usize)
    put32(present, 16usize, 1usize)
    put_pointer(present, 24usize, signal_semaphores)
    put32(present, 32usize, 1usize)
    let (swapchains, swapchains_error) = record(a, 8usize)
    if swapchains_error != ok { ret VK_DEVICE_LOST }
    put64(swapchains, 0usize, sc.handle)
    put_pointer(present, 40usize, swapchains)
    let (indices, indices_error) = record(a, 4usize)
    if indices_error != ok { ret VK_DEVICE_LOST }
    put32(indices, 0usize, usize(index))
    put_pointer(present, 48usize, indices)
    if sc.incremental {
        // VkPresentRegionsKHR { sType, pNext, swapchainCount, pRegions } -> VkPresentRegionKHR { rectangleCount, pRectangles } -> VkRectLayerKHR.
        let (rectangle, rectangle_error) = record(a, 20usize)
        if rectangle_error != ok { ret VK_DEVICE_LOST }
        put32(rectangle, 0usize, usize(x))
        put32(rectangle, 4usize, usize(y))
        put32(rectangle, 8usize, usize(w))
        put32(rectangle, 12usize, usize(h))
        let (present_region, present_region_error) = record(a, 16usize)
        if present_region_error != ok { ret VK_DEVICE_LOST }
        put32(present_region, 0usize, 1usize)
        put_pointer(present_region, 8usize, rectangle)
        let (regions, regions_error) = record(a, 32usize)
        if regions_error != ok { ret VK_DEVICE_LOST }
        put32(regions, 0usize, 1000084000usize)
        put32(regions, 16usize, 1usize)
        put_pointer(regions, 24usize, present_region)
        put_pointer(present, 8usize, regions)
    }
    ret wsi.queue_present(context.queue, &present[0usize])
}

// The present mode picked from what the surface lists (D5928): MAILBOX, then IMMEDIATE, then FIFO; a named mode when listed.
@test
fn present_mode_prefers_mailbox_then_immediate(a: *mem.Arena) -> err {
    var modes: [12]u8 = zero
    modes[0usize] = 2u8
    modes[4usize] = 0u8
    modes[8usize] = 1u8
    if pick_present_mode(modes[0usize..12usize], 3usize, 4294967295u32) != 1u32 { ret Failed }
    var without: [8]u8 = zero
    without[0usize] = 2u8
    without[4usize] = 0u8
    if pick_present_mode(without[0usize..8usize], 2usize, 4294967295u32) != 0u32 { ret Failed }
    if pick_present_mode(without[0usize..4usize], 1usize, 4294967295u32) != 2u32 { ret Failed }
    if pick_present_mode(modes[0usize..12usize], 3usize, 0u32) != 0u32 { ret Failed }
    if pick_present_mode(without[0usize..4usize], 1usize, 1u32) != 2u32 { ret Failed }
    ret ok
}
