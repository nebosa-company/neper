// Row 6 (D1614): narrow and wide integers, private aggregates, a by-value helper
// parameter and a monomorphised generic instance in one device module.
use e.gpu

type Pair = struct { byte: u8, delta: i16, wide: u64 }

fn sum[T: type](left: T, right: T) -> T {
    ret left + right
}

fn combine(value: Pair, lane: u16) -> u64 {
    var words: [2]u64 = [2]u64{ value.wide, u64(u16(value.delta)) }
    words[1usize] = sum(words[1usize], u64(lane))
    ret words[0usize] + words[1usize] + u64(value.byte)
}

@gpu(64, caps(.Int8, .Int16, .Int64))
fn types(n: u32, input: []const Pair, output: []u64) {
    let lane = gpu.gid.x
    if lane >= n { ret }
    let at = usize(lane)
    var value = Pair { byte: 0u8, delta: 0i16, wide: 0u64 }
    value.byte = input[at].byte
    value.delta = input[at].delta
    value.wide = input[at].wide
    output[at] = combine(value, u16(lane))
}

fn main() {}
