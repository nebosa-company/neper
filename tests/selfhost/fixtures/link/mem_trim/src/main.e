// (D5931) A reset that frees 512 MiB or more hands all but the first 128 MiB of it back to the
// operating system, and a smaller one makes no system call. Pages handed back read as zero, on
// every host. The checker refuses a slice past its reset (E-SAFETY-0013), so what no program
// can do by accident this one does on purpose: `mem.view` reaches the bytes by offset, the one
// observation that needs no memory-reporting call, which macOS lacks.
use e.mem

const MIB: usize = 1048576usize

error KeptBelowTheThreshold
error KeptTheFirst
error DiscardedTheRest
error ReusedTheArena
error TouchedPastTheBuffer

fn fill(block: []u8, value: u8) {
    var at = 0usize
    while at < block.len {
        block[at] = value
        at += 4096usize
    }
}

fn peek(a: *mem.Arena, at: usize) -> u8 {
    let byte = mem.view(a, at, 1usize)
    ret byte[0usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let start = mem.mark(a)

    // Under the threshold: nothing goes back, so the bytes are as the reset left them.
    let (small, small_error) = mem.alloc[u8](a, 400usize * MIB)
    if small_error != ok { ret small_error }
    fill(small, 7u8)
    mem.reset(a, start)
    if peek(a, start + 399usize * MIB) == 0u8 { ret KeptBelowTheThreshold }

    // Over it: the first 128 MiB stay, and what is past them is zero.
    let (large, large_error) = mem.alloc[u8](a, 700usize * MIB)
    if large_error != ok { ret large_error }
    fill(large, 7u8)
    mem.reset(a, start)
    if peek(a, start + MIB) == 0u8 { ret KeptTheFirst }
    if peek(a, start + 500usize * MIB) != 0u8 { ret DiscardedTheRest }
    if peek(a, start + 699usize * MIB) != 0u8 { ret DiscardedTheRest }

    // The arena goes on as before, over the same addresses.
    let (again, again_error) = mem.alloc[u8](a, 700usize * MIB)
    if again_error != ok { ret again_error }
    fill(again, 9u8)
    if again[500usize * MIB] != 9u8 { ret ReusedTheArena }
    mem.reset(a, start)

    // An arena over a caller's buffer gives back nothing outside that buffer.
    let (outer, outer_error) = mem.alloc[u8](a, 701usize * MIB)
    if outer_error != ok { ret outer_error }
    fill(outer, 5u8)
    var inner = mem.arena_from(outer[0usize..700usize * MIB + 4096usize])
    let inner_start = mem.mark(&inner)
    let (inside, inside_error) = mem.alloc[u8](&inner, 700usize * MIB)
    if inside_error != ok { ret inside_error }
    fill(inside, 6u8)
    mem.reset(&inner, inner_start)
    if outer[700usize * MIB + 4096usize] != 5u8 { ret TouchedPastTheBuffer }
    if peek(&inner, inner_start + 500usize * MIB) != 0u8 { ret DiscardedTheRest }
    ret ok
}
