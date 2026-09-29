use e.io
use e.mem
use e.algo.csp

// Four talks in hour slots 0..7; each pair listed below must be two slots apart.
type Talks = struct { checks: usize }

fn gap(t: *Talks, x: usize, y: usize, a: usize, b: usize) -> bool {
    t.checks += 1usize
    if x < y { ret a + 2usize <= b }
    ret b + 2usize <= a
}

fn show(domains: []const u8, n: usize, k: usize) -> err {
    var x = 0usize
    while x < n {
        try io.printf["  talk {}:"](x)
        var v = 0usize
        while v < k {
            if domains[x * k + v] == 1u8 { try io.printf[" {}"](v) }
            v += 1usize
        }
        try io.printf["\n"]()
        x += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let n = 4usize
    let k = 8usize
    // Talk 0 before 1 before 2 before 3, and talk 0 at least two slots before 3.
    var pairs = [8]usize{ 0usize, 1usize, 1usize, 2usize, 2usize, 3usize, 0usize, 3usize }
    var queue: [8]usize = zero
    var queued: [8]u8 = zero
    var last: [64]usize = zero

    var d3: [32]u8 = zero
    var d2: [32]u8 = zero
    var i = 0usize
    while i < n * k {
        d3[i] = 1u8
        d2[i] = 1u8
        i += 1usize
    }
    var by3 = Talks { checks: 0usize }
    try csp.ac3[Talks](d3[..], n, k, pairs[..], &by3, gap, queue[..], queued[..])
    var by2001 = Talks { checks: 0usize }
    try csp.ac2001[Talks](d2[..], n, k, pairs[..], &by2001, gap, queue[..], queued[..], last[..])

    try io.printf["slots left after arc consistency:\n"]()
    try show(d2[..], n, k)
    try io.printf["constraint checks: AC-3 {}, AC-2001 {}\n"](by3.checks, by2001.checks)
    ret ok
}
