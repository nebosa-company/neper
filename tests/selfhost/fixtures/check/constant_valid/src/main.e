use dep as d

type Count = usize

const WIDTH: Count = d.BASE * 2usize
const FORWARD: usize = LATER + 1usize
const LATER: usize = 3usize
const SIGNED: i64 = -3i64 + 10i64
const REMAINDER: usize = 11usize % 4usize
const QUOTIENT: usize = (20usize / 5usize) - 1usize
const INFERRED = 5i32
const MINIMUM: i8 = -128
const MAXIMUM: u64 = 0xffff_ffff_ffff_ffffu64

fn array(values: [WIDTH]u8) -> [4usize]u8 {
    let copy: [WIDTH]u8 = values
    ret copy
}

fn forwarded(values: [FORWARD]u8) -> [4usize]u8 {
    ret values
}

fn quotient(values: [QUOTIENT]u8) -> [3usize]u8 {
    ret values
}

fn imported() -> i32 {
    ret d.VALUE
}

fn signed() -> i64 {
    ret SIGNED
}

fn inferred() -> i32 {
    ret INFERRED
}

fn forward() -> usize {
    ret FORWARD + REMAINDER
}

fn bounds() -> i8 {
    ret MINIMUM
}

fn maximum() -> u64 {
    ret MAXIMUM
}
