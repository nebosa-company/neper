// Load-balancer pick rules over caller storage: plain and nginx smooth
// weighted round-robin, least connections, power-of-two-choices, weighted
// random, and Google's Maglev consistent lookup table (offset/skip
// permutations filled round-robin over the backends) with a disruption count
// between two tables. Ring consistent hashing, rendezvous and jump hashing
// live in `e.algo.consistent_hash` and are not repeated here.

use e.algo.hash
use e.algo.rand

// Smooth weighted round-robin state: `current` is one i64 per weight.
type Wrr = struct { weights: []const u32, current: []i64 }
error Invalid
error TooSmall

// The next index in 0..n, advancing `state`; 0 when `n` is 0.
fn round_robin(state: *u32, n: usize) -> usize {
    if n == 0usize { ret 0usize }
    let pick = usize(*state) % n
    *state = *state +% 1u32
    ret pick
}

// `Invalid` for no weights or an all-zero total; `TooSmall` when `current`
// has fewer slots than `weights`. `current` is zeroed.
fn wrr(weights: []const u32, current: []i64) -> (Wrr, err) {
    let w = Wrr { weights: weights, current: current }
    if current.len < weights.len { ret (w, TooSmall) }
    if weights.len == 0usize || total_weight(weights) == 0u64 { ret (w, Invalid) }
    var i = 0usize
    while i < weights.len {
        current[i] = 0i64
        i += 1usize
    }
    ret (w, ok)
}

// nginx's smooth weighted round-robin: every current weight grows by its
// weight, the largest wins (the lowest index on a tie) and gives back the
// total. Weights {5, 1, 1} yield a a b a c a a.
fn weighted_round_robin(w: *Wrr) -> usize {
    var best = 0usize
    var i = 0usize
    while i < w.weights.len {
        w.current[i] += i64(w.weights[i])
        if w.current[i] > w.current[best] { best = i }
        i += 1usize
    }
    w.current[best] -= i64(total_weight(w.weights))
    ret best
}

fn total_weight(weights: []const u32) -> u64 {
    var total = 0u64
    var i = 0usize
    while i < weights.len {
        total += u64(weights[i])
        i += 1usize
    }
    ret total
}

// The index of the lowest load; the lowest index on a tie, 0 when empty.
fn least_connections(loads: []const u64) -> usize {
    var best = 0usize
    var i = 1usize
    while i < loads.len {
        if loads[i] < loads[best] { best = i }
        i += 1usize
    }
    ret best
}

// Power of two choices: two distinct uniform candidates from `r`, the lower
// load wins and the lower index on a tie. Fewer than two loads pick index 0.
fn power_of_two(loads: []const u64, r: *rand.Pcg64) -> usize {
    if loads.len < 2usize { ret 0usize }
    let i = usize(rand.pcg64_bounded(r, u64(loads.len)))
    var j = usize(rand.pcg64_bounded(r, u64(loads.len - 1usize)))
    if j >= i { j += 1usize }
    if loads[j] < loads[i] { ret j }
    if loads[i] < loads[j] { ret i }
    if j < i { ret j }
    ret i
}

// The index whose weight covers `draw % total`; 0 when the total is 0.
fn weighted_random(weights: []const u32, draw: u64) -> usize {
    let total = total_weight(weights)
    if total == 0u64 { ret 0usize }
    var rest = draw % total
    var i = 0usize
    while i < weights.len {
        if rest < u64(weights[i]) { ret i }
        rest -= u64(weights[i])
        i += 1usize
    }
    ret 0usize
}

// The smallest prime at or above 100 * n (the paper's table-size guidance),
// never below 2.
fn maglev_prime(n: usize) -> usize {
    var candidate = 100usize * n
    if candidate < 2usize { candidate = 2usize }
    while !is_prime(candidate) { candidate += 1usize }
    ret candidate
}

fn is_prime(n: usize) -> bool {
    if n < 2usize { ret false }
    var d = 2usize
    while d * d <= n {
        if n % d == 0usize { ret false }
        d += 1usize
    }
    ret true
}

// Fill `table[..m]` with backend indexes: backend `i` visits slots
// `(offset + j * skip) mod m` with offset from FNV-1a 64 of its name and
// skip from FNV-1a 64 under a second basis, and the backends take turns
// claiming their first free slot until the table is full. `scratch` holds
// three u32 per backend (offset, skip, next). `Invalid` when `m` is not
// prime or is too small for `names`, `TooSmall` when `table` or `scratch`
// lack room.
fn maglev_build(names: []const str, table: []u32, scratch: []u32, m: usize) -> err {
    if !is_prime(m) || names.len == 0usize || m <= names.len { ret Invalid }
    if table.len < m || scratch.len < 3usize * names.len { ret TooSmall }
    let n = names.len
    let m64 = u64(m)
    var i = 0usize
    while i < n {
        scratch[3usize * i] = u32(hash.fnv1a64(names[i]) % m64)
        scratch[3usize * i + 1usize] = u32(fnv1a64_basis(names[i], 11400714819323198485u64) % (m64 - 1u64) + 1u64)
        scratch[3usize * i + 2usize] = 0u32
        i += 1usize
    }
    i = 0usize
    while i < m {
        table[i] = 4294967295u32
        i += 1usize
    }
    var filled = 0usize
    while true {
        i = 0usize
        while i < n {
            let offset = u64(scratch[3usize * i])
            let skip = u64(scratch[3usize * i + 1usize])
            var j = u64(scratch[3usize * i + 2usize])
            var c = usize((offset + j * skip) % m64)
            while table[c] != 4294967295u32 {
                j += 1u64
                c = usize((offset + j * skip) % m64)
            }
            table[c] = u32(i)
            scratch[3usize * i + 2usize] = u32(j + 1u64)
            filled += 1usize
            if filled == m { ret ok }
            i += 1usize
        }
    }
    ret ok
}

fn fnv1a64_basis(data: []const u8, basis: u64) -> u64 {
    var h = basis
    var at = 0usize
    while at < data.len {
        h = (h ^ u64(data[at])) *% 1099511628211u64
        at += 1usize
    }
    ret h
}

// The backend for `key_hash`: `table[key_hash mod table.len]`.
fn maglev_lookup(table: []const u32, key_hash: u64) -> u32 {
    ret table[usize(key_hash % u64(table.len))]
}

// How many slots of the shorter table point at a different backend in the
// other; both tables must number their backends the same way.
fn maglev_disruption(old_table: []const u32, new_table: []const u32) -> usize {
    var m = old_table.len
    if new_table.len < m { m = new_table.len }
    var changed = 0usize
    var i = 0usize
    while i < m {
        if old_table[i] != new_table[i] { changed += 1usize }
        i += 1usize
    }
    ret changed
}

// Maglev under its planned name: `maglev_build`.
fn maglev(names: []const str, table: []u32, scratch: []u32, m: usize) -> err { ret maglev_build(names, table, scratch, m) }
