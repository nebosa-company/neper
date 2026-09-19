use e.mem

// A mutable call addressed through an aggregate's pointer field changes the
// pointed-to container, not the aggregate carrying that pointer (D687).
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
    let items = view(&holder.bag)
    let context = Context { target: &holder }
    mutate(&context.target.bag)
    if items[0usize] != 1u32 { ret mem.Exhausted }
    ret ok
}
