// A NeperOS program that spawns a thread through e.thread (C107, D2157): the worker runs in the
// same address space on its own kernel-mapped stack and writes a sentinel through a pointer into
// the spawner's memory; after the join the spawner reads it back, proving os.thread_create and
// os.thread_join over NeperOS. Started as program 0 of a one-program archive on the shell boot.
use e.mem
use e.io
use e.thread

type Box = struct { value: i64 }

fn worker(b: *Box) {
    b.value = 99i64
}

fn say(text: str) {
    let print_error = io.print(text)
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    say(digits[at..20usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    var box = Box { value: 0i64 }
    let (worker_thread, spawn_error) = thread.spawn[Box](worker, &box, 65536usize)
    if spawn_error != ok {
        say("thread spawn failed\n")
        ret ok
    }
    let join_error = thread.join(worker_thread)
    say("thread box = ")
    say_num(usize(box.value))
    say("\n")
    if box.value == 99i64 {
        say("thread wrote 99 via shared memory\n")
    } else {
        say("thread value wrong\n")
    }
    // Group spawn (D2185): three workers over three contexts, started together and reclaimed by one
    // join_all -- the barrier makes every worker's write visible, so a 0 means that worker never ran.
    var ctxs: [3]Box = [3]Box{ Box { value: 0i64 }, Box { value: 0i64 }, Box { value: 0i64 } }
    let (group, group_error) = thread.spawn_all[Box](a, worker, ctxs[0usize..], 65536usize)
    if group_error != ok {
        say("thread group spawn failed\n")
        ret ok
    }
    let join_all_error = thread.join_all(group)
    var all_ran = true
    var gi = 0usize
    while gi < 3usize {
        if ctxs[gi].value != 99i64 { all_ran = false }
        gi += 1usize
    }
    if all_ran {
        say("thread group of 3 joined\n")
    } else {
        say("thread group incomplete\n")
    }
    ret ok
}
