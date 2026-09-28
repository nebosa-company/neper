// The externs' owner, which never calls them: which module's artifact names the
// library is what the fixture is about. Each foreign function ignores its arguments
// and answers a constant: a structural `cmp` of two equal points is 0, where this one
// is -1, and a structural `hash` tells -7 from 7, where this one hashes every key alike.
type Point = struct { x: i64 }
type Key = struct { k: i64 }

// The pseudo-handle -1.
@import("kernel32", "GetCurrentProcess")
extern fn point_cmp(a: Point, b: Point) -> i32

// The pseudo-handle -2.
@import("kernel32", "GetCurrentThread")
extern fn key_hash(k: Key) -> u64
