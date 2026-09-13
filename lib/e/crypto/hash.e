// The hash functions a toolchain needs: SHA-256 and SHA-512 (FIPS 180-4), SHA3-256 and
// SHA3-512 (FIPS 202, Keccak-f[1600] with rates 136 and 72), and the two legacy digests
// kept for what still identifies itself by them. Each SHA-2 and SHA-3 has a streaming
// form -- `init`, `update`, `done` -- whose state is exactly what the surface names,
// and a one-call form over it. `equal_constant_time` compares digests without an early
// exit. Every constant is the published one; the fixture checks the published vectors.

type Sha256 = struct { h: [8]u32, block: [64]u8, block_len: u8, total: u64 }
type Sha512 = struct { h: [8]u64, block: [128]u8, block_len: u8, total_hi: u64, total_lo: u64 }
type Sha3_256 = struct { lanes: [25]u64, block: [136]u8, block_len: u8 }
type Sha3_512 = struct { lanes: [25]u64, block: [72]u8, block_len: u8 }

// A rotate by 0 would shift by the whole width, which section 11 traps (D196): the
// complementary count is masked, and the masked shift by 0 gives the value back.
fn rotr32(x: u32, n: u32) -> u32 {
    let low = x >> n
    ret low | (x << ((32u32 - n) & 31u32))
}

fn rotr64(x: u64, n: u32) -> u64 {
    let low = x >> n
    ret low | (x << ((64u32 - n) & 63u32))
}

fn rotl64(x: u64, n: u32) -> u64 {
    let high = x << n
    ret high | (x >> ((64u32 - n) & 63u32))
}

fn rotl32(x: u32, n: u32) -> u32 {
    let high = x << n
    ret high | (x >> ((32u32 - n) & 31u32))
}

fn load_be32(block: []const u8, at: usize) -> u32 {
    let top = u32(block[at]) << 24u32
    ret top | (u32(block[at + 1usize]) << 16u32) | (u32(block[at + 2usize]) << 8u32) | u32(block[at + 3usize])
}

fn load_be64(block: []const u8, at: usize) -> u64 {
    let high = u64(load_be32(block, at)) << 32u32
    let low = u64(load_be32(block, at + 4usize))
    ret high | low
}

fn store_be32(out: []u8, at: usize, value: u32) {
    out[at] = u8(value >> 24u32)
    out[at + 1usize] = u8((value >> 16u32) & 255u32)
    out[at + 2usize] = u8((value >> 8u32) & 255u32)
    out[at + 3usize] = u8(value & 255u32)
}

fn store_be64(out: []u8, at: usize, value: u64) {
    store_be32(out, at, u32(value >> 32u32))
    store_be32(out, at + 4usize, u32(value & 4294967295u64))
}

fn sha256_k(index: usize) -> u32 {
    let table: [64]u32 = [64]u32{
        1116352408u32, 1899447441u32, 3049323471u32, 3921009573u32, 961987163u32, 1508970993u32, 2453635748u32, 2870763221u32,
        3624381080u32, 310598401u32, 607225278u32, 1426881987u32, 1925078388u32, 2162078206u32, 2614888103u32, 3248222580u32,
        3835390401u32, 4022224774u32, 264347078u32, 604807628u32, 770255983u32, 1249150122u32, 1555081692u32, 1996064986u32,
        2554220882u32, 2821834349u32, 2952996808u32, 3210313671u32, 3336571891u32, 3584528711u32, 113926993u32, 338241895u32,
        666307205u32, 773529912u32, 1294757372u32, 1396182291u32, 1695183700u32, 1986661051u32, 2177026350u32, 2456956037u32,
        2730485921u32, 2820302411u32, 3259730800u32, 3345764771u32, 3516065817u32, 3600352804u32, 4094571909u32, 275423344u32,
        430227734u32, 506948616u32, 659060556u32, 883997877u32, 958139571u32, 1322822218u32, 1537002063u32, 1747873779u32,
        1955562222u32, 2024104815u32, 2227730452u32, 2361852424u32, 2428436474u32, 2756734187u32, 3204031479u32, 3329325298u32 }
    ret table[index]
}

fn sha256_init() -> Sha256 {
    var s: Sha256 = zero
    s.h[0] = 1779033703u32
    s.h[1] = 3144134277u32
    s.h[2] = 1013904242u32
    s.h[3] = 2773480762u32
    s.h[4] = 1359893119u32
    s.h[5] = 2600822924u32
    s.h[6] = 528734635u32
    s.h[7] = 1541459225u32
    ret s
}

