// H25's CPU program workload (D943): a million particles in a box, each a record read
// whole, moved and written back, for sixty steps -- the aggregate copies a program of
// structs makes; prints a checksum of the final positions.
use e.mem
use e.io
use e.str

type Particle = struct {
    x: i64,
    y: i64,
    vx: i64,
    vy: i64,
    bounces: i64,
}

fn step(p: Particle, size: i64) -> Particle {
    var next = p
    next.x = p.x + p.vx
    next.y = p.y + p.vy
    if next.x < 0i64 || next.x >= size {
        next.vx = 0i64 - p.vx
        next.x = p.x
        next.bounces = p.bounces + 1i64
    }
    if next.y < 0i64 || next.y >= size {
        next.vy = 0i64 - p.vy
        next.y = p.y
        next.bounces = next.bounces + 1i64
    }
    ret next
}

fn main(a: *mem.Arena, args: []str) -> err {
    let count = 1000000usize
    let size = 1000000i64
    let (particles, particles_error) = mem.alloc[Particle](a, count)
    if particles_error != ok { ret particles_error }
    var state = 99i64
    var at = 0usize
    while at < count {
        state = (state * 1103515245i64 + 12345i64) & 2147483647i64
        let x = state % size
        state = (state * 1103515245i64 + 12345i64) & 2147483647i64
        let y = state % size
        state = (state * 1103515245i64 + 12345i64) & 2147483647i64
        let vx = state % 2001i64 - 1000i64
        state = (state * 1103515245i64 + 12345i64) & 2147483647i64
        let vy = state % 2001i64 - 1000i64
        particles[at] = Particle { x: x, y: y, vx: vx, vy: vy, bounces: 0i64 }
        at += 1usize
    }
    var round = 0usize
    while round < 60usize {
        at = 0usize
        while at < count {
            let p = particles[at]
            particles[at] = step(p, size)
            at += 1usize
        }
        round += 1usize
    }
    var checksum = 0i64
    at = 0usize
    while at < count {
        let p = particles[at]
        checksum = (checksum * 31i64 + p.x + p.y * 7i64 + p.bounces) & 1152921504606846975i64
        at += 1usize
    }
    let (b0, b0_error) = str.builder(a, 64usize)
    if b0_error != ok { ret b0_error }
    var b = b0
    try str.push_i64(&b, checksum)
    try str.push(&b, "\n")
    try io.print(str.done(&b))
    ret ok
}
