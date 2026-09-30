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
// Storage, device-address, and both transfer directions.
const BUFFER_USAGE: u32 = 131107u32

type Api = struct {
    create_instance: fn(*u8, usize, *usize) -> i32,
    destroy_instance: fn(usize, usize),
    enumerate_physical_devices: fn(usize, *u32, *usize) -> i32,
    get_physical_device_properties: fn(usize, *u8),
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
    get_buffer_device_address: fn(usize, *u8) -> u64,
    device_wait_idle: fn(usize) -> i32,
    create_shader_module: fn(usize, *u8, usize, *usize) -> i32,
    destroy_shader_module: fn(usize, usize, usize),
    create_pipeline_layout: fn(usize, *u8, usize, *usize) -> i32,
    destroy_pipeline_layout: fn(usize, usize, usize),
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
    memory_bytes: u64,
    // `gpu.Cap`'s members as bits (Int8 Int16 Int64 Float16 Float64 Atomic64 ...).
    caps: usize,
    // Whether the section 10 floor holds: Vulkan 1.2, buffer device addresses, scalar block
    // layout and a compute queue.
    floor: bool,
    compute_family: u32,
    uuid: [16]u8,
}

// An opened device: its handles, the memory type buffers come from, and the queue.
type Context = struct {
    physical: usize,
    device: usize,
    queue: usize,
    family: u32,
    memory_type: u32,
}

// A buffer: its handle and memory, its device address, and its bytes mapped on the host.
type Buffer = struct {
    handle: usize,
    memory: usize,
    address: u64,
    bytes: []u8,
}

var api: Api = zero
// The loader, kept open for the process: its entry points are in `api`.
var loader: os.Lib = zero
var loaded: bool = zero
var instance: usize = zero

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

// The loader and every entry point this runtime calls, once per process.
fn load(a: *mem.Arena) -> err {
    if loaded { ret ok }
    let (library, library_error) = os.dlopen(a, library_name())
    if library_error != ok { ret NoLoader }
    let (p1, e1) = os.dlsym[fn(*u8, usize, *usize) -> i32](a, library, "vkCreateInstance")
    let (p2, e2) = os.dlsym[fn(usize, usize)](a, library, "vkDestroyInstance")
    let (p3, e3) = os.dlsym[fn(usize, *u32, *usize) -> i32](a, library, "vkEnumeratePhysicalDevices")
    let (p4, e4) = os.dlsym[fn(usize, *u8)](a, library, "vkGetPhysicalDeviceProperties")
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
    let (p18, e18) = os.dlsym[fn(usize, *u8) -> u64](a, library, "vkGetBufferDeviceAddress")
    let (p19, e19) = os.dlsym[fn(usize) -> i32](a, library, "vkDeviceWaitIdle")
    let dispatch_error = load_dispatch(a, library)
    if dispatch_error != ok {
        let closed = os.dlclose(library)
        ret dispatch_error
    }
    loader = library
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret NoLoader }
    if e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok { ret NoLoader }
    api = Api { create_instance: p1, destroy_instance: p2, enumerate_physical_devices: p3, get_physical_device_properties: p4, get_physical_device_features2: p5, get_physical_device_memory_properties: p6, get_physical_device_queue_family_properties: p7, create_device: p8, destroy_device: p9, get_device_queue: p10, create_buffer: p11, destroy_buffer: p12, get_buffer_memory_requirements: p13, allocate_memory: p14, free_memory: p15, bind_buffer_memory: p16, map_memory: p17, get_buffer_device_address: p18, device_wait_idle: p19, create_shader_module: api.create_shader_module, destroy_shader_module: api.destroy_shader_module, create_pipeline_layout: api.create_pipeline_layout, destroy_pipeline_layout: api.destroy_pipeline_layout, create_compute_pipelines: api.create_compute_pipelines, destroy_pipeline: api.destroy_pipeline, create_command_pool: api.create_command_pool, destroy_command_pool: api.destroy_command_pool, allocate_command_buffers: api.allocate_command_buffers, begin_command_buffer: api.begin_command_buffer, end_command_buffer: api.end_command_buffer, cmd_bind_pipeline: api.cmd_bind_pipeline, cmd_push_constants: api.cmd_push_constants, cmd_dispatch: api.cmd_dispatch, queue_submit: api.queue_submit, queue_wait_idle: api.queue_wait_idle }
    // One instance for the process: the application record, then the instance's.
    let (application, application_error) = record(a, 48usize)
    if application_error != ok { ret application_error }
    put32(application, 44usize, usize(API_VERSION))
    let (create, create_error) = record(a, 64usize)
    if create_error != ok { ret create_error }
    put32(create, 0usize, 1usize)
    put_pointer(create, 24usize, application)
    var made = 0usize
    if api.create_instance(&create[0usize], 0usize, &made) != 0i32 { ret NoLoader }
    instance = made
    loaded = true
    ret ok
}

