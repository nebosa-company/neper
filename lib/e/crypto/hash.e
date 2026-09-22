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

// BLAKE2b (RFC 7693): twelve rounds of the 64-bit G over 128-byte blocks, the SHA-512
// initial values as its IV, a digest of 1..64 bytes and an optional key of at most 64
// bytes that is absorbed as a padded first block. The streaming form mirrors SHA-2's;
// `blake2b_init` takes the digest length and the key so Argon2's H' can ask for a
// short digest.

type Blake2b = struct { h: [8]u64, t_lo: u64, t_hi: u64, block: [128]u8, block_len: usize, out_len: usize }

fn blake2b_sigma(round: usize, i: usize) -> usize {
    let table: [160]u8 = [160]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3, 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4, 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8, 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13, 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9, 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11, 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10, 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5, 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 }
    ret usize(table[(round % 10usize) * 16usize + i])
}

fn load_le64(bytes: []const u8, at: usize) -> u64 {
    var value = 0u64
    var i = 0usize
    while i < 8usize {
        value = value | (u64(bytes[at + i]) << u32(i * 8usize))
        i += 1usize
    }
    ret value
}

fn blake2b_g(v: []u64, a: usize, b: usize, c: usize, d: usize, x: u64, y: u64) {
    v[a] = v[a] +% v[b] +% x
    v[d] = rotr64(v[d] ^ v[a], 32u32)
    v[c] = v[c] +% v[d]
    v[b] = rotr64(v[b] ^ v[c], 24u32)
    v[a] = v[a] +% v[b] +% y
    v[d] = rotr64(v[d] ^ v[a], 16u32)
    v[c] = v[c] +% v[d]
    v[b] = rotr64(v[b] ^ v[c], 63u32)
}

fn blake2b_compress(s: *Blake2b, last: bool) {
    var m: [16]u64 = zero
    var i = 0usize
    while i < 16usize {
        m[i] = load_le64(s.block[0..], i * 8usize)
        i += 1usize
    }
    let iv = sha512_init()
    var v: [16]u64 = zero
    i = 0usize
    while i < 8usize {
        v[i] = s.h[i]
        v[i + 8usize] = iv.h[i]
        i += 1usize
    }
    v[12] = v[12] ^ s.t_lo
    v[13] = v[13] ^ s.t_hi
    if last { v[14] = ~v[14] }
    var round = 0usize
    while round < 12usize {
        blake2b_g(v[0..], 0usize, 4usize, 8usize, 12usize, m[blake2b_sigma(round, 0usize)], m[blake2b_sigma(round, 1usize)])
        blake2b_g(v[0..], 1usize, 5usize, 9usize, 13usize, m[blake2b_sigma(round, 2usize)], m[blake2b_sigma(round, 3usize)])
        blake2b_g(v[0..], 2usize, 6usize, 10usize, 14usize, m[blake2b_sigma(round, 4usize)], m[blake2b_sigma(round, 5usize)])
        blake2b_g(v[0..], 3usize, 7usize, 11usize, 15usize, m[blake2b_sigma(round, 6usize)], m[blake2b_sigma(round, 7usize)])
        blake2b_g(v[0..], 0usize, 5usize, 10usize, 15usize, m[blake2b_sigma(round, 8usize)], m[blake2b_sigma(round, 9usize)])
        blake2b_g(v[0..], 1usize, 6usize, 11usize, 12usize, m[blake2b_sigma(round, 10usize)], m[blake2b_sigma(round, 11usize)])
        blake2b_g(v[0..], 2usize, 7usize, 8usize, 13usize, m[blake2b_sigma(round, 12usize)], m[blake2b_sigma(round, 13usize)])
        blake2b_g(v[0..], 3usize, 4usize, 9usize, 14usize, m[blake2b_sigma(round, 14usize)], m[blake2b_sigma(round, 15usize)])
        round += 1usize
    }
    i = 0usize
    while i < 8usize {
        s.h[i] = s.h[i] ^ v[i] ^ v[i + 8usize]
        i += 1usize
    }
}

