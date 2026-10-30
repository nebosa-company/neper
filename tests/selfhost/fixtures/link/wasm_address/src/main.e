// The 32-bit address row on wasm32-wasi (D5663): a memory access through a pointer whose bits above
// 31 are set traps in a debug build (`bounds`, "address N is outside the 32-bit memory"), where
// `i32.wrap_i64` would have reached some other cell. Without an argument the program does nothing,
// which is what the sweep runs; with one it forges a pointer (bit 40 set, built from a view whose
// base lies far below the offset) and uses it: `load`, `store` or `copy`. Native faults on such a
// pointer with no record, so the trap text is this target's own.
use e.mem
use e.os

type Pair = struct { first: u64, second: u64 }

fn forge(cell: *u8) -> *u8 {
    var window = mem.Arena { base: cell, cap: 1099511627784usize, off: 0usize }
    let far = mem.view(&window, 1099511627776usize, 1usize)
    ret &far[0usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret ok }
    var cell: [16]u8 = zero
    let wild = forge(&cell[0usize])
    let mode = args[1usize][0usize]
    if mode == 108u8 {
        let seen = *wild
        if seen != 0u8 { os.exit(1i32) }
    }
    if mode == 115u8 { *wild = 1u8 }
    if mode == 99u8 {
        let pair = mem.cast[*Pair](wild)
        var local: Pair = Pair { first: 1u64, second: 2u64 }
        *pair = local
    }
    os.exit(2i32)
    ret ok
}
