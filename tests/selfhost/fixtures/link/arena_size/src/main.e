// `emit-executable --arena SIZE` (D225): the root arena is the size given rather than
// the runtime's default. An allocation of twelve mebibytes fits the default and not an
// arena of eight, so the build with `--arena 8m` fails it -- `main` returns
// `mem.Exhausted`, exit 1 -- and the build without succeeds, on both platforms.
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let (block, block_error) = mem.alloc[u8](a, 12582912usize)
    if block_error != ok { ret block_error }
    block[12582911] = 7u8
    if block[12582911] != 7u8 { ret mem.Exhausted }
    ret ok
}
