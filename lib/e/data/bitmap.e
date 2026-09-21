// Compressed bitmaps in caller storage. `Roaring` holds u32 keys in
// containers by the high 16 bits: every container is one 4096-word chunk of
// a `[]u16` pool, either a sorted array of low halves (up to 4096 entries)
// or a bitset of 65536 bits; an array converts to a bitset when it fills.
// `Wah` is a bit vector as 32-bit word-aligned hybrid words: a literal
// (top bit 0, 31 payload bits) or a fill (top bit 1, bit 30 the value,
// a 30-bit run of 31-bit groups); `wah_and` and `wah_or` walk two encoded
// streams and write a canonical encoded result.

use e.bytes

const CHUNK: usize = 4096usize
const ARRAY: u8 = 0u8
const BITSET: u8 = 1u8
const WAH_FILL: u32 = 0x80000000u32
const WAH_ONES: u32 = 0x7fffffffu32
const WAH_RUN: u32 = 0x3fffffffu32
const NO_END: usize = 4611686018427387904usize

type Roaring = struct { keys: []u16, kind: []u8, count: []u32, slot: []u32, pool: []u16, n: usize }
type Wah = struct { words: []u32, used: usize, bits: usize }
error TooSmall
error Invalid

// A roaring bitmap over parallel container arrays and a pool of
// 4096-word chunks (`pool.len / 4096` containers at most).
fn roaring(keys: []u16, kind: []u8, count: []u32, slot: []u32, pool: []u16) -> Roaring {
    ret Roaring { keys: keys, kind: kind, count: count, slot: slot, pool: pool, n: 0usize }
}

// Position of `key` among the containers, and whether it is there.
fn find_key(r: *const Roaring, key: u16) -> (usize, bool) {
    var lo = 0usize
    var hi = r.n
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if r.keys[mid] < key { lo = mid + 1usize } else { hi = mid }
    }
    ret (lo, lo < r.n && r.keys[lo] == key)
}

fn chunk_of(r: *const Roaring, pos: usize) -> []u16 {
    let start = usize(r.slot[pos]) * CHUNK
    ret r.pool[start..start + CHUNK]
}

// Position of `low` in a sorted array container, and whether it is there.
fn array_find(c: []const u16, count: usize, low: u16) -> (usize, bool) {
    var lo = 0usize
    var hi = count
    while lo < hi {
        let mid = (lo + hi) / 2usize
        if c[mid] < low { lo = mid + 1usize } else { hi = mid }
    }
    ret (lo, lo < count && c[lo] == low)
}

fn bit_at(c: []const u16, low: u16) -> bool { ret (c[usize(low >> 4u32)] >> u32(low & 15u16)) & 1u16 == 1u16 }
fn set_bit(c: []u16, low: u16) { c[usize(low >> 4u32)] |= 1u16 << u32(low & 15u16) }
fn clear_bit(c: []u16, low: u16) { c[usize(low >> 4u32)] &= ~(1u16 << u32(low & 15u16)) }

fn container_has(c: []const u16, kind: u8, count: usize, low: u16) -> bool {
    if kind == BITSET { ret bit_at(c, low) }
    let (_, present) = array_find(c, count, low)
    ret present
}

fn zero_chunk(c: []u16) {
    var w = 0usize
    while w < CHUNK {
        c[w] = 0u16
        w += 1usize
    }
}

fn chunk_ones(c: []const u16) -> u32 {
    var total = 0u32
    var w = 0usize
    while w < CHUNK {
        total += bytes.count_ones[u16](c[w])
        w += 1usize
    }
    ret total
}

fn to_bitset(c: []u16, count: usize) {
    var tmp: [4096]u16 = zero
    var i = 0usize
    while i < count {
        tmp[i] = c[i]
        i += 1usize
    }
    zero_chunk(c)
    i = 0usize
    while i < count {
        set_bit(c, tmp[i])
        i += 1usize
    }
}

// A bitset chunk of at most 4096 ones back to a sorted array.
fn to_array(c: []u16) {
    var tmp: [4096]u16 = zero
    var n = 0usize
    var w = 0usize
    while w < CHUNK {
        var word = c[w]
        while word != 0u16 {
            tmp[n] = u16(w * 16usize) | u16(bytes.trailing_zeros[u16](word))
            n += 1usize
            word &= word - 1u16
        }
        w += 1usize
    }
    var i = 0usize
    while i < n {
        c[i] = tmp[i]
        i += 1usize
    }
}

// Or the values of a container into the bitset chunk `c`.
fn or_into(c: []u16, src: []const u16, kind: u8, count: usize) {
    var i = 0usize
    if kind == BITSET {
        while i < CHUNK {
            c[i] |= src[i]
            i += 1usize
        }
        ret
    }
    while i < count {
        set_bit(c, src[i])
        i += 1usize
    }
}

