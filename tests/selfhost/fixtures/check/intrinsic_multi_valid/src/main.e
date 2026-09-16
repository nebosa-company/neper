use e.os as os

fn run(file: os.File, bytes: []u8) -> err {
    let (first_count, first_error) = os.read(file, bytes)
    let second_count = try os.read(file, bytes)
    var third_count = 0usize
    var third_error: err = ok
    (third_count, third_error) = os.read(file, bytes)
    var fourth_count = 0usize
    fourth_count = try os.read(file, bytes)
    ret third_error
}
