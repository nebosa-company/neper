use e.os

// A zero-to-length sweep consumes every element of an owned resource slice.
fn drain(files: own []os.File) -> err {
    var i = 0usize
    while i < files.len {
        try os.close(files[i])
        i += 1usize
    }
    ret ok
}

fn main() -> err { ret ok }
