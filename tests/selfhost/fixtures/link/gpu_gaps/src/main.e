// `e.gpu` sort and attention: `sort_bitonic` over 1024 LCG keys is one launch per
// (stage, pass) -- 55 submissions -- and answers them sorted with the multiset kept
// (sum, xor and sum of squares against the Python reference); 1000 keys go through
// the padded copy and come back the same way; `bitonic_step` runs the network on
// the host. `attention_flash` over (64, 8) in tiles of 16 walks four tiles a row
// and matches numpy's softmax(QK^T / sqrt(d)) V within 1e-4; one tile of 64 and
// three of 24 answer the same rows, so the online softmax is tile-independent.
// Refusals: a count past the buffer, a zero tile, a head past 256, a short output.

use e.gpu
use e.io
use e.mem
use e.os

fn near(x: f32, y: f64, tolerance: f64) -> bool {
    let d = f64(x) - y
    ret d < tolerance && d > 0.0 - tolerance
}

fn fill_keys(keys: []u32, seed: u64) {
    var state = seed
    var i = 0usize
    while i < keys.len {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        keys[i] = u32(state >> 33u32)
        i += 1usize
    }
}

// Sum, xor and sum of squares (wrapping) of the keys: the multiset's fingerprint.
fn digest(keys: []const u32) -> (u64, u64, u64) {
    var sum = 0u64
    var x = 0u64
    var squares = 0u64
    var i = 0usize
    while i < keys.len {
        let k = u64(keys[i])
        sum = sum +% k
        x = x ^ k
        squares = squares +% k *% k
        i += 1usize
    }
    ret (sum, x, squares)
}