// An empty array container for `key` at sorted position `pos`.
fn new_container(r: *Roaring, pos: usize, key: u16) -> err {
    if r.n >= r.keys.len || r.n >= r.kind.len || r.n >= r.count.len || r.n >= r.slot.len || (r.n + 1usize) * CHUNK > r.pool.len { ret TooSmall }
    var i = r.n
    while i > pos {
        r.keys[i] = r.keys[i - 1usize]
        r.kind[i] = r.kind[i - 1usize]
        r.count[i] = r.count[i - 1usize]
        r.slot[i] = r.slot[i - 1usize]
        i -= 1usize
    }
    r.keys[pos] = key
    r.kind[pos] = ARRAY
    r.count[pos] = 0u32
    r.slot[pos] = u32(r.n)
    r.n += 1usize
    ret ok
}

fn roaring_add(r: *Roaring, x: u32) -> err {
    let key = u16(x >> 16u32)
    let low = u16(x & 65535u32)
    let (pos, found) = find_key(r, key)
    if !found {
        let e = new_container(r, pos, key)
        if e != ok { ret e }
    }
    let c = chunk_of(r, pos)
    let count = usize(r.count[pos])
    if r.kind[pos] == ARRAY {
        let (i, present) = array_find(c, count, low)
        if present { ret ok }
        if count < CHUNK {
            var j = count
            while j > i {
                c[j] = c[j - 1usize]
                j -= 1usize
            }
            c[i] = low
            r.count[pos] += 1u32
            ret ok
        }
        to_bitset(c, count)
        r.kind[pos] = BITSET
    }
    if bit_at(c, low) { ret ok }
    set_bit(c, low)
    r.count[pos] += 1u32
    ret ok
}

fn roaring_contains(r: *const Roaring, x: u32) -> bool {
    let (pos, found) = find_key(r, u16(x >> 16u32))
    if !found { ret false }
    ret container_has(chunk_of(r, pos), r.kind[pos], usize(r.count[pos]), u16(x & 65535u32))
}

// Remove `x`; answers whether it was there. A bitset container stays a
// bitset however sparse it gets, and an emptied container stays.
// ponytail: no bitset->array demotion, add when memory after removals matters.
fn roaring_remove(r: *Roaring, x: u32) -> bool {
    let low = u16(x & 65535u32)
    let (pos, found) = find_key(r, u16(x >> 16u32))
    if !found { ret false }
    let c = chunk_of(r, pos)
    if r.kind[pos] == BITSET {
        if !bit_at(c, low) { ret false }
        clear_bit(c, low)
        r.count[pos] -= 1u32
        ret true
    }
    let count = usize(r.count[pos])
    let (i, present) = array_find(c, count, low)
    if !present { ret false }
    var j = i
    while j + 1usize < count {
        c[j] = c[j + 1usize]
        j += 1usize
    }
    r.count[pos] -= 1u32
    ret true
}

fn roaring_count(r: *const Roaring) -> usize {
    var total = 0usize
    var pos = 0usize
    while pos < r.n {
        total += usize(r.count[pos])
        pos += 1usize
    }
    ret total
}

// Every key in ascending order into `out`; answers the count.
fn roaring_to_list(r: *const Roaring, out: []u32) -> (usize, err) {
    var used = 0usize
    var pos = 0usize
    while pos < r.n {
        let high = u32(r.keys[pos]) << 16u32
        let c = chunk_of(r, pos)
        if r.kind[pos] == ARRAY {
            var i = 0usize
            while i < usize(r.count[pos]) {
                if used >= out.len { ret (used, TooSmall) }
                out[used] = high | u32(c[i])
                used += 1usize
                i += 1usize
            }
        } else {
            var w = 0usize
            while w < CHUNK {
                var word = c[w]
                while word != 0u16 {
                    if used >= out.len { ret (used, TooSmall) }
                    out[used] = high | (u32(w) * 16u32 + bytes.trailing_zeros[u16](word))
                    used += 1usize
                    word &= word - 1u16
                }
                w += 1usize
            }
        }
        pos += 1usize
    }
    ret (used, ok)
}

