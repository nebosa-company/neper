// One small function, inlined in a release build: its callers carry inlined records.
fn step(x: i64) -> i64 {
    ret x +% 3i64
}
