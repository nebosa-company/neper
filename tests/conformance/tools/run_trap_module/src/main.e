// A trap inside a dependency (D503): the run record's trap span and the frame in
// `deep` name that module's source under its own root, `project-src`, with the line
// and column the child printed, where both were null before.
use deep
use e.os

fn main() -> err {
    var bytes: [2]u8 = zero
    os.exit(i32(deep.pick(bytes[..], 5usize)))
    ret ok
}