// A BLAKE2b state for `out_len` bytes (1..64) of digest; a non-empty `key` (at most 64
// bytes) makes the keyed variant, which is BLAKE2b's own MAC.
fn blake2b_init(out_len: usize, key: []const u8) -> Blake2b {
    var s: Blake2b = zero
    let iv = sha512_init()
    var i = 0usize
    while i < 8usize {
        s.h[i] = iv.h[i]
        i += 1usize
    }
    s.h[0] = s.h[0] ^ 16842752u64 ^ u64(out_len & 255usize) ^ (u64(key.len & 255usize) << 8u32)
    s.out_len = out_len
    if key.len > 0usize {
        var padded: [128]u8 = zero
        i = 0usize
        while i < key.len {
            padded[i] = key[i]
            i += 1usize
        }
        blake2b_update(&s, padded[0..])
    }
    ret s
}

fn blake2b_update(s: *Blake2b, bytes: []const u8) {
    var i = 0usize
    while i < bytes.len {
        if s.block_len == 128usize {
            s.t_lo += 128u64
            if s.t_lo < 128u64 { s.t_hi += 1u64 }
            blake2b_compress(s, false)
            s.block_len = 0usize
        }
        s.block[s.block_len] = bytes[i]
        s.block_len += 1usize
        i += 1usize
    }
}

// The digest in the first `out_len` bytes of the answer; the state is spent.
fn blake2b_done(s: *Blake2b) -> [64]u8 {
    s.t_lo += u64(s.block_len)
    if s.t_lo < u64(s.block_len) { s.t_hi += 1u64 }
    while s.block_len < 128usize {
        s.block[s.block_len] = 0u8
        s.block_len += 1usize
    }
    blake2b_compress(s, true)
    var out: [64]u8 = zero
    var i = 0usize
    while i < s.out_len {
        out[i] = u8((s.h[i / 8usize] >> u32((i % 8usize) * 8usize)) & 255u64)
        i += 1usize
    }
    ret out
}

fn blake2b(data: []const u8) -> [64]u8 {
    let none: [0]u8 = zero
    var s = blake2b_init(64usize, none[0..])
    blake2b_update(&s, data)
    ret blake2b_done(&s)
}

fn blake2b_keyed(key: []const u8, data: []const u8) -> [64]u8 {
    var s = blake2b_init(64usize, key)
    blake2b_update(&s, data)
    ret blake2b_done(&s)
}

// --- BLAKE3 by the specification's reference implementation: 1024-byte chunks of
// sixteen 64-byte blocks through the seven-round compression, chunk chaining values
// merged up a binary tree by a stack of at most 54 subtree values, and the root
// output extended by counter for any length. The same state serves the plain, keyed
// and derive-key modes, which differ only in the key words and the domain flags.
// ponytail: chunks are compressed one at a time in order; the tree structure
// permits parallel chunk hashing, and that is the upgrade for large inputs.
type Blake3 = struct { key: [8]u32, cv: [8]u32, chunk_counter: u64, block: [64]u8, block_len: usize, blocks_compressed: usize, flags: u32, stack: [432]u32, stack_len: usize }
type Blake3Output = struct { cv: [8]u32, block: [16]u32, counter: u64, block_len: u32, flags: u32 }

fn blake3_iv(index: usize) -> u32 {
    let iv: [8]u32 = [8]u32{ 1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225 }
    ret iv[index]
}

fn blake3_word(bytes: []const u8, at: usize) -> u32 {
    let low = u32(bytes[at]) | (u32(bytes[at + 1usize]) << 8u32)
    ret low | (u32(bytes[at + 2usize]) << 16u32) | (u32(bytes[at + 3usize]) << 24u32)
}

fn blake3_words(bytes: []const u8) -> [16]u32 {
    var words: [16]u32 = zero
    var i = 0usize
    while i < 16usize {
        words[i] = blake3_word(bytes, i * 4usize)
        i += 1usize
    }
    ret words
}

