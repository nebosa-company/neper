// `pair_eq` compares only `key`, so it is not structural equality: a comparison
// that failed to reach the declaration would disagree on `tag`.

type Pair = struct { key: i64, tag: i64 }

fn pair_eq(a: Pair, b: Pair) -> bool {
    ret a.key == b.key
}
