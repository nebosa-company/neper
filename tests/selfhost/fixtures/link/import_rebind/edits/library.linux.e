// The externs' owner. Each foreign function ignores its arguments and answers the same
// for every call: `ident` is never zero, and `key_hash` hashes every key alike.
type Key = struct { k: i64 }

// The process's identifier. libpthread.so.0 exports neither function; it needs
// libc.so.6, and the loader finds an undefined global in any library it loaded.
@import("libpthread.so.0", "getpid")
extern fn ident() -> u32

// The calling thread's identifier, likewise.
@import("libpthread.so.0", "pthread_self")
extern fn key_hash(k: Key) -> u64
