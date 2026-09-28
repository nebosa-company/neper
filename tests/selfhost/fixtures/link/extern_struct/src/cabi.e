// The layouts of cabi.c, and its functions. The suite builds cabi.c as a library named
// `nepercabi`: PE's loader adds `.dll`, and ELF's takes `DT_NEEDED` verbatim, so on
// Linux the file is `nepercabi` itself, found through LD_LIBRARY_PATH.
//
// Each size and class is here once (D1675). Win64 passes 1, 2, 4 and 8 bytes as their
// bits and anything else as a copy's address; System V classifies up to sixteen bytes
// into INTEGER and SSE eightbytes and puts anything larger, or unaligned, on the stack.
type Byte = struct { a: u8 }
type Short = struct { a: i16 }
type Triple = struct { a: u8, b: u8, c: u8 }
type Single = struct { a: f32 }
type Pair = struct { x: i32, y: i32 }
type Floats = struct { x: f32, y: f32 }
type Longs = struct { a: i64, b: i64 }
type DoubleInt = struct { d: f64, i: i64 }
type IntDouble = struct { i: i64, d: f64 }
type Doubles = struct { x: f64, y: f64 }
type ThreeFloats = struct { a: f32, b: f32, c: f32 }
type Nest = struct { p: Pair, f: [2]f32 }
type Num = union { i: i64, d: f64 }
type Big = struct { a: i64, b: i64, c: i64 }
@packed
type Packed = struct { tag: u8, value: i32 }
type Key = struct { k: i64 }

@import("nepercabi", "byte_in")
extern fn byte_in(s: Byte) -> i64
@import("nepercabi", "short_in")
extern fn short_in(s: Short) -> i64
@import("nepercabi", "triple_in")
extern fn triple_in(s: Triple) -> i64
@import("nepercabi", "single_in")
extern fn single_in(s: Single) -> f64
@import("nepercabi", "pair_in")
extern fn pair_in(s: Pair) -> i64
@import("nepercabi", "floats_in")
extern fn floats_in(s: Floats) -> f64
@import("nepercabi", "longs_in")
extern fn longs_in(s: Longs) -> i64
@import("nepercabi", "double_int_in")
extern fn double_int_in(s: DoubleInt) -> f64
@import("nepercabi", "int_double_in")
extern fn int_double_in(s: IntDouble) -> f64
@import("nepercabi", "doubles_in")
extern fn doubles_in(s: Doubles) -> f64
@import("nepercabi", "three_floats_in")
extern fn three_floats_in(s: ThreeFloats) -> f64
@import("nepercabi", "nest_in")
extern fn nest_in(s: Nest) -> f64
@import("nepercabi", "num_in")
extern fn num_in(s: Num) -> i64
@import("nepercabi", "big_in")
extern fn big_in(s: Big) -> i64
@import("nepercabi", "packed_in")
extern fn packed_in(s: Packed) -> i64
@import("nepercabi", "big_then")
extern fn big_then(s: Big, x: i64) -> i64
@import("nepercabi", "crowd")
extern fn crowd(a: i64, b: i64, c: i64, d: i64, e: i64, s: Longs, f: i64) -> i64
@import("nepercabi", "crowd_sse")
extern fn crowd_sse(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, s: Doubles, h: f64) -> f64
@import("nepercabi", "sum_longs")
extern fn sum_longs(n: i32, ...) -> i64

@import("nepercabi", "byte_out")
extern fn byte_out(a: u8) -> Byte
@import("nepercabi", "short_out")
extern fn short_out(a: i16) -> Short
@import("nepercabi", "triple_out")
extern fn triple_out(a: u8, b: u8, c: u8) -> Triple
@import("nepercabi", "single_out")
extern fn single_out(a: f32) -> Single
@import("nepercabi", "pair_out")
extern fn pair_out(x: i32, y: i32) -> Pair
@import("nepercabi", "floats_out")
extern fn floats_out(x: f32, y: f32) -> Floats
@import("nepercabi", "longs_out")
extern fn longs_out(a: i64, b: i64) -> Longs
@import("nepercabi", "double_int_out")
extern fn double_int_out(d: f64, i: i64) -> DoubleInt
@import("nepercabi", "int_double_out")
extern fn int_double_out(i: i64, d: f64) -> IntDouble
@import("nepercabi", "doubles_out")
extern fn doubles_out(x: f64, y: f64) -> Doubles
@import("nepercabi", "three_floats_out")
extern fn three_floats_out(a: f32, b: f32, c: f32) -> ThreeFloats
@import("nepercabi", "nest_out")
extern fn nest_out(x: i32, y: i32, f0: f32, f1: f32) -> Nest
@import("nepercabi", "num_out")
extern fn num_out(d: f64) -> Num
@import("nepercabi", "big_out")
extern fn big_out(a: i64, b: i64, c: i64) -> Big
@import("nepercabi", "packed_out")
extern fn packed_out(tag: u8, value: i32) -> Packed
@import("nepercabi", "doubles_swap")
extern fn doubles_swap(s: Doubles) -> Doubles
@import("nepercabi", "big_rotate")
extern fn big_rotate(s: Big) -> Big

