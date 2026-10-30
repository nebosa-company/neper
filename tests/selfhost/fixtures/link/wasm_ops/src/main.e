// The rest of NIR on the WebAssembly target (C181, D5213): floats of both widths (arithmetic,
// the six comparisons under IEEE, `sqrt`, negation, conversions in both directions and
// between the widths, section 11's canonical NaN), function values called through the table,
// the five atomics, and section 4's lane-wise operators over simd128. Each group prints the
// number of checks that failed; the program exits 0 on x64 and on wasm32-wasi alike, and the
// sweep (scripts/wasm-sweep.sh) compares the two byte for byte. With an argument it runs one
// check that must trap -- `narrow` (a float outside an integer's range), `shift` (a packed
// shift by a count past the lane) or `null` (a call through a zero function value).
use e.atomic
use e.math
use e.mem
use e.os
use e.simd

error Broken

type Op = struct { run: fn(i64, i64) -> i64, tag: i64 }
type Gauge = struct { hits: Atomic[u64], small: Atomic[i8], mid: Atomic[u16], word: Atomic[i32] }

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn digit_line(label: str, value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    if rest == 0usize {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest != 0usize {
        at -= 1usize
        digits[at] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
    }
    say(label)
    say(" ")
    let (shown, shown_error) = os.write(os.stdout(), digits[at..20usize])
    say("\n")
}

fn add(a: i64, b: i64) -> i64 { ret a + b }
fn sub(a: i64, b: i64) -> i64 { ret a - b }
fn mul(a: i64, b: i64) -> i64 { ret a * b }

fn apply(f: fn(i64, i64) -> i64, a: i64, b: i64) -> i64 { ret f(a, b) }

fn divmod(a: i64, b: i64) -> (i64, i64) { ret (a / b, a % b) }

fn pair_of(f: fn(i64, i64) -> (i64, i64), a: i64, b: i64) -> i64 {
    let (q, r) = f(a, b)
    ret q * 10i64 + r
}

fn scale(v: f32, by: f32) -> f32 { ret v * by }

fn apply_float(f: fn(f32, f32) -> f32, a: f32, b: f32) -> f32 { ret f(a, b) }

fn floats() -> usize {
    var failed = 0usize
    let one = 1.0f64
    let two = 2.0f64
    let nan = 0.0f64 / 0.0f64
    let infinity = 1.0f64 / 0.0f64
    if 1.5f64 + 2.25f64 != 3.75f64 || 10.0f64 / 4.0f64 != 2.5f64 || 3.0f64 * -0.5f64 != -1.5f64 || 5.5f64 - 0.5f64 != 5.0f64 { failed += 1usize }
    if 1.5f32 + 0.25f32 != 1.75f32 || 7.0f32 / 2.0f32 != 3.5f32 || scale(6.0f32, 7.0f32) != 42.0f32 || 9.0f32 - 10.0f32 != -1.0f32 { failed += 1usize }
    if -one != 0.0f64 - 1.0f64 || math.sqrt[f64](2.25f64) != 1.5f64 || math.sqrt[f32](16.0f32) != 4.0f32 { failed += 1usize }
    if !(one < two) || !(one <= two) || !(two > one) || !(two >= one) || !(one == one) || one != one { failed += 1usize }
    if nan == nan || nan < one || nan <= one || nan > one || nan >= one || !(nan != nan) { failed += 1usize }
    if !(infinity > 1.7976931348623157e308f64) || !(-infinity < -1.7976931348623157e308f64) { failed += 1usize }
    if !(1.0f32 < 2.0f32) || !(2.0f32 >= 2.0f32) || 0.0f32 / 0.0f32 == 0.0f32 / 0.0f32 { failed += 1usize }
    if i64(7.9f64) != 7i64 || i64(-7.9f64) != -7i64 || i32(-300.7f64) != -300i32 || u32(300.7f64) != 300u32 || u8(200.5f32) != 200u8 || i8(-100.25f32) != -100i8 { failed += 1usize }
    if f64(3i64) + f64(4i64) != 7.0f64 || f32(-5i8) != -5.0f32 || f64(250u8) != 250.0f64 || f32(65535u16) != 65535.0f32 || f64(-70000i32) != -70000.0f64 { failed += 1usize }
    if f64(18446744073709551615u64) != 18446744073709551616.0f64 || f64(9223372036854775809u64) != 9223372036854775808.0f64 || f32(18446744073709551615u64) != 18446744073709551616.0f32 { failed += 1usize }
    if u64(9223372036854775808.0f64) != 9223372036854775808u64 || u64(18446744073709549568.0f64) != 18446744073709549568u64 || usize(f64(5usize)) != 5usize { failed += 1usize }
    if f64(1.5f32) != 1.5f64 || f32(0.1f64) != 0.1f32 || f64(0.1f32) == 0.1f64 { failed += 1usize }
    let canonical = 9221120237041090560u64
    if mem.bitcast[u64](nan) != canonical || mem.bitcast[u64](infinity - infinity) != canonical || mem.bitcast[u64](-nan) != canonical { failed += 1usize }
    if mem.bitcast[u64](-0.0f64) != 9223372036854775808u64 || mem.bitcast[u64](infinity) != 9218868437227405312u64 { failed += 1usize }
    let narrow_nan = 0.0f32 / 0.0f32
    if mem.bitcast[u32](narrow_nan) != 2143289344u32 || mem.bitcast[u32](-narrow_nan) != 2143289344u32 { failed += 1usize }
    if mem.bitcast[u64](f64(narrow_nan)) != canonical || mem.bitcast[u32](f32(nan)) != 2143289344u32 { failed += 1usize }
    let payload = mem.bitcast[f64](9221120237041090561u64)
    if mem.bitcast[u64](payload + one) != canonical || mem.bitcast[u64](math.sqrt[f64](-one)) != canonical { failed += 1usize }
    var held: [3]f64 = zero
    held[1usize] = 2.5f64
    held[2usize] = held[1usize] * held[1usize]
    if held[0usize] != 0.0f64 || held[2usize] != 6.25f64 { failed += 1usize }
    ret failed
}

fn function_values() -> usize {
    var failed = 0usize
    if apply(add, 2i64, 3i64) != 5i64 || apply(sub, 9i64, 4i64) != 5i64 || apply(mul, 6i64, 7i64) != 42i64 { failed += 1usize }
    var chosen = add
    if chosen(10i64, 1i64) != 11i64 { failed += 1usize }
    chosen = sub
    if chosen(10i64, 1i64) != 9i64 { failed += 1usize }
    let table = [3]Op{ Op { run: add, tag: 1i64 }, Op { run: sub, tag: 2i64 }, Op { run: mul, tag: 3i64 } }
    var total = 0i64
    var at = 0usize
    while at < table.len {
        total += table[at].run(8i64, 3i64) * table[at].tag
        at += 1usize
    }
    if total != 11i64 + 10i64 + 72i64 { failed += 1usize }
    if pair_of(divmod, 47i64, 5i64) != 92i64 { failed += 1usize }
    if apply_float(scale, 1.5f32, 4.0f32) != 6.0f32 { failed += 1usize }
    ret failed
}

fn atomics() -> usize {
    var failed = 0usize
    var g: Gauge = zero
    if atomic.add(&g.hits, 5u64, .Relaxed) != 0u64 || atomic.add(&g.hits, 7u64, .Relaxed) != 5u64 || atomic.load(&g.hits, .Acquire) != 12u64 { failed += 1usize }
    if atomic.sub(&g.hits, 2u64, .Relaxed) != 12u64 || atomic.xchg(&g.hits, 9u64, .AcqRel) != 10u64 { failed += 1usize }
    atomic.store(&g.hits, 12u64, .Release)
    if atomic.or(&g.hits, 3u64, .Relaxed) != 12u64 || atomic.and(&g.hits, 6u64, .Relaxed) != 15u64 || atomic.xor(&g.hits, 5u64, .Relaxed) != 6u64 { failed += 1usize }
    if atomic.min(&g.hits, 9u64, .Relaxed) != 3u64 || atomic.max(&g.hits, 9u64, .Relaxed) != 3u64 || atomic.load(&g.hits, .Relaxed) != 9u64 { failed += 1usize }
    let (won, seen) = atomic.cas(&g.hits, 9u64, 42u64, .AcqRel, .Acquire)
    let (lost, found) = atomic.cas(&g.hits, 9u64, 7u64, .AcqRel, .Acquire)
    if !won || seen != 9u64 || lost || found != 42u64 || atomic.load(&g.hits, .Relaxed) != 42u64 { failed += 1usize }
    atomic.store(&g.small, -5i8, .Relaxed)
    if atomic.min(&g.small, 3i8, .Relaxed) != -5i8 || atomic.max(&g.small, 3i8, .Relaxed) != -5i8 || atomic.load(&g.small, .Relaxed) != 3i8 { failed += 1usize }
    if atomic.add(&g.small, 127i8, .Relaxed) != 3i8 { failed += 1usize }
    atomic.store(&g.mid, 65535u16, .Relaxed)
    if atomic.add(&g.mid, 2u16, .Relaxed) != 65535u16 || atomic.load(&g.mid, .Relaxed) != 1u16 { failed += 1usize }
    atomic.store(&g.word, -7i32, .Relaxed)
    if atomic.add(&g.word, 10i32, .Relaxed) != -7i32 || atomic.min(&g.word, -1i32, .Relaxed) != 3i32 || atomic.load(&g.word, .Relaxed) != -1i32 { failed += 1usize }
    if atomic.load(&g.hits, .Relaxed) != 42u64 { failed += 1usize }
    atomic.fence(.SeqCst)
    ret failed
}

fn vectors() -> usize {
    var failed = 0usize
    let a = simd.splat[Vec[f32, 4]](1.5)
    let b = simd.splat[Vec[f32, 4]](2.0)
    let c = a * b + a
    let d = (c - b) / b
    if c.lanes[0] != 4.5 || c.lanes[3] != 4.5 || d.lanes[2] != 1.25 { failed += 1usize }
    var x: Vec[i32, 4] = zero
    x.lanes[0] = 2147483647i32
    x.lanes[1] = 6i32
    let y = simd.splat[Vec[i32, 4]](1i32)
    let w = x +% y
    let m = (x *% y) -% y
    let bits = (x & y) | (y ^ y)
    if w.lanes[0] != -2147483648i32 || w.lanes[1] != 7i32 || m.lanes[1] != 5i32 || bits.lanes[0] != 1i32 || bits.lanes[1] != 0i32 { failed += 1usize }
    let sh = y << 3u32
    let back = sh >> 2u32
    let inv = ~y
    if sh.lanes[3] != 8i32 || back.lanes[3] != 2i32 || inv.lanes[0] != -2i32 { failed += 1usize }
    let flipped = ~Vec[u8, 16]{ 0u8, 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8 }
    if flipped[0] != 255u8 || flipped[7] != 248u8 || flipped[15] != 240u8 { failed += 1usize }
    let bytes = Vec[u8, 16]{ 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8, 200u8 }
    let product = bytes *% bytes
    let sums = bytes +% bytes
    let diff = bytes -% Vec[u8, 16]{ 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8 }
    if product[0] != 1u8 || product[8] != 81u8 || product[15] != 64u8 || sums[15] != 144u8 || diff[0] != 255u8 || diff[2] != 1u8 { failed += 1usize }
    let wide = Vec[i16, 8]{ 1i16, -2i16, 3i16, -4i16, 5i16, -6i16, 7i16, -32768i16 }
    let wide_left = wide << 2u32
    let wide_right = wide >> 1u32
    let unsigned = Vec[u16, 8]{ 65535u16, 1u16, 2u16, 3u16, 4u16, 5u16, 6u16, 32768u16 }
    let unsigned_right = unsigned >> 3u32
    if wide_left[0] != 4i16 || wide_left[7] != 0i16 || wide_right[1] != -1i16 || wide_right[6] != 3i16 || unsigned_right[0] != 8191u16 || unsigned_right[7] != 4096u16 { failed += 1usize }
    let quad = Vec[u64, 2]{ 18446744073709551615u64, 1u64 }
    let signed_quad = Vec[i64, 2]{ -16i64, 48i64 }
    if (quad >> 60u32)[0] != 15u64 || (quad << 63u32)[1] != 9223372036854775808u64 || (signed_quad >> 2u32)[0] != -4i64 || (signed_quad *% signed_quad)[1] != 2304i64 { failed += 1usize }
    let count = u32(x.lanes[1])
    let by_register = Vec[i32, 4]{ -1i32, 2i32, 3i32, 4i32 }
    if (by_register << count)[1] != 128i32 || (by_register >> count)[0] != -1i32 || (by_register >> count)[3] != 0i32 { failed += 1usize }
    if (wide << count)[0] != 64i16 || (unsigned >> count)[0] != 1023u16 { failed += 1usize }
    let doubles = Vec[f64, 2]{ 1.5, -2.0 }
    let dsum = doubles + doubles
    let dquot = doubles / Vec[f64, 2]{ 2.0, 4.0 }
    let dprod = doubles * doubles - doubles
    if dsum[0] != 3.0 || dsum[1] != -4.0 || dquot[0] != 0.75 || dquot[1] != -0.5 || dprod[0] != 0.75 || dprod[1] != 6.0 { failed += 1usize }
    var quiet = simd.splat[Vec[f32, 4]](1.0)
    quiet[2] = mem.bitcast[f32](4290772993u32)
    let cleaned = quiet - quiet
    if mem.bitcast[u32](cleaned[2]) != 2143289344u32 || cleaned[0] != 0.0 || cleaned[3] != 0.0 { failed += 1usize }
    var long = simd.splat[Vec[f32, 8]](1.5)
    long[0] = 0.5
    long[7] = 4.0
    let long_sum = long * simd.splat[Vec[f32, 8]](2.0) + long
    if long_sum[0] != 1.5 || long_sum[3] != 4.5 || long_sum[7] != 12.0 { failed += 1usize }
    let mask_not = ~Mask[i32, 4]{ true, false, true, false }
    if mask_not[0] || !mask_not[1] || mask_not[2] || !mask_not[3] { failed += 1usize }
    ret failed
}

fn trap_case(name: str, bump: f64) -> usize {
    var count = 40u32
    if name.len == 6usize && name[0usize] == 110u8 {
        ret usize(u8(bump * 100.0f64))
    }
    if name.len == 5usize && name[0usize] == 115u8 {
        let lanes = Vec[i32, 4]{ 1i32, 2i32, 3i32, 4i32 }
        ret usize((lanes << count)[1])
    }
    if name.len == 4usize && name[0usize] == 110u8 {
        var empty: Op = zero
        ret usize(empty.run(1i64, 2i64))
    }
    ret 0usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let trapped = trap_case(args[1usize], 3.0f64)
        ret ok
    }
    say("wasm_ops\n")
    let float_failed = floats()
    digit_line("floats", float_failed)
    let value_failed = function_values()
    digit_line("function values", value_failed)
    let atomic_failed = atomics()
    digit_line("atomics", atomic_failed)
    let vector_failed = vectors()
    digit_line("vectors", vector_failed)
    if float_failed + value_failed + atomic_failed + vector_failed != 0usize { ret Broken }
    say("ok\n")
    ret ok
}