fn blake3_g(state: []u32, a: usize, b: usize, c: usize, d: usize, mx: u32, my: u32) {
    state[a] = state[a] +% state[b] +% mx
    state[d] = rotr32(state[d] ^ state[a], 16u32)
    state[c] = state[c] +% state[d]
    state[b] = rotr32(state[b] ^ state[c], 12u32)
    state[a] = state[a] +% state[b] +% my
    state[d] = rotr32(state[d] ^ state[a], 8u32)
    state[c] = state[c] +% state[d]
    state[b] = rotr32(state[b] ^ state[c], 7u32)
}

fn blake3_round(state: []u32, m: []const u32) {
    blake3_g(state, 0usize, 4usize, 8usize, 12usize, m[0], m[1])
    blake3_g(state, 1usize, 5usize, 9usize, 13usize, m[2], m[3])
    blake3_g(state, 2usize, 6usize, 10usize, 14usize, m[4], m[5])
    blake3_g(state, 3usize, 7usize, 11usize, 15usize, m[6], m[7])
    blake3_g(state, 0usize, 5usize, 10usize, 15usize, m[8], m[9])
    blake3_g(state, 1usize, 6usize, 11usize, 12usize, m[10], m[11])
    blake3_g(state, 2usize, 7usize, 8usize, 13usize, m[12], m[13])
    blake3_g(state, 3usize, 4usize, 9usize, 14usize, m[14], m[15])
}

fn blake3_compress(cv: [8]u32, block: [16]u32, counter: u64, block_len: u32, flags: u32) -> [16]u32 {
    var state: [16]u32 = zero
    var i = 0usize
    while i < 8usize {
        state[i] = cv[i]
        i += 1usize
    }
    state[8] = blake3_iv(0usize)
    state[9] = blake3_iv(1usize)
    state[10] = blake3_iv(2usize)
    state[11] = blake3_iv(3usize)
    state[12] = u32(counter & 4294967295u64)
    state[13] = u32(counter >> 32u32)
    state[14] = block_len
    state[15] = flags
    let permutation: [16]usize = [16]usize{ 2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8 }
    var m = block
    var round = 0usize
    while round < 7usize {
        blake3_round(state[0..], m[0..])
        var permuted: [16]u32 = zero
        i = 0usize
        while i < 16usize {
            permuted[i] = m[permutation[i]]
            i += 1usize
        }
        m = permuted
        round += 1usize
    }
    i = 0usize
    while i < 8usize {
        state[i] = state[i] ^ state[i + 8usize]
        state[i + 8usize] = state[i + 8usize] ^ cv[i]
        i += 1usize
    }
    ret state
}

fn blake3_output_cv(o: Blake3Output) -> [8]u32 {
    let words = blake3_compress(o.cv, o.block, o.counter, o.block_len, o.flags)
    var cv: [8]u32 = zero
    var i = 0usize
    while i < 8usize {
        cv[i] = words[i]
        i += 1usize
    }
    ret cv
}

// The root output: 64 bytes per counter value, as many as `out` takes.
fn blake3_output_root(o: Blake3Output, out: []u8) {
    var at = 0usize
    var counter = 0u64
    while at < out.len {
        let words = blake3_compress(o.cv, o.block, counter, o.block_len, o.flags | 8u32)
        var i = 0usize
        while i < 64usize && at < out.len {
            out[at] = u8((words[i / 4usize] >> u32((i % 4usize) * 8usize)) & 255u32)
            at += 1usize
            i += 1usize
        }
        counter += 1u64
    }
}

fn blake3_start_flag(h: *Blake3) -> u32 {
    if h.blocks_compressed == 0usize { ret 1u32 }
    ret 0u32
}

// The current chunk's output node, with CHUNK_END set.
fn blake3_chunk_output(h: *Blake3) -> Blake3Output {
    var o: Blake3Output = zero
    o.cv = h.cv
    o.block = blake3_words(h.block[0..])
    o.counter = h.chunk_counter
    o.block_len = u32(h.block_len)
    o.flags = h.flags | blake3_start_flag(h) | 2u32
    ret o
}

