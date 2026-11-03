use e.simd

type V8 = Vec[i16, 8]

// More vector temporaries live at once than there are vector registers (so some must stay in memory), packed operations whose result
// is also an operand, a vector copied between variables, and a loop: the answer is checked lane by lane against the scalar sum.
fn many(a: []i16, out: []i16) {
    let v0 = simd.load[V8](a, 0usize)
    let v1 = simd.load[V8](a, 8usize)
    let v2 = simd.load[V8](a, 16usize)
    let v3 = simd.load[V8](a, 24usize)
    let v4 = simd.load[V8](a, 32usize)
    let v5 = simd.load[V8](a, 40usize)
    let v6 = simd.load[V8](a, 48usize)
    let v7 = simd.load[V8](a, 56usize)
    let v8 = simd.load[V8](a, 64usize)
    let v9 = simd.load[V8](a, 72usize)
    let v10 = simd.load[V8](a, 80usize)
    let v11 = simd.load[V8](a, 88usize)
    let v12 = simd.load[V8](a, 96usize)
    let v13 = simd.load[V8](a, 104usize)
    let v14 = simd.load[V8](a, 112usize)
    let v15 = simd.load[V8](a, 120usize)
    var acc = simd.splat[V8](0i16)
    var round = 0usize
    while round < 3usize {
        acc = acc +% v0
        acc = acc +% v1
        acc = acc +% v2
        acc = acc +% v3
        acc = acc +% v4
        acc = acc +% v5
        acc = acc +% v6
        acc = acc +% v7
        acc = acc +% v8
        acc = acc +% v9
        acc = acc +% v10
        acc = acc +% v11
        acc = acc +% v12
        acc = acc +% v13
        acc = acc +% v14
        acc = acc +% v15
        let copy = acc
        acc = copy +% acc
        round += 1usize
    }
    simd.store[V8](out, 0usize, acc)
}

fn main() -> i64 {
    var a: [128]i16 = zero
    var out: [8]i16 = zero
    var k = 0usize
    while k < 128usize {
        a[k] = i16(k % 13usize + 1usize)
        k += 1usize
    }
    many(a[..], out[..])
    // the scalar version: per lane l, acc = 0; three rounds of (acc += sum over the sixteen vectors of a[8 * v + l]), then acc *= 2
    var lane = 0usize
    while lane < 8usize {
        var acc = 0i32
        var round = 0usize
        while round < 3usize {
            var v = 0usize
            while v < 16usize {
                acc += i32(a[8usize * v + lane])
                v += 1usize
            }
            acc = acc * 2i32
            round += 1usize
        }
        if i32(out[lane]) != acc { ret i64(lane) + 1i64 }
        lane += 1usize
    }
    ret 0i64
}
