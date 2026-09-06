// examples/sample.e — every construct in the language, once, in one program.
//
//   neper run  examples/sample.e -- 12.5 41.25 38.0 45.5
//   neper test examples/sample.e
//
// Not a tutorial. A checklist: each block names the spec section that defines it.

use e.mem
use e.io
use e.str
use e.math
use e.simd
use e.meta
use algo.sort
use e.data.map
use e.time
use e.thread
use e.atomic
use e.gpu
use e.test

// ---- §5 declarations: const, error, module-scope var, type alias ----

const MAX_SENSORS: usize = 1024
const WARN_ABOVE: f32 = 40.0

error BadArgument
error NoReadings

type Celsius = f32 // an alias, not a distinct type (D48)

var g_parsed: Atomic[u64] = atomic.init(0u64)

// ---- §4 types: struct, enum, tagged union, bare union, attributes ----

type Sensor = struct {
    id:   u32,
    site: str,
    temp: Celsius,
}

type Kind = enum u8 {
    Temp,
    Humidity,
    Pressure,
}

type Reading = union enum u8 { // the variant type: tag-checked (§4)
    Temp:     f32,
    Humidity: u8,
    Pressure: u32,
    Missing,
}

@packed
type Wire = struct { // no padding: a binary protocol header
    magic: u32,
    count: u16,
    kind:  Kind,
}

@align(64)
type Line = struct { // one cache line, for the SIMD path
    values: [16]f32,
}

type Raw = union { // bare union: C layout only (D49)
    bits:  u32,
    value: f32,
}

type Reducer = fn(f32, f32) -> f32 // function pointer: CPU profile only (§5)

// ---- §5 extern: the C ABI, one symbol from libc and one function exported back ----

@import("c", "llabs")
@cc(c)
extern fn c_llabs(v: i64) -> i64

// @cc on a plain fn makes it C-callable under the extern signature rule (§5), and
// that boundary is what a bare union is for: a union crosses by value, a union enum
// does not (D49).
@cc(c)
fn raw_bits(r: Raw) -> u32 {
    ret r.bits
}

// ---- §9 protocols: found by name in this module at compile time (D52) ----

fn sensor_hash(v: Sensor) -> u64 {
    var h: u64 = 14695981039346656037 // FNV-1a, and `*%` never traps (§6)
    h = (h ^ u64(v.id)) *% 1099511628211
    for c in v.site {
        h = (h ^ u64(c)) *% 1099511628211
    }
    ret h
}

fn sensor_eq(a: Sensor, b: Sensor) -> bool {
    ret a.id == b.id && str.eq(a.site, b.site) // never `==` on a slice (§6)
}

fn sensor_cmp(a: Sensor, b: Sensor) -> i32 {
    if a.temp < b.temp { ret -1i32 }
    if a.temp > b.temp { ret 1i32 }
    ret 0i32
}

fn sensor_format(v: Sensor, b: *str.Builder) -> err {
    try str.push(b, v.site)
    try str.push(b, "#")
    try str.push_u32(b, v.id)
    ret ok
}

// ---- §6 + §9: the iteration protocol; `for` calls `window_next` ----

type Window = struct {
    data: []const f32,
    i:    usize,
    n:    usize,
}

fn window_next(it: *Window) -> (f32, bool) {
    if it.i + it.n > it.data.len {
        ret (0.0, false)
    }
    var s: f32 = 0.0
    for v in it.data[it.i..it.i+it.n] {
        s = s + v
    }
    it.i += 1
    ret (s / f32(it.n), true)
}

// ---- §9 introspection: one function that prints any struct (D53) ----

fn dump[T: type](v: *const T, b: *str.Builder) -> err {
    try str.push(b, meta.type_name[T]())
    try str.push(b, "{ ")
    for f in meta.fields[T]() { // unrolled by the interpreter
        try str.push(b, f.name)
        try str.push(b, "=")
        try f.ty.format(meta.get[f, T](v), b)
        try str.push(b, " ")
    }
    try str.push(b, "}")
    ret ok
}

// ---- §4 Vec and Mask: explicit SIMD, no auto-vectoriser (D40) ----

fn sum_above[N: usize](xs: []const f32, limit: f32) -> f32 {
    let zeros = simd.splat[Vec[f32, N]](0.0)
    var acc = zeros
    let lim = simd.splat[Vec[f32, N]](limit)
    var i: usize = 0
    while i + N <= xs.len {
        let v = simd.load[Vec[f32, N]](xs, i)
        let m = simd.cmp_gt(v, lim) // Mask[f32, N], register-only
        acc = acc + simd.select(m, v, zeros)
        i += N
    }
    var total = simd.reduce_add(acc) // fixed tree: bit-identical
    for j in i..xs.len { // the tail, scalar
        if xs[j] > limit {
            total = total + xs[j]
        }
    }
    ret total
}

