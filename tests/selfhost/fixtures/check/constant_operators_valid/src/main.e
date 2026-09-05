const BIT_AND: usize = 240usize & 60usize
const BIT_OR: usize = BIT_AND | 3usize
const BIT_XOR: usize = BIT_OR ^ 15usize
const BIT_NOT: usize = ~18446744073709551614usize
const SHIFT_LEFT: usize = 1usize << 7u8
const SHIFT_RIGHT: usize = 128usize >> 7u16
const WRAP_ADD: usize = 18446744073709551615usize +% 2usize
const WRAP_SUB: usize = 0usize -% 18446744073709551615usize
const WRAP_MUL: usize = 9223372036854775808usize *% 2usize
const SIGNED_SHIFT: i8 = -2i8 >> 1u8

type AndResult = [BIT_AND]u8
type OrResult = [BIT_OR]u8
type XorResult = [BIT_XOR]u8
type NotResult = [BIT_NOT]u8
type ShiftLeftResult = [SHIFT_LEFT]u8
type ShiftRightResult = [SHIFT_RIGHT]u8
type WrapAddResult = [WRAP_ADD]u8
type WrapSubResult = [WRAP_SUB]u8
type WrapMulResult = [WRAP_MUL]u8
type DirectResult = [(3usize << 1u8) | 1usize]u8

type Inner[N: usize] = struct {
    values: [N]u8,
}

type Outer[N: usize] = struct {
    inner: Inner[(N << 1u8) | 1usize],
}

fn generic_bound[N: usize](values: [(N << 1u8) | 1usize]u8) -> usize {
    ret values.len
}

fn aggregate_bound[N: usize](value: Inner[(N << 1u8) | 1usize]) -> Inner[(N << 1u8) | 1usize] {
    ret value
}

fn prove_arrays(and_value: [48]u8, or_value: [51]u8, xor_value: [60]u8, not_value: [1]u8, shift_left: [128]u8, shift_right: [1]u8, wrap_add: [1]u8, wrap_sub: [1]u8, wrap_mul: [0]u8, direct: [7]u8) -> DirectResult {
    let a: AndResult = and_value
    let b: OrResult = or_value
    let c: XorResult = xor_value
    let d: NotResult = not_value
    let e: ShiftLeftResult = shift_left
    let f: ShiftRightResult = shift_right
    let g: WrapAddResult = wrap_add
    let h: WrapSubResult = wrap_sub
    let i: WrapMulResult = wrap_mul
    ret direct
}

fn prove_bounds(outer: Outer[3usize], inner: Inner[7usize], values: [7]u8) -> usize {
    let nested: Inner[7usize] = outer.inner
    let specialized = aggregate_bound[3usize](inner)
    ret generic_bound[3usize](values)
}
