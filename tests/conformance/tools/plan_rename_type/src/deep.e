type Rec = struct { left: usize, right: usize }

fn make(n: usize) -> Rec {
    ret Rec { left: n, right: n }
}
