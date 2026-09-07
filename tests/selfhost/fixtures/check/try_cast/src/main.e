// `try` needs a call that can fail; a conversion cannot.

fn narrowed(v: i64) -> err {
    try i32(v)
    ret ok
}

fn main() -> err { ret ok }
