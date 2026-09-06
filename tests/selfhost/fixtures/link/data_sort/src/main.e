use e.data.sort
use e.io
use e.mem

error Failed

type Rec = struct { key: i64, seq: i64 }
type Flip = struct { calls: i64 }

// Orders on `key` alone, so records with equal keys are ties and a stable sort has
// to keep their input order.
fn rec_cmp(a: Rec, b: Rec) -> i32 {
    if a.key < b.key { ret 0i32 - 1i32 }
    if a.key > b.key { ret 1i32 }
    ret 0i32
}

fn descending(ctx: *Flip, a: i64, b: i64) -> i32 {
    ctx.calls += 1i64
    if a > b { ret 0i32 - 1i32 }
    if a < b { ret 1i32 }
    ret 0i32
}

fn rec_by_key_desc(ctx: *Flip, a: Rec, b: Rec) -> i32 {
    ctx.calls += 1i64
    ret 0i32 - rec_cmp(a, b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // in_place over integers, with duplicates and negatives.
    var values: [9]i64 = zero
    values[0usize] = 5i64
    values[1usize] = 0i64 - 3i64
    values[2usize] = 9i64
    values[3usize] = 5i64
    values[4usize] = 0i64
    values[5usize] = 0i64 - 12i64
    values[6usize] = 7i64
    values[7usize] = 1i64
    values[8usize] = 5i64
    if sort.is_sorted[i64](values[..]) { ret Failed }
    sort.in_place[i64](values[..])
    if !sort.is_sorted[i64](values[..]) { ret Failed }
    if values[0usize] != 0i64 - 12i64 || values[1usize] != 0i64 - 3i64 { ret Failed }
    if values[8usize] != 9i64 { ret Failed }
    var duplicates = 0usize
    var at = 0usize
    while at < 9usize {
        if values[at] == 5i64 { duplicates += 1usize }
        at += 1usize
    }
    if duplicates != 3usize { ret Failed }

    // Degenerate lengths are left alone.
    var empty: [0]i64 = zero
    sort.in_place[i64](empty[..])
    if !sort.is_sorted[i64](empty[..]) { ret Failed }
    var single: [1]i64 = zero
    single[0usize] = 4i64
    sort.in_place[i64](single[..])
    if single[0usize] != 4i64 || !sort.is_sorted[i64](single[..]) { ret Failed }

    // Already sorted, and exactly reversed.
    var ordered: [4]i64 = zero
    ordered[0usize] = 1i64
    ordered[1usize] = 2i64
    ordered[2usize] = 3i64
    ordered[3usize] = 4i64
    sort.in_place[i64](ordered[..])
    if ordered[0usize] != 1i64 || ordered[3usize] != 4i64 { ret Failed }
    var reversed: [4]i64 = zero
    reversed[0usize] = 4i64
    reversed[1usize] = 3i64
    reversed[2usize] = 2i64
    reversed[3usize] = 1i64
    sort.in_place[i64](reversed[..])
    if !sort.is_sorted[i64](reversed[..]) || reversed[0usize] != 1i64 { ret Failed }

    // A user type orders by the cmp its own module declares.
    var records: [5]Rec = zero
    records[0usize] = Rec { key: 2i64, seq: 1i64 }
    records[1usize] = Rec { key: 1i64, seq: 2i64 }
    records[2usize] = Rec { key: 2i64, seq: 3i64 }
    records[3usize] = Rec { key: 0i64, seq: 4i64 }
    records[4usize] = Rec { key: 1i64, seq: 5i64 }
    sort.in_place[Rec](records[..])
    if !sort.is_sorted[Rec](records[..]) { ret Failed }
    if records[0usize].key != 0i64 || records[4usize].key != 2i64 { ret Failed }

    // in_place_by, with the comparison carrying context it mutates.
    var flip = Flip { calls: 0i64 }
    var by_values: [6]i64 = zero
    by_values[0usize] = 3i64
    by_values[1usize] = 8i64
    by_values[2usize] = 1i64
    by_values[3usize] = 8i64
    by_values[4usize] = 0i64
    by_values[5usize] = 5i64
    sort.in_place_by[i64, Flip](by_values[..], &flip, descending)
    if flip.calls == 0i64 { ret Failed }
    if by_values[0usize] != 8i64 || by_values[1usize] != 8i64 { ret Failed }
    if by_values[5usize] != 0i64 { ret Failed }
    var falling = 0usize
    while falling + 1usize < 6usize {
        if by_values[falling] < by_values[falling + 1usize] { ret Failed }
        falling += 1usize
    }

    // stable_in_place keeps equal keys in input order.
    var stable_records: [7]Rec = zero
    stable_records[0usize] = Rec { key: 2i64, seq: 1i64 }
    stable_records[1usize] = Rec { key: 1i64, seq: 2i64 }
    stable_records[2usize] = Rec { key: 2i64, seq: 3i64 }
    stable_records[3usize] = Rec { key: 1i64, seq: 4i64 }
    stable_records[4usize] = Rec { key: 2i64, seq: 5i64 }
    stable_records[5usize] = Rec { key: 0i64, seq: 6i64 }
    stable_records[6usize] = Rec { key: 1i64, seq: 7i64 }
    try sort.stable_in_place[Rec](a, stable_records[..])
    if !sort.is_sorted[Rec](stable_records[..]) { ret Failed }
    if stable_records[0usize].seq != 6i64 { ret Failed }
    if stable_records[1usize].seq != 2i64 || stable_records[2usize].seq != 4i64 || stable_records[3usize].seq != 7i64 { ret Failed }
    if stable_records[4usize].seq != 1i64 || stable_records[5usize].seq != 3i64 || stable_records[6usize].seq != 5i64 { ret Failed }

    // stable_in_place_by, same records under the opposite ordering. Ties still keep
    // input order, so the sequence numbers within one key stay ascending.
    var stable_by: [7]Rec = zero
    stable_by[0usize] = Rec { key: 2i64, seq: 1i64 }
    stable_by[1usize] = Rec { key: 1i64, seq: 2i64 }
    stable_by[2usize] = Rec { key: 2i64, seq: 3i64 }
    stable_by[3usize] = Rec { key: 1i64, seq: 4i64 }
    stable_by[4usize] = Rec { key: 2i64, seq: 5i64 }
    stable_by[5usize] = Rec { key: 0i64, seq: 6i64 }
    stable_by[6usize] = Rec { key: 1i64, seq: 7i64 }
    var stable_flip = Flip { calls: 0i64 }
    try sort.stable_in_place_by[Rec, Flip](a, stable_by[..], &stable_flip, rec_by_key_desc)
    if stable_flip.calls == 0i64 { ret Failed }
    if stable_by[0usize].seq != 1i64 || stable_by[1usize].seq != 3i64 || stable_by[2usize].seq != 5i64 { ret Failed }
    if stable_by[3usize].seq != 2i64 || stable_by[4usize].seq != 4i64 || stable_by[5usize].seq != 7i64 { ret Failed }
    if stable_by[6usize].seq != 6i64 { ret Failed }

    // Radix over unsigned values, including ones with the high bit set that a
    // signed comparison would order wrongly.
    var wide: [6]u32 = zero
    wide[0usize] = 4000000000u32
    wide[1usize] = 1u32
    wide[2usize] = 4294967295u32
    wide[3usize] = 0u32
    wide[4usize] = 256u32
    wide[5usize] = 4000000000u32
    try sort.radix_u32_in_place(a, wide[..])
    if wide[0usize] != 0u32 || wide[1usize] != 1u32 || wide[2usize] != 256u32 { ret Failed }
    if wide[3usize] != 4000000000u32 || wide[4usize] != 4000000000u32 { ret Failed }
    if wide[5usize] != 4294967295u32 { ret Failed }

    var huge: [5]u64 = zero
    huge[0usize] = 18446744073709551615u64
    huge[1usize] = 1u64
    huge[2usize] = 9223372036854775808u64
    huge[3usize] = 0u64
    huge[4usize] = 65536u64
    try sort.radix_u64_in_place(a, huge[..])
    if huge[0usize] != 0u64 || huge[1usize] != 1u64 || huge[2usize] != 65536u64 { ret Failed }
    if huge[3usize] != 9223372036854775808u64 || huge[4usize] != 18446744073709551615u64 { ret Failed }

    // The arena is handed back after each sort, so repeated calls do not grow it.
    let before = mem.stats(a)
    try sort.stable_in_place[Rec](a, stable_records[..])
    try sort.radix_u32_in_place(a, wide[..])
    let after = mem.stats(a)
    if after.used != before.used { ret Failed }

    try io.print("data sort ok\n")
    ret ok
}
