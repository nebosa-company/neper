// Section 9's compile-time evaluation of a call in a `const` initialiser (D218): the
// interpreter walks the callee with integer and bool values -- locals, assignment and
// the compound forms, `if`, `while`, `break`, `ret`, every operator, a checked cast,
// a constant, a bool through a flag, and calls to other functions, here and in a
// second module. Each constant
// is checked against the value the same code gives at run time, and one is an array
// length, which only a value settled at compile time can be. Exit 0 when all agree.
use e.os
use table

const FIB_20 = fib(20)
const POW_3_5 = power(3, 5)
const PRIMES_BELOW_100 = count_primes(100usize)
const SIGNED_FLOOR = floor_div(-7, 2)
const TABLE_SUM = table.checksum(16u32)
const LEAP_2024 = leap_flag(2024)
const SHIFTED: u8 = u8(narrow(300u32))

fn fib(n: i64) -> i64 {
    var a = 0i64
    var b = 1i64
    var i = 0i64
    while i < n {
        let next = a + b
        a = b
        b = next
        i += 1i64
    }
    ret a
}

fn power(base: i64, exponent: i64) -> i64 {
    if exponent == 0i64 { ret 1i64 }
    ret base * power(base, exponent - 1i64)
}

fn count_primes(limit: usize) -> usize {
    var count = 0usize
    var n = 2usize
    while n < limit {
        var divisor = 2usize
        var prime = true
        while divisor * divisor <= n {
            if n % divisor == 0usize {
                prime = false
                break
            }
            divisor += 1usize
        }
        if prime { count += 1usize }
        n += 1usize
    }
    ret count
}

fn floor_div(a: i64, b: i64) -> i64 {
    var q = a / b
    if (a % b != 0i64) && ((a < 0i64) != (b < 0i64)) { q -= 1i64 }
    ret q
}

fn leap(year: i64) -> bool {
    let by_four = year % 4i64 == 0i64 && year % 100i64 != 0i64
    ret by_four || year % 400i64 == 0i64
}

fn leap_flag(year: i64) -> i64 {
    if leap(year) { ret 1i64 }
    ret 0i64
}

fn narrow(x: u32) -> u32 {
    let halved = x >> 1u32
    ret halved & 255u32
}

fn main() {
    var sized: [PRIMES_BELOW_100]u8 = zero
    if sized.len != 25usize { os.exit(10) }
    if FIB_20 != fib(20) || FIB_20 != 6765i64 { os.exit(11) }
    if POW_3_5 != power(3, 5) || POW_3_5 != 243i64 { os.exit(12) }
    if PRIMES_BELOW_100 != count_primes(100usize) { os.exit(13) }
    if SIGNED_FLOOR != floor_div(-7, 2) || SIGNED_FLOOR != -4i64 { os.exit(14) }
    if TABLE_SUM != table.checksum(16u32) || TABLE_SUM != 1224u32 { os.exit(15) }
    if LEAP_2024 != 1i64 || LEAP_2024 != leap_flag(2024) || leap_flag(1900) != 0i64 { os.exit(16) }
    if SHIFTED != 150u8 { os.exit(17) }
    os.exit(0)
}
