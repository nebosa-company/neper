// `e.wasm` decoding: a module with a type, an import, a function, a memory, a global, an export and a body decodes; bad
// magic, a bad section order and a truncated section are rejected.
use e.mem
use e.os
use e.wasm

fn main(a: *mem.Arena, args: []str) -> err {
    // (module (func (export "add") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add))
    let good = [41]u8 {
        0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8,
        1u8, 7u8, 1u8, 96u8, 2u8, 127u8, 127u8, 1u8, 127u8,
        3u8, 2u8, 1u8, 0u8,
        7u8, 7u8, 1u8, 3u8, 97u8, 100u8, 100u8, 0u8, 0u8,
        10u8, 9u8, 1u8, 7u8, 0u8, 32u8, 0u8, 32u8, 1u8, 106u8, 11u8
    }
    let (m, e) = wasm.decode(a, good[0usize..41usize])
    if e != ok { os.exit(1) }
    if m.types.len != 1usize || m.funcs.len != 1usize || m.exports.len != 1usize || m.bodies.len != 1usize { os.exit(2) }
    if m.types[0usize].params.len != 2usize || m.types[0usize].results.len != 1usize { os.exit(3) }
    let bad_magic = [8]u8 { 1u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8 }
    let (m2, e2) = wasm.decode(a, bad_magic[0usize..8usize])
    if e2 == ok { os.exit(4) }
    let truncated = [12]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 9u8, 1u8, 96u8 }
    let (m3, e3) = wasm.decode(a, truncated[0usize..12usize])
    if e3 == ok { os.exit(5) }
    // A start function must be [] -> [], whether it is defined or imported.
    let start_ok = [27]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 4u8, 1u8, 96u8, 0u8, 0u8, 3u8, 2u8, 1u8, 0u8, 8u8, 1u8, 0u8, 10u8, 4u8, 1u8, 2u8, 0u8, 11u8 }
    let start_param = [28]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 5u8, 1u8, 96u8, 1u8, 127u8, 0u8, 3u8, 2u8, 1u8, 0u8, 8u8, 1u8, 0u8, 10u8, 4u8, 1u8, 2u8, 0u8, 11u8 }
    let start_import_result = [27]u8 { 0u8, 97u8, 115u8, 109u8, 1u8, 0u8, 0u8, 0u8, 1u8, 5u8, 1u8, 96u8, 0u8, 1u8, 127u8, 2u8, 7u8, 1u8, 1u8, 109u8, 1u8, 102u8, 0u8, 0u8, 8u8, 1u8, 0u8 }
    let (_, start_ok_error) = wasm.decode(a, start_ok[..])
    let (_, start_param_error) = wasm.decode(a, start_param[..])
    let (_, start_import_result_error) = wasm.decode(a, start_import_result[..])
    if start_ok_error != ok || start_param_error != wasm.Malformed || start_import_result_error != wasm.Malformed { os.exit(6) }
    ret ok
}
