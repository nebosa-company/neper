// Structured loops (D1612): `while` has several source back edges through `continue`,
// `for` has its increment block, and both carry mutable values in private memory.
use e.gpu

@gpu(64)
fn fill(n: u32, y: []u32) {
    let id = gpu.gid.x
    if id >= n { ret }
    var sum = 0u32
    var i = 0u32
    while i < id + 7u32 {
        i += 1u32
        if i % 3u32 == 0u32 { continue }
        if i > 11u32 { break }
        sum += i
    }
    for j in 0u32..id + 4u32 {
        if j == 2u32 { continue }
        if j >= 8u32 { break }
        sum += j * 2u32
    }
    var outer = 0u32
    while outer < 3u32 {
        outer += 1u32
        var inner = 0u32
        while inner < 5u32 {
            inner += 1u32
            if inner == 2u32 { continue }
            if outer == 3u32 {
                if inner == 4u32 { break }
            }
            sum += outer * inner
        }
    }
    y[usize(id)] = sum
}

fn main() {}