// The physical devices, each with its name, kind, memory, capabilities and whether section 10's
// floor holds on it.
fn devices(a: *mem.Arena, limit: usize) -> ([]Physical, err) {
    var none: []Physical = zero
    let load_error = load(a)
    if load_error != ok { ret (none, load_error) }
    var count = 0u32
    var no_handles: *usize = zero
    if api.enumerate_physical_devices(instance, &count, no_handles) != 0i32 { ret (none, Failed) }
    if count == 0u32 { ret (none, NoDevice) }
    let (handles, handles_error) = mem.alloc[usize](a, usize(count))
    if handles_error != ok { ret (none, handles_error) }
    if api.enumerate_physical_devices(instance, &count, &handles[0usize]) != 0i32 { ret (none, Failed) }
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
    let (properties, properties_error) = record(a, 824usize)
    if properties_error != ok { ret (described, properties_error) }
    api.get_physical_device_properties(handle, &properties[0usize])
    described.api_version = u32(get32(properties, 0usize))
    described.vendor = u32(get32(properties, 8usize))
    described.device = u32(get32(properties, 12usize))
    described.device_type = u32(get32(properties, 16usize))
    var length = 0usize
    while length < 256usize && properties[20usize + length] != 0u8 { length += 1usize }
    described.name = properties[20usize..20usize + length]
    // The pipeline cache UUID stands in for the device's identity (D83's DeviceKey).
    var k = 0usize
    while k < 16usize {
        described.uuid[k] = properties[276usize + k]
        k += 1usize
    }
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
    var kind = 0usize
    while kind < types && kind < 32usize {
        let flags = get32(memory, 4usize + kind * 8usize)
        // A host-visible, coherent type, a device-local one first where there is one.
        if (flags & wanted) == wanted {
            if chosen == 32usize || ((flags & usize(MEMORY_DEVICE_LOCAL)) != 0usize && (get32(memory, 4usize + chosen * 8usize) & usize(MEMORY_DEVICE_LOCAL)) == 0usize) { chosen = kind }
        }
        kind += 1usize
    }
    if chosen == 32usize { ret (context, Unsupported) }
    context.memory_type = u32(chosen)
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

// A SPIR-V module's `entry` made into a compute pipeline whose one push constant is eight
// bytes, the argument block's device address (D1610's launch ABI).
fn pipeline(a: *mem.Arena, context: Context, code: []const u8, entry: str) -> (Pipeline, err) {
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
    if api.create_compute_pipelines(context.device, 0usize, 1u32, &pipeline_create[0usize], 0usize, &compute) != 0i32 {
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

// One dispatch of `groups` workgroups with the argument block at `block`, waited for: a
// command pool for the launch, one command buffer, and the queue idle before it returns.
// ponytail: a pool and an idle wait per launch; a queue's own pool and a fence per launch
// when launches overlap.
fn dispatch(a: *mem.Arena, context: Context, made: Pipeline, block: u64, x: u32, y: u32, z: u32) -> err {
    let (pool_create, pool_create_error) = record(a, 24usize)
    if pool_create_error != ok { ret pool_create_error }
    put32(pool_create, 0usize, 39usize)
    put32(pool_create, 20usize, usize(context.family))
    var pool = 0usize
    if api.create_command_pool(context.device, &pool_create[0usize], 0usize, &pool) != 0i32 { ret Failed }
    let answer = record_and_submit(a, context, made, pool, block, x, y, z)
    api.destroy_command_pool(context.device, pool, 0usize)
    ret answer
}

fn record_and_submit(a: *mem.Arena, context: Context, made: Pipeline, pool: usize, block: u64, x: u32, y: u32, z: u32) -> err {
    let (allocate, allocate_error) = record(a, 32usize)
    if allocate_error != ok { ret allocate_error }
    put32(allocate, 0usize, 40usize)
    put64(allocate, 16usize, pool)
    put32(allocate, 28usize, 1usize)
    var command = 0usize
    if api.allocate_command_buffers(context.device, &allocate[0usize], &command) != 0i32 { ret Failed }
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
    let (commands, commands_error) = record(a, 8usize)
    if commands_error != ok { ret commands_error }
    put64(commands, 0usize, command)
    let (submit, submit_error) = record(a, 72usize)
    if submit_error != ok { ret submit_error }
    put32(submit, 0usize, 4usize)
    put32(submit, 40usize, 1usize)
    put_pointer(submit, 48usize, commands)
    if api.queue_submit(context.queue, 1u32, &submit[0usize], 0usize) != 0i32 { ret Failed }
    if api.queue_wait_idle(context.queue) != 0i32 { ret Failed }
    ret ok
}

fn close(context: Context) {
    if context.device == 0usize { ret }
    let idle = api.device_wait_idle(context.device)
    api.destroy_device(context.device, 0usize)
}

// A buffer of `size` bytes: storage and device-addressable, its memory host-visible and
// mapped for as long as it lives, so an upload or a download is a copy.
fn buffer(a: *mem.Arena, context: Context, size: usize) -> (Buffer, err) {
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
    if requirements_error != ok { ret (made, requirements_error) }
    api.get_buffer_memory_requirements(context.device, handle, &requirements[0usize])
    if (get32(requirements, 16usize) & (1usize << usize(context.memory_type))) == 0usize {
        api.destroy_buffer(context.device, handle, 0usize)
        ret (made, Unsupported)
    }
    let (flags, flags_error) = record(a, 24usize)
    if flags_error != ok { ret (made, flags_error) }
    put32(flags, 0usize, 1000060000usize)
    put32(flags, 16usize, 2usize)
    let (allocate, allocate_error) = record(a, 32usize)
    if allocate_error != ok { ret (made, allocate_error) }
    put32(allocate, 0usize, 5usize)
    put_pointer(allocate, 8usize, flags)
    put64(allocate, 16usize, get64(requirements, 0usize))
    put32(allocate, 24usize, usize(context.memory_type))
    var memory = 0usize
    if api.allocate_memory(context.device, &allocate[0usize], 0usize, &memory) != 0i32 {
        api.destroy_buffer(context.device, handle, 0usize)
        ret (made, OutOfMemory)
    }
    made.memory = memory
    if api.bind_buffer_memory(context.device, handle, memory, 0u64) != 0i32 {
        free(context, made)
        ret (made, Failed)
    }
    var mapped: *u8 = zero
    if api.map_memory(context.device, memory, 0u64, u64(bytes_size), 0u32, &mapped) != 0i32 {
        free(context, made)
        ret (made, Failed)
    }
    var region: mem.Arena = zero
    region.base = mapped
    region.cap = bytes_size
    region.off = 0usize
    made.bytes = mem.view(&region, 0usize, size)
    let (address_info, address_error) = record(a, 24usize)
    if address_error != ok { ret (made, address_error) }
    put32(address_info, 0usize, 1000244001usize)
    put64(address_info, 16usize, handle)
    made.address = api.get_buffer_device_address(context.device, &address_info[0usize])
    ret (made, ok)
}

fn free(context: Context, made: Buffer) {
    if made.handle != 0usize { api.destroy_buffer(context.device, made.handle, 0usize) }
    if made.memory != 0usize { api.free_memory(context.device, made.memory, 0usize) }
}
