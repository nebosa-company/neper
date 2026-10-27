// `x.khronos.egl`: EGL 1.0 to 1.5, the context interface for OpenGL ES everywhere and for
// desktop OpenGL on Linux (D5880, D5883, D5885). `load` opens the EGL library -- Mesa's
// `libEGL.so.1`, or ANGLE's `libEGL.dll` on Windows -- and fills every entry point through
// `eglGetProcAddress`, falling back to the library's own export. `proc_address` is the
// resolver `gl.load` takes once a context is current.
//
// Names drop the `egl`/`EGL_` prefix: `eglGetPlatformDisplay` is `get_platform_display`.
// Constants are `i32`, the type of an attribute list's entries; `TRUE` and `FALSE` are
// EGLBoolean `u32`, the `NO_*` handles `usize`. A parameter declared `EGLenum` takes `u32(X)`.

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
var loaded: bool = false
var missing_name: str = zero

fn default_library() -> str {
    if os.NATIVE_SEPARATOR == 92u8 { ret "libEGL.dll" }
    ret "libEGL.so.1"
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
fn proc_address(a: *mem.Arena, context: usize, name: str) -> usize {
    if !loaded || name.len >= 127usize { ret 0usize }
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

// Opens `name` (empty for the platform's default) and fills the table. `NoLoader` when the
// library or its `eglGetProcAddress` is missing; `Unsupported` names, through `missing`, an
// EGL 1.5 entry point the library lacks.
fn load(a: *mem.Arena, name: str) -> err {
    if loaded { ret ok }
    var path = name
    if path.len == 0usize { path = default_library() }
    let (opened, open_error) = os.dlopen(a, path)
    if open_error != ok { ret NoLoader }
    let (lookup, lookup_error) = os.dlsym[GetProc](a, opened, "eglGetProcAddress")
    if lookup_error != ok {
        let closed = os.dlclose(opened)
        ret NoLoader
    }
    library = opened
    lookup_state.get_proc = lookup
    loaded = true
    missing_name = ""
    ret load_entries(a, proc_address, 0usize, 1u8)
}

fn missing() -> str { ret missing_name }
