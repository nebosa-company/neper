use e.mem

// A view returned through an address reached by an aggregate pointer field belongs
// to the pointed-to container, not to the aggregate carrying the pointer (D688).
type Bag = struct { items: [2]u32 }
type Holder = struct { bag: Bag }
type Context = struct { target: *Holder }

fn view(bag: *Bag) -> []u32 {
    ret bag.items[0usize..]
}

fn mutate(bag: *Bag) {
    bag.items[0usize] = 2u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var holder = Holder { bag: Bag { items: [2]u32{ 1u32, 0u32 } } }
    let context = Context { target: &holder }
    let items = view(&context.target.bag)
    mutate(&holder.bag)
    if items[0usize] != 1u32 { ret mem.Exhausted }
    ret ok
}
