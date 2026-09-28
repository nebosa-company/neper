// The extern's owner. The foreign function ignores its arguments: `ident` is never zero.
@import("kernel32", "GetCurrentProcessId")
extern fn ident(tag: i32, ...) -> u32
