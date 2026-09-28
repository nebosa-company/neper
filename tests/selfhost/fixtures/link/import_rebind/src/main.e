// A warm build after an extern's `@import` changes rebuilds every module compiled
// against the old binding (D1672): `direct` calls `plat.ident` by name, and `seq`
// reaches `plat.key_hash` only through a sequence's supplied `hash`.
use direct
use seq

error DirectFailed
error SequenceFailed

fn main() -> err {
    if !direct.run() { ret DirectFailed }
    if !seq.run() { ret SequenceFailed }
    ret ok
}
