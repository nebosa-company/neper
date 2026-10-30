// `e.mem.pages`: an arena's pages and the operating system. `mem.reset` hands back a large drop
// on its own (D5931); these are what a program asks for by name (D5932). This file is every
// host with nothing to ask: a wasm32 module's memory only grows and NeperOS maps it whole, so
// `discard` has nothing to give back, and `ensure` answers what fits under the ceiling.
use e.mem
use e.os

// Gives the whole pages inside `bytes` back to the operating system. They read as zero or as
// they were, and the slice stays usable; the partial pages at either end keep their bytes. A
// refusal is not a failure the program must handle: the memory stays where it was.
fn discard(bytes: []u8) -> err { ret ok }

// `ok` when the arena's next `n` bytes are there, `mem.Exhausted` when they are not: the answer
// a page fault would otherwise give later, as the end of the process. Allocates nothing.
fn ensure(a: *mem.Arena, n: usize) -> err {
    let s = mem.stats(a)
    if n > s.capacity - s.used { ret mem.Exhausted }
    ret ok
}

// A range of addresses of its own, up to `capacity`, halved until the host gives it, and
// charged as it is touched. Where nothing can be reserved the answer is `os.Unsupported`.
fn reserve(capacity: usize) -> ([]u8, err) { ret (zero, os.Unsupported) }

// What `reserve` gave.
fn release(bytes: []u8) -> err { ret os.Unsupported }
