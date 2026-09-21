// `e.dist.failure_detector`: phi over a window of sixteen LCG-driven
// heartbeat intervals (the ring having wrapped) matches Python's exact normal
// form (-log10(0.5 erfc(z / sqrt 2))) at several delays, the suspicion
// threshold crosses where the replica says, the tail is clamped, a constant
// heartbeat is held up by the minimum deviation, and a partial window uses
// only what it has. Each check exits with its own code.

use e.dist.failure_detector as fd
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    var scale = want
    if scale < 0.0f64 { scale = 0.0f64 - scale }
    if scale < 1.0f64 { scale = 1.0f64 }
    ret d <= 0.000000001f64 * scale
}

fn main(a: *mem.Arena, args: []str) -> err {
    var ring: [16]u64 = zero
    var d = fd.detector(ring[..], 1.0f64)

    // 1: before any interval phi is 0; after one heartbeat still 0.
    if fd.phi(&d, 500u64) != 0.0f64 { os.exit(1i32) }
    fd.heartbeat(&d, 0u64)
    if fd.phi(&d, 5000u64) != 0.0f64 || d.count != 0usize { os.exit(1i32) }

    // 2: twenty-four heartbeats with LCG gaps in 900..1100; the ring keeps the last sixteen.
    var state = 42u64
    var now = 0u64
    var i = 0usize
    while i < 24usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += 900u64 + (state >> 33u32) % 201u64
        fd.heartbeat(&d, now)
        i += 1usize
    }
    if now != 24708u64 || d.count != 16usize || d.head != 8usize || ring[7usize] != 965u64 || ring[8usize] != 1070u64 { os.exit(2i32) }

    // 3: phi at several delays against Python.
    if fd.phi(&d, now) != 0.0f64 { os.exit(3i32) }
    if !near(fd.phi(&d, now + 1000u64), 0.18929909026611483f64) { os.exit(3i32) }
    if !near(fd.phi(&d, now + 1300u64), 5.223349639665527f64) { os.exit(3i32) }
    if !near(fd.phi(&d, now + 1600u64), 19.477785787332973f64) { os.exit(3i32) }
    if !near(fd.phi(&d, now + 2500u64), 120.64356724289388f64) { os.exit(3i32) }
    if fd.phi(&d, now + 10000u64) != 300.0f64 { os.exit(3i32) }

    // 4: the threshold crossing.
    if fd.suspect(&d, now + 1377u64, 8.0f64) || !fd.suspect(&d, now + 1378u64, 8.0f64) { os.exit(4i32) }
    if !near(fd.phi(&d, now + 1377u64), 7.9667203887470865f64) || !near(fd.phi(&d, now + 1378u64), 8.006471954824498f64) { os.exit(4i32) }

    // 5: a constant heartbeat is floored at min_std_dev 50.
    var flat: [8]u64 = zero
    var c = fd.detector(flat[..], 50.0f64)
    i = 0usize
    while i <= 8usize {
        fd.heartbeat(&c, u64(i) * 1000u64)
        i += 1usize
    }
    if c.count != 8usize || !near(fd.phi(&c, 8000u64 + 1200u64), 4.499334907556478f64) || !near(fd.phi(&c, 9000u64), 0.3010299956639812f64) { os.exit(5i32) }

    // 6: a partial window of five intervals.
    var part: [16]u64 = zero
    var p = fd.detector(part[..], 1.0f64)
    state = 42u64
    now = 0u64
    fd.heartbeat(&p, 0u64)
    i = 0usize
    while i < 5usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += 900u64 + (state >> 33u32) % 201u64
        fd.heartbeat(&p, now)
        i += 1usize
    }
    if p.count != 5usize || !near(fd.phi(&p, now + 1500u64), 90.59497255122398f64) { os.exit(6i32) }

    try io.print("dist failure_detector ok\n")
    ret ok
}
