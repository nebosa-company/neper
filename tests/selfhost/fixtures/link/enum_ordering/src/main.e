// An enum orders by its backing integer, so `Huge` is above `Low` in a `u64`
// enum and below it under a signed comparison. Spec section 9 rule 4 supplies
// `cmp` for the same shapes.

error Failed

type Big = enum u64 {
    Low = 1u64,
    Huge = 18446744073709551615u64,
}

type Byte = enum u8 {
    Lo = 1u8,
    Hi = 250u8,
}

type Word = enum i32 {
    First = 1i32,
    Second = 2000000000i32,
}

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn smaller[T: type](a: T, b: T) -> bool {
    ret T.cmp(a, b) < 0i32
}

fn main() -> err {
    let low = Big.Low
    let huge = Big.Huge
    // A signed comparison reads `Huge` as -1 and fails every one of these.
    if !(low < huge) { ret Failed }
    if huge < low { ret Failed }
    if !(huge > low) { ret Failed }
    if !(low <= huge) { ret Failed }
    if !(huge >= low) { ret Failed }
    if !(low <= low) { ret Failed }
    let lo = Byte.Lo
    let hi = Byte.Hi
    if !(lo < hi) { ret Failed }
    if hi < lo { ret Failed }
    let first = Word.First
    let second = Word.Second
    if !(first < second) { ret Failed }
    if second < first { ret Failed }
    if order[Big](low, huge) != 0i32 - 1i32 { ret Failed }
    if order[Big](huge, low) != 1i32 { ret Failed }
    if order[Big](huge, huge) != 0i32 { ret Failed }
    if order[Byte](lo, hi) != 0i32 - 1i32 { ret Failed }
    if order[Byte](hi, lo) != 1i32 { ret Failed }
    if order[Word](first, second) != 0i32 - 1i32 { ret Failed }
    if order[Word](second, second) != 0i32 { ret Failed }
    if !smaller[Big](low, huge) { ret Failed }
    if smaller[Big](huge, low) { ret Failed }
    ret ok
}
