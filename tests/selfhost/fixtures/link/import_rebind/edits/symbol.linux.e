// The externs' owner. Each foreign function ignores its arguments and answers the same
// for every call: `ident` is never zero, and `key_hash` hashes every key alike.
type Key = struct { k: i64 }

// The parent process's identifier, found through libpthread.so.0's libc.so.6.
@import("libpthread.so.0", "getppid")
extern fn ident() -> u32

// The page size, likewise.
@import("libpthread.so.0", "getpagesize")
extern fn key_hash(k: Key) -> u64