// ---- §6 control flow: while, break, continue, and a discarded return ----

fn first_above(xs: []const f32, limit: f32) -> (usize, bool) {
    var i: usize = 0
    while i < xs.len {
        if xs[i] < 0.0 {
            i += 1
            continue // a reading below absolute zero: skip
        }
        if xs[i] > limit {
            break
        }
        i += 1
    }
    ret (i, i < xs.len)
}

// ---- §4 + §6: exhaustive switch over a tagged union, payload bound with `as` ----

fn describe(r: Reading, b: *str.Builder) -> err {
    switch r {
    case .Temp as t:
        try str.push(b, "temp ")
        try str.push_f32(b, t)
    case .Humidity as h:
        try str.push(b, "humidity ")
        try str.push_u32(b, u32(h))
    case .Pressure as p:
        try str.push(b, "pressure ")
        try str.push_u32(b, p)
    case .Missing:
        try str.push(b, "missing")
    }
    ret ok
}

fn kind_name(k: Kind) -> str {
    switch k {
    case .Temp:
        ret "temp"
    case .Humidity:
        ret "humidity"
    case .Pressure:
        ret "pressure"
    }
    unreachable() // exhaustive above; §11
}

// ---- §6 `when`: both branches type-check, one is emitted ----

fn platform() -> str {
    when target.os == .Windows {
        ret "windows"
    } else {
        ret "posix"
    }
}

// ---- §8 threads and atomics: OS threads, an explicit context, no scheduler ----

type Job = struct {
    xs:  []const f32,
    out: f32,
}

fn worker(j: *Job) {
    var s: f32 = 0.0
    for v in j.xs {
        s = s + v
    }
    j.out = s
}

fn parallel_sum(xs: []const f32) -> (f32, err) {
    let half = xs.len / 2
    var left  = Job{ xs: xs[0..half],      out: 0.0 }
    var right = Job{ xs: xs[half..xs.len], out: 0.0 }
    let h = try thread.spawn[Job](worker, &left, thread.DEFAULT_STACK)
    worker(&right) // this thread takes the other half
    try thread.join(h)
    ret (left.out + right.out, ok)
}

// ---- §10 GPU: one source, device and CPU; the CPU build is the debugger ----

@gpu(256)
fn scale(n: u32, k: f32, xs: []f32) {
    let i = gpu.gid.x // u32
    if i >= n { // the grid rounds up to whole workgroups
        ret
    }
    let j = usize(i) // indices are usize; no implicit widening
    xs[j] = xs[j] * k // a multiply, never fused (§11)
}

fn run_on_device(a: *mem.Arena, xs: []f32, k: f32) -> err {
    let dev = try gpu.open(a, .Cpu, 0) // .Cpu always exists at index 0
    defer gpu.close(dev)
    let q = try gpu.queue(dev)
    let dx = try gpu.upload[f32](q, xs)
    defer gpu.release(q, dx) // queued in order behind the launch
    try gpu.launch[scale](q, gpu.grid1(xs.len), u32(xs.len), k, dx)
    try gpu.download[f32](q, dx, xs) // waits, then copies back
    ret ok
}

// ---- higher-order over a function pointer ----

fn add_f32(x: f32, y: f32) -> f32 {
    ret x + y
}

fn fold(xs: []const f32, seed: f32, r: Reducer) -> f32 {
    var acc = seed
    for v in xs {
        acc = r(acc, v)
    }
    ret acc
}

// ---- §11 `@nocheck`: the one hot loop that opts out in debug ----

fn hot_sum(xs: []const f32) -> f32 {
    var s: f32 = 0.0
    @nocheck {
        for i in 0usize..xs.len {
            s = s + xs[i]
        }
    }
    ret s
}

// ---- parsing: multiple returns, destructuring, an arena ----

fn parse_sensors(a: *mem.Arena, readings: []str) -> ([]Sensor, err) {
    if readings.len == 0 { // the caller passes args[1..] (§13)
        ret (nil, NoReadings) // `nil` is the empty slice too (§4)
    }
    if readings.len > MAX_SENSORS {
        ret (nil, BadArgument)
    }
    let out = try mem.alloc[Sensor](a, readings.len)
    for i, s in readings {
        let (t, e) = str.parse_f32(s) // handled, not propagated
        if e != ok {
            ret (nil, BadArgument)
        }
        out[i] = Sensor{ id: u32(i), site: "cli", temp: t }
        let _ = atomic.add(&g_parsed, 1u64, .Relaxed) // every return is bound (§5)
    }
    ret (out, ok)
}

// ---- §13 entry point: the root arena and the arguments arrive as parameters ----

