use e.mem

// A mutable call through a runtime-selected pointer may change either candidate,
// so views of every possible container end at the call (D713).
type Bag = struct { items: [2]u32 }

fn view(bag: *Bag) -> []u32 {
    ret bag.items[0usize..]
}

fn mutate(bag: *Bag) {
    bag.items[0usize] = 2u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var first = Bag { items: [2]u32{ 1u32, 0u32 } }
    var second = Bag { items: [2]u32{ 1u32, 0u32 } }
    let items = view(&second)
    let targets = [2usize]*Bag{ &first, &second }
    let which = args.len % 2usize
    mutate(targets[which])
    if items[0usize] != 1u32 { ret mem.Exhausted }
    ret ok
}
