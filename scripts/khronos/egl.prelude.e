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
// What the library's `load` answered: 0 ok, 2 Unsupported (a module-scope `err` cannot be
// stored). A library that did not open is not remembered, so `load` may try another.
var load_code: u8 = 0u8
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

// Opens `name` (empty for the platform's default) and fills the table, once per process: a
// second call answers what the first did. `NoLoader` when the library or its
// `eglGetProcAddress` is missing; `Unsupported` names, through `missing`, an EGL 1.4 entry
// point the library lacks. EGL 1.5's entries are filled when present; ask `present`.
fn load(a: *mem.Arena, name: str) -> err {
    if loaded {
        if load_code != 0u8 { ret Unsupported }
        ret ok
    }
    let (opened, open_error) = open_library(a, name)
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
    if load_entries(a, proc_address, 0usize, 1u8) != ok {
        load_code = 2u8
        ret Unsupported
    }
    ret ok
}

fn missing() -> str { ret missing_name }

// Whether the library supplied the entry in slot `entry` (a `*_ENTRY` constant).
fn present(entry: usize) -> bool { ret entry < ENTRY_COUNT && procs[entry] != 0usize }
