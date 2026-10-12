// C098: AES-GCM in hardware. e.crypto.aead seals and opens through AES-NI and PCLMULQDQ
// (os.aes_expand_key, os.aes_ctr, os.ghash_blocks) when os.cpu_features() has them and
// through the bitsliced portable path otherwise; this checks the two against each other over
// every length that crosses a block, a four-block step and a short tail, at all three key
// sizes, and the three intrinsics against independent references: the byte-oriented AES of
// e.crypto.cipher's block function and a bit-at-a-time GF(2^128) product. The tags themselves
// are pinned to OpenSSL by link/crypto_aead. Every check has its own exit code.
use e.os
use e.mem
use e.crypto.aead as aead

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn fill(buf: []u8, seed: usize) {
    var i = 0usize
    while i < buf.len {
        buf[i] = u8(((i + seed) * 131usize + (i / 7usize) * 17usize + seed * 3usize + 11usize) % 256usize)
        i += 1usize
    }
}

// The 128-bit GCM product by shifting, bit 0 the most significant (NIST SP 800-38D 6.3).
fn gf_mul(xh: u64, xl: u64, yh: u64, yl: u64) -> (u64, u64) {
    var zh = 0u64
    var zl = 0u64
    var vh = yh
    var vl = yl
    var i = 0usize
    while i < 128usize {
        var bit = 0u64
        if i < 64usize { bit = (xh >> u32(63usize - i)) & 1u64 } else { bit = (xl >> u32(127usize - i)) & 1u64 }
        if bit == 1u64 {
            zh = zh ^ vh
            zl = zl ^ vl
        }
        let lsb = vl & 1u64
        vl = (vl >> 1u32) | (vh << 63u32)
        vh = vh >> 1u32
        if lsb == 1u64 { vh = vh ^ 16212958658533785600u64 }
        i += 1usize
    }
    ret (zh, zl)
}

fn be64(b: []const u8, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v = (v << 8u32) | u64(b[at + i])
        i += 1usize
    }
    ret v
}

fn put_be64(b: []u8, at: usize, v: u64) {
    var i = 0usize
    while i < 8usize {
        b[at + i] = u8((v >> u32((7usize - i) * 8usize)) & 255u64)
        i += 1usize
    }
}

// Seal and open under both paths, cross-open, and tamper.
fn gcm_matches(a: *mem.Arena, key_len: usize, n: usize, aad_len: usize) -> i32 {
    var key: [32]u8 = zero
    var nonce: [12]u8 = zero
    var aad: [48]u8 = zero
    fill(key[0..], key_len + 1usize)
    fill(nonce[0..], n + 5usize)
    fill(aad[0..], aad_len + 9usize)
    let (plain, plain_error) = mem.alloc[u8](a, n + 1usize)
    let (hw, hw_error) = mem.alloc[u8](a, n + 17usize)
    let (soft, soft_error) = mem.alloc[u8](a, n + 17usize)
    let (back, back_error) = mem.alloc[u8](a, n + 1usize)
    if plain_error != ok || hw_error != ok || soft_error != ok || back_error != ok { ret 90i32 }
    fill(plain[0..], n)
    let k = key[..key_len]
    let ad = aad[..aad_len]
    let (h1, e1) = aead.gcm_seal(hw, k, nonce, ad, plain[..n])
    let (s1, e2) = aead.gcm_seal_portable(soft, k, nonce, ad, plain[..n])
    if e1 != ok || e2 != ok || h1 != n + 16usize || s1 != n + 16usize { ret 10i32 }
    if !same(hw[..h1], soft[..s1]) { ret 11i32 }
    let (b1, e3) = aead.gcm_open(back, k, nonce, ad, soft[..s1])
    if e3 != ok || b1 != n || !same(back[..n], plain[..n]) { ret 12i32 }
    let (b2, e4) = aead.gcm_open_portable(back, k, nonce, ad, hw[..h1])
    if e4 != ok || b2 != n || !same(back[..n], plain[..n]) { ret 13i32 }
    // in place: dst is the plaintext's own buffer
    fill(hw[0..n], n)
    let (h2, e5) = aead.gcm_seal(hw, k, nonce, ad, hw[..n])
    if e5 != ok || h2 != n + 16usize || !same(hw[..h2], soft[..s1]) { ret 14i32 }
    // a flipped ciphertext byte, a flipped tag bit and a flipped aad byte are refused
    if n > 0usize {
        let at = (n * 5usize) / 7usize
        soft[at] = soft[at] ^ 4u8
        let (_, e6) = aead.gcm_open(back, k, nonce, ad, soft[..s1])
        soft[at] = soft[at] ^ 4u8
        if e6 == ok { ret 15i32 }
    }
    soft[n + 3usize] = soft[n + 3usize] ^ 128u8
    let (_, e7) = aead.gcm_open(back, k, nonce, ad, soft[..s1])
    soft[n + 3usize] = soft[n + 3usize] ^ 128u8
    if e7 == ok { ret 16i32 }
    if aad_len > 0usize {
        aad[0] = aad[0] ^ 1u8
        let (_, e8) = aead.gcm_open(back, k, nonce, aad[..aad_len], soft[..s1])
        if e8 == ok { ret 17i32 }
    }
    ret 0i32
}

