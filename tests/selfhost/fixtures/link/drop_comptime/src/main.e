// A module's tokens and tree go right after its own artifact is written (D1668), and a
// comptime call into it from a module lowered later parses it again from its text. p, q
// and r are modules 1, 2 and 3: at `-j 1` p reads q in place, q goes, and r parses q
// privately; `--perturb` turns that order around; `--fault-dry 2` has the generous worker
// lower p, q and r after the first worker's modules went; `-j 3 --perturb` puts q on a
// thread of its own. Every image is one, and the program exits 0.
use p
use q
use r

fn main() -> i64 {
    if q.run() != 1i64 { ret 1i64 }
    if p.run(7u8) != 30i64 { ret 2i64 }
    if r.run(7u8) != 300i64 { ret 3i64 }
    if p.run(1u8) != 2010i64 { ret 4i64 }
    ret 0i64
}
