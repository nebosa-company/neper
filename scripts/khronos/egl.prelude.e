// `x.khronos.egl`: EGL 1.0 to 1.5, the context interface for OpenGL ES everywhere and for
// desktop OpenGL on Linux (D5880, D5883, D5885). `load` opens the EGL library -- Mesa's
// `libEGL.so.1`, or ANGLE's `libEGL.dll` on Windows -- and fills every entry point through
// `eglGetProcAddress`, falling back to the library's own export. `proc_address` is the
// resolver `gl.load` takes once a context is current.
//
// Names drop the `egl`/`EGL_` prefix: `eglGetPlatformDisplay` is `get_platform_display`.
// Constants are `i32`, the type of an attribute list's entries; `TRUE` and `FALSE` are
// EGLBoolean `u32`, the `NO_*` handles `usize`. A parameter declared `EGLenum` takes `u32(X)`.

use e.atomic
use e.mem
use e.os

error NoLoader
error Unsupported

type Resolve = fn(*mem.Arena, usize, str) -> usize
type GetProc = fn(*const u8) -> usize
type Proc = fn()
type ProcPun = union { function: Proc, bits: usize }
type Lookup = struct { get_proc: GetProc }

var library: os.Lib = zero
var lookup_state: Lookup = zero
// 0 is idle (including a retryable NoLoader result), 1 is filling the table, 2 is a
// complete usable table and 3 is a completed rejected initialization whose required
// entry was missing.
// The state is the publication barrier for `library`, `lookup_state`, `procs` and
// `missing_name`: no other caller sees those globals until initialization finishes.
const LOAD_IDLE: u32 = 0u32
const LOAD_FILLING: u32 = 1u32
const LOAD_READY: u32 = 2u32
const LOAD_UNSUPPORTED: u32 = 3u32
// Keep the one atomic word in addressable static storage on every self-host target.
var load_state: [1]Atomic[u32] = zero
var missing_name: str = zero

fn default_library() -> str {
    if os.NATIVE_SEPARATOR == 92u8 { ret "libEGL.dll" }
    ret "libEGL.so.1"
}

// `name`, or the platform's default; Android names the default without its version, `libEGL.so`.
fn open_library(a: *mem.Arena, name: str) -> (os.Lib, err) {
    var path = name
    if path.len == 0usize { path = default_library() }
    let (opened, open_error) = os.dlopen(a, path)
    if open_error != ok {
        var none: os.Lib = zero
        if name.len != 0usize || os.NATIVE_SEPARATOR == 92u8 { ret (none, open_error) }
        let (unversioned, unversioned_error) = os.dlopen(a, "libEGL.so")
        ret (unversioned, unversioned_error)
    }
    ret (opened, ok)
}

fn fetch(a: *mem.Arena, resolve: Resolve, context: usize, index: usize, name: str, required: u8) -> err {
    let address = resolve(a, context, name)
    procs[index] = address
    if address == 0usize && required != 0u8 {
        missing_name = name
        ret Unsupported
    }
    ret ok
}

// An entry point by C name: `eglGetProcAddress` first, then the library's export.
// This is used only by the initializing caller, after it filled `library` and
// `lookup_state`; public lookup below waits for the state publication first.
fn initializing_proc_address(a: *mem.Arena, context: usize, name: str) -> usize {
    if name.len >= 127usize { ret 0usize }
    var buffer: [128]u8 = zero
    var k = 0usize
    while k < name.len {
        buffer[k] = name[k]
        k += 1usize
    }
    let address = lookup_state.get_proc(&buffer[0usize])
    if address != 0usize { ret address }
    let (symbol, symbol_error) = os.dlsym[Proc](a, library, name)
    if symbol_error != ok { ret 0usize }
    var pun: ProcPun = zero
    pun.function = symbol
    ret pun.bits
}

// Public lookup accepts only a completely published EGL table, never the filling
// state that another thread can observe while `load_entries` runs.
fn proc_address(a: *mem.Arena, context: usize, name: str) -> usize {
    let state = atomic.load(&load_state[0usize], .Acquire)
    if state != LOAD_READY { ret 0usize }
    ret initializing_proc_address(a, context, name)
}

// The work a caller that won initialization performs. A missing library is not
// remembered and lets a later call try another name; an incomplete EGL implementation
// is terminal for this process, as the original once-per-process contract specified.
fn load_first(a: *mem.Arena, name: str) -> err {
    let (opened, open_error) = open_library(a, name)
    if open_error != ok { ret NoLoader }
    let (lookup, lookup_error) = os.dlsym[GetProc](a, opened, "eglGetProcAddress")
    if lookup_error != ok {
        let closed = os.dlclose(opened)
        ret NoLoader
    }
    library = opened
    lookup_state.get_proc = lookup
    missing_name = ""
    if load_entries(a, initializing_proc_address, 0usize, 1u8) != ok { ret Unsupported }
    ret ok
}

// Opens `name` (empty for the platform's default) and fills the table once per process.
// Concurrent callers wait until the current attempt completes. `NoLoader` resets to
// idle, so its caller gets that error and woken callers retry their own name; the first
// `ok` or `Unsupported` result is process-wide. `Unsupported` remembers the incomplete
// implementation and names the missing required entry through `missing`.
fn load(a: *mem.Arena, name: str) -> err {
    while true {
        let state = atomic.load(&load_state[0usize], .Acquire)
        if state == LOAD_READY { ret ok }
        if state == LOAD_UNSUPPORTED { ret Unsupported }
        if state == LOAD_FILLING {
            let ignored = os.wait_u32(&load_state[0usize], LOAD_FILLING, -1i64)
            continue
        }
        let (won, seen) = atomic.cas(&load_state[0usize], LOAD_IDLE, LOAD_FILLING, .Acquire, .Acquire)
        if !won { continue }
        let result = load_first(a, name)
        var published = LOAD_IDLE
        if result == ok { published = LOAD_READY }
        if result == Unsupported { published = LOAD_UNSUPPORTED }
        atomic.store(&load_state[0usize], published, .Release)
        os.wake_all_u32(&load_state[0usize])
        ret result
    }
    ret NoLoader
}

fn missing() -> str {
    let state = atomic.load(&load_state[0usize], .Acquire)
    if state != LOAD_READY && state != LOAD_UNSUPPORTED { ret "" }
    ret missing_name
}

// Whether the library supplied the entry in slot `entry` (a `*_ENTRY` constant).
fn present(entry: usize) -> bool {
    let state = atomic.load(&load_state[0usize], .Acquire)
    if state != LOAD_READY { ret false }
    ret entry < ENTRY_COUNT && procs[entry] != 0usize
}