fn is_sorted(keys: []const u32) -> bool {
    var i = 1usize
    while i < keys.len {
        if keys[i - 1usize] > keys[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }

    // 1024 keys, seed 7: ten stages, 55 launches.
    var keys: [1024]u32 = zero
    fill_keys(keys[0..], 7u64)
    let (dk, dk_error) = gpu.upload[u32](q, keys[0..])
    if dk_error != ok { os.exit(3i32) }
    if gpu.sort_bitonic(device, q, dk, 1024usize) != ok { os.exit(4i32) }
    let (after, token_error) = gpu.token(q)
    if token_error != ok || after.serial != 55u64 { os.exit(5i32) }
    var sorted: [1024]u32 = zero
    if gpu.download(q, dk, sorted[0..]) != ok { os.exit(6i32) }
    if !is_sorted(sorted[0..]) { os.exit(7i32) }
    if sorted[0] != 3559865u32 || sorted[511] != 1002407834u32 || sorted[1023] != 2146170724u32 { os.exit(8i32) }
    let (sum, x, squares) = digest(sorted[0..])
    if sum != 1065780158091u64 || x != 804479497u64 || squares != 235513228252193195u64 { os.exit(9i32) }
    // The host copy is untouched.
    let (host_sum, _, _) = digest(keys[0..])
    if host_sum != sum || is_sorted(keys[0..]) { os.exit(10i32) }

    // 1000 keys, seed 11: padded to 1024 through a device copy and written back.
    var short: [1000]u32 = zero
    fill_keys(short[0..], 11u64)
    let (ds, ds_error) = gpu.upload[u32](q, short[0..])
    if ds_error != ok { os.exit(11i32) }
    if gpu.sort_bitonic(device, q, ds, 1000usize) != ok { os.exit(12i32) }
    var sorted_short: [1000]u32 = zero
    if gpu.download(q, ds, sorted_short[0..]) != ok { os.exit(13i32) }
    if !is_sorted(sorted_short[0..]) { os.exit(14i32) }
    if sorted_short[0] != 10944899u32 || sorted_short[499] != 1072756204u32 || sorted_short[999] != 2144335252u32 { os.exit(15i32) }
    let (sum_short, x_short, squares_short) = digest(sorted_short[0..])
    if sum_short != 1064545362427u64 || x_short != 2073194067u64 || squares_short != 16762808195985540877u64 { os.exit(16i32) }
    // A prefix sorts, the rest stays; a count past the buffer is refused; one key is a no-op.
    if gpu.write[u32](q, ds, 0usize, short[0..]) != ok { os.exit(17i32) }
    if gpu.sort_bitonic(device, q, ds, 8usize) != ok { os.exit(18i32) }
    if gpu.download(q, ds, sorted_short[0..]) != ok || !is_sorted(sorted_short[0..8]) || sorted_short[8] != short[8] || sorted_short[999] != short[999] { os.exit(19i32) }
    if gpu.sort_bitonic(device, q, ds, 1001usize) != gpu.TooLarge { os.exit(20i32) }
    let (before_one, _) = gpu.token(q)
    if gpu.sort_bitonic(device, q, ds, 1usize) != ok { os.exit(21i32) }
    let (after_one, _) = gpu.token(q)
    if after_one.serial != before_one.serial { os.exit(22i32) }

    // The network on the host through `bitonic_step`, every invocation in turn.
    var eight: [8]u32 = [8]u32{ 5u32, 1u32, 7u32, 3u32, 8u32, 2u32, 6u32, 4u32 }
    var k = 2u32
    while k <= 8u32 {
        var j = k >> 1u32
        while j > 0u32 {
            var i = 0u32
            while i < 8u32 {
                gpu.bitonic_step(eight[0..], i, j, k)
                i += 1u32
            }
            j = j >> 1u32
        }
        k = k << 1u32
    }
    var e = 0usize
    while e < 8usize {
        if eight[e] != u32(e) + 1u32 { os.exit(23i32) }
        e += 1usize
    }

    // Attention over (64, 8), seed 3: Q, K, V drawn in that order.
    var state = 3u64
    var qv: [512]f32 = zero
    var kv: [512]f32 = zero
    var vv: [512]f32 = zero
    var at = 0usize
    while at < 1536usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let v = f32((state >> 33u32) % 1000u64) / 1000.0 - 0.5
        if at < 512usize { qv[at] = v } else {
            if at < 1024usize { kv[at - 512usize] = v } else { vv[at - 1024usize] = v }
        }
        at += 1usize
    }
    let (dq, dq_error) = gpu.upload[f32](q, qv[0..])
    if dq_error != ok { os.exit(24i32) }
    let (dkeys, dkeys_error) = gpu.upload[f32](q, kv[0..])
    if dkeys_error != ok { os.exit(25i32) }
    let (dv, dv_error) = gpu.upload[f32](q, vv[0..])
    if dv_error != ok { os.exit(26i32) }
    let (dout, dout_error) = gpu.alloc[f32](q, 512usize)
    if dout_error != ok { os.exit(27i32) }
    let scale: f32 = 0.35355338
    let (tiles, attention_error) = gpu.attention_flash(device, q, dq, dkeys, dv, dout, 64usize, 8usize, 16usize, scale)
    if attention_error != ok || tiles != 4usize { os.exit(28i32) }
    var out: [512]f32 = zero
    if gpu.download(q, dout, out[0..]) != ok { os.exit(29i32) }
    if !near(out[0], -0.011398327867950388, 0.0001) { os.exit(30i32) }
    if !near(out[83], 0.09094175637745573, 0.0001) { os.exit(31i32) }
    if !near(out[511], 0.029474464221183827, 0.0001) { os.exit(32i32) }
    var total = 0.0f64
    var t = 0usize
    while t < 512usize {
        total = total + f64(out[t])
        t += 1usize
    }
    if total - 7.424579225656224 > 0.001 || 7.424579225656224 - total > 0.001 { os.exit(33i32) }
    // One tile of 64 and three of 24: the same rows.
    let (one, one_error) = gpu.attention_flash(device, q, dq, dkeys, dv, dout, 64usize, 8usize, 64usize, scale)
    if one_error != ok || one != 1usize { os.exit(34i32) }
    var again: [512]f32 = zero
    if gpu.download(q, dout, again[0..]) != ok { os.exit(35i32) }
    t = 0usize
    while t < 512usize {
        if !near(again[t], f64(out[t]), 0.00001) { os.exit(36i32) }
        t += 1usize
    }
    let (three, three_error) = gpu.attention_flash(device, q, dq, dkeys, dv, dout, 64usize, 8usize, 24usize, scale)
    if three_error != ok || three != 3usize { os.exit(37i32) }
    if gpu.download(q, dout, again[0..]) != ok || !near(again[83], f64(out[83]), 0.00001) { os.exit(38i32) }
    // Refusals.
    let (_, zero_tile) = gpu.attention_flash(device, q, dq, dkeys, dv, dout, 64usize, 8usize, 0usize, scale)
    if zero_tile != gpu.TooLarge { os.exit(39i32) }
    let (_, wide_head) = gpu.attention_flash(device, q, dq, dkeys, dv, dout, 2usize, 300usize, 16usize, scale)
    if wide_head != gpu.TooLarge { os.exit(40i32) }
    let (small, small_error) = gpu.alloc[f32](q, 500usize)
    if small_error != ok { os.exit(41i32) }
    let (_, short_out) = gpu.attention_flash(device, q, dq, dkeys, dv, small, 64usize, 8usize, 16usize, scale)
    if short_out != gpu.TooLarge { os.exit(42i32) }
    try io.print("gpu gaps ok\n")
    ret ok
}
