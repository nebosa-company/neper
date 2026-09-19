// H06's semantic law for supplied operations: equality is an equivalence relation,
// and equal values have equal hashes. Exhaust the small u8 domain and pin the
// sequence fallbacks on equal storage reached through different slices.

error Failed

fn same[T: type](a: T, b: T) -> bool { ret T.eq(a, b) }
fn digest[T: type](value: T) -> u64 { ret T.hash(value) }

fn main() -> err {
    var values: [8]i64 = zero
    var at = 0usize
    while at < values.len {
        values[at] = i64(at)
        at += 1usize
    }

    var a = 0usize
    while a < values.len {
        if !same[i64](values[a], values[a]) { ret Failed }
        var b = 0usize
        while b < values.len {
            let ab = same[i64](values[a], values[b])
            if ab != same[i64](values[b], values[a]) { ret Failed }
            if ab && digest[i64](values[a]) != digest[i64](values[b]) { ret Failed }
            var d = 0usize
            while d < values.len {
                if ab && same[i64](values[b], values[d]) && !same[i64](values[a], values[d]) { ret Failed }
                d += 1usize
            }
            b += 1usize
        }
        a += 1usize
    }

    var bytes: [6]i64 = zero
    bytes[0usize] = 3i64
    bytes[1usize] = 5i64
    bytes[2usize] = 8i64
    bytes[3usize] = 3i64
    bytes[4usize] = 5i64
    bytes[5usize] = 9i64
    let left = bytes[0usize..2usize]
    let equal = bytes[3usize..5usize]
    let different = bytes[3usize..6usize]
    if !same[[]i64](left, equal) { ret Failed }
    if digest[[]i64](left) != digest[[]i64](equal) { ret Failed }
    if same[[]i64](left, different) { ret Failed }
    ret ok
}
