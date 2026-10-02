use e.gpu

var counter: u32 = 0u32

type Iter = struct { next: u32 }

fn iter_next(it: *Iter) -> (u32, bool) {
    counter += 1u32
    let value = it.next
    it.next += 1u32
    ret (value, value < 2u32)
}

fn sum() -> u32 {
    var it = Iter { next: 0u32 }
    var total = 0u32
    for value in it { total += value }
    ret total
}

@gpu(8)
fn fill(out: []u32) { out[usize(gpu.lid.x)] = sum() }
