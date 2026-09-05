use e.mem as mem
use e.os as os

fn run(a: *mem.Arena, file: os.File, pointer: *u8, count: usize) {
    let output: os.File = os.stdout()
    let failure: os.File = os.stderr()
    let mark: usize = mem.mark(a)
    let stats: mem.Stats = mem.stats(a)
    let closed: err = os.close(file)
    let committed: err = os.commit(pointer, count)
    mem.reset(a, mark)
    os.exit(0)
}