fn sha256_compress(s: *Sha256, block: []const u8) {
    var w: [64]u32 = zero
    var t = 0usize
    while t < 16usize {
        w[t] = load_be32(block, t * 4usize)
        t += 1usize
    }
    while t < 64usize {
        let s0 = rotr32(w[t - 15usize], 7u32) ^ rotr32(w[t - 15usize], 18u32) ^ (w[t - 15usize] >> 3u32)
        let s1 = rotr32(w[t - 2usize], 17u32) ^ rotr32(w[t - 2usize], 19u32) ^ (w[t - 2usize] >> 10u32)
        w[t] = w[t - 16usize] +% s0 +% w[t - 7usize] +% s1
        t += 1usize
    }
    var a = s.h[0]
    var b = s.h[1]
    var c = s.h[2]
    var d = s.h[3]
    var e = s.h[4]
    var f = s.h[5]
    var g = s.h[6]
    var h = s.h[7]
    t = 0usize
    while t < 64usize {
        let big1 = rotr32(e, 6u32) ^ rotr32(e, 11u32) ^ rotr32(e, 25u32)
        let choose = (e & f) ^ ((~e) & g)
        let t1 = h +% big1 +% choose +% sha256_k(t) +% w[t]
        let big0 = rotr32(a, 2u32) ^ rotr32(a, 13u32) ^ rotr32(a, 22u32)
        let majority = (a & b) ^ (a & c) ^ (b & c)
        let t2 = big0 +% majority
        h = g
        g = f
        f = e
        e = d +% t1
        d = c
        c = b
        b = a
        a = t1 +% t2
        t += 1usize
    }
    s.h[0] = s.h[0] +% a
    s.h[1] = s.h[1] +% b
    s.h[2] = s.h[2] +% c
    s.h[3] = s.h[3] +% d
    s.h[4] = s.h[4] +% e
    s.h[5] = s.h[5] +% f
    s.h[6] = s.h[6] +% g
    s.h[7] = s.h[7] +% h
}

fn sha256_update(h: *Sha256, data: []const u8) {
    var at = 0usize
    while at < data.len {
        h.block[usize(h.block_len)] = data[at]
        h.block_len += 1u8
        h.total += 1u64
        if h.block_len == 64u8 {
            sha256_compress(h, h.block[0..])
            h.block_len = 0u8
        }
        at += 1usize
    }
}

fn sha256_done(h: *Sha256) -> [32]u8 {
    let bits = h.total * 8u64
    var pad: [1]u8 = [1]u8{ 128 }
    sha256_update(h, pad[0..])
    var none: [1]u8 = zero
    while h.block_len != 56u8 { sha256_update(h, none[0..]) }
    var length: [8]u8 = zero
    store_be64(length[0..], 0usize, bits)
    sha256_update(h, length[0..])
    var out: [32]u8 = zero
    var i = 0usize
    while i < 8usize {
        store_be32(out[0..], i * 4usize, h.h[i])
        i += 1usize
    }
    ret out
}

fn sha256(data: []const u8) -> [32]u8 {
    var s = sha256_init()
    sha256_update(&s, data)
    ret sha256_done(&s)
}

fn sha512_k(index: usize) -> u64 {
    let table: [80]u64 = [80]u64{
        4794697086780616226u64, 8158064640168781261u64, 13096744586834688815u64, 16840607885511220156u64, 4131703408338449720u64, 6480981068601479193u64, 10538285296894168987u64, 12329834152419229976u64,
        15566598209576043074u64, 1334009975649890238u64, 2608012711638119052u64, 6128411473006802146u64, 8268148722764581231u64, 9286055187155687089u64, 11230858885718282805u64, 13951009754708518548u64,
        16472876342353939154u64, 17275323862435702243u64, 1135362057144423861u64, 2597628984639134821u64, 3308224258029322869u64, 5365058923640841347u64, 6679025012923562964u64, 8573033837759648693u64,
        10970295158949994411u64, 12119686244451234320u64, 12683024718118986047u64, 13788192230050041572u64, 14330467153632333762u64, 15395433587784984357u64, 489312712824947311u64, 1452737877330783856u64,
        2861767655752347644u64, 3322285676063803686u64, 5560940570517711597u64, 5996557281743188959u64, 7280758554555802590u64, 8532644243296465576u64, 9350256976987008742u64, 10552545826968843579u64,
        11727347734174303076u64, 12113106623233404929u64, 14000437183269869457u64, 14369950271660146224u64, 15101387698204529176u64, 15463397548674623760u64, 17586052441742319658u64, 1182934255886127544u64,
        1847814050463011016u64, 2177327727835720531u64, 2830643537854262169u64, 3796741975233480872u64, 4115178125766777443u64, 5681478168544905931u64, 6601373596472566643u64, 7507060721942968483u64,
        8399075790359081724u64, 8693463985226723168u64, 9568029438360202098u64, 10144078919501101548u64, 10430055236837252648u64, 11840083180663258601u64, 13761210420658862357u64, 14299343276471374635u64,
        14566680578165727644u64, 15097957966210449927u64, 16922976911328602910u64, 17689382322260857208u64, 500013540394364858u64, 748580250866718886u64, 1242879168328830382u64, 1977374033974150939u64,
        2944078676154940804u64, 3659926193048069267u64, 4368137639120453308u64, 4836135668995329356u64, 5532061633213252278u64, 6448918945643986474u64, 6902733635092675308u64, 7801388544844847127u64 }
    ret table[index]
}

