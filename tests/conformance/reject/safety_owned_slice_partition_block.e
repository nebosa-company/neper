use e.os

fn close_all(files: own []os.File) {
    var i = 0usize
    while i < files.len {
        let _ = os.close(files[i])
        i += 1usize
    }
}

// (D1566, H01) The first side handed over in an arm that ends without the other: the arm's path
// and the path around it cannot both owe the rest, so the arm's end refuses it.
fn split(files: own []os.File, k: usize, early: bool) {
    if early {
        close_all(files[..k])
    }
    close_all(files[k..])
}

fn main() {}
