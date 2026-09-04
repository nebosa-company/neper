use e.mem
use e.io

type Small = struct {
    a: u64,
    b: u64,
}

type Big = struct {
    a: u64,
    b: u64,
    c: u64,
}

type Bucket = struct {
    values: [2]Small,
    mark: u8,
}

fn sum_small(value: Small) -> u64 {
    ret value.a + value.b
}

fn sum_big(value: Big) -> u64 {
    ret value.a + value.b + value.c
}

fn make_big(seed: u64) -> Big {
    ret Big{ c: seed + 2u64, a: seed, b: seed + 1u64 }
}

fn adjust(value: Big) -> Big {
    var copy = value
    copy.b += 5u64
    ret copy
}

fn pick(values: [2]Small) -> Small {
    ret values[1usize]
}

fn make_values() -> [2]Small {
    ret [2]Small{ Small{ a: 12u64, b: 13u64 }, Small{ a: 14u64, b: 15u64 } }
}

fn mixed(prefix: u64, small: Small, big: Big, suffix: u64) -> u64 {
    ret prefix + small.a + small.b + big.a + big.b + big.c + suffix
}

fn main(a: *mem.Arena, args: []str) -> err {
    var small = Small{ a: 2u64, b: 3u64 }
    let copied = small
    var assigned: Small = zero
    assigned = copied
    var values = [2]Small{ Small{ a: 1u64, b: 4u64 }, Small{ a: 6u64, b: 7u64 } }
    values[0usize] = assigned
    values[1usize].a += 2u64
    let selected = pick(values)
    let returned_values = make_values()
    let big = make_big(10u64)
    let changed = adjust(big)
    let nested = adjust(make_big(20u64))
    var bucket = Bucket{ mark: 9u8, values: values }
    let bucket_copy = bucket
    bucket.values = bucket_copy.values
    var matrix = [2][2]u16{ [2]u16{ 1u16, 2u16 }, [2]u16{ 3u16, 4u16 } }
    matrix[1usize][0usize] = 9u16
    let matrix_copy = matrix
    var total: u64 = 0u64
    for i, value in values {
        total += value.a + value.b
        if i == 1usize {
            total += 1u64
        }
    }
    if sum_small(small) == 5u64 && sum_small(pick(values)) == 15u64 && make_big(30u64).c == 32u64 && returned_values[1usize].b == 15u64 && assigned.b == 3u64 && selected.a == 8u64 && selected.b == 7u64 && sum_big(big) == 33u64 && mixed(100u64, small, big, 200u64) == 338u64 && changed.b == 16u64 && nested.b == 26u64 && big.b == 11u64 && bucket.values[0usize].a == 2u64 && bucket_copy.values[1usize].b == 7u64 && bucket.mark == 9u8 && matrix_copy[1usize][0usize] == 9u16 && matrix_copy[0usize][1usize] == 2u16 && matrix[0usize].len == 2usize && total == 21u64 {
        try io.print("aggregate abi ok\n")
    } else {
        try io.print("aggregate abi failed\n")
    }
    ret ok
}
