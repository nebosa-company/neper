// (D5933) A block is never freed: refused, with no run to find it.
use e.mem
use e.mem.heap

fn main(a: *mem.Arena, args: []str) -> err {
    let (h, open_error) = heap.open(1073741824usize)
    if open_error != ok { ret open_error }
    let (block, block_error) = heap.alloc(h, 64usize)
    if block_error != ok { ret block_error }
    ret heap.close(h)
}
