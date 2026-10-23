// The externs' owner, which never calls them: which module's artifact names the
// library is what the fixture is about. Each foreign function ignores its arguments
// and answers a constant: a structural `cmp` of two equal points is 0, where this one
// is 4096, and a structural `hash` tells -7 from 7, where this one hashes every key alike.
type Point = struct { x: i64 }
type Key = struct { k: i64 }

// The page size.
@import("libc.so.6", "getpagesize")
extern fn point_cmp(a: Point, b: Point) -> i32

// The calling thread's identifier.
@import("libc.so.6", "pthread_self")
extern fn key_hash(k: Key) -> u64
