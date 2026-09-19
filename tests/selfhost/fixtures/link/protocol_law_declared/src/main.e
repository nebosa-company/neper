// A reusable finite-domain property check for declared equality and hash strategies.

use models

error Failed

fn laws[T: type](values: []const T) -> bool {
    var a = 0usize
    while a < values.len {
        if !T.eq(values[a], values[a]) { ret false }
        var b = 0usize
        while b < values.len {
            let ab = T.eq(values[a], values[b])
            if ab != T.eq(values[b], values[a]) { ret false }
            if ab && T.hash(values[a]) != T.hash(values[b]) { ret false }
            var d = 0usize
            while d < values.len {
                if ab && T.eq(values[b], values[d]) && !T.eq(values[a], values[d]) { ret false }
                d += 1usize
            }
            b += 1usize
        }
        a += 1usize
    }
    ret true
}

fn main() -> err {
    var keys: [4]models.Key = zero
    keys[0usize] = models.Key { id: 1u64, ignored: 10u64 }
    keys[1usize] = models.Key { id: 1u64, ignored: 99u64 }
    keys[2usize] = models.Key { id: 2u64, ignored: 10u64 }
    keys[3usize] = models.Key { id: 3u64, ignored: 99u64 }
    if !laws[models.Key](keys[..]) { ret Failed }

    var broken: [2]models.Broken = zero
    broken[0usize] = models.Broken { id: 1u64, ignored: 10u64 }
    broken[1usize] = models.Broken { id: 1u64, ignored: 99u64 }
    if laws[models.Broken](broken[..]) { ret Failed }
    ret ok
}