fn blake3_parent(left: [8]u32, right: [8]u32, key: [8]u32, flags: u32) -> Blake3Output {
    var o: Blake3Output = zero
    o.cv = key
    var i = 0usize
    while i < 8usize {
        o.block[i] = left[i]
        o.block[8usize + i] = right[i]
        i += 1usize
    }
    o.counter = 0u64
    o.block_len = 64u32
    o.flags = flags | 4u32
    ret o
}

fn blake3_stack_get(h: *Blake3, index: usize) -> [8]u32 {
    var cv: [8]u32 = zero
    var i = 0usize
    while i < 8usize {
        cv[i] = h.stack[index * 8usize + i]
        i += 1usize
    }
    ret cv
}

fn blake3_stack_push(h: *Blake3, cv: [8]u32) {
    var i = 0usize
    while i < 8usize {
        h.stack[h.stack_len * 8usize + i] = cv[i]
        i += 1usize
    }
    h.stack_len += 1usize
}

// A finished chunk's value joins the stack, merging with its left siblings for every
// trailing zero bit of the chunk count.
fn blake3_add_chunk_cv(h: *Blake3, cv_in: [8]u32, total_chunks: u64) {
    var cv = cv_in
    var remaining = total_chunks
    while (remaining & 1u64) == 0u64 {
        h.stack_len -= 1usize
        cv = blake3_output_cv(blake3_parent(blake3_stack_get(h, h.stack_len), cv, h.key, h.flags))
        remaining = remaining >> 1u32
    }
    blake3_stack_push(h, cv)
}

fn blake3_init_with(key: [8]u32, flags: u32) -> Blake3 {
    var h: Blake3 = zero
    h.key = key
    h.cv = key
    h.flags = flags
    ret h
}

fn blake3_init() -> Blake3 {
    var key: [8]u32 = zero
    var i = 0usize
    while i < 8usize {
        key[i] = blake3_iv(i)
        i += 1usize
    }
    ret blake3_init_with(key, 0u32)
}

fn blake3_key_words(key: [32]u8) -> [8]u32 {
    var words: [8]u32 = zero
    var i = 0usize
    while i < 8usize {
        words[i] = blake3_word(key[0..], i * 4usize)
        i += 1usize
    }
    ret words
}

fn blake3_keyed_init(key: [32]u8) -> Blake3 { ret blake3_init_with(blake3_key_words(key), 16u32) }

// Derive-key mode: the context string is hashed in DERIVE_KEY_CONTEXT mode and its
// 32-byte digest keys the DERIVE_KEY_MATERIAL hasher.
fn blake3_derive_key_init(context: []const u8) -> Blake3 {
    var iv: [8]u32 = zero
    var i = 0usize
    while i < 8usize {
        iv[i] = blake3_iv(i)
        i += 1usize
    }
    var context_hasher = blake3_init_with(iv, 32u32)
    blake3_update(&context_hasher, context)
    var context_key: [32]u8 = zero
    blake3_done(&context_hasher, context_key[0..])
    ret blake3_init_with(blake3_key_words(context_key), 64u32)
}

// The output node reads all sixteen words of the buffer, so a compressed block is cleared.
fn blake3_clear_block(h: *Blake3) {
    var i = 0usize
    while i < 64usize {
        h.block[i] = 0u8
        i += 1usize
    }
}

fn blake3_update(h: *Blake3, data: []const u8) {
    var at = 0usize
    while at < data.len {
        if h.blocks_compressed * 64usize + h.block_len == 1024usize {
            let chunk_cv = blake3_output_cv(blake3_chunk_output(h))
            let total_chunks = h.chunk_counter + 1u64
            blake3_add_chunk_cv(h, chunk_cv, total_chunks)
            h.cv = h.key
            h.chunk_counter = total_chunks
            h.block_len = 0usize
            h.blocks_compressed = 0usize
            blake3_clear_block(h)
        }
        if h.block_len == 64usize {
            let words = blake3_compress(h.cv, blake3_words(h.block[0..]), h.chunk_counter, 64u32, h.flags | blake3_start_flag(h))
            var i = 0usize
            while i < 8usize {
                h.cv[i] = words[i]
                i += 1usize
            }
            h.blocks_compressed += 1usize
            h.block_len = 0usize
            blake3_clear_block(h)
        }
        var take = 64usize - h.block_len
        if take > data.len - at { take = data.len - at }
        var i = 0usize
        while i < take {
            h.block[h.block_len + i] = data[at + i]
            i += 1usize
        }
        h.block_len += take
        at += take
    }
}