fn sha512_init() -> Sha512 {
    var s: Sha512 = zero
    s.h[0] = 7640891576956012808u64
    s.h[1] = 13503953896175478587u64
    s.h[2] = 4354685564936845355u64
    s.h[3] = 11912009170470909681u64
    s.h[4] = 5840696475078001361u64
    s.h[5] = 11170449401992604703u64
    s.h[6] = 2270897969802886507u64
    s.h[7] = 6620516959819538809u64
    ret s
}

fn sha512_compress(s: *Sha512, block: []const u8) {
    var w: [80]u64 = zero
    var t = 0usize
    while t < 16usize {
        w[t] = load_be64(block, t * 8usize)
        t += 1usize
    }
    while t < 80usize {
        let s0 = rotr64(w[t - 15usize], 1u32) ^ rotr64(w[t - 15usize], 8u32) ^ (w[t - 15usize] >> 7u32)
        let s1 = rotr64(w[t - 2usize], 19u32) ^ rotr64(w[t - 2usize], 61u32) ^ (w[t - 2usize] >> 6u32)
        w[t] = w[t - 16usize] +% s0 +% w[t - 7usize] +% s1
        t += 1usize
    }
    var a = s.h[0]
    var b = s.h[1]
    var c = s.h[2]
    var d = s.h[3]
    var e = s.h[4]
    var f = s.h[5]
    var g = s.h[6]
    var h = s.h[7]
    t = 0usize
    while t < 80usize {
        let big1 = rotr64(e, 14u32) ^ rotr64(e, 18u32) ^ rotr64(e, 41u32)
        let choose = (e & f) ^ ((~e) & g)
        let t1 = h +% big1 +% choose +% sha512_k(t) +% w[t]
        let big0 = rotr64(a, 28u32) ^ rotr64(a, 34u32) ^ rotr64(a, 39u32)
        let majority = (a & b) ^ (a & c) ^ (b & c)
        let t2 = big0 +% majority
        h = g
        g = f
        f = e
        e = d +% t1
        d = c
        c = b
        b = a
        a = t1 +% t2
        t += 1usize
    }
    s.h[0] = s.h[0] +% a
    s.h[1] = s.h[1] +% b
    s.h[2] = s.h[2] +% c
    s.h[3] = s.h[3] +% d
    s.h[4] = s.h[4] +% e
    s.h[5] = s.h[5] +% f
    s.h[6] = s.h[6] +% g
    s.h[7] = s.h[7] +% h
}

fn sha512_update(h: *Sha512, data: []const u8) {
    var at = 0usize
    while at < data.len {
        h.block[usize(h.block_len)] = data[at]
        h.block_len += 1u8
        h.total_lo += 1u64
        if h.total_lo == 0u64 { h.total_hi += 1u64 }
        if h.block_len == 128u8 {
            sha512_compress(h, h.block[0..])
            h.block_len = 0u8
        }
        at += 1usize
    }
}

fn sha512_done(h: *Sha512) -> [64]u8 {
    let bits_lo = h.total_lo << 3u32
    let bits_hi = (h.total_hi << 3u32) | (h.total_lo >> 61u32)
    var pad: [1]u8 = [1]u8{ 128 }
    sha512_update(h, pad[0..])
    var none: [1]u8 = zero
    while h.block_len != 112u8 { sha512_update(h, none[0..]) }
    var length: [16]u8 = zero
    store_be64(length[0..], 0usize, bits_hi)
    store_be64(length[0..], 8usize, bits_lo)
    sha512_update(h, length[0..])
    var out: [64]u8 = zero
    var i = 0usize
    while i < 8usize {
        store_be64(out[0..], i * 8usize, h.h[i])
        i += 1usize
    }
    ret out
}

