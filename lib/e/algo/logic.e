// Boolean minimisation by Quine-McCluskey in caller storage: a function
// of `n` variables (`n <= 16`) given by its minterms (and optional don't
// cares) is reduced to its prime implicants, then a cover of the minterms
// is chosen greedily after the essential primes. An implicant is a pair
// of bit masks (`value`, `care`): the term matches minterms `m` with
// `m & care == value`.

error TooSmall
error Invalid

type Implicant = struct { value: u32, care: u32 }

fn popcount(x: u32) -> usize {
    var c = 0usize
    var v = x
    while v != 0u32 {
        c += usize(v & 1u32)
        v = v >> 1u32
    }
    ret c
}

// Prime implicants of the minterms (with `dont_cares` allowed to join
// terms). `primes` receives them; `work` and `merged` are scratch of at
// least `capacity` implicants and bytes each, where `capacity` bounds the
// terms alive in one round (`3^n` at most, usually far fewer).
fn prime_implicants(n: usize, minterms: []const u32, dont_cares: []const u32, primes: []Implicant, work: []Implicant, merged: []u8) -> (usize, err) {
    if n == 0usize || n > 16usize { ret (0usize, Invalid) }
    let all = (1u32 << u32(n)) - 1u32
    var count = 0usize
    var i = 0usize
    while i < minterms.len + dont_cares.len {
        var m = 0u32
        if i < minterms.len { m = minterms[i] } else { m = dont_cares[i - minterms.len] }
        if m > all { ret (0usize, Invalid) }
        // Skip duplicates.
        var seen = false
        var j = 0usize
        while j < count && !seen {
            if work[j].value == m && work[j].care == all { seen = true }
            j += 1usize
        }
        if !seen {
            if count >= work.len || count >= merged.len { ret (0usize, TooSmall) }
            work[count] = Implicant { value: m, care: all }
            count += 1usize
        }
        i += 1usize
    }
    var prime_count = 0usize
    var live = count
    var rounds = 0usize
    while live > 0usize && rounds <= n {
        i = 0usize
        while i < live {
            merged[i] = 0u8
            i += 1usize
        }
        // Terms of this round are work[..live]; the next round's are appended after.
        var next = live
        i = 0usize
        while i < live {
            var j = i + 1usize
            while j < live {
                let a = work[i]
                let b = work[j]
                if a.care == b.care {
                    let diff = a.value ^ b.value
                    if popcount(diff) == 1usize {
                        merged[i] = 1u8
                        merged[j] = 1u8
                        let term = Implicant { value: a.value & (all ^ diff), care: a.care & (all ^ diff) }
                        var seen = false
                        var q = live
                        while q < next && !seen {
                            if work[q].value == term.value && work[q].care == term.care { seen = true }
                            q += 1usize
                        }
                        if !seen {
                            if next >= work.len || next >= merged.len { ret (0usize, TooSmall) }
                            work[next] = term
                            next += 1usize
                        }
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < live {
            if merged[i] == 0u8 {
                if prime_count >= primes.len { ret (0usize, TooSmall) }
                primes[prime_count] = work[i]
                prime_count += 1usize
            }
            i += 1usize
        }
        // Shift the next round down.
        i = 0usize
        while i < next - live {
            work[i] = work[live + i]
            i += 1usize
        }
        live = next - live
        rounds += 1usize
    }
    ret (prime_count, ok)
}

fn covers(p: Implicant, m: u32) -> bool { ret (m & p.care) == p.value }

// A cover of `minterms` by `primes`: the essential ones first, then the
// prime covering the most uncovered minterms until all are; `chosen`
// receives the indices, `covered.len >= minterms.len`. Answers the count.
fn cover(minterms: []const u32, primes: []const Implicant, chosen: []usize, covered: []u8) -> (usize, err) {
    if covered.len < minterms.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < minterms.len {
        covered[i] = 0u8
        i += 1usize
    }
    var count = 0usize
    // Essentials: a minterm covered by exactly one prime.
    i = 0usize
    while i < minterms.len {
        var only = primes.len
        var how_many = 0usize
        var p = 0usize
        while p < primes.len {
            if covers(primes[p], minterms[i]) {
                how_many += 1usize
                only = p
            }
            p += 1usize
        }
        if how_many == 1usize {
            var already = false
            var c = 0usize
            while c < count && !already {
                if chosen[c] == only { already = true }
                c += 1usize
            }
            if !already {
                if count >= chosen.len { ret (count, TooSmall) }
                chosen[count] = only
                count += 1usize
                var j = 0usize
                while j < minterms.len {
                    if covers(primes[only], minterms[j]) { covered[j] = 1u8 }
                    j += 1usize
                }
            }
        }
        i += 1usize
    }
    var progressing = true
    while progressing {
        var best = primes.len
        var best_gain = 0usize
        var p = 0usize
        while p < primes.len {
            var gain = 0usize
            var j = 0usize
            while j < minterms.len {
                if covered[j] == 0u8 && covers(primes[p], minterms[j]) { gain += 1usize }
                j += 1usize
            }
            if gain > best_gain {
                best_gain = gain
                best = p
            }
            p += 1usize
        }
        if best == primes.len {
            progressing = false
        } else {
            if count >= chosen.len { ret (count, TooSmall) }
            chosen[count] = best
            count += 1usize
            var j = 0usize
            while j < minterms.len {
                if covers(primes[best], minterms[j]) { covered[j] = 1u8 }
                j += 1usize
            }
        }
    }
    i = 0usize
    while i < minterms.len {
        if covered[i] == 0u8 { ret (count, Invalid) }
        i += 1usize
    }
    ret (count, ok)
}

// The whole method: primes, then a cover; `chosen` receives prime indices.
fn quine_mccluskey(n: usize, minterms: []const u32, dont_cares: []const u32, primes: []Implicant, chosen: []usize, work: []Implicant, merged: []u8, covered: []u8) -> (usize, usize, err) {
    let (prime_count, prime_error) = prime_implicants(n, minterms, dont_cares, primes, work, merged)
    if prime_error != ok { ret (0usize, 0usize, prime_error) }
    let (chosen_count, cover_error) = cover(minterms, primes[..prime_count], chosen, covered)
    ret (prime_count, chosen_count, cover_error)
}

// Does the cover agree with the function on every minterm and reject
// every other input outside the don't cares?
fn verify(n: usize, minterms: []const u32, dont_cares: []const u32, primes: []const Implicant, chosen: []const usize) -> bool {
    let total = 1u32 << u32(n)
    var m = 0u32
    while m < total {
        var wanted = false
        var i = 0usize
        while i < minterms.len && !wanted {
            if minterms[i] == m { wanted = true }
            i += 1usize
        }
        var free = false
        i = 0usize
        while i < dont_cares.len && !free {
            if dont_cares[i] == m { free = true }
            i += 1usize
        }
        var got = false
        i = 0usize
        while i < chosen.len && !got {
            if covers(primes[chosen[i]], m) { got = true }
            i += 1usize
        }
        if !free && got != wanted { ret false }
        m += 1u32
    }
    ret true
}
