// What the compiler does differently by the machine it runs on, chosen by module variant
// (D5640): this file is every native host, platform.wasi.e the compiler built as neper.wasm.
// The C bootstrap ignores variants and always builds this one.

// The most workers a phase runs: as asked (0 is no limit), since threads exist.
fn jobs(asked: usize) -> usize { ret asked }

// A worker's reservation (D339): one page short of the root's capacity, the mark by which
// the runtime tells a reservation from the root. Reserved address costs nothing here.
fn reservation(root_capacity: usize) -> usize { ret root_capacity - 4096usize }

// The host's triple when the current directory's shape is not the answer, else "".
fn triple() -> str { ret "" }