fn sha512(data: []const u8) -> [64]u8 {
    var s = sha512_init()
    sha512_update(&s, data)
    ret sha512_done(&s)
}

// Keccak-f[1600]: twenty-four rounds of theta, rho, pi, chi and iota over 25 lanes.
fn keccak_round_constant(round: usize) -> u64 {
    let table: [24]u64 = [24]u64{
        1u64, 32898u64, 9223372036854808714u64, 9223372039002292224u64, 32907u64, 2147483649u64, 9223372039002292353u64, 9223372036854808585u64,
        138u64, 136u64, 2147516425u64, 2147483658u64, 2147516555u64, 9223372036854775947u64, 9223372036854808713u64, 9223372036854808579u64,
        9223372036854808578u64, 9223372036854775936u64, 32778u64, 9223372039002259466u64, 9223372039002292353u64, 9223372036854808704u64, 2147483649u64, 9223372039002292232u64 }
    ret table[round]
}

fn keccak_rho(index: usize) -> u32 {
    let table: [25]u32 = [25]u32{ 0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14 }
    ret table[index]
}

fn keccak_f(lanes: []u64) {
    var round = 0usize
    while round < 24usize {
        // theta
        var c: [5]u64 = zero
        var x = 0usize
        while x < 5usize {
            c[x] = lanes[x] ^ lanes[x + 5usize] ^ lanes[x + 10usize] ^ lanes[x + 15usize] ^ lanes[x + 20usize]
            x += 1usize
        }
        x = 0usize
        while x < 5usize {
            let d = c[(x + 4usize) % 5usize] ^ rotl64(c[(x + 1usize) % 5usize], 1u32)
            var y = 0usize
            while y < 25usize {
                lanes[y + x] = lanes[y + x] ^ d
                y += 5usize
            }
            x += 1usize
        }
        // rho and pi: lane (x, y) rotated moves to (y, 2x + 3y).
        var moved: [25]u64 = zero
        x = 0usize
        while x < 5usize {
            var y = 0usize
            while y < 5usize {
                let from = x + 5usize * y
                let to = y + 5usize * ((2usize * x + 3usize * y) % 5usize)
                moved[to] = rotl64(lanes[from], keccak_rho(from))
                y += 1usize
            }
            x += 1usize
        }
        // chi
        var y = 0usize
        while y < 25usize {
            x = 0usize
            while x < 5usize {
                lanes[y + x] = moved[y + x] ^ ((~moved[y + (x + 1usize) % 5usize]) & moved[y + (x + 2usize) % 5usize])
                x += 1usize
            }
            y += 5usize
        }
        // iota
        lanes[0] = lanes[0] ^ keccak_round_constant(round)
        round += 1usize
    }
}

// Absorbs one block of `rate` bytes into the lanes, little-endian per lane.
fn keccak_absorb(lanes: []u64, block: []const u8) {
    var lane = 0usize
    while lane * 8usize < block.len {
        var value = 0u64
        var byte = 0usize
        while byte < 8usize {
            value = value | (u64(block[lane * 8usize + byte]) << u32(byte * 8usize))
            byte += 1usize
        }
        lanes[lane] = lanes[lane] ^ value
        lane += 1usize
    }
    keccak_f(lanes)
}

fn keccak_squeeze(lanes: []const u64, out: []u8) {
    var at = 0usize
    while at < out.len {
        out[at] = u8((lanes[at / 8usize] >> u32((at % 8usize) * 8usize)) & 255u64)
        at += 1usize
    }
}

fn sha3_256_init() -> Sha3_256 {
    var s: Sha3_256 = zero
    ret s
}

fn sha3_256_update(h: *Sha3_256, data: []const u8) {
    var at = 0usize
    while at < data.len {
        h.block[usize(h.block_len)] = data[at]
        h.block_len += 1u8
        if usize(h.block_len) == 136usize {
            keccak_absorb(h.lanes[0..], h.block[0..])
            h.block_len = 0u8
        }
        at += 1usize
    }
}

