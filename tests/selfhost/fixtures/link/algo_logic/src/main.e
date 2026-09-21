// `e.algo.logic`: Quine-McCluskey on the textbook function
// f(A,B,C,D) = Σm(4,8,10,11,12,15) + d(9,14) finds its four prime implicants
// and a cover of three that `verify` accepts, a full function reduces to
// one term, and the argument checks answer. Each check exits with its own
// code.

use e.algo.logic as logic
use e.io
use e.mem
use e.os

fn has(primes: []const logic.Implicant, count: usize, value: u32, care: u32) -> bool {
    var i = 0usize
    while i < count {
        if primes[i].value == value && primes[i].care == care { ret true }
        i += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    var minterms: [6]u32 = zero
    minterms[0usize] = 4u32
    minterms[1usize] = 8u32
    minterms[2usize] = 10u32
    minterms[3usize] = 11u32
    minterms[4usize] = 12u32
    minterms[5usize] = 15u32
    var dont: [2]u32 = zero
    dont[0usize] = 9u32
    dont[1usize] = 14u32
    var primes: [32]logic.Implicant = zero
    var chosen: [32]usize = zero
    var work: [128]logic.Implicant = zero
    var merged: [128]u8 = zero
    var covered: [8]u8 = zero

    // 1: primes and cover.
    let (prime_count, chosen_count, qm_error) = logic.quine_mccluskey(4usize, minterms[..], dont[..], primes[..], chosen[..], work[..], merged[..], covered[..])
    if qm_error != ok || prime_count != 4usize || chosen_count != 3usize { os.exit(1i32) }
    // Primes: -100 (B C' D'), 1-1- (A C), 1--0 (A D'), 10-- (A B').
    if !has(primes[..], prime_count, 4u32, 7u32) || !has(primes[..], prime_count, 10u32, 10u32) || !has(primes[..], prime_count, 8u32, 9u32) || !has(primes[..], prime_count, 8u32, 12u32) { os.exit(1i32) }
    if !logic.verify(4usize, minterms[..], dont[..], primes[..], chosen[..chosen_count]) { os.exit(1i32) }
    // The essential primes B C' D' and A C are in the cover.
    var essential = 0usize
    var i = 0usize
    while i < chosen_count {
        let p = primes[chosen[i]]
        if (p.value == 4u32 && p.care == 7u32) || (p.value == 10u32 && p.care == 10u32) { essential += 1usize }
        i += 1usize
    }
    if essential != 2usize { os.exit(1i32) }
    // Dropping a prime from the cover breaks it.
    if logic.verify(4usize, minterms[..], dont[..], primes[..], chosen[..2usize]) { os.exit(1i32) }

    // 2: every minterm of two variables is the constant 1; a single minterm is itself.
    var all: [4]u32 = zero
    all[1usize] = 1u32
    all[2usize] = 2u32
    all[3usize] = 3u32
    let (one_prime, one_chosen, all_error) = logic.quine_mccluskey(2usize, all[..], dont[..0usize], primes[..], chosen[..], work[..], merged[..], covered[..])
    if all_error != ok || one_prime != 1usize || one_chosen != 1usize || primes[0usize].care != 0u32 { os.exit(2i32) }
    let (single_prime, single_chosen, single_error) = logic.quine_mccluskey(3usize, all[..1usize], dont[..0usize], primes[..], chosen[..], work[..], merged[..], covered[..])
    if single_error != ok || single_prime != 1usize || single_chosen != 1usize || primes[0usize].care != 7u32 || primes[0usize].value != 0u32 { os.exit(2i32) }
    let (_, _, invalid) = logic.quine_mccluskey(2usize, minterms[..], dont[..0usize], primes[..], chosen[..], work[..], merged[..], covered[..])
    if invalid != logic.Invalid { os.exit(2i32) }
    let (_, _, room) = logic.quine_mccluskey(4usize, minterms[..], dont[..], primes[..2usize], chosen[..], work[..], merged[..], covered[..])
    if room != logic.TooSmall { os.exit(2i32) }

    try io.print("algo logic ok\n")
    ret ok
}
