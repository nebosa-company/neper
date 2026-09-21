// `e.data.hamt`: sixty versions built by random puts and removes each still
// answer exactly their own dictionary (persistence), the node and slot
// usage matches the Python mirror of the path copying, a longer 50/50 run
// over 64 keys ends on the reference checksum, and a tiny pool reports
// TooSmall. Reference values come from scratchpad/hamt_ref.py.

use e.data.hamt
use e.io
use e.mem
use e.os

fn checksum(h: *const hamt.Hamt, root: u32, keys: u64) -> u64 {
    var s = 0u64
    var k = 0u64
    while k < keys {
        let (v, present) = hamt.get(h, root, k)
        if present { s = s *% 1000003u64 +% k *% 31u64 +% v }
        k += 1u64
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    var bitmap: [1024]u32 = zero
    var first: [1024]u32 = zero
    var key: [1024]u64 = zero
    var value: [1024]u64 = zero
    var slots: [8192]u32 = zero
    var h = hamt.hamt(bitmap[..], first[..], key[..], value[..], slots[..])
    var state = 12345u64

    // 1: sixty versions from the LCG, every root kept.
    var roots: [61]u32 = zero
    roots[0usize] = hamt.NONE
    var step = 0usize
    while step < 60usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r1 = state >> 33u32
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r2 = state >> 33u32
        let k = r1 % 40u64
        if r2 % 3u64 < 2u64 {
            let (root, e) = hamt.put(&h, roots[step], k, r1)
            if e != ok { os.exit(1i32) }
            roots[step + 1usize] = root
        } else {
            let (root, e) = hamt.remove(&h, roots[step], k)
            if e != ok { os.exit(1i32) }
            roots[step + 1usize] = root
        }
        step += 1usize
    }

    // 2, 3: each version answers its own dictionary; counts agree.
    var sums: [61]u64 = [61]u64{ 0u64, 235319008u64, 1901869044908320u64, 1860574893990134496u64, 14388845512480533400u64, 3865665485273888968u64, 3865665485273888968u64, 3865665485273888968u64, 13140293369125320040u64, 16011211198671887064u64, 1885159656962742792u64, 179464344931770408u64, 17999626656136190640u64, 16092035005590419312u64, 16092035005590419312u64, 10748762688231993672u64, 7681751699418263024u64, 7681751699418263024u64, 7681751699418263024u64, 8915156385357887024u64, 3372741511490566136u64, 14963545195083567024u64, 14963545195083567024u64, 14963545195083567024u64, 5517151682232609584u64, 15160526216207879608u64, 15801614707495458352u64, 8793655172736897824u64, 7973300631272560264u64, 5819523887716149504u64, 14303368546757227056u64, 11429872393161562872u64, 11429872393161562872u64, 15820740498284492688u64, 16486941758696090080u64, 13404428703482861280u64, 2155255095878710984u64, 8022440862091254024u64, 1471845961780078776u64, 16527202845378365840u64, 5283369558579068504u64, 1155907832292407000u64, 7216304732398884752u64, 15440626990794237816u64, 9212910086263075680u64, 4445200035433464064u64, 4044866817527317840u64, 13696331447443161408u64, 11900267629499843816u64, 4259332243446949944u64, 6826617894967137688u64, 7751065112132699720u64, 14251920181052763928u64, 3198411823932049264u64, 7362441133107647432u64, 398254225870831464u64, 17493249942811107328u64, 987041121409545240u64, 987041121409545240u64, 14147766161564523600u64, 2974935446467796248u64 }
    var counts: [61]u32 = [61]u32{ 0u32, 1u32, 2u32, 3u32, 4u32, 5u32, 5u32, 5u32, 6u32, 7u32, 8u32, 9u32, 10u32, 11u32, 11u32, 12u32, 12u32, 12u32, 12u32, 12u32, 13u32, 14u32, 14u32, 14u32, 15u32, 16u32, 16u32, 17u32, 18u32, 18u32, 18u32, 18u32, 18u32, 19u32, 20u32, 21u32, 22u32, 22u32, 23u32, 24u32, 24u32, 25u32, 24u32, 25u32, 24u32, 25u32, 25u32, 26u32, 27u32, 27u32, 27u32, 27u32, 27u32, 26u32, 25u32, 25u32, 25u32, 24u32, 24u32, 25u32, 26u32 }
    var v = 0usize
    while v <= 60usize {
        if checksum(&h, roots[v], 40u64) != sums[v] { os.exit(2i32) }
        if hamt.count(&h, roots[v]) != usize(counts[v]) { os.exit(3i32) }
        v += 1usize
    }

    // 4: only the path is copied: usage matches the mirror and sits far under 60 * 13.
    if h.used != 112usize || h.slots_used != 747usize { os.exit(4i32) }
    let (same, absent_error) = hamt.remove(&h, roots[60usize], 1000u64)
    if absent_error != ok || same != roots[60usize] || h.used != 112usize { os.exit(4i32) }

    // 5: four hundred 50/50 steps over 64 keys from the last version.
    var root = roots[60usize]
    step = 0usize
    while step < 400usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r1 = state >> 33u32
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r2 = state >> 33u32
        let k = r1 % 64u64
        if r2 % 2u64 == 0u64 {
            let (new_root, e) = hamt.put(&h, root, k, r1)
            if e != ok { os.exit(5i32) }
            root = new_root
        } else {
            let (new_root, e) = hamt.remove(&h, root, k)
            if e != ok { os.exit(5i32) }
            root = new_root
        }
        step += 1usize
    }
    if hamt.count(&h, root) != 28usize || checksum(&h, root, 64u64) != 3721446346232443136u64 { os.exit(5i32) }
    if h.used != 777usize || h.slots_used != 7372usize { os.exit(5i32) }
    if checksum(&h, roots[60usize], 40u64) != sums[60usize] { os.exit(5i32) }

    // 6: a tiny pool runs out.
    var tiny = hamt.hamt(bitmap[..3usize], first[..3usize], key[..3usize], value[..3usize], slots[..4usize])
    let (one, e1) = hamt.put(&tiny, hamt.NONE, 1u64, 1u64)
    let (two, e2) = hamt.put(&tiny, one, 2u64, 2u64)
    let (_, e3) = hamt.put(&tiny, two, 3u64, 3u64)
    if e1 != ok || e2 != ok || e3 != hamt.TooSmall { os.exit(6i32) }
    let (v2, present2) = hamt.get(&tiny, two, 2u64)
    if !present2 || v2 != 2u64 || hamt.count(&tiny, two) != 2usize { os.exit(6i32) }

    try io.print("data hamt ok\n")
    ret ok
}
