// A release build must compile a program that links the GPU module (round 268).
//
// The release inliner lowers each candidate body with the instruction cap armed. `nir.emit` reports
// `TooLong` when the cap is passed, but `begin_block`, `set_terminator` and the operand rows can refuse
// control flow of their own accord, and those refusals used to escape as a hard `cannot lower` error
// naming whichever function happened to be over the line. `e.gpu` is the module that reproduced it:
// `emit-executable minigpu.e --release` failed on `subgroup_add_u64`, and the failing function moved to
// `subgroup_exchange64` at --inline-cap 8 and `subgroup_begin` at 16 - proof that the cap, not the
// function, was the trigger.
//
// Build it with `scripts/check-fixture.sh gpu_release --release`: before the fix that build could not
// emit at all, so reaching this body is the regression check. The arithmetic below is an ordinary
// loop so the release inliner has work to do inside main itself as well.
use e.mem
use e.gpu

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    var total = 0usize
    var i = 0usize
    while i < 8usize {
        total = total + i * 3usize
        i += 1usize
    }
    if total != 84usize { ret Failed }
    // A reference into `gpu` keeps its bodies in the oracle's candidate set instead of linking the module away.
    let backend = gpu.Backend.Cpu
    if backend != gpu.Backend.Cpu { ret Failed }
    ret ok
}