fn sha3_256_done(h: *Sha3_256) -> [32]u8 {
    // The SHA-3 domain bits `01` and the pad10*1 rule together: 0x06 then 0x80 last.
    var at = usize(h.block_len)
    while at < 136usize {
        h.block[at] = 0u8
        at += 1usize
    }
    h.block[usize(h.block_len)] = h.block[usize(h.block_len)] ^ 6u8
    h.block[135] = h.block[135] ^ 128u8
    keccak_absorb(h.lanes[0..], h.block[0..])
    var out: [32]u8 = zero
    keccak_squeeze(h.lanes[0..], out[0..])
    ret out
}

fn sha3_256(data: []const u8) -> [32]u8 {
    var s = sha3_256_init()
    sha3_256_update(&s, data)
    ret sha3_256_done(&s)
}

fn sha3_512_init() -> Sha3_512 {
    var s: Sha3_512 = zero
    ret s
}

fn sha3_512_update(h: *Sha3_512, data: []const u8) {
    var at = 0usize
    while at < data.len {
        h.block[usize(h.block_len)] = data[at]
        h.block_len += 1u8
        if usize(h.block_len) == 72usize {
            keccak_absorb(h.lanes[0..], h.block[0..])
            h.block_len = 0u8
        }
        at += 1usize
    }
}

fn sha3_512_done(h: *Sha3_512) -> [64]u8 {
    var at = usize(h.block_len)
    while at < 72usize {
        h.block[at] = 0u8
        at += 1usize
    }
    h.block[usize(h.block_len)] = h.block[usize(h.block_len)] ^ 6u8
    h.block[71] = h.block[71] ^ 128u8
    keccak_absorb(h.lanes[0..], h.block[0..])
    var out: [64]u8 = zero
    keccak_squeeze(h.lanes[0..], out[0..])
    ret out
}

fn sha3_512(data: []const u8) -> [64]u8 {
    var s = sha3_512_init()
    sha3_512_update(&s, data)
    ret sha3_512_done(&s)
}

// Merkle-Damgard padding shared by the two legacy digests: 0x80, zeros to 56 mod 64,
// then the bit length in the byte order each wants.
fn legacy_padded_len(length: usize) -> usize {
    var padded = length + 1usize
    while padded % 64usize != 56usize { padded += 1usize }
    ret padded + 8usize
}

fn legacy_sha1(data: []const u8) -> [20]u8 {
    var h0 = 1732584193u32
    var h1 = 4023233417u32
    var h2 = 2562383102u32
    var h3 = 271733878u32
    var h4 = 3285377520u32
    let total = legacy_padded_len(data.len)
    var block: [64]u8 = zero
    var offset = 0usize
    while offset < total {
        var i = 0usize
        while i < 64usize {
            let at = offset + i
            var byte = 0u8
            if at < data.len { byte = data[at] }
            if at == data.len { byte = 128u8 }
            if at >= total - 8usize { byte = u8(((u64(data.len) * 8u64) >> u32((total - 1usize - at) * 8usize)) & 255u64) }
            block[i] = byte
            i += 1usize
        }
        var w: [80]u32 = zero
        i = 0usize
        while i < 16usize {
            w[i] = load_be32(block[0..], i * 4usize)
            i += 1usize
        }
        while i < 80usize {
            w[i] = rotl32(w[i - 3usize] ^ w[i - 8usize] ^ w[i - 14usize] ^ w[i - 16usize], 1u32)
            i += 1usize
        }
        var a = h0
        var b = h1
        var c = h2
        var d = h3
        var e = h4
        i = 0usize
        while i < 80usize {
            var f = 0u32
            var k = 0u32
            if i < 20usize {
                f = (b & c) | ((~b) & d)
                k = 1518500249u32
            } else {
                if i < 40usize {
                    f = b ^ c ^ d
                    k = 1859775393u32
                } else {
                    if i < 60usize {
                        f = (b & c) | (b & d) | (c & d)
                        k = 2400959708u32
                    } else {
                        f = b ^ c ^ d
                        k = 3395469782u32
                    }
                }
            }
            let temp = rotl32(a, 5u32) +% f +% e +% k +% w[i]
            e = d
            d = c
            c = rotl32(b, 30u32)
            b = a
            a = temp
            i += 1usize
        }
        h0 = h0 +% a
        h1 = h1 +% b
        h2 = h2 +% c
        h3 = h3 +% d
        h4 = h4 +% e
        offset += 64usize
    }
    var out: [20]u8 = zero
    store_be32(out[0..], 0usize, h0)
    store_be32(out[0..], 4usize, h1)
    store_be32(out[0..], 8usize, h2)
    store_be32(out[0..], 12usize, h3)
    store_be32(out[0..], 16usize, h4)
    ret out
}

