use e.mem
use e.thread

// A thread group is a resource owed to `thread.join_all` (D434, H04): an exit
// with the group unjoined is E-SAFETY-0002, as one thread's is.
type Slot = struct { hits: u32 }

fn work(s: *Slot) {
    s.hits = s.hits + 1u32
}

fn start(a: *mem.Arena, slots: []Slot, fail: bool) -> err {
    let (group, spawn_error) = thread.spawn_all[Slot](a, work, slots, 0usize)
    if spawn_error != ok { ret spawn_error }
    if fail { ret mem.Exhausted }
    ret thread.join_all(group)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (slots, slots_error) = mem.alloc[Slot](a, 2usize)
    if slots_error != ok { ret slots_error }
    ret start(a, slots, args.len > 3usize)
}
