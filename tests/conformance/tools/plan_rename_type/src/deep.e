type Rec = struct { left: usize, right: usize }

fn make(n: usize) -> Rec {
    ret Rec { left: n, right: n }
}

fn rec_cmp(a: Rec, b: Rec) -> i32 {
    if a.left < b.left { ret 0i32 - 1i32 }
    if a.left > b.left { ret 1i32 }
    ret 0i32
}
