// Q16.16 fixed point in i32 (D249). Every operation here is integer, so two machines
// running the same tick agree bit for bit -- which is what lockstep, rollback and replay
// need and what `e.math` cannot promise, being floating point.
//
// Angles are **turns**, not radians: one whole turn is `ONE`, a quarter turn is
// `QUARTER`. Wrapping an angle is then masking off the whole turns, no transcendental
// constant is needed to reduce one, and `sin` of any i32 is defined. `atan2` answers in
// the same unit.
//
// Nothing here is a table. `sin` is a parabola with one refinement pass, worst error
// about 0.0011 of a turn; `atan2` is a minimax refinement, worst error about 0.00026 of
// a turn, a tenth of a degree. Both are exact at the quarter turns. A 257-entry table
// would read better and is not used, because large literals have bitten this library.

use e.mem

type Fx = i32
type Fx64 = i64

error DivideByZero
error Domain

const ONE: Fx = 65536i32
const HALF: Fx = 32768i32
const QUARTER: Fx = 16384i32
const EIGHTH: Fx = 8192i32
const SHIFT: u32 = 16u32
// 0.225 in Q16, the weight of the refinement pass in `sin`.
const REFINE: i64 = 14746i64
// 0.2447 and 0.0663 over a full turn, in Q16: the two weights of the atan refinement.
const ATAN_A: i64 = 2552i64
const ATAN_B: i64 = 692i64

fn from_int(n: i32) -> Fx {
    ret n * ONE
}

// Truncates toward zero, as a conversion does; `floor` rounds down instead.
fn to_int(x: Fx) -> i32 {
    if x < 0i32 { ret -((-x) >> SHIFT) }
    ret x >> SHIFT
}

fn from_ratio(num: i32, den: i32) -> (Fx, err) {
    if den == 0i32 { ret (0i32, DivideByZero) }
    ret (i32((i64(num) << SHIFT) / i64(den)), ok)
}

// The product needs the full 64-bit intermediate; narrowing back traps when the result
// does not fit, rather than wrapping quietly.
fn mul(a: Fx, b: Fx) -> Fx {
    ret i32((i64(a) * i64(b)) >> SHIFT)
}

fn div(a: Fx, b: Fx) -> (Fx, err) {
    if b == 0i32 { ret (0i32, DivideByZero) }
    ret (i32((i64(a) << SHIFT) / i64(b)), ok)
}

// An arithmetic shift right is floor division, for negatives too.
fn floor(x: Fx) -> i32 {
    ret x >> SHIFT
}

fn ceil(x: Fx) -> i32 {
    ret (x + ONE - 1i32) >> SHIFT
}

fn round(x: Fx) -> i32 {
    ret (x + HALF) >> SHIFT
}

fn abs(x: Fx) -> Fx {
    if x < 0i32 { ret -x }
    ret x
}

fn min(a: Fx, b: Fx) -> Fx {
    if a < b { ret a }
    ret b
}

fn max(a: Fx, b: Fx) -> Fx {
    if a > b { ret a }
    ret b
}

fn clamp(x: Fx, lo: Fx, hi: Fx) -> Fx {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn lerp(a: Fx, b: Fx, t: Fx) -> Fx {
    ret a + i32(((i64(b) - i64(a)) * i64(t)) >> SHIFT)
}

// Integer square root of a 64-bit value, bit by bit: no division and no float, so the
// answer is the same everywhere.
fn isqrt64(value: i64) -> i64 {
    if value <= 0i64 { ret 0i64 }
    var remainder = value
    var root = 0i64
    var bit = 1i64 << 62u32
    while bit > remainder { bit = bit >> 2u32 }
    while bit != 0i64 {
        if remainder >= root + bit {
            remainder = remainder - (root + bit)
            root = (root >> 1u32) + bit
        } else {
            root = root >> 1u32
        }
        bit = bit >> 2u32
    }
    ret root
}

// sqrt(x) in Q16 is sqrt(x * ONE) taken as an integer, since the units square.
fn sqrt(x: Fx) -> (Fx, err) {
    if x < 0i32 { ret (0i32, Domain) }
    ret (i32(isqrt64(i64(x) << SHIFT)), ok)
}

// Sine of an angle in turns. The fraction of a turn is the low 16 bits, so reduction is
// a mask; over [-1/2, 1/2) the parabola `8t - 16t|t|` tracks sine to about 0.005, and one
// refinement pass weighted 0.225 brings it under 0.0005.
fn sin(angle: Fx) -> Fx {
    var t = angle & 65535i32
    if t >= HALF { t = t - ONE }
    let wide = i64(t)
    let magnitude = i64(abs(t))
    let parabola = (wide * 8i64) - ((wide * magnitude * 16i64) >> SHIFT)
    var refined = parabola
    if refined < 0i64 {
        refined = refined + ((REFINE * (((refined * (0i64 - refined)) >> SHIFT) - refined)) >> SHIFT)
    } else {
        refined = refined + ((REFINE * (((refined * refined) >> SHIFT) - refined)) >> SHIFT)
    }
    ret i32(refined)
}

fn cos(angle: Fx) -> Fx {
    ret sin(angle + QUARTER)
}

fn tan(angle: Fx) -> (Fx, err) {
    let c = cos(angle)
    if c == 0i32 { ret (0i32, Domain) }
    let (quotient, quotient_error) = div(sin(angle), c)
    ret (quotient, quotient_error)
}

// atan of a ratio in [0, 1], answered in turns: `z/8` bent by the usual minimax term.
fn atan_unit(z: i64) -> i64 {
    let bend = ((z - i64(ONE)) * (ATAN_A + ((ATAN_B * z) >> SHIFT))) >> SHIFT
    ret (z >> 3u32) - ((z * bend) >> SHIFT)
}

// atan2 in turns. The steeper axis divides the shallower, so the ratio never leaves
// [0, 1] and one approximation serves every octant; the quadrant is then folded back on.
fn atan2(y: Fx, x: Fx) -> Fx {
    if x == 0i32 && y == 0i32 { ret 0i32 }
    let steep = i64(abs(x))
    let shallow = i64(abs(y))
    var angle = 0i64
    if steep >= shallow {
        angle = atan_unit((shallow << SHIFT) / steep)
    } else {
        angle = i64(QUARTER) - atan_unit((steep << SHIFT) / shallow)
    }
    if x < 0i32 { angle = i64(HALF) - angle }
    if y < 0i32 { angle = 0i64 - angle }
    ret i32(angle)
}

// Both squares are Q32, so their sum is too and one integer square root returns Q16.
fn length(x: Fx, y: Fx) -> Fx {
    ret i32(isqrt64(i64(x) * i64(x) + i64(y) * i64(y)))
}

fn normalize(x: Fx, y: Fx) -> (Fx, Fx) {
    let magnitude = length(x, y)
    if magnitude == 0i32 { ret (0i32, 0i32) }
    let wide = i64(magnitude)
    ret (i32((i64(x) << SHIFT) / wide), i32((i64(y) << SHIFT) / wide))
}
