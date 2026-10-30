// (D5932) `pages.ensure` says now, as an error, what a page fault would otherwise say later as a
// death: bytes it answers `ok` for are there, and bytes the machine does not have are
// `mem.Exhausted`. `pages.discard` gives whole pages back and leaves the slice usable.
use e.mem
use e.mem.pages

const MIB: usize = 1048576usize

error EnsureRefusedWhatFits
error EnsureAcceptedTheImpossible
error EnsurePastTheCeiling
error DiscardKeptThePage
error DiscardTouchedTheEdge
error DiscardLeftItUnusable

fn main(a: *mem.Arena, args: []str) -> err {
    // What is plainly there.
    if pages.ensure(a, 16usize * MIB) != ok { ret EnsureRefusedWhatFits }
    let (block, block_error) = mem.alloc[u8](a, 16usize * MIB)
    if block_error != ok { ret block_error }
    block[15usize * MIB] = 3u8
    if block[15usize * MIB] != 3u8 { ret EnsureRefusedWhatFits }

    // More than any machine running this has, inside the ceiling.
    let room = mem.stats(a).capacity - mem.stats(a).used
    if pages.ensure(a, room) != mem.Exhausted { ret EnsureAcceptedTheImpossible }

    // Past the ceiling.
    if pages.ensure(a, room + 1usize) != mem.Exhausted { ret EnsurePastTheCeiling }

    // Nothing was allocated by asking.
    let (after, after_error) = mem.alloc[u8](a, 4096usize)
    if after_error != ok { ret after_error }
    after[0usize] = 1u8

    // Whole pages go back; the partial pages at the edges keep their bytes.
    let (span, span_error) = mem.alloc[u8](a, 4usize * MIB)
    if span_error != ok { ret span_error }
    var at = 0usize
    while at < span.len {
        span[at] = 7u8
        at += 1024usize
    }
    if pages.discard(span[1024usize..3usize * MIB + 1024usize]) != ok { ret DiscardKeptThePage }
    if span[MIB] != 0u8 { ret DiscardKeptThePage }
    if span[1024usize] != 7u8 { ret DiscardTouchedTheEdge }
    if span[3usize * MIB + 1024usize] != 7u8 { ret DiscardTouchedTheEdge }
    span[MIB] = 9u8
    if span[MIB] != 9u8 { ret DiscardLeftItUnusable }
    ret ok
}
