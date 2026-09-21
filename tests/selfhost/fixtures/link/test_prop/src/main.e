// `e.test.prop`: generators stay in range over 1000 integer draws, 200
// byte strings, 100 choices and 100 lists and hash to the Python PCG
// replica's value; `shrink` takes a random failing `x > 100` to exactly
// 101, `x < -100` to -101, and a non-monotone predicate to the replica's
// answers; `shrink_bytes` takes a 20-byte list with an equal adjacent pair
// down to two bytes, and a "sum >= 300" list to the replica's result. Each
// check exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.os
use e.test.prop as prop

type Ctx = struct { threshold: i64, calls: usize }

fn mix(h: u64, v: u64) -> u64 { ret (h ^ v) *% 1099511628211u64 }
fn mix_int(h: u64, v: i64) -> u64 { ret mix(h, mem.bitcast[u64](v)) }

fn above(c: *Ctx, x: i64) -> bool {
    c.calls += 1usize
    ret x > c.threshold
}
fn below(c: *Ctx, x: i64) -> bool { ret x < 0i64 - c.threshold }
fn mod7(c: *Ctx, x: i64) -> bool { ret x > 50i64 && x % 7i64 == 3i64 }
fn adjacent(c: *Ctx, d: []const u8) -> bool {
    c.calls += 1usize
    var i = 1usize
    while i < d.len {
        if d[i] == d[i - 1usize] { ret true }
        i += 1usize
    }
    ret false
}
fn heavy(c: *Ctx, d: []const u8) -> bool {
    var total = 0usize
    var i = 0usize
    while i < d.len {
        total += usize(d[i])
        i += 1usize
    }
    ret total >= 300usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    var r = rand.pcg64(11u64, 3u64)
    var bytes: [16]u8 = zero
    var ints: [8]i64 = zero
    let choices: [3]i64 = [3]i64{ 3, 7, 11 }

    // 1: generation ranges and the stream.
    var h = 14695981039346656037u64
    var i = 0usize
    while i < 1000usize {
        let v = prop.generate(&r, prop.int_gen(-50i64, 50i64), bytes[..], ints[..])
        if v.int < -50i64 || v.int > 50i64 { os.exit(1i32) }
        h = mix_int(h, v.int)
        i += 1usize
    }
    i = 0usize
    while i < 200usize {
        let v = prop.generate(&r, prop.bytes_gen(10usize), bytes[..], ints[..])
        if v.len > 10usize { os.exit(1i32) }
        var j = 0usize
        while j < v.len {
            h = mix(h, u64(bytes[j]))
            j += 1usize
        }
        h = mix(h, 256u64)
        i += 1usize
    }
    i = 0usize
    while i < 100usize {
        let v = prop.generate(&r, prop.choice_gen(choices[..]), bytes[..], ints[..])
        if v.int != 3i64 && v.int != 7i64 && v.int != 11i64 { os.exit(1i32) }
        h = mix_int(h, v.int)
        i += 1usize
    }
    i = 0usize
    while i < 100usize {
        let v = prop.generate(&r, prop.list_gen(5usize, 1i64, 6i64), bytes[..], ints[..])
        if v.len > 5usize { os.exit(1i32) }
        var j = 0usize
        while j < v.len {
            if ints[j] < 1i64 || ints[j] > 6i64 { os.exit(1i32) }
            h = mix_int(h, ints[j])
            j += 1usize
        }
        h = mix(h, 256u64)
        i += 1usize
    }
    if h != 12262430223815677329u64 { os.exit(1i32) }
    if prop.gen_int(&r, 5i64, 5i64) != 5i64 || prop.gen_int(&r, 9i64, 2i64) != 9i64 || prop.gen_choice(&r, choices[..0usize]) != 0i64 { os.exit(1i32) }

    // 2: integer shrinking.
    var ctx = Ctx { threshold: 100i64, calls: 0usize }
    i = 0usize
    while i < 20usize {
        let x = prop.gen_int(&r, 101i64, 1000000i64)
        if prop.shrink[Ctx](&ctx, above, x) != 101i64 { os.exit(2i32) }
        i += 1usize
    }
    if ctx.calls == 0usize || ctx.calls > 20usize * 64usize { os.exit(2i32) }
    h = 14695981039346656037u64
    i = 0usize
    while i < 20usize {
        let x = 7i64 * prop.gen_int(&r, 8i64, 100000i64) + 3i64
        let res = prop.shrink[Ctx](&ctx, mod7, x)
        if !mod7(&ctx, res) { os.exit(2i32) }
        h = mix_int(h, res)
        i += 1usize
    }
    if h != 13702791000993946209u64 { os.exit(2i32) }
    i = 0usize
    while i < 20usize {
        let x = prop.gen_int(&r, -1000000i64, -101i64)
        if prop.shrink[Ctx](&ctx, below, x) != -101i64 { os.exit(2i32) }
        i += 1usize
    }
    if prop.shrink[Ctx](&ctx, above, 0i64) != 0i64 { os.exit(2i32) }

    // 3: byte-list shrinking.
    var data: [20]u8 = zero
    var scratch: [20]u8 = zero
    h = 14695981039346656037u64
    i = 0usize
    while i < 10usize {
        var j = 0usize
        while j < 20usize {
            data[j] = u8(rand.pcg64_next(&r) & 255u64)
            j += 1usize
        }
        let k = usize(prop.gen_int(&r, 0i64, 18i64))
        data[k + 1usize] = data[k]
        let (n, e) = prop.shrink_bytes[Ctx](&ctx, adjacent, data[..], 20usize, scratch[..])
        if e != ok || n != 2usize || data[0usize] != data[1usize] { os.exit(3i32) }
        h = mix(h, u64(data[0usize]))
        h = mix(h, u64(data[1usize]))
        j = 0usize
        while j < 20usize {
            data[j] = u8(rand.pcg64_next(&r) & 255u64)
            j += 1usize
        }
        if !heavy(&ctx, data[..]) {
            data[0usize] = 255u8
            data[1usize] = 255u8
        }
        let (m, f) = prop.shrink_bytes[Ctx](&ctx, heavy, data[..], 20usize, scratch[..])
        if f != ok || !heavy(&ctx, data[..m]) { os.exit(3i32) }
        j = 0usize
        while j < m {
            h = mix(h, u64(data[j]))
            j += 1usize
        }
        h = mix(h, 256u64)
        i += 1usize
    }
    if h != 2174989304769940607u64 { os.exit(3i32) }
    let (_, room) = prop.shrink_bytes[Ctx](&ctx, heavy, data[..], 20usize, scratch[..4usize])
    if room != prop.TooSmall { os.exit(3i32) }

    try io.print("test prop ok\n")
    ret ok
}
