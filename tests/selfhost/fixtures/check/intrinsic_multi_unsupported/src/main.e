use e.os as os

fn run(file: os.File, bytes: []u8) {
    os.read(file, bytes)
}
