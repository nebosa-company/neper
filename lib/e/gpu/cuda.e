// CUDA device enumeration under `e.gpu` (C093, D4705): the driver library opened at run time --
// `nvcuda.dll` on Windows, `libcuda.so.1` on Linux -- so a program that never asks for a `.Cuda`
// device needs no NVIDIA driver, and the handful of driver-API entry points the enumeration
// needs looked up by name through `os.dlsym`. Only enumeration lives here: there is no CUDA
// compute backend yet (M4), so a device found is reported and `open` stays `Unsupported`.
//
// A device's identity is `cuDeviceGetUuid`'s sixteen bytes, which on a GPU that also has a
// Vulkan driver is the same bytes as Vulkan's `deviceUUID`; the key still carries its backend and
// is never matched across backends.

use e.mem
use e.os

error NoLoader
error NoDevice
error Failed

const CUDA_SUCCESS: i32 = 0i32
const CUDA_ERROR_NO_DEVICE: i32 = 100i32
// CU_DEVICE_ATTRIBUTE_INTEGRATED.
const ATTRIBUTE_INTEGRATED: i32 = 18i32
const NAME_BYTES: usize = 128usize

// A CUDA device as `devices` reports it.
type Physical = struct {
    name: str,
    uuid: [16]u8,
    uuid_valid: bool,
    memory_bytes: u64,
    integrated: bool,
}

type Api = struct {
    init: fn(u32) -> i32,
    device_get_count: fn(*i32) -> i32,
    device_get: fn(*i32, i32) -> i32,
    device_get_name: fn(*u8, i32, i32) -> i32,
    device_get_uuid: fn(*u8, i32) -> i32,
    device_total_mem: fn(*usize, i32) -> i32,
    device_get_attribute: fn(*i32, i32, i32) -> i32,
}

var api: Api = zero
var driver: os.Lib = zero
var loaded: bool = false
var initialised: bool = false

fn library_name() -> str {
    if os.NATIVE_SEPARATOR == 92u8 { ret "nvcuda.dll" }
    ret "libcuda.so.1"
}

fn load(a: *mem.Arena) -> err {
    if loaded { ret ok }
    let (library, library_error) = os.dlopen(a, library_name())
    if library_error != ok { ret NoLoader }
    let (p1, e1) = os.dlsym[fn(u32) -> i32](a, library, "cuInit")
    let (p2, e2) = os.dlsym[fn(*i32) -> i32](a, library, "cuDeviceGetCount")
    let (p3, e3) = os.dlsym[fn(*i32, i32) -> i32](a, library, "cuDeviceGet")
    let (p4, e4) = os.dlsym[fn(*u8, i32, i32) -> i32](a, library, "cuDeviceGetName")
    let (p5, e5) = os.dlsym[fn(*u8, i32) -> i32](a, library, "cuDeviceGetUuid")
    let (p6, e6) = os.dlsym[fn(*usize, i32) -> i32](a, library, "cuDeviceTotalMem_v2")
    let (p7, e7) = os.dlsym[fn(*i32, i32, i32) -> i32](a, library, "cuDeviceGetAttribute")
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok {
        let closed = os.dlclose(library)
        ret NoLoader
    }
    driver = library
    api = Api { init: p1, device_get_count: p2, device_get: p3, device_get_name: p4, device_get_uuid: p5, device_total_mem: p6, device_get_attribute: p7 }
    loaded = true
    ret ok
}

// The CUDA devices, at most `limit`, each with its name, identity and memory. `NoLoader` is no
// driver, `NoDevice` a driver with no device, `Failed` a driver call that did not answer.
fn devices(a: *mem.Arena, limit: usize) -> ([]Physical, err) {
    var none: []Physical = zero
    let load_error = load(a)
    if load_error != ok { ret (none, load_error) }
    if !initialised {
        if api.init(0u32) != CUDA_SUCCESS { ret (none, NoLoader) }
        initialised = true
    }
    var count = 0i32
    let count_status = api.device_get_count(&count)
    if count_status == CUDA_ERROR_NO_DEVICE { ret (none, NoDevice) }
    if count_status != CUDA_SUCCESS { ret (none, Failed) }
    if count <= 0i32 { ret (none, NoDevice) }
    var total = usize(count)
    if total > limit { total = limit }
    let (found, found_error) = mem.alloc[Physical](a, total)
    if found_error != ok { ret (none, found_error) }
    var at = 0usize
    while at < total {
        var device = 0i32
        if api.device_get(&device, i32(at)) != CUDA_SUCCESS { ret (none, Failed) }
        let (text, text_error) = mem.alloc[u8](a, NAME_BYTES)
        if text_error != ok { ret (none, text_error) }
        var fill = 0usize
        while fill < NAME_BYTES {
            text[fill] = 0u8
            fill += 1usize
        }
        if api.device_get_name(&text[0usize], i32(NAME_BYTES), device) != CUDA_SUCCESS { ret (none, Failed) }
        var length = 0usize
        while length < NAME_BYTES && text[length] != 0u8 { length += 1usize }
        var record: Physical = zero
        record.name = text[0usize..length]
        var uuid: [16]u8 = zero
        if api.device_get_uuid(&uuid[0usize], device) != CUDA_SUCCESS { ret (none, Failed) }
        record.uuid = uuid
        var any = false
        var byte = 0usize
        while byte < 16usize {
            if uuid[byte] != 0u8 { any = true }
            byte += 1usize
        }
        record.uuid_valid = any
        var memory = 0usize
        if api.device_total_mem(&memory, device) != CUDA_SUCCESS { ret (none, Failed) }
        record.memory_bytes = u64(memory)
        var integrated = 0i32
        if api.device_get_attribute(&integrated, ATTRIBUTE_INTEGRATED, device) != CUDA_SUCCESS { ret (none, Failed) }
        record.integrated = integrated != 0i32
        found[at] = record
        at += 1usize
    }
    ret (found, ok)
}
