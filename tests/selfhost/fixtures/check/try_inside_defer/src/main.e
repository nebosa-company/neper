// The one situation the "try is not legal inside defer" text is actually about.

fn fallible() -> err {
    ret ok
}

fn guarded() -> err {
    defer {
        try fallible()
    }
    ret ok
}

fn main() -> err { ret ok }
