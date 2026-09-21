// `e.math.ntheory` against values from Python's `math`, `pow(_, -1, m)` and
// SymPy: gcd, lcm and the extended gcd; modular products, powers and inverses at
// the top of the 64-bit range; Miller-Rabin on primes, Carmichael numbers and
// the largest 64-bit prime; the three sieves against each other; trial, rho and
// p-1 factoring; Garner's CRT; baby-step giant-step, Pohlig-Hellman and the
// kangaroo; Tonelli-Shanks; the Stern-Brocot walk and the Farey sequence. Each
// check exits with its own code.

use e.io
use e.math.ntheory
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: gcd, lcm, extended gcd.
    if ntheory.gcd(462u64, 1071u64) != 21u64 || ntheory.lcm(462u64, 1071u64) != 23562u64 { os.exit(1i32) }
    if ntheory.gcd(0u64, 9u64) != 9u64 || ntheory.gcd(0u64, 0u64) != 0u64 || ntheory.lcm(0u64, 5u64) != 0u64 { os.exit(1i32) }
    if ntheory.gcd(18446744073709551615u64, 18446744073709551557u64) != 1u64 { os.exit(1i32) }
    let (g, x, y) = ntheory.extended_gcd(240i64, 46i64)
    if g != 2i64 || 240i64 * x + 46i64 * y != 2i64 { os.exit(1i32) }
    let (g2, x2, y2) = ntheory.extended_gcd(0i64 - 25i64, 15i64)
    if g2 != 5i64 || 0i64 - 25i64 * x2 + 15i64 * y2 != 5i64 { os.exit(1i32) }

    // 2: modular arithmetic without overflow.
    let big = 18446744073709551557u64
    if ntheory.mul_mod(18446744073709551556u64, 18446744073709551556u64, big) != 1u64 { os.exit(2i32) }
    if ntheory.pow_mod(3u64, 123456789u64, 1000000000000000009u64) != 806184978439295656u64 { os.exit(2i32) }
    if ntheory.pow_mod(3u64, 1000000000000000008u64, 1000000000000000009u64) != 1u64 { os.exit(2i32) }
    if ntheory.pow_mod(2u64, big - 1u64, big) != 1u64 { os.exit(2i32) }
    if ntheory.pow_mod(3u64, 12345678901234567u64, big) != 4247258853224294822u64 { os.exit(2i32) }
    if ntheory.pow_mod(7u64, 0u64, 1u64) != 0u64 || ntheory.pow_mod(7u64, 0u64, 5u64) != 1u64 { os.exit(2i32) }
    let (inv17, ok17) = ntheory.inverse_mod(17u64, 3120u64)
    if !ok17 || inv17 != 2753u64 { os.exit(2i32) }
    let (inv_big, ok_big) = ntheory.inverse_mod(123456789u64, big)
    if !ok_big || inv_big != 2326704147043708191u64 { os.exit(2i32) }
    let (_, ok_none) = ntheory.inverse_mod(6u64, 9u64)
    if ok_none { os.exit(2i32) }
    let (inv1, ok1) = ntheory.inverse_mod(5u64, 1u64)
    if !ok1 || inv1 != 0u64 { os.exit(2i32) }

    // 3: primality.
    if !ntheory.is_prime(2u64) || !ntheory.is_prime(3u64) || ntheory.is_prime(1u64) || ntheory.is_prime(0u64) { os.exit(3i32) }
    if ntheory.is_prime(561u64) || ntheory.is_prime(1105u64) || ntheory.is_prime(3215031751u64) { os.exit(3i32) }
    if !ntheory.is_prime(1000000007u64) || !ntheory.is_prime(big) || !ntheory.is_prime(2305843009213693951u64) { os.exit(3i32) }
    if ntheory.is_prime(18446744073709551615u64) || ntheory.is_prime(1000000007u64 * 998244353u64) { os.exit(3i32) }
    if !ntheory.is_prime(18446744073709551557u64) || ntheory.is_prime(18446744073709551559u64) { os.exit(3i32) }

    // 4: the three sieves agree, and the segmented one lands on 1000003.
    var flags: [1101]u8 = zero
    if ntheory.sieve(1100usize, flags[..]) != ok { os.exit(4i32) }
    var spf: [1101]u32 = zero
    var primes: [200]u32 = zero
    let (prime_count, linear_error) = ntheory.sieve_linear(1100usize, spf[..], primes[..])
    if linear_error != ok || prime_count != 184usize { os.exit(4i32) }
    var n = 0usize
    var counted = 0usize
    while n <= 1100usize {
        if flags[n] != 0u8 {
            counted += 1usize
            if usize(spf[n]) != n { os.exit(4i32) }
        } else if n >= 2usize {
            if spf[n] == 0u32 || usize(spf[n]) == n || n % usize(spf[n]) != 0usize { os.exit(4i32) }
        }
        if (flags[n] != 0u8) != ntheory.is_prime(u64(n)) { os.exit(4i32) }
        n += 1usize
    }
    if counted != 184usize || primes[0usize] != 2u32 || primes[183usize] != 1097u32 { os.exit(4i32) }
    var window: [101]u8 = zero
    var scratch: [1024]u8 = zero
    if ntheory.sieve_segmented(1000000u64, 1000100u64, window[..], scratch[..]) != ok { os.exit(4i32) }
    var seen = 0usize
    n = 0usize
    while n <= 100usize {
        if window[n] != 0u8 { seen += 1usize }
        if (window[n] != 0u8) != ntheory.is_prime(1000000u64 + u64(n)) { os.exit(4i32) }
        n += 1usize
    }
    if seen != 6usize || window[3usize] != 1u8 || window[99usize] != 1u8 { os.exit(4i32) }
    var low_window: [21]u8 = zero
    if ntheory.sieve_segmented(0u64, 20u64, low_window[..], scratch[..]) != ok { os.exit(4i32) }
    if low_window[0usize] != 0u8 || low_window[1usize] != 0u8 || low_window[2usize] != 1u8 || low_window[19usize] != 1u8 || low_window[20usize] != 0u8 { os.exit(4i32) }
    if ntheory.sieve(2000usize, flags[..]) != ntheory.TooSmall { os.exit(4i32) }
    if ntheory.sieve_segmented(50u64, 40u64, window[..], scratch[..]) != ntheory.Invalid { os.exit(4i32) }

    // 5: factoring.
    var factors: [16]u64 = zero
    var exponents: [16]u32 = zero
    let (count360, trial_error) = ntheory.factor_trial(360u64, factors[..], exponents[..])
    if trial_error != ok || count360 != 3usize { os.exit(5i32) }
    if factors[0usize] != 2u64 || exponents[0usize] != 3u32 || factors[1usize] != 3u64 || exponents[1usize] != 2u32 || factors[2usize] != 5u64 || exponents[2usize] != 1u32 { os.exit(5i32) }
    let (count1, one_error) = ntheory.factor_trial(1u64, factors[..], exponents[..])
    if one_error != ok || count1 != 0usize { os.exit(5i32) }
    let (count_p, p_error) = ntheory.factor_trial(1000000007u64, factors[..], exponents[..])
    if p_error != ok || count_p != 1usize || factors[0usize] != 1000000007u64 { os.exit(5i32) }
    let (_, tiny_error) = ntheory.factor_trial(360u64, factors[..1usize], exponents[..])
    if tiny_error != ntheory.TooSmall { os.exit(5i32) }
    let semiprime = 1000000007u64 * 998244353u64
    let rho = ntheory.factor_rho(semiprime)
    if rho != 1000000007u64 && rho != 998244353u64 { os.exit(5i32) }
    if ntheory.factor_rho(2305843009213693951u64) != 2305843009213693951u64 { os.exit(5i32) }
    if ntheory.factor_rho(1000u64) != 2u64 || ntheory.factor_rho(3u64) != 3u64 { os.exit(5i32) }
    let rho_odd = ntheory.factor_rho(1000003u64 * 999983u64)
    if rho_odd != 1000003u64 && rho_odd != 999983u64 { os.exit(5i32) }
    let triple = ntheory.factor_rho(semiprime * 3u64)
    if triple == 1u64 || triple == semiprime * 3u64 || (semiprime * 3u64) % triple != 0u64 { os.exit(5i32) }
    // 65537 - 1 = 2^16 is a prime power at most 65536, so p-1 with that bound finds 65537
    // in 65537 * 1000003; 1000000007 - 1 = 2 * 500000003 and 998244353 - 1 = 2^23 * 7 * 17
    // both hold a prime power past 1000.
    let (pm1, pm1_found) = ntheory.factor_p_minus_1(65537u64 * 1000003u64, 65536u64)
    if !pm1_found || pm1 != 65537u64 { os.exit(5i32) }
    let (_, pm1_missed) = ntheory.factor_p_minus_1(1000000007u64 * 998244353u64, 1000u64)
    if pm1_missed { os.exit(5i32) }

    // 6: the Chinese remainder theorem.
    var residues: [3]u64 = zero
    var moduli: [3]u64 = zero
    residues[0usize] = 2u64
    residues[1usize] = 3u64
    residues[2usize] = 5u64
    moduli[0usize] = 7u64
    moduli[1usize] = 11u64
    moduli[2usize] = 13u64
    let (crt_value, crt_modulus, crt_ok) = ntheory.crt(residues[..], moduli[..])
    if !crt_ok || crt_value != 135u64 || crt_modulus != 1001u64 { os.exit(6i32) }
    residues[0usize] = 123456u64
    residues[1usize] = 654321u64
    residues[2usize] = 111111u64
    moduli[0usize] = 1000003u64
    moduli[1usize] = 999983u64
    moduli[2usize] = 1000033u64
    let (crt_big, crt_big_modulus, crt_big_ok) = ntheory.crt(residues[..], moduli[..])
    if !crt_big_ok || crt_big != 655535098890520329u64 || crt_big_modulus != 1000018999486998317u64 { os.exit(6i32) }
    moduli[1usize] = 1000003u64
    let (_, _, crt_shared) = ntheory.crt(residues[..], moduli[..])
    if crt_shared { os.exit(6i32) }
    var mixed: [3]u64 = zero
    moduli[1usize] = 999983u64
    let (garner_value, garner_ok) = ntheory.crt_garner(residues[..], moduli[..], mixed[..])
    if !garner_ok || garner_value != 655535098890520329u64 || mixed[0usize] != 123456u64 { os.exit(6i32) }
    if (mixed[0usize] + mixed[1usize] * 1000003u64 + mixed[2usize] * 1000003u64 * 999983u64) != garner_value { os.exit(6i32) }

    // 7: totient.
    if ntheory.totient(36u64) != 12u64 || ntheory.totient(97u64) != 96u64 || ntheory.totient(1u64) != 1u64 { os.exit(7i32) }
    if ntheory.totient(2000000014u64) != 1000000006u64 || ntheory.totient(4294967296u64) != 2147483648u64 { os.exit(7i32) }

    // 8: discrete logarithms.
    var pairs: [4096]u64 = zero
    let (log29, log29_found) = ntheory.discrete_log_bsgs(2u64, 29u64, 1019u64, 1019u64, pairs[..])
    if !log29_found || log29 != 138u64 { os.exit(8i32) }
    let (log1, log1_found) = ntheory.discrete_log_bsgs(2u64, 1u64, 1019u64, 1019u64, pairs[..])
    if !log1_found || log1 != 0u64 { os.exit(8i32) }
    let (_, log_none) = ntheory.discrete_log_bsgs(2u64, 3u64, 7u64, 7u64, pairs[..])
    if log_none { os.exit(8i32) }
    let (ph, ph_found) = ntheory.discrete_log_pohlig_hellman(3u64, 40360u64, 65537u64, pairs[..])
    if !ph_found || ph != 12345u64 { os.exit(8i32) }
    let (ph2, ph2_found) = ntheory.discrete_log_pohlig_hellman(2u64, 29u64, 1019u64, pairs[..])
    if !ph2_found || ph2 != 138u64 { os.exit(8i32) }
    let (kangaroo, kangaroo_found) = ntheory.discrete_log_kangaroo(2u64, 770825u64, 1000003u64, 700000u64, 800000u64)
    if !kangaroo_found || kangaroo != 777777u64 { os.exit(8i32) }
    let (kangaroo_exact, exact_found) = ntheory.discrete_log_kangaroo(2u64, 29u64, 1019u64, 130u64, 140u64)
    if !exact_found || kangaroo_exact != 138u64 { os.exit(8i32) }

    // 9: modular square roots.
    let (r10, r10_ok) = ntheory.sqrt_mod(10u64, 13u64)
    if !r10_ok || (r10 != 6u64 && r10 != 7u64) { os.exit(9i32) }
    let (r5, r5_ok) = ntheory.sqrt_mod(5u64, 41u64)
    if !r5_ok || (r5 != 13u64 && r5 != 28u64) { os.exit(9i32) }
    let (r2, r2_ok) = ntheory.sqrt_mod(2u64, 7u64)
    if !r2_ok || (r2 != 3u64 && r2 != 4u64) { os.exit(9i32) }
    let (_, r3_ok) = ntheory.sqrt_mod(3u64, 7u64)
    if r3_ok { os.exit(9i32) }
    let (r0, r0_ok) = ntheory.sqrt_mod(0u64, 13u64)
    if !r0_ok || r0 != 0u64 { os.exit(9i32) }
    let (rbig, rbig_ok) = ntheory.sqrt_mod(4u64, big)
    if !rbig_ok || ntheory.mul_mod(rbig, rbig, big) != 4u64 { os.exit(9i32) }
    let square = ntheory.mul_mod(123456789123u64, 123456789123u64, big)
    let (rsq, rsq_ok) = ntheory.sqrt_mod(square, big)
    if !rsq_ok || ntheory.mul_mod(rsq, rsq, big) != square { os.exit(9i32) }

    // 10: Stern-Brocot and Farey.
    let (pi_n, pi_d) = ntheory.stern_brocot_search(3.14159265f64, 0.0001f64, 100u64)
    if pi_n != 311u64 || pi_d != 99u64 { os.exit(10i32) }
    let (half_n, half_d) = ntheory.stern_brocot_search(0.5f64, 0.000001f64, 10u64)
    if half_n != 1u64 || half_d != 2u64 { os.exit(10i32) }
    let (third_n, third_d) = ntheory.stern_brocot_search(0.333333333f64, 0.0000001f64, 1000u64)
    if third_n != 1u64 || third_d != 3u64 { os.exit(10i32) }
    var terms: [64]u64 = zero
    let (farey_count, farey_error) = ntheory.farey(5u64, terms[..])
    if farey_error != ok || farey_count != 11usize { os.exit(10i32) }
    if terms[0usize] != 0u64 || terms[1usize] != 1u64 || terms[2usize] != 1u64 || terms[3usize] != 5u64 { os.exit(10i32) }
    if terms[4usize] != 1u64 || terms[5usize] != 4u64 || terms[10usize] != 1u64 || terms[11usize] != 2u64 { os.exit(10i32) }
    if terms[20usize] != 1u64 || terms[21usize] != 1u64 { os.exit(10i32) }
    let (e, f) = ntheory.farey_next(0u64, 1u64, 1u64, 5u64, 5u64)
    if e != 1u64 || f != 4u64 { os.exit(10i32) }
    let (_, farey_room) = ntheory.farey(5u64, terms[..8usize])
    if farey_room != ntheory.TooSmall { os.exit(10i32) }

    try io.print("math ntheory ok\n")
    ret ok
}