fn lengths_checked(a: *mem.Arena) -> i32 {
    let sizes: [3]usize = [3]usize{ 16, 24, 32 }
    let aads: [6]usize = [6]usize{ 0, 1, 13, 16, 17, 40 }
    var s = 0usize
    while s < 3usize {
        var n = 0usize
        while n < 150usize {
            let code = gcm_matches(a, sizes[s], n, aads[(n + s) % 6usize])
            if code != 0i32 { ret code }
            n += 1usize
        }
        let big: [8]usize = [8]usize{ 255, 256, 257, 1000, 4095, 4096, 4097, 16385 }
        var j = 0usize
        while j < 8usize {
            var m = 0usize
            while m < 2usize {
                let code = gcm_matches(a, sizes[s], big[j], aads[(j + m * 3usize) % 6usize])
                if code != 0i32 { ret code }
                m += 1usize
            }
            j += 1usize
        }
        s += 1usize
    }
    ret 0i32
}

// The intrinsics against the byte-oriented AES and the shifting product.
fn primitives(a: *mem.Arena, cpu: usize) -> i32 {
    // Without the feature bits every one answers none and touches nothing.
    var probe_key: [16]u8 = zero
    var probe_out: [240]u8 = zero
    if os.aes_expand_key(0usize, probe_key[0..], probe_out[0..]) != 0usize { ret 20i32 }
    var probe_counter: [16]u8 = zero
    var probe_data: [32]u8 = zero
    probe_data[5] = 9u8
    if os.aes_ctr(0usize, probe_out[..176], probe_counter[0..], probe_data[0..]) != 0usize || probe_data[5] != 9u8 { ret 21i32 }
    var probe_state: [16]u8 = zero
    if os.ghash_blocks(0usize, probe_state[0..], probe_key[0..], probe_data[0..]) != 0usize { ret 22i32 }
    if (cpu & 34079234usize) != 34079234usize { ret 0i32 }
    // The schedule: 128 and 256 against expand_key, 192 declined, a short `out` declined.
    var k: [32]u8 = zero
    var s = 0usize
    while s < 3usize {
        let key_len = 16usize + 8usize * s
        fill(k[0..], 40usize + s)
        let want = aead.expand_key(k[..key_len])
        let bytes = (want.rounds + 1usize) * 16usize
        var got: [240]u8 = zero
        let done = os.aes_expand_key(cpu, k[..key_len], got[0..])
        if key_len == 24usize {
            if done != 0usize { ret 23i32 }
        } else {
            if done != bytes || !same(got[..bytes], want.round_keys[..bytes]) { ret 24i32 }
            if os.aes_expand_key(cpu, k[..key_len], got[..bytes - 1usize]) != 0usize { ret 25i32 }
        }
        s += 1usize
    }
    // Counter mode: the counter wraps at 2^32 and stays in its last four bytes, whole blocks
    // only, and the byte-oriented block function agrees.
    var key: [16]u8 = zero
    fill(key[0..], 77usize)
    let sched = aead.expand_key(key[0..])
    var rk: [176]u8 = zero
    if os.aes_expand_key(cpu, key[0..], rk[0..]) != 176usize { ret 26i32 }
    var counter: [16]u8 = zero
    fill(counter[0..], 3usize)
    counter[12] = 255u8
    counter[13] = 255u8
    counter[14] = 255u8
    counter[15] = 253u8
    var first: [16]u8 = zero
    var i = 0usize
    while i < 16usize {
        first[i] = counter[i]
        i += 1usize
    }
    var data: [171]u8 = zero
    fill(data[0..], 5usize)
    var want: [171]u8 = zero
    i = 0usize
    while i < 171usize {
        want[i] = data[i]
        i += 1usize
    }
    var block: [16]u8 = zero
    var b = 0usize
    while b < 10usize {
        i = 0usize
        while i < 16usize {
            block[i] = first[i]
            i += 1usize
        }
        let c = ((u32(first[12]) << 24u32) | (u32(first[13]) << 16u32) | (u32(first[14]) << 8u32) | u32(first[15])) +% u32(b)
        block[12] = u8(c >> 24u32)
        block[13] = u8((c >> 16u32) & 255u32)
        block[14] = u8((c >> 8u32) & 255u32)
        block[15] = u8(c & 255u32)
        aead.aes_encrypt_block(&sched, block[0..])
        i = 0usize
        while i < 16usize {
            want[b * 16usize + i] = want[b * 16usize + i] ^ block[i]
            i += 1usize
        }
        b += 1usize
    }
    // 171 bytes: ten whole blocks and eleven left alone
    let done = os.aes_ctr(cpu, rk[0..], counter[0..], data[0..])
    if done != 10usize || !same(data[0..], want[0..]) { ret 27i32 }
    if counter[12] != 0u8 || counter[13] != 0u8 || counter[14] != 0u8 || counter[15] != 7u8 { ret 28i32 }
    if counter[0] != first[0] || counter[11] != first[11] { ret 29i32 }
    // GHASH: n blocks folded into a state, against the shifting product.
    let counts: [7]usize = [7]usize{ 1, 2, 3, 4, 5, 8, 11 }
    var c = 0usize
    while c < 7usize {
        let n = counts[c]
        let (blocks, blocks_error) = mem.alloc[u8](a, n * 16usize)
        if blocks_error != ok { ret 90i32 }
        fill(blocks[0..], 100usize + n)
        var h: [16]u8 = zero
        var st: [16]u8 = zero
        fill(h[0..], 200usize + n)
        fill(st[0..], 300usize + n)
        var yh = be64(st[0..], 0usize)
        var yl = be64(st[0..], 8usize)
        let hh = be64(h[0..], 0usize)
        let hl = be64(h[0..], 8usize)
        var j = 0usize
        while j < n {
            let (mh, ml) = gf_mul(yh ^ be64(blocks[0..], j * 16usize), yl ^ be64(blocks[0..], j * 16usize + 8usize), hh, hl)
            yh = mh
            yl = ml
            j += 1usize
        }
        if os.ghash_blocks(cpu, st[0..], h[0..], blocks[0..]) != n { ret 30i32 }
        var ref: [16]u8 = zero
        put_be64(ref[0..], 0usize, yh)
        put_be64(ref[0..], 8usize, yl)
        if !same(st[0..], ref[0..]) { ret 31i32 }
        c += 1usize
    }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let cpu = os.cpu_features()
    let p = primitives(a, cpu)
    if p != 0i32 { os.exit(p) }
    let code = lengths_checked(a)
    if code != 0i32 { os.exit(code) }
    ret ok
}
