// R's "L'Ecuyer-CMRG" generator (MRGk3a of L'Ecuyer 1999): the seeding of set.seed, `unif` (unif_rand),
// and the stream jumps of the parallel package, `next_stream` (2^127 steps) and `next_substream` (2^76
// steps), by multiplying the state with the precomputed jump matrices.
//
// Also rngseq_start, the seeding of rngtools::RNGseq. Not here: .Random.seed bookkeeping and the doRNG per-task
// conventions beyond the stream jumps.

type State = struct { s: [6]u64 }

fn m1() -> u64 { ret 4294967087u64 }

fn m2() -> u64 { ret 4294944443u64 }

// set.seed(seed) for this kind: the scrambling of Randomize, rejecting words at or above m2
fn set_seed(seed: u32) -> State {
    var st: State = zero
    var x = u64(seed)
    var i = 0usize
    while i < 50usize {
        x = (69069u64 * x + 1u64) % 4294967296u64
        i += 1usize
    }
    var j = 0usize
    while j < 6usize {
        x = (69069u64 * x + 1u64) % 4294967296u64
        while x >= m2() { x = (69069u64 * x + 1u64) % 4294967296u64 }
        st.s[j] = x
        j += 1usize
    }
    ret st
}

// unif_rand(): one step of both components
fn unif(st: *State) -> f64 {
    let p1a = 1403580u64 * st.s[1usize] % m1()
    let p1b = 810728u64 * st.s[0usize] % m1()
    let p1 = (p1a + m1() - p1b) % m1()
    st.s[0usize] = st.s[1usize]
    st.s[1usize] = st.s[2usize]
    st.s[2usize] = p1
    let p2a = 527612u64 * st.s[5usize] % m2()
    let p2b = 1370589u64 * st.s[3usize] % m2()
    let p2 = (p2a + m2() - p2b) % m2()
    st.s[3usize] = st.s[4usize]
    st.s[4usize] = st.s[5usize]
    st.s[5usize] = p2
    var z = p1 + m1() - p2
    z = z % m1()
    var zz = z
    if zz == 0u64 { zz = m1() }
    ret f64(zz) * 2.328306549295727688e-10f64
}

// out = mat (3 x 3, row-major) * v (3) modulo m
fn matvec(mat: []const u64, v: []const u64, m: u64, out: []u64) {
    var i = 0usize
    while i < 3usize {
        var s = 0u64
        var j = 0usize
        while j < 3usize {
            s = (s + mat[i * 3usize + j] * v[j] % m) % m
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
}

// which 0: 2^127 steps (nextRNGStream), 1: 2^76 steps (nextRNGSubStream)
fn jump(st: State, which: u8) -> State {
    var a1: [9]u64 = zero
    var a2: [9]u64 = zero
    if which == 0u8 {
        a1[0usize] = 2427906178u64
        a1[1usize] = 3580155704u64
        a1[2usize] = 949770784u64
        a1[3usize] = 226153695u64
        a1[4usize] = 1230515664u64
        a1[5usize] = 3580155704u64
        a1[6usize] = 1988835001u64
        a1[7usize] = 986791581u64
        a1[8usize] = 1230515664u64
        a2[0usize] = 1464411153u64
        a2[1usize] = 277697599u64
        a2[2usize] = 1610723613u64
        a2[3usize] = 32183930u64
        a2[4usize] = 1464411153u64
        a2[5usize] = 1022607788u64
        a2[6usize] = 2824425944u64
        a2[7usize] = 32183930u64
        a2[8usize] = 2093834863u64
    } else {
        a1[0usize] = 82758667u64
        a1[1usize] = 1871391091u64
        a1[2usize] = 4127413238u64
        a1[3usize] = 3672831523u64
        a1[4usize] = 69195019u64
        a1[5usize] = 1871391091u64
        a1[6usize] = 3672091415u64
        a1[7usize] = 3528743235u64
        a1[8usize] = 69195019u64
        a2[0usize] = 1511326704u64
        a2[1usize] = 3759209742u64
        a2[2usize] = 1610795712u64
        a2[3usize] = 4292754251u64
        a2[4usize] = 1511326704u64
        a2[5usize] = 3889917532u64
        a2[6usize] = 3859662829u64
        a2[7usize] = 4292754251u64
        a2[8usize] = 3708466080u64
    }
    var out: State = zero
    var v1: [3]u64 = zero
    var v2: [3]u64 = zero
    var r1: [3]u64 = zero
    var r2: [3]u64 = zero
    var i = 0usize
    while i < 3usize {
        v1[i] = st.s[i]
        v2[i] = st.s[3usize + i]
        i += 1usize
    }
    matvec(a1[0usize..9usize], v1[0usize..3usize], m1(), r1[0usize..3usize])
    matvec(a2[0usize..9usize], v2[0usize..3usize], m2(), r2[0usize..3usize])
    i = 0usize
    while i < 3usize {
        out.s[i] = r1[i]
        out.s[3usize + i] = r2[i]
        i += 1usize
    }
    ret out
}

// rngtools::RNGseq(n, seed) for a single number seed under the default generator: set.seed(seed) with the
// Mersenne-Twister, then RNGkind("L'Ecuyer-CMRG") reseeds the new generator from floor(u * (2^32 - 1)) for the
// next uniform u of the old one; stream i is that state advanced by i stream jumps
fn rngseq_start(u: f64) -> State {
    let s = u32(u * 4294967295.0f64)
    ret set_seed(s)
}