// The callee side (D1676): C calls a neper `@cc` function through these types, and hands
// out its own functions as them. The convention is the type's: `extern fn(...)`.
type PairBack = extern fn(Pair) -> i64
type ThreeBack = extern fn(ThreeFloats) -> f64
type MixedBack = extern fn(DoubleInt, IntDouble) -> f64
type BigBack = extern fn(Big, i64) -> i64
type PackedBack = extern fn(Packed) -> i64
type CrowdBack = extern fn(i64, i64, i64, i64, i64, Longs, i64) -> i64
type CrowdSseBack = extern fn(f64, f64, f64, f64, f64, f64, f64, Doubles, f64) -> f64
type ByteMaker = extern fn(u8) -> Byte
type PairMaker = extern fn(i32, i32) -> Pair
type LongsMaker = extern fn(i64, i64) -> Longs
type DoubleIntMaker = extern fn(f64, i64) -> DoubleInt
type IntDoubleMaker = extern fn(i64, f64) -> IntDouble
type ThreeMaker = extern fn(f32, f32, f32) -> ThreeFloats
type BigMaker = extern fn(i64, i64, i64) -> Big
type DoublesMap = extern fn(Doubles) -> Doubles
type BigMap = extern fn(Big) -> Big

@import("nepercabi", "call_pair")
extern fn call_pair(f: PairBack, x: i32, y: i32) -> i64
@import("nepercabi", "call_three")
extern fn call_three(f: ThreeBack, a: f32, b: f32, c: f32) -> f64
@import("nepercabi", "call_mixed")
extern fn call_mixed(f: MixedBack, d: f64, i: i64) -> f64
@import("nepercabi", "call_big")
extern fn call_big(f: BigBack, a: i64, b: i64, c: i64, x: i64) -> i64
@import("nepercabi", "call_packed")
extern fn call_packed(f: PackedBack, tag: u8, value: i32) -> i64
@import("nepercabi", "call_crowd")
extern fn call_crowd(f: CrowdBack) -> i64
@import("nepercabi", "call_crowd_sse")
extern fn call_crowd_sse(f: CrowdSseBack) -> f64
@import("nepercabi", "take_byte")
extern fn take_byte(f: ByteMaker, a: u8) -> i64
@import("nepercabi", "take_pair")
extern fn take_pair(f: PairMaker, x: i32, y: i32) -> i64
@import("nepercabi", "take_longs")
extern fn take_longs(f: LongsMaker, a: i64, b: i64) -> i64
@import("nepercabi", "take_double_int")
extern fn take_double_int(f: DoubleIntMaker, d: f64, i: i64) -> f64
@import("nepercabi", "take_int_double")
extern fn take_int_double(f: IntDoubleMaker, i: i64, d: f64) -> f64
@import("nepercabi", "take_three")
extern fn take_three(f: ThreeMaker, a: f32, b: f32, c: f32) -> f64
@import("nepercabi", "take_big")
extern fn take_big(f: BigMaker, a: i64, b: i64, c: i64) -> i64
@import("nepercabi", "map_doubles")
extern fn map_doubles(f: DoublesMap, s: Doubles) -> Doubles
@import("nepercabi", "pair_in_pointer")
extern fn pair_in_pointer() -> PairBack
@import("nepercabi", "big_rotate_pointer")
extern fn big_rotate_pointer() -> BigMap
@import("nepercabi", "double_int_out_pointer")
extern fn double_int_out_pointer() -> DoubleIntMaker

// Found by name as the key's own `cmp` and `hash`, so a supplied protocol over `[N]Key`
// calls them per element from lowering's protocol emitters, not from a call site.
@import("nepercabi", "key_cmp")
extern fn key_cmp(a: Key, b: Key) -> i32
@import("nepercabi", "key_hash")
extern fn key_hash(s: Key) -> u64
