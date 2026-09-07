// The one situation the "ret is not legal inside defer" text is actually about.

fn guarded() -> usize {
    defer {
        ret 1usize
    }
    ret 0usize
}

fn main() -> err { ret ok }