fn main(a: *mem.Arena, args: []str) -> err {
    let t0 = try time.monotonic()
    let m = mem.mark(a)
    defer mem.reset(a, m) // everything below is freed at once

    if args.len <= 1 { // args[0] is the program as invoked (§13)
        try io.print("usage: sample <temp>...\n")
        ret ok
    }

    let (sensors, e) = parse_sensors(a, args[1..])
    if e != ok {
        ret e // main maps a non-ok err to exit 1
    }

    sort.in_place[Sensor](sensors) // uses sensor_cmp; `in_place` says it mutates

    var seen = try map.make[Sensor, u32](a, 64)
    for sensor in sensors {
        try map.put[Sensor, u32](&seen, sensor, sensor.id) // sensor_hash, sensor_eq
    }

    var temps = try mem.alloc[f32](a, sensors.len)
    for i, s in sensors {
        temps[i] = s.temp
    }

    let hot = sum_above[8](temps, WARN_ABOVE)
    let total = try parallel_sum(temps)
    let folded = fold(temps, 0.0, add_f32)
    let plain = hot_sum(temps)
    let peak = math.max(hot, plain) // e.math, comptime-generic over the float
    let (idx, found) = first_above(temps, WARN_ABOVE)

    try run_on_device(a, temps, 2.0) // doubles every reading in place

    // §4 casts and bit-level access: every conversion is written down.
    let first_bits = mem.bitcast[u32](temps[0])
    let narrow = f16(temps[0])
    let magnitude = c_llabs(-42i64)
    let warn_bits = raw_bits(Raw{ value: WARN_ABOVE }) // through the C boundary

    // @packed, so the header is its seven bytes with nothing between them.
    let header = Wire{ magic: 0x4E455045, count: u16(sensors.len), kind: .Temp }
    let wire_bytes = mem.bitcast[[7]u8](header)

    var scratch: [64]u8 = undef // no store; poisoned in debug
    var counts: [4]u32 = zero // memset, visible on the page
    counts[usize(u8(Kind.Temp))] = u32(sensors.len) // enum to a wider int: two casts

    var b = try str.builder(a, 512)
    try dump[Sensor](&sensors[0], &b)
    try str.push(&b, " | ")
    try describe(Reading{ Temp: sensors[0].temp }, &b)

    try io.printf["{} on {}\n"](str.done(&b), platform())
    try io.printf["{} sensors, {} parsed, {} bytes each\n"](
        sensors.len,
        atomic.load(&g_parsed, .Acquire),
        mem.size_of[Sensor]())
    try io.printf["sum {} above {} = {}, total {}, folded {}, plain {}, peak {}\n"](
        kind_name(.Temp),
        WARN_ABOVE,
        hot,
        total,
        folded,
        plain,
        peak)
    try io.printf["first over limit: index {} present {}\n"](idx, found)
    try io.printf["bits {x} warn {x} as f16 {} llabs {}\n"](
        first_bits,
        warn_bits,
        narrow,
        magnitude)
    try io.printf["line is {} bytes, wire byte {x}, scratch {}\n"](
        mem.size_of[Line](),
        wire_bytes[0],
        scratch.len)

    switch sensors.len {
    case 1:
        try io.print("one reading\n")
    case 2, 3:
        try io.print("a couple of readings\n")
    default:
        try io.print("a batch\n")
    }

    try io.printf["took {}us\n"](time.as_micros(time.since(t0)))
    ret ok
}

// ---- §13 tests: discovered by the compiler, one fresh arena each ----

@test
fn cmp_orders_by_temperature(a: *mem.Arena) -> err {
    let lo = Sensor{ id: 1, site: "a", temp: 10.0 }
    let hi = Sensor{ id: 2, site: "b", temp: 20.0 }
    try test.assert(sensor_cmp(lo, hi) < 0i32, "lo sorts before hi")
    try test.assert(sensor_cmp(hi, hi) == 0i32, "equal temperatures tie")
    ret ok
}

@test
fn window_walks_in_pairs(a: *mem.Arena) -> err {
    let xs = [_]f32{ 1.0, 2.0, 3.0, 4.0 }
    var w = Window{ data: xs[0..], i: 0, n: 2 }
    var first: f32 = 0.0
    var seen: usize = 0
    for avg in w { // window_next, found by name
        if seen == 0 {
            first = avg
        }
        seen += 1
    }
    try test.eq[usize](seen, 3, "three windows of two across four points")
    try test.near(f64(first), 1.5, 1e-6, 0.0, "first window averages 1 and 2")
    ret ok
}

@test
fn simd_and_scalar_agree(a: *mem.Arena) -> err {
    let xs = [_]f32{ 5.0, 50.0, 41.0, 39.0, 60.0, 1.0, 44.0, 43.0 }
    let wide = sum_above[8](xs[0..], WARN_ABOVE)
    var slow: f32 = 0.0
    for v in xs {
        if v > WARN_ABOVE {
            slow = slow + v
        }
    }
    try test.near(f64(wide), f64(slow), 1e-6, 0.0, "vector path matches the scalar one")
    ret ok
}
