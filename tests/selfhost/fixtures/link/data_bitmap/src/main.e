// `e.data.bitmap`: two roaring bitmaps built from LCG points plus dense
// ranges (so containers convert to bitsets) agree with Python sets on
// counts, membership, AND, OR and removals; WAH encoding of two bit
// vectors with long runs is shorter than the literal form, round-trips,
// and AND/OR over the encoded streams equal the canonical encoding of
// the combined bits. Each check exits with its own code.

use e.data.bitmap as bitmap
use e.io
use e.mem
use e.os

const K: u64 = 1099511628211u64

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 12345u64
    var keys_a: [8]u16 = zero
    var kind_a: [8]u8 = zero
    var count_a: [8]u32 = zero
    var slot_a: [8]u32 = zero
    var pool_a: [32768]u16 = zero
    var keys_b: [8]u16 = zero
    var kind_b: [8]u8 = zero
    var count_b: [8]u32 = zero
    var slot_b: [8]u32 = zero
    var pool_b: [32768]u16 = zero
    var keys_c: [8]u16 = zero
    var kind_c: [8]u8 = zero
    var count_c: [8]u32 = zero
    var slot_c: [8]u32 = zero
    var pool_c: [32768]u16 = zero
    var ra = bitmap.roaring(keys_a[..], kind_a[..], count_a[..], slot_a[..], pool_a[..])
    var rb = bitmap.roaring(keys_b[..], kind_b[..], count_b[..], slot_b[..], pool_b[..])
    var rc = bitmap.roaring(keys_c[..], kind_c[..], count_c[..], slot_c[..], pool_c[..])

    // 1: build A and B; counts.
    var i = 0usize
    while i < 3000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        if bitmap.roaring_add(&ra, u32((state >> 33u32) & 524287u64)) != ok { os.exit(1i32) }
        i += 1usize
    }
    var x = 70000u32
    while x < 140000u32 {
        if bitmap.roaring_add(&ra, x) != ok { os.exit(1i32) }
        x += 1u32
    }
    i = 0usize
    while i < 3000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        if bitmap.roaring_add(&rb, u32((state >> 33u32) & 524287u64)) != ok { os.exit(1i32) }
        i += 1usize
    }
    x = 100000u32
    while x < 200000u32 {
        if bitmap.roaring_add(&rb, x) != ok { os.exit(1i32) }
        x += 1u32
    }
    if bitmap.roaring_count(&ra) != 72595usize { os.exit(1i32) }
    if bitmap.roaring_count(&rb) != 102394usize { os.exit(1i32) }
    if bitmap.roaring_add(&ra, 70001u32) != ok || bitmap.roaring_count(&ra) != 72595usize { os.exit(1i32) }

    // 2: membership probes.
    var h = 0u64
    i = 0usize
    while i < 500usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let p = u32((state >> 33u32) & 524287u64)
        var bit = 0u64
        if bitmap.roaring_contains(&ra, p) { bit = 1u64 }
        h = h *% K +% bit
        bit = 0u64
        if bitmap.roaring_contains(&rb, p) { bit = 1u64 }
        h = h *% K +% bit
        i += 1usize
    }
    if h != 16037545063824590213u64 { os.exit(2i32) }

    // 3: AND and OR as sorted lists.
    var list: [140000]u32 = zero
    if bitmap.roaring_and(&ra, &rb, &rc) != ok { os.exit(3i32) }
    if bitmap.roaring_count(&rc) != 40511usize { os.exit(3i32) }
    let (and_n, and_error) = bitmap.roaring_to_list(&rc, list[..])
    if and_error != ok || and_n != 40511usize { os.exit(3i32) }
    h = 0u64
    i = 0usize
    while i < and_n {
        if i > 0usize && list[i] <= list[i - 1usize] { os.exit(3i32) }
        h = h *% K +% u64(list[i])
        i += 1usize
    }
    if h != 14453561037433207198u64 { os.exit(3i32) }
    if bitmap.roaring_or(&ra, &rb, &rc) != ok { os.exit(3i32) }
    if bitmap.roaring_count(&rc) != 134478usize { os.exit(3i32) }
    let (or_n, or_error) = bitmap.roaring_to_list(&rc, list[..])
    if or_error != ok || or_n != 134478usize { os.exit(3i32) }
    h = 0u64
    i = 0usize
    while i < or_n {
        if i > 0usize && list[i] <= list[i - 1usize] { os.exit(3i32) }
        h = h *% K +% u64(list[i])
        i += 1usize
    }
    if h != 9760721822780986994u64 { os.exit(3i32) }
    let (_, room) = bitmap.roaring_to_list(&rc, list[..100usize])
    if room != bitmap.TooSmall { os.exit(3i32) }

    // 4: removals from A.
    h = 0u64
    i = 0usize
    while i < 2000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        var bit = 0u64
        if bitmap.roaring_remove(&ra, 60000u32 + u32((state >> 33u32) % 90000u64)) { bit = 1u64 }
        h = h *% K +% bit
        i += 1usize
    }
    if h != 6697964693116326283u64 || bitmap.roaring_count(&ra) != 71078usize { os.exit(4i32) }
    let (after_n, _) = bitmap.roaring_to_list(&ra, list[..])
    h = 0u64
    i = 0usize
    while i < after_n {
        h = h *% K +% u64(list[i])
        i += 1usize
    }
    if after_n != 71078usize || h != 37543764686393552u64 { os.exit(4i32) }
    if bitmap.roaring_remove(&ra, 4000000u32) || bitmap.roaring_contains(&ra, 4000000u32) { os.exit(4i32) }

    // 5: WAH encoding is shorter than literal form and round-trips.
    var bits_a: [79]u64 = zero
    var bits_b: [63]u64 = zero
    i = 0usize
    while i < 150usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let p = usize((state >> 33u32) % 5000u64)
        bits_a[p / 64usize] |= 1u64 << u32(p % 64usize)
        i += 1usize
    }
    i = 1000usize
    while i < 3500usize {
        bits_a[i / 64usize] |= 1u64 << u32(i % 64usize)
        i += 1usize
    }
    i = 0usize
    while i < 150usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let p = usize((state >> 33u32) % 4000u64)
        bits_b[p / 64usize] |= 1u64 << u32(p % 64usize)
        i += 1usize
    }
    i = 1500usize
    while i < 3800usize {
        bits_b[i / 64usize] |= 1u64 << u32(i % 64usize)
        i += 1usize
    }
    var words_a: [162]u32 = zero
    var words_b: [162]u32 = zero
    let (wa, wa_error) = bitmap.wah(bits_a[..], 5000usize, words_a[..])
    if wa_error != ok || wa.used != 77usize || bitmap.wah_count(&wa) != 2575usize { os.exit(5i32) }
    h = 0u64
    i = 0usize
    while i < wa.used {
        h = h *% K +% u64(wa.words[i])
        i += 1usize
    }
    if h != 10460522084942780758u64 { os.exit(5i32) }
    let (wb, wb_error) = bitmap.wah(bits_b[..], 4000usize, words_b[..])
    if wb_error != ok || wb.used != 54usize || bitmap.wah_count(&wb) != 2367usize { os.exit(5i32) }
    h = 0u64
    i = 0usize
    while i < wb.used {
        h = h *% K +% u64(wb.words[i])
        i += 1usize
    }
    if h != 8038000964316304404u64 { os.exit(5i32) }
    var back: [79]u64 = zero
    if bitmap.wah_decode(&wa, back[..]) != ok { os.exit(5i32) }
    i = 0usize
    while i < 79usize {
        if back[i] != bits_a[i] { os.exit(5i32) }
        i += 1usize
    }
    if bitmap.wah_decode(&wb, back[..]) != ok { os.exit(5i32) }
    i = 0usize
    while i < 63usize {
        if back[i] != bits_b[i] { os.exit(5i32) }
        i += 1usize
    }
    if bitmap.wah_decode(&wa, back[..78usize]) != bitmap.TooSmall { os.exit(5i32) }
    let (_, tight) = bitmap.wah(bits_a[..], 5000usize, words_a[..76usize])
    if tight != bitmap.TooSmall { os.exit(5i32) }
    let (_, short) = bitmap.wah(bits_a[..], 6000usize, words_a[..])
    if short != bitmap.Invalid { os.exit(5i32) }

    // 6: AND and OR over the encoded streams.
    var words_c: [162]u32 = zero
    let (wand, wand_error) = bitmap.wah_and(&wa, &wb, words_c[..])
    if wand_error != ok || wand.used != 26usize || wand.bits != 5000usize || bitmap.wah_count(&wand) != 2035usize { os.exit(6i32) }
    h = 0u64
    i = 0usize
    while i < wand.used {
        h = h *% K +% u64(wand.words[i])
        i += 1usize
    }
    if h != 15825249923478980567u64 { os.exit(6i32) }
    if bitmap.wah_decode(&wand, back[..]) != ok { os.exit(6i32) }
    i = 0usize
    while i < 79usize {
        var expect = bits_a[i]
        if i < 63usize { expect &= bits_b[i] } else { expect = 0u64 }
        if back[i] != expect { os.exit(6i32) }
        i += 1usize
    }
    let (wor, wor_error) = bitmap.wah_or(&wa, &wb, words_c[..])
    if wor_error != ok || wor.used != 74usize || bitmap.wah_count(&wor) != 2907usize { os.exit(6i32) }
    h = 0u64
    i = 0usize
    while i < wor.used {
        h = h *% K +% u64(wor.words[i])
        i += 1usize
    }
    if h != 9362394043759202468u64 { os.exit(6i32) }
    if bitmap.wah_decode(&wor, back[..]) != ok { os.exit(6i32) }
    i = 0usize
    while i < 79usize {
        var expect = bits_a[i]
        if i < 63usize { expect |= bits_b[i] }
        if back[i] != expect { os.exit(6i32) }
        i += 1usize
    }
    // The merged stream is canonical: encoding the decoded bits gives the same words.
    let (again, _) = bitmap.wah(back[..], 5000usize, words_a[..])
    if again.used != wor.used { os.exit(6i32) }
    i = 0usize
    while i < again.used {
        if again.words[i] != wor.words[i] { os.exit(6i32) }
        i += 1usize
    }

    try io.print("data bitmap ok\n")
    ret ok
}
