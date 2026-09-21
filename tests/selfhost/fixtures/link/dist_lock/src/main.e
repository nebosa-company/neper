// `e.dist.lock`: a scripted Redlock sequence over five instances with clock
// skew, per-call latency and two outages answers the grants, validities,
// release counts and holders a Python replica answers (including a ttl too
// short for the latencies, which is rolled back), and a scripted lease
// sequence answers its grants, renewals, heartbeat due-ness and expiry.
// Each check exits with its own code.

use e.dist.lock
use e.io
use e.mem
use e.os

fn holders(insts: []const lock.Instance, want: []const u64) -> bool {
    var i = 0usize
    while i < insts.len {
        if insts[i].holder != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var insts: [5]lock.Instance = zero
    insts[0usize] = lock.instance(0i64, 1u64)
    insts[1usize] = lock.instance(3i64, 2u64)
    insts[2usize] = lock.instance(0i64 - 2i64, 1u64)
    insts[3usize] = lock.instance(0i64, 3u64)
    insts[4usize] = lock.instance(5i64, 2u64)

    // 1: A takes the lock at 0 with validity 10; B cannot at 2.
    let (ok1, v1) = lock.redlock_acquire(insts[..], 11u64, 0u64, 20u64, 1u64)
    if !ok1 || v1 != 10u64 || lock.redlock_held(insts[..], 11u64, 2u64) != 5usize { os.exit(1i32) }
    let (ok2, v2) = lock.redlock_acquire(insts[..], 22u64, 2u64, 20u64, 1u64)
    if ok2 || v2 != 0u64 { os.exit(1i32) }

    // 2: two instances go down; A releases the three it can reach; B takes a
    // majority at 6; the two come back still holding A's stale grant.
    insts[1usize].up = false
    insts[3usize].up = false
    if lock.redlock_release(insts[..], 11u64) != 3usize { os.exit(2i32) }
    let (ok3, v3) = lock.redlock_acquire(insts[..], 22u64, 6u64, 20u64, 1u64)
    if !ok3 || v3 != 10u64 { os.exit(2i32) }
    insts[1usize].up = true
    insts[3usize].up = true
    let (ok4, _) = lock.redlock_acquire(insts[..], 33u64, 8u64, 20u64, 1u64)
    if ok4 || lock.redlock_held(insts[..], 11u64, 8u64) != 2usize { os.exit(2i32) }

    // 3: at 25 only the stale two are free (minority, rolled back); at 27 all are.
    let (ok5, _) = lock.redlock_acquire(insts[..], 33u64, 25u64, 20u64, 1u64)
    let want5 = [5]u64 { 22u64, 0u64, 22u64, 0u64, 22u64 }
    if ok5 || !holders(insts[..], want5[..]) { os.exit(3i32) }
    let (ok6, v6) = lock.redlock_acquire(insts[..], 33u64, 27u64, 20u64, 1u64)
    if !ok6 || v6 != 10u64 { os.exit(3i32) }
    insts[2usize].up = false
    if lock.redlock_release(insts[..], 33u64) != 4usize { os.exit(3i32) }
    // A ttl shorter than the latencies plus drift never holds.
    let (ok7, v7) = lock.redlock_acquire(insts[..], 11u64, 40u64, 8u64, 1u64)
    let want7 = [5]u64 { 0u64, 0u64, 33u64, 0u64, 0u64 }
    if ok7 || v7 != 0u64 || !holders(insts[..], want7[..]) { os.exit(3i32) }

    // 4: leases.
    var l = lock.lease()
    if !lock.lease_acquire(&l, 11u64, 0u64, 10u64) || lock.lease_acquire(&l, 22u64, 5u64, 10u64) { os.exit(4i32) }
    if !lock.lease_due(&l, 5u64, 1u64, 2u64) || lock.lease_due(&l, 4u64, 1u64, 2u64) { os.exit(4i32) }
    if !lock.lease_renew(&l, 11u64, 5u64, 10u64) || lock.lease_due(&l, 8u64, 1u64, 2u64) { os.exit(4i32) }
    if lock.lease_renew(&l, 22u64, 9u64, 10u64) || lock.lease_expired(&l, 14u64) || !lock.lease_expired(&l, 15u64) { os.exit(4i32) }
    if lock.lease_renew(&l, 11u64, 16u64, 10u64) || !lock.lease_acquire(&l, 22u64, 16u64, 10u64) { os.exit(4i32) }
    if !lock.lease_acquire(&l, 22u64, 20u64, 5u64) || l.expires != 25u64 || l.holder != 22u64 { os.exit(4i32) }

    try io.print("dist lock ok\n")
    ret ok
}
