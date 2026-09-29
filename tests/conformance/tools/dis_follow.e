// `dis` follows jumps (T010): a string's bytes are laid inline behind a `jmp`, and these
// ones read as code -- `nop`, `ret`, a `jmp` into the next function -- so a sweep listed
// them as instructions. They are one `db` line, and the `lea` after them is decoded
// where it starts.
use e.os

fn table() -> str {
    ret "\x90\xc3\xe9\x10\x00\x00\x00\xcc\xff"
}

fn main() {
    os.exit(i32(table().len))
}
