// `e.wasm` execution of hand-assembled modules: arithmetic, control flow (block, loop, if, br_table), recursion, linear memory and
// data segments, tables with call_indirect, 64-bit and float operations, conversions, and the traps the specification names.
use e.mem
use e.os
use e.wasm

fn run_case(a: *mem.Arena, bytes: []const u8, args: []const u64, want: u64, trap: err) -> i32 {
    let (m, de) = wasm.decode(a, bytes)
    if de != ok { ret 1i32 }
    let (st, se) = wasm.store_new(a)
    if se != ok { ret 2i32 }
    let none: [1]wasm.ImportVal = zero
    let (inst, ie) = wasm.instantiate(a, st, &m, none[0usize..0usize])
    if ie != ok { ret 3i32 }
    let (ex, found) = wasm.find_export(&m, "f")
    if !found { ret 4i32 }
    var out: [1]u64 = zero
    var nres = 0usize
    if m.types[usize(m.funcs[usize(ex.index)])].results.len > 0usize { nres = 1usize }
    let e = wasm.invoke(st, inst.funcs[usize(ex.index)], args, out[0usize..nres])
    if trap != ok {
        if e != trap { ret 5i32 }
        ret 0i32
    }
    if e != ok { ret 6i32 }
    if nres == 1usize && out[0usize] != want { ret 7i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    // add
    let m0 = [39]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 7u8, 1u8, 96u8, 2u8, 127u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 9u8, 1u8, 7u8, 0u8, 32u8, 0u8, 32u8, 1u8, 106u8, 11u8 }
    let a0 = [2]u64 { 3u64, 4u64 }
    let r0 = run_case(a, m0[0usize..39usize], a0[0usize..2usize], 7u64, ok)
    if r0 != 0i32 { os.exit(10 + r0) }
    // fact
    let m1 = [68]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 39u8, 1u8, 37u8, 1u8, 1u8, 127u8, 65u8, 1u8, 33u8, 1u8, 2u8, 64u8, 3u8, 64u8, 32u8, 0u8, 69u8, 13u8, 1u8, 32u8, 1u8, 32u8, 0u8, 108u8, 33u8, 1u8, 32u8, 0u8, 65u8, 1u8, 107u8, 33u8, 0u8, 12u8, 0u8, 11u8, 11u8, 32u8, 1u8, 11u8 }
    let a1 = [1]u64 { 5u64 }
    let r1 = run_case(a, m1[0usize..68usize], a1[0usize..1usize], 120u64, ok)
    if r1 != 0i32 { os.exit(20 + r1) }
    // divzero
    let m2 = [39]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 7u8, 1u8, 96u8, 2u8, 127u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 9u8, 1u8, 7u8, 0u8, 32u8, 0u8, 32u8, 1u8, 109u8, 11u8 }
    let a2 = [2]u64 { 1u64, 0u64 }
    let r2 = run_case(a, m2[0usize..39usize], a2[0usize..2usize], 0u64, wasm.TrapDivZero)
    if r2 != 0i32 { os.exit(30 + r2) }
    // divovf
    let m3 = [39]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 7u8, 1u8, 96u8, 2u8, 127u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 9u8, 1u8, 7u8, 0u8, 32u8, 0u8, 32u8, 1u8, 109u8, 11u8 }
    let a3 = [2]u64 { 2147483648u64, 4294967295u64 }
    let r3 = run_case(a, m3[0usize..39usize], a3[0usize..2usize], 0u64, wasm.TrapOverflow)
    if r3 != 0i32 { os.exit(40 + r3) }
    // mem
    let m4 = [65]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 5u8, 1u8, 96u8, 0u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 5u8, 3u8, 1u8, 0u8, 1u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 23u8, 1u8, 21u8, 0u8, 65u8, 8u8, 65u8, 227u8, 0u8, 54u8, 2u8, 0u8, 65u8, 8u8, 40u8, 2u8, 0u8, 65u8, 0u8, 45u8, 0u8, 0u8, 106u8, 11u8, 11u8, 7u8, 1u8, 0u8, 65u8, 0u8, 11u8, 1u8, 42u8 }
    let a4: [1]u64 = zero
    let r4 = run_case(a, m4[0usize..65usize], a4[0usize..0usize], 141u64, ok)
    if r4 != 0i32 { os.exit(50 + r4) }
    // oob
    let m5 = [44]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 5u8, 1u8, 96u8, 0u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 5u8, 3u8, 1u8, 0u8, 1u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 11u8, 1u8, 9u8, 0u8, 65u8, 255u8, 255u8, 3u8, 40u8, 2u8, 0u8, 11u8 }
    let a5: [1]u64 = zero
    let r5 = run_case(a, m5[0usize..44usize], a5[0usize..0usize], 0u64, wasm.TrapMemory)
    if r5 != 0i32 { os.exit(60 + r5) }
    // sqrt
    let m6 = [36]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 124u8, 1u8, 124u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 7u8, 1u8, 5u8, 0u8, 32u8, 0u8, 159u8, 11u8 }
    let a6 = [1]u64 { 4625196817309499392u64 }
    let r6 = run_case(a, m6[0usize..36usize], a6[0usize..1usize], 4616189618054758400u64, ok)
    if r6 != 0i32 { os.exit(70 + r6) }
    // fadd
    let m7 = [39]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 7u8, 1u8, 96u8, 2u8, 124u8, 124u8, 1u8, 124u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 9u8, 1u8, 7u8, 0u8, 32u8, 0u8, 32u8, 1u8, 160u8, 11u8 }
    let a7 = [2]u64 { 4609434218613702656u64, 4612248968380809216u64 }
    let r7 = run_case(a, m7[0usize..39usize], a7[0usize..2usize], 4615626668101337088u64, ok)
    if r7 != 0i32 { os.exit(80 + r7) }
    // indirect1
    let m8 = [70]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 10u8, 2u8, 96u8, 0u8, 1u8, 127u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 4u8, 3u8, 0u8, 0u8, 1u8, 4u8, 4u8, 1u8, 112u8, 0u8, 2u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 2u8, 9u8, 8u8, 1u8, 0u8, 65u8, 0u8, 11u8, 2u8, 0u8, 1u8, 10u8, 19u8, 3u8, 4u8, 0u8, 65u8, 10u8, 11u8, 4u8, 0u8, 65u8, 20u8, 11u8, 7u8, 0u8, 32u8, 0u8, 17u8, 0u8, 0u8, 11u8 }
    let a8 = [1]u64 { 1u64 }
    let r8 = run_case(a, m8[0usize..70usize], a8[0usize..1usize], 20u64, ok)
    if r8 != 0i32 { os.exit(90 + r8) }
    // indirect_oob
    let m9 = [70]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 10u8, 2u8, 96u8, 0u8, 1u8, 127u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 4u8, 3u8, 0u8, 0u8, 1u8, 4u8, 4u8, 1u8, 112u8, 0u8, 2u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 2u8, 9u8, 8u8, 1u8, 0u8, 65u8, 0u8, 11u8, 2u8, 0u8, 1u8, 10u8, 19u8, 3u8, 4u8, 0u8, 65u8, 10u8, 11u8, 4u8, 0u8, 65u8, 20u8, 11u8, 7u8, 0u8, 32u8, 0u8, 17u8, 0u8, 0u8, 11u8 }
    let a9 = [1]u64 { 5u64 }
    let r9 = run_case(a, m9[0usize..70usize], a9[0usize..1usize], 0u64, wasm.TrapTable)
    if r9 != 0i32 { os.exit(100 + r9) }
    // if_then
    let m10 = [43]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 14u8, 1u8, 12u8, 0u8, 32u8, 0u8, 4u8, 127u8, 65u8, 11u8, 5u8, 65u8, 22u8, 11u8, 11u8 }
    let a10 = [1]u64 { 1u64 }
    let r10 = run_case(a, m10[0usize..43usize], a10[0usize..1usize], 11u64, ok)
    if r10 != 0i32 { os.exit(110 + r10) }
    // if_else
    let m11 = [43]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 14u8, 1u8, 12u8, 0u8, 32u8, 0u8, 4u8, 127u8, 65u8, 11u8, 5u8, 65u8, 22u8, 11u8, 11u8 }
    let a11 = [1]u64 { 0u64 }
    let r11 = run_case(a, m11[0usize..43usize], a11[0usize..1usize], 22u64, ok)
    if r11 != 0i32 { os.exit(120 + r11) }
    // br_table0
    let m12 = [60]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 31u8, 1u8, 29u8, 0u8, 2u8, 64u8, 2u8, 64u8, 2u8, 64u8, 32u8, 0u8, 14u8, 2u8, 0u8, 1u8, 2u8, 11u8, 65u8, 228u8, 0u8, 15u8, 11u8, 65u8, 200u8, 1u8, 15u8, 11u8, 65u8, 172u8, 2u8, 11u8 }
    let a12 = [1]u64 { 0u64 }
    let r12 = run_case(a, m12[0usize..60usize], a12[0usize..1usize], 100u64, ok)
    if r12 != 0i32 { os.exit(130 + r12) }
    // br_table1
    let m13 = [60]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 31u8, 1u8, 29u8, 0u8, 2u8, 64u8, 2u8, 64u8, 2u8, 64u8, 32u8, 0u8, 14u8, 2u8, 0u8, 1u8, 2u8, 11u8, 65u8, 228u8, 0u8, 15u8, 11u8, 65u8, 200u8, 1u8, 15u8, 11u8, 65u8, 172u8, 2u8, 11u8 }
    let a13 = [1]u64 { 1u64 }
    let r13 = run_case(a, m13[0usize..60usize], a13[0usize..1usize], 200u64, ok)
    if r13 != 0i32 { os.exit(140 + r13) }
    // br_table9
    let m14 = [60]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 31u8, 1u8, 29u8, 0u8, 2u8, 64u8, 2u8, 64u8, 2u8, 64u8, 32u8, 0u8, 14u8, 2u8, 0u8, 1u8, 2u8, 11u8, 65u8, 228u8, 0u8, 15u8, 11u8, 65u8, 200u8, 1u8, 15u8, 11u8, 65u8, 172u8, 2u8, 11u8 }
    let a14 = [1]u64 { 9u64 }
    let r14 = run_case(a, m14[0usize..60usize], a14[0usize..1usize], 300u64, ok)
    if r14 != 0i32 { os.exit(150 + r14) }
    // unreachable
    let m15 = [32]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 4u8, 1u8, 96u8, 0u8, 0u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 5u8, 1u8, 3u8, 0u8, 0u8, 11u8 }
    let a15: [1]u64 = zero
    let r15 = run_case(a, m15[0usize..32usize], a15[0usize..0usize], 0u64, wasm.TrapUnreachable)
    if r15 != 0i32 { os.exit(160 + r15) }
    // fib
    let m16 = [59]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 30u8, 1u8, 28u8, 0u8, 32u8, 0u8, 65u8, 2u8, 72u8, 4u8, 127u8, 32u8, 0u8, 5u8, 32u8, 0u8, 65u8, 1u8, 107u8, 16u8, 0u8, 32u8, 0u8, 65u8, 2u8, 107u8, 16u8, 0u8, 106u8, 11u8, 11u8 }
    let a16 = [1]u64 { 15u64 }
    let r16 = run_case(a, m16[0usize..59usize], a16[0usize..1usize], 610u64, ok)
    if r16 != 0i32 { os.exit(170 + r16) }
    // i64mul
    let m17 = [41]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 5u8, 1u8, 96u8, 0u8, 1u8, 126u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 13u8, 1u8, 11u8, 0u8, 66u8, 128u8, 188u8, 193u8, 150u8, 11u8, 66u8, 7u8, 126u8, 11u8 }
    let a17: [1]u64 = zero
    let r17 = run_case(a, m17[0usize..41usize], a17[0usize..0usize], 21000000000u64, ok)
    if r17 != 0i32 { os.exit(180 + r17) }
    // trunc_sat
    let m18 = [37]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 124u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 8u8, 1u8, 6u8, 0u8, 32u8, 0u8, 252u8, 2u8, 11u8 }
    let a18 = [1]u64 { 4906019910204099648u64 }
    let r18 = run_case(a, m18[0usize..37usize], a18[0usize..1usize], 2147483647u64, ok)
    if r18 != 0i32 { os.exit(190 + r18) }
    // extend8
    let m19 = [36]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 7u8, 1u8, 5u8, 0u8, 32u8, 0u8, 192u8, 11u8 }
    let a19 = [1]u64 { 128u64 }
    let r19 = run_case(a, m19[0usize..36usize], a19[0usize..1usize], 4294967168u64, ok)
    if r19 != 0i32 { os.exit(200 + r19) }
    // popcnt
    let m20 = [36]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 7u8, 1u8, 5u8, 0u8, 32u8, 0u8, 105u8, 11u8 }
    let a20 = [1]u64 { 61680u64 }
    let r20 = run_case(a, m20[0usize..36usize], a20[0usize..1usize], 8u64, ok)
    if r20 != 0i32 { os.exit(210 + r20) }
    // rotl
    let m21 = [39]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 7u8, 1u8, 96u8, 2u8, 127u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 9u8, 1u8, 7u8, 0u8, 32u8, 0u8, 32u8, 1u8, 119u8, 11u8 }
    let a21 = [2]u64 { 2147483649u64, 1u64 }
    let r21 = run_case(a, m21[0usize..39usize], a21[0usize..2usize], 3u64, ok)
    if r21 != 0i32 { os.exit(220 + r21) }
    // shr_s
    let m22 = [39]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 7u8, 1u8, 96u8, 2u8, 127u8, 127u8, 1u8, 127u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 9u8, 1u8, 7u8, 0u8, 32u8, 0u8, 32u8, 1u8, 117u8, 11u8 }
    let a22 = [2]u64 { 2147483648u64, 4u64 }
    let r22 = run_case(a, m22[0usize..39usize], a22[0usize..2usize], 4160749568u64, ok)
    if r22 != 0i32 { os.exit(230 + r22) }
    // u64conv
    let m23 = [36]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 6u8, 1u8, 96u8, 1u8, 126u8, 1u8, 124u8, 3u8, 2u8, 1u8, 0u8, 7u8, 5u8, 1u8, 1u8, 102u8, 0u8, 0u8, 10u8, 7u8, 1u8, 5u8, 0u8, 32u8, 0u8, 186u8, 11u8 }
    let a23 = [1]u64 { 18446744073709551615u64 }
    let r23 = run_case(a, m23[0usize..36usize], a23[0usize..1usize], 4895412794951729152u64, ok)
    if r23 != 0i32 { os.exit(240 + r23) }
    ret ok
}
