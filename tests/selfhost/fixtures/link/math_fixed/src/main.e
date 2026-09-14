// `e.math.fixed` (D265): Q16.16 integer arithmetic and angles in turns. Every expected
// value below was computed independently in Python, not read off this implementation.
// Each check returns its own number when it fails; 0 is every check passed.

use e.mem
use e.math.fixed

fn main() -> i64 {
    // Conversion, and the difference between truncation and floor on a negative.
    if fixed.from_int(3i32) != 196608i32 { ret 1i64 }
    if fixed.to_int(196608i32) != 3i32 { ret 2i64 }
    if fixed.to_int(-98304i32) != -1i32 { ret 3i64 }
    if fixed.floor(-98304i32) != -2i32 { ret 4i64 }
    if fixed.ceil(98304i32) != 2i32 { ret 5i64 }
    if fixed.round(98304i32) != 2i32 { ret 6i64 }

    // Multiplication and division carry a 64-bit intermediate.
    if fixed.mul(131072i32, 196608i32) != 393216i32 { ret 7i64 }
    let (quotient, quotient_error) = fixed.div(393216i32, 196608i32)
    if quotient_error != ok || quotient != 131072i32 { ret 8i64 }
    let (quarter, quarter_error) = fixed.from_ratio(1i32, 4i32)
    if quarter_error != ok || quarter != 16384i32 { ret 9i64 }
    let (bad, bad_error) = fixed.div(65536i32, 0i32)
    if bad_error != fixed.DivideByZero { ret 10i64 }

    if fixed.abs(-65536i32) != 65536i32 { ret 11i64 }
    if fixed.clamp(196608i32, 0i32, 65536i32) != 65536i32 { ret 12i64 }
    if fixed.min(3i32, 9i32) != 3i32 || fixed.max(3i32, 9i32) != 9i32 { ret 13i64 }
    // lerp(1.0, 3.0, 0.25) is 1.5
    if fixed.lerp(65536i32, 196608i32, 16384i32) != 98304i32 { ret 14i64 }

    // sqrt(2) is 92681 in Q16; sqrt(0.25) is exactly 0.5.
    let (root_two, root_two_error) = fixed.sqrt(131072i32)
    if root_two_error != ok || root_two != 92681i32 { ret 15i64 }
    let (root_quarter, root_quarter_error) = fixed.sqrt(16384i32)
    if root_quarter_error != ok || root_quarter != 32768i32 { ret 16i64 }
    let (negative, negative_error) = fixed.sqrt(-65536i32)
    if negative_error != fixed.Domain { ret 17i64 }

    // Angles are turns: a quarter turn is 16384, and sine is exact at every quarter.
    if fixed.sin(0i32) != 0i32 { ret 18i64 }
    if fixed.sin(16384i32) != 65536i32 { ret 19i64 }
    if fixed.sin(32768i32) != 0i32 { ret 20i64 }
    if fixed.sin(49152i32) != -65536i32 { ret 21i64 }
    if fixed.cos(0i32) != 65536i32 { ret 22i64 }
    if fixed.cos(16384i32) != 0i32 { ret 23i64 }
    // A whole turn later is the same angle, which is what masking the turns buys.
    if fixed.sin(16384i32 + 65536i32) != fixed.sin(16384i32) { ret 24i64 }
    // One twelfth of a turn is 30 degrees, whose sine is a half.
    if fixed.sin(5461i32) != 32766i32 { ret 25i64 }

    // 3-4-5, so the length is exactly 5 and the unit vector is (0.6, 0.8).
    if fixed.length(196608i32, 262144i32) != 327680i32 { ret 26i64 }
    let (unit_x, unit_y) = fixed.normalize(196608i32, 262144i32)
    if unit_x != 39321i32 || unit_y != 52428i32 { ret 27i64 }
    if fixed.length(0i32, 0i32) != 0i32 { ret 28i64 }
    let (zero_x, zero_y) = fixed.normalize(0i32, 0i32)
    if zero_x != 0i32 || zero_y != 0i32 { ret 29i64 }

    // atan2 is exact on the axes and the diagonals, and answers in turns.
    if fixed.atan2(0i32, 65536i32) != 0i32 { ret 30i64 }
    if fixed.atan2(65536i32, 0i32) != 16384i32 { ret 31i64 }
    if fixed.atan2(0i32, -65536i32) != 32768i32 { ret 32i64 }
    if fixed.atan2(-65536i32, 0i32) != -16384i32 { ret 33i64 }
    if fixed.atan2(65536i32, 65536i32) != 8192i32 { ret 34i64 }
    if fixed.atan2(-65536i32, -65536i32) != -24576i32 { ret 35i64 }
    if fixed.atan2(0i32, 0i32) != 0i32 { ret 36i64 }

    // sin and atan2 agree: the angle of (cos t, sin t) is t again, within the error
    // both approximations carry.
    var turn = 0i32
    while turn < 65536i32 {
        let recovered = fixed.atan2(fixed.sin(turn), fixed.cos(turn))
        var difference = recovered - turn
        if difference > 32768i32 { difference = difference - 65536i32 }
        if difference < -32768i32 { difference = difference + 65536i32 }
        if fixed.abs(difference) > 120i32 { ret 37i64 }
        turn = turn + 271i32
    }

    ret 0i64
}
