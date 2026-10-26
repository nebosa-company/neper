// A null function value called two frames deep. Native ends it with an access violation
// (D5604); under WebAssembly the engine traps in `call_indirect` and the runner names the
// line of the call from the module's source map (C211, D5683).
use e.mem

error Failed

type Hook = struct { run: fn(i64) -> i64 }

fn double(v: i64) -> i64 { ret v + v }

fn fire(hook: *const Hook, v: i64) -> i64 {
    ret hook.run(v + 1i64)
}

fn relay(hook: *const Hook, v: i64) -> i64 {
    let fired = fire(hook, v)
    ret fired + 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var hook: Hook = zero
    if args.len > 100usize { hook.run = double }
    if relay(&hook, 3i64) == 9i64 { ret Failed }
    ret ok
}