// Fills `out` with the root output; the state is left intact and may take more data.
fn blake3_done(h: *Blake3, out: []u8) {
    var o = blake3_chunk_output(h)
    var remaining = h.stack_len
    while remaining > 0usize {
        remaining -= 1usize
        o = blake3_parent(blake3_stack_get(h, remaining), blake3_output_cv(o), h.key, h.flags)
    }
    blake3_output_root(o, out)
}

fn blake3(data: []const u8) -> [32]u8 {
    var h = blake3_init()
    blake3_update(&h, data)
    var out: [32]u8 = zero
    blake3_done(&h, out[0..])
    ret out
}

fn blake3_xof(data: []const u8, out: []u8) {
    var h = blake3_init()
    blake3_update(&h, data)
    blake3_done(&h, out)
}

fn blake3_keyed(key: [32]u8, data: []const u8) -> [32]u8 {
    var h = blake3_keyed_init(key)
    blake3_update(&h, data)
    var out: [32]u8 = zero
    blake3_done(&h, out[0..])
    ret out
}

fn blake3_derive_key(context: []const u8, key_material: []const u8, out: []u8) {
    var h = blake3_derive_key_init(context)
    blake3_update(&h, key_material)
    blake3_done(&h, out)
}

// SHAKE128 and SHAKE256 (FIPS 202 section 6.2): the same Keccak-f[1600] with rates 168
// and 136, domain bits `1111` (0x1F then 0x80), and a squeeze that may run past one
// block. `shake_absorb` is refused silently once squeezing has begun.
type Shake = struct { lanes: [25]u64, block: [168]u8, block_len: usize, rate: usize, offset: usize, squeezing: bool }

fn shake128_init() -> Shake {
    var s: Shake = zero
    s.rate = 168usize
    ret s
}

fn shake256_init() -> Shake {
    var s: Shake = zero
    s.rate = 136usize
    ret s
}

fn shake_absorb(s: *Shake, data: []const u8) {
    if s.squeezing { ret }
    var at = 0usize
    while at < data.len {
        s.block[s.block_len] = data[at]
        s.block_len += 1usize
        if s.block_len == s.rate {
            keccak_absorb(s.lanes[0..], s.block[0..s.rate])
            s.block_len = 0usize
        }
        at += 1usize
    }
}

fn shake_squeeze(s: *Shake, out: []u8) {
    if !s.squeezing {
        var at = s.block_len
        while at < s.rate {
            s.block[at] = 0u8
            at += 1usize
        }
        s.block[s.block_len] = s.block[s.block_len] ^ 31u8
        s.block[s.rate - 1usize] = s.block[s.rate - 1usize] ^ 128u8
        keccak_absorb(s.lanes[0..], s.block[0..s.rate])
        s.squeezing = true
        s.offset = 0usize
    }
    var at = 0usize
    while at < out.len {
        if s.offset == s.rate {
            keccak_f(s.lanes[0..])
            s.offset = 0usize
        }
        out[at] = u8((s.lanes[s.offset / 8usize] >> u32((s.offset % 8usize) * 8usize)) & 255u64)
        s.offset += 1usize
        at += 1usize
    }
}

fn shake128(data: []const u8, out: []u8) {
    var s = shake128_init()
    shake_absorb(&s, data)
    shake_squeeze(&s, out)
}

fn shake256(data: []const u8, out: []u8) {
    var s = shake256_init()
    shake_absorb(&s, data)
    shake_squeeze(&s, out)
}
