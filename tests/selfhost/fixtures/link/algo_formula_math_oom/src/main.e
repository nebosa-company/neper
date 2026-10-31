// MEDIAN, LARGE, and IS_NORMAL allocate once to collect numbers and once to
// sort them. A full arena for the second allocation must yield a formula error,
// never an empty-slice index trap.
use e.algo.formula as formula
use e.algo.formula.math as math
use e.mem
use e.os

fn median_oom() -> bool {
    var storage: [16]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var args: [2]formula.Value = zero
    args[0usize] = formula.number(2.0f64)
    args[1usize] = formula.number(4.0f64)
    var call: formula.Call = zero
    call.a = &arena
    call.args = args[0..]
    ret formula.is_error(math.h_median(&call))
}

fn large_oom() -> bool {
    var storage: [16]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var args: [3]formula.Value = zero
    args[0usize] = formula.number(2.0f64)
    args[1usize] = formula.number(4.0f64)
    args[2usize] = formula.number(1.0f64)
    var call: formula.Call = zero
    call.a = &arena
    call.args = args[0..]
    ret formula.is_error(math.h_large(&call))
}

fn normal_oom() -> bool {
    var storage: [64]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var args: [8]formula.Value = zero
    var i = 0usize
    while i < args.len {
        args[i] = formula.number(f64(i + 1usize))
        i += 1usize
    }
    var call: formula.Call = zero
    call.a = &arena
    call.args = args[0..]
    ret formula.is_error(math.h_is_normal(&call))
}

fn main() {
    if !median_oom() || !large_oom() || !normal_oom() { os.exit(1) }
    os.exit(0)
}