// `out` becomes the intersection of `a` and `b`.
fn roaring_and(a: *const Roaring, b: *const Roaring, out: *Roaring) -> err {
    out.n = 0usize
    var i = 0usize
    var j = 0usize
    while i < a.n && j < b.n {
        if a.keys[i] < b.keys[j] {
            i += 1usize
            continue
        }
        if a.keys[i] > b.keys[j] {
            j += 1usize
            continue
        }
        let e = new_container(out, out.n, a.keys[i])
        if e != ok { ret e }
        let pos = out.n - 1usize
        let c = chunk_of(out, pos)
        let ca = chunk_of(a, i)
        let cb = chunk_of(b, j)
        if a.kind[i] == BITSET && b.kind[j] == BITSET {
            out.kind[pos] = BITSET
            var w = 0usize
            while w < CHUNK {
                c[w] = ca[w] & cb[w]
                w += 1usize
            }
            out.count[pos] = chunk_ones(c)
        } else {
            // Walk the array side and test each value against the other.
            var src = ca
            var src_count = usize(a.count[i])
            var other = cb
            var other_kind = b.kind[j]
            var other_count = usize(b.count[j])
            if a.kind[i] == BITSET {
                src = cb
                src_count = usize(b.count[j])
                other = ca
                other_kind = a.kind[i]
                other_count = usize(a.count[i])
            }
            var k = 0usize
            var n = 0usize
            while k < src_count {
                if container_has(other, other_kind, other_count, src[k]) {
                    c[n] = src[k]
                    n += 1usize
                }
                k += 1usize
            }
            out.count[pos] = u32(n)
        }
        if out.count[pos] == 0u32 { out.n -= 1usize }
        i += 1usize
        j += 1usize
    }
    ret ok
}

// `out` becomes the union of `a` and `b`.
fn roaring_or(a: *const Roaring, b: *const Roaring, out: *Roaring) -> err {
    out.n = 0usize
    var i = 0usize
    var j = 0usize
    while i < a.n || j < b.n {
        let take_a = j >= b.n || (i < a.n && a.keys[i] <= b.keys[j])
        let take_b = i >= a.n || (j < b.n && b.keys[j] <= a.keys[i])
        var key = 0u16
        if take_a { key = a.keys[i] } else { key = b.keys[j] }
        let e = new_container(out, out.n, key)
        if e != ok { ret e }
        let pos = out.n - 1usize
        let c = chunk_of(out, pos)
        zero_chunk(c)
        if take_a {
            or_into(c, chunk_of(a, i), a.kind[i], usize(a.count[i]))
            i += 1usize
        }
        if take_b {
            or_into(c, chunk_of(b, j), b.kind[j], usize(b.count[j]))
            j += 1usize
        }
        let total = chunk_ones(c)
        out.count[pos] = total
        if usize(total) <= CHUNK {
            to_array(c)
        } else {
            out.kind[pos] = BITSET
        }
        if total == 0u32 { out.n -= 1usize }
    }
    ret ok
}

// --- WAH ---

fn wah_push_fill(out: []u32, used: usize, value: u32, run: usize) -> (usize, err) {
    var n = used
    var left = run
    while left > 0usize {
        if n > 0usize && (out[n - 1usize] & WAH_FILL) != 0u32 && ((out[n - 1usize] >> 30u32) & 1u32) == value && (out[n - 1usize] & WAH_RUN) < WAH_RUN {
            let room = usize(WAH_RUN - (out[n - 1usize] & WAH_RUN))
            var k = left
            if k > room { k = room }
            out[n - 1usize] += u32(k)
            left -= k
        } else {
            if n >= out.len { ret (n, TooSmall) }
            var k = left
            if k > usize(WAH_RUN) { k = usize(WAH_RUN) }
            out[n] = WAH_FILL | (value << 30u32) | u32(k)
            n += 1usize
            left -= k
        }
    }
    ret (n, ok)
}

fn wah_push_literal(out: []u32, used: usize, literal: u32) -> (usize, err) {
    if literal == 0u32 {
        let (n0, e0) = wah_push_fill(out, used, 0u32, 1usize)
        ret (n0, e0)
    }
    if literal == WAH_ONES {
        let (n1, e1) = wah_push_fill(out, used, 1u32, 1usize)
        ret (n1, e1)
    }
    if used >= out.len { ret (used, TooSmall) }
    out[used] = literal
    ret (used + 1usize, ok)
}

fn groups_for(n: usize) -> usize { ret (n + 30usize) / 31usize }

// The 31-bit group `g` of a bit vector of `n` bits.
fn group_of(bits: []const u64, n: usize, g: usize) -> u32 {
    let p = g * 31usize
    let w = p / 64usize
    let s = u32(p % 64usize)
    var v = bits[w] >> s
    if s > 33u32 && w + 1usize < bits.len { v |= bits[w + 1usize] << (64u32 - s) }
    var mask = u64(WAH_ONES)
    if p + 31usize > n { mask = (1u64 << u32(n - p)) - 1u64 }
    ret u32(v & mask)
}

fn put_group(bits: []u64, g: usize, v: u32) {
    let p = g * 31usize
    let w = p / 64usize
    if w >= bits.len { ret }
    let s = u32(p % 64usize)
    bits[w] |= u64(v) << s
    if s > 33u32 && w + 1usize < bits.len { bits[w + 1usize] |= u64(v) >> (64u32 - s) }
}

