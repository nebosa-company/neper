use e.mem

// Runtime selection remains a candidate set below a named aggregate field; the
// nested path cannot hide the array element whose owner was reset (D715).
type Context = struct { targets: [2usize]*u8 }

fn main(a: *mem.Arena, args: []str) -> err {
    var stable = 1u8
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let context = Context { targets: [2usize]*u8{ &stable, &scratch[0usize] } }
    mem.reset(a, checkpoint)
    let which = args.len % 2usize
    if *context.targets[which] != 0u8 { ret mem.Exhausted }
    ret ok
}