fn md5_k(index: usize) -> u32 {
    let table: [64]u32 = [64]u32{
        3614090360u32, 3905402710u32, 606105819u32, 3250441966u32, 4118548399u32, 1200080426u32, 2821735955u32, 4249261313u32,
        1770035416u32, 2336552879u32, 4294925233u32, 2304563134u32, 1804603682u32, 4254626195u32, 2792965006u32, 1236535329u32,
        4129170786u32, 3225465664u32, 643717713u32, 3921069994u32, 3593408605u32, 38016083u32, 3634488961u32, 3889429448u32,
        568446438u32, 3275163606u32, 4107603335u32, 1163531501u32, 2850285829u32, 4243563512u32, 1735328473u32, 2368359562u32,
        4294588738u32, 2272392833u32, 1839030562u32, 4259657740u32, 2763975236u32, 1272893353u32, 4139469664u32, 3200236656u32,
        681279174u32, 3936430074u32, 3572445317u32, 76029189u32, 3654602809u32, 3873151461u32, 530742520u32, 3299628645u32,
        4096336452u32, 1126891415u32, 2878612391u32, 4237533241u32, 1700485571u32, 2399980690u32, 4293915773u32, 2240044497u32,
        1873313359u32, 4264355552u32, 2734768916u32, 1309151649u32, 4149444226u32, 3174756917u32, 718787259u32, 3951481745u32 }
    ret table[index]
}

fn md5_shift(index: usize) -> u32 {
    let table: [64]u32 = [64]u32{
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21 }
    ret table[index]
}

fn legacy_md5(data: []const u8) -> [16]u8 {
    var a0 = 1732584193u32
    var b0 = 4023233417u32
    var c0 = 2562383102u32
    var d0 = 271733878u32
    let total = legacy_padded_len(data.len)
    var block: [64]u8 = zero
    var offset = 0usize
    while offset < total {
        var i = 0usize
        while i < 64usize {
            let at = offset + i
            var byte = 0u8
            if at < data.len { byte = data[at] }
            if at == data.len { byte = 128u8 }
            if at >= total - 8usize { byte = u8(((u64(data.len) * 8u64) >> u32((at - (total - 8usize)) * 8usize)) & 255u64) }
            block[i] = byte
            i += 1usize
        }
        var m: [16]u32 = zero
        i = 0usize
        while i < 16usize {
            m[i] = u32(block[i * 4usize]) | (u32(block[i * 4usize + 1usize]) << 8u32) | (u32(block[i * 4usize + 2usize]) << 16u32) | (u32(block[i * 4usize + 3usize]) << 24u32)
            i += 1usize
        }
        var a = a0
        var b = b0
        var c = c0
        var d = d0
        i = 0usize
        while i < 64usize {
            var f = 0u32
            var g = 0usize
            if i < 16usize {
                f = (b & c) | ((~b) & d)
                g = i
            } else {
                if i < 32usize {
                    f = (d & b) | ((~d) & c)
                    g = (5usize * i + 1usize) % 16usize
                } else {
                    if i < 48usize {
                        f = b ^ c ^ d
                        g = (3usize * i + 5usize) % 16usize
                    } else {
                        f = c ^ (b | (~d))
                        g = (7usize * i) % 16usize
                    }
                }
            }
            let mixed = f +% a +% md5_k(i) +% m[g]
            a = d
            d = c
            c = b
            b = b +% rotl32(mixed, md5_shift(i))
            i += 1usize
        }
        a0 = a0 +% a
        b0 = b0 +% b
        c0 = c0 +% c
        d0 = d0 +% d
        offset += 64usize
    }
    var out: [16]u8 = zero
    var words: [4]u32 = [4]u32{ a0, b0, c0, d0 }
    var w = 0usize
    while w < 4usize {
        out[w * 4usize] = u8(words[w] & 255u32)
        out[w * 4usize + 1usize] = u8((words[w] >> 8u32) & 255u32)
        out[w * 4usize + 2usize] = u8((words[w] >> 16u32) & 255u32)
        out[w * 4usize + 3usize] = u8(words[w] >> 24u32)
        w += 1usize
    }
    ret out
}

// Every byte is compared whatever the earlier ones said, so the time taken tells
// nothing about where two digests first differ.
fn equal_constant_time(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var difference = 0u8
    var at = 0usize
    while at < a.len {
        difference = difference | (a[at] ^ b[at])
        at += 1usize
    }
    ret difference == 0u8
}