// Encode the first `n` bits of `bits` into `out`.
fn wah(bits: []const u64, n: usize, out: []u32) -> (Wah, err) {
    if bits.len * 64usize < n { ret (zero, Invalid) }
    var used = 0usize
    var g = 0usize
    while g < groups_for(n) {
        let (next_used, e) = wah_push_literal(out, used, group_of(bits, n, g))
        if e != ok { ret (zero, e) }
        used = next_used
        g += 1usize
    }
    ret (Wah { words: out, used: used, bits: n }, ok)
}

// Decode into `bits`, which needs a word per 64 bits.
fn wah_decode(w: *const Wah, bits: []u64) -> err {
    let words = (w.bits + 63usize) / 64usize
    if bits.len < words { ret TooSmall }
    let dst = bits[..words]
    var i = 0usize
    while i < words {
        dst[i] = 0u64
        i += 1usize
    }
    var g = 0usize
    i = 0usize
    while i < w.used {
        let word = w.words[i]
        if (word & WAH_FILL) != 0u32 {
            let run = usize(word & WAH_RUN)
            if ((word >> 30u32) & 1u32) == 1u32 {
                var k = 0usize
                while k < run {
                    put_group(dst, g + k, WAH_ONES)
                    k += 1usize
                }
            }
            g += run
        } else {
            put_group(dst, g, word)
            g += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn wah_count(w: *const Wah) -> usize {
    var total = 0usize
    var i = 0usize
    while i < w.used {
        let word = w.words[i]
        if (word & WAH_FILL) != 0u32 {
            if ((word >> 30u32) & 1u32) == 1u32 { total += 31usize * usize(word & WAH_RUN) }
        } else {
            total += usize(bytes.count_ones[u32](word))
        }
        i += 1usize
    }
    ret total
}

// The current group of a stream: its value, how many groups it still
// covers, and whether it is a fill. Past the end it is an endless zero fill.
fn wah_peek(w: *const Wah, i: usize, done: usize) -> (u32, usize, bool) {
    if i >= w.used { ret (0u32, NO_END, true) }
    let word = w.words[i]
    if (word & WAH_FILL) == 0u32 { ret (word, 1usize, false) }
    var v = 0u32
    if ((word >> 30u32) & 1u32) == 1u32 { v = WAH_ONES }
    ret (v, usize(word & WAH_RUN) - done, true)
}

// Consume `k` groups; answers the new (word index, groups done of it).
fn wah_skip(w: *const Wah, i: usize, done: usize, k: usize) -> (usize, usize) {
    if i >= w.used { ret (i, done) }
    let word = w.words[i]
    if (word & WAH_FILL) == 0u32 { ret (i + 1usize, 0usize) }
    if done + k >= usize(word & WAH_RUN) { ret (i + 1usize, 0usize) }
    ret (i, done + k)
}

fn wah_merge(a: *const Wah, b: *const Wah, out: []u32, is_and: bool) -> (Wah, err) {
    var ia = 0usize
    var da = 0usize
    var ib = 0usize
    var db = 0usize
    var used = 0usize
    while ia < a.used || ib < b.used {
        let (va, ra, fa) = wah_peek(a, ia, da)
        let (vb, rb, fb) = wah_peek(b, ib, db)
        var v = va & vb
        if !is_and { v = va | vb }
        var k = 1usize
        var e = ok
        if fa && fb {
            k = ra
            if rb < k { k = rb }
            var bit = 0u32
            if v == WAH_ONES { bit = 1u32 }
            let (fill_used, fill_error) = wah_push_fill(out, used, bit, k)
            used = fill_used
            e = fill_error
        } else {
            let (literal_used, literal_error) = wah_push_literal(out, used, v)
            used = literal_used
            e = literal_error
        }
        if e != ok { ret (zero, e) }
        let (nia, nda) = wah_skip(a, ia, da, k)
        ia = nia
        da = nda
        let (nib, ndb) = wah_skip(b, ib, db, k)
        ib = nib
        db = ndb
    }
    var bits = a.bits
    if b.bits > bits { bits = b.bits }
    ret (Wah { words: out, used: used, bits: bits }, ok)
}

// The encoded AND of two streams, canonical (equal to encoding the result).
fn wah_and(a: *const Wah, b: *const Wah, out: []u32) -> (Wah, err) {
    let (w, e) = wah_merge(a, b, out, true)
    ret (w, e)
}

// The encoded OR of two streams, canonical (equal to encoding the result).
fn wah_or(a: *const Wah, b: *const Wah, out: []u32) -> (Wah, err) {
    let (w, e) = wah_merge(a, b, out, false)
    ret (w, e)
}
