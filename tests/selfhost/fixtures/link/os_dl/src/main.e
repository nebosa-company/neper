// `e.os`'s loader: `dlopen`, `dlsym` and `dlclose`.
//
// The library each host opens is the one it already depends on and is therefore certain to be
// there -- `kernel32.dll` on Windows, `libc.so.6` on Linux -- so nothing here needs anything
// installed. The name is passed through as `@import` takes it, which is why it differs per host
// and why `os.NATIVE_SEPARATOR` is what tells them apart.

use e.mem
use e.os

fn host_library() -> str {
    if os.NATIVE_SEPARATOR == 92u8 { ret "kernel32.dll" }
    ret "libc.so.6"
}

// A symbol each host is certain to export from the library above, with a signature that can be
// checked by calling it: one takes nothing and answers with something non-zero.
fn host_symbol() -> str {
    if os.NATIVE_SEPARATOR == 92u8 { ret "GetCurrentProcessId" }
    ret "getpid"
}

fn main(a: *mem.Arena) -> err {
    // --- A library that is certainly loaded already opens, and opening it again is a second
    // reference rather than a second load: both hosts count them, so both closes must succeed.
    let (first, first_error) = os.dlopen(a, host_library())
    if first_error != ok { os.exit(10i32) }
    if first.raw == 0usize { os.exit(11i32) }
    let (second, second_error) = os.dlopen(a, host_library())
    if second_error != ok { os.exit(12i32) }
    if second.raw != first.raw { os.exit(13i32) }
    if os.dlclose(second) != ok { os.exit(14i32) }
    if os.dlclose(first) != ok { os.exit(15i32) }

    // --- A symbol, called. `dlsym` answers with a value of the type asked for, so this is an
    // ordinary indirect call afterwards -- which is the whole point of it, and the one thing no
    // library could do for itself.
    let (library, library_error) = os.dlopen(a, host_library())
    if library_error != ok { os.exit(30i32) }
    let (identity, identity_error) = os.dlsym[fn() -> i32](a, library, host_symbol())
    if identity_error != ok { os.exit(31i32) }
    let own = identity()
    if own <= 0i32 { os.exit(32i32) }
    // The same symbol twice is the same address, so calling either gives the same answer.
    let (again, again_error) = os.dlsym[fn() -> i32](a, library, host_symbol())
    if again_error != ok { os.exit(33i32) }
    if again() != own { os.exit(34i32) }

    // --- A symbol that is not there is `NotFound`, not an address that would crash on a call.
    let (absent, absent_error) = os.dlsym[fn() -> i32](a, library, "np_no_such_symbol_here")
    if absent_error == ok { os.exit(35i32) }
    // An empty symbol name is not a symbol name.
    let (unnamed, unnamed_error) = os.dlsym[fn() -> i32](a, library, "")
    if unnamed_error != os.NotFound { os.exit(36i32) }
    if os.dlclose(library) != ok { os.exit(37i32) }

    // --- A name nothing will load is `NotFound` rather than a handle that is zero.
    let (missing, missing_error) = os.dlopen(a, "np-no-such-library-here.so")
    if missing_error == ok { os.exit(20i32) }
    if missing.raw != 0usize { os.exit(21i32) }

    // --- An empty name is not a library name.
    let (empty, empty_error) = os.dlopen(a, "")
    if empty_error != os.NotFound { os.exit(22i32) }
    ret ok
}
