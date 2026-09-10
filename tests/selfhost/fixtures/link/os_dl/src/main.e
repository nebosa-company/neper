// `e.os`'s loader -- `dlopen`, `dlsym`, `dlclose` -- and the error detail pair, which are here
// because both reach the host for something a table could not keep in step with.
//
// The library each host opens is the one it already depends on and is therefore certain to be
// there -- `kernel32.dll` on Windows, `libc.so.6` on Linux -- so nothing here needs anything
// installed. The name is passed through as `@import` takes it, which is why it differs per host
// and why `os.NATIVE_SEPARATOR` is what tells them apart.

use e.mem
use e.os

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

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

    // --- `last_error_detail` reports the code of the call that just failed, which is what makes
    // it more than the portable `err`: two failures can classify the same and carry different
    // codes. A failing syscall is what it is asked about, because that is the path both hosts
    // record on -- `dlopen` answers `NotFound` from its own handle check on one of them and never
    // reaches the classifier, so it would report whatever failed before it.
    let (missing_info, missing_info_error) = os.stat(a, "np-no-such-file-anywhere")
    if missing_info_error != os.NotFound { os.exit(50i32) }
    let detail = os.last_error_detail("stat", "np-no-such-file-anywhere")
    // The strings are the caller's own, borrowed rather than copied.
    if !same(detail.operation, "stat") { os.exit(51i32) }
    if !same(detail.subject, "np-no-such-file-anywhere") { os.exit(52i32) }
    // Zero would mean nothing was recorded, which is the whole failure this exists to avoid.
    if detail.native_code == 0i32 { os.exit(53i32) }
    if detail.kind != .NotFound { os.exit(54i32) }
    // The message for that code renders, which is the pair working together.
    let (detail_text, detail_text_error) = os.error_message(a, detail)
    if detail_text_error != ok { os.exit(55i32) }
    if detail_text.len == 0usize { os.exit(56i32) }
    // A later failure of a different kind replaces it: this is the last error, not the first.
    if os.mkdir(a, "") == ok { os.exit(57i32) }
    let later_detail = os.last_error_detail("mkdir", "")
    if later_detail.native_code == 0i32 { os.exit(58i32) }

    // --- `error_message` renders a native code. The code is the caller's, carried in the detail,
    // so this needs no ambient state and says nothing about what failed last.
    var built: os.ErrorDetail = zero
    built.kind = .NotFound
    built.operation = "open"
    built.subject = "np-nothing"
    // The code for a missing file on each host: ERROR_FILE_NOT_FOUND, and ENOENT.
    built.native_code = 2i32
    let (message, message_error) = os.error_message(a, built)
    if message_error != ok { os.exit(40i32) }
    if message.len == 0usize { os.exit(41i32) }
    // Whatever the wording and locale, it is one line: the trailing period and newline the system
    // appends belong to a display, not to the message.
    var at = 0usize
    while at < message.len {
        if message[at] == 10u8 { os.exit(42i32) }
        if message[at] == 13u8 { os.exit(43i32) }
        at += 1usize
    }
    // A different code gives a different message, which is what says the code is read at all.
    var other: os.ErrorDetail = zero
    other.native_code = 13i32
    let (second_message, second_message_error) = os.error_message(a, other)
    if second_message_error != ok { os.exit(44i32) }
    if second_message.len == 0usize { os.exit(45i32) }
    if second_message.len == message.len {
        var same_text = true
        var scan = 0usize
        while scan < message.len {
            if message[scan] != second_message[scan] { same_text = false }
            scan += 1usize
        }
        if same_text { os.exit(46i32) }
    }
    ret ok
}
