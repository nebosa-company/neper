// Section 12's incremental rebuild on the edge rule, driven by the runner: this tree is
// copied to a scratch directory and compiled to artifacts once; `emit-em-all
// --incremental` over unchanged sources keeps every artifact; `edits/dep_body.e` over
// `dep.e` changes a body behind a signature edge, so `dep` is rebuilt and `main` kept,
// the linked result equals a clean build and exits 8; `edits/dep_signature.e` with
// `edits/main_signature.e` changes the signature, so both are rebuilt.
use dep
use e.os

fn main() -> err {
    os.exit(dep.answer(3i32))
    ret ok
}
