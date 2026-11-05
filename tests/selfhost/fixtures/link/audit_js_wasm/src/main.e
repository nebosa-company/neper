// `e.js.bigint` and `e.js.b_wasm` gaps, driven through `e.js.realm`: a BigInt too large
// for a Number converts to Infinity without walking every chunk, a detached/out-of-bounds
// BufferSource is a TypeError rather than an empty module, and customSections returns the
// payloads of the matching custom section. Each check has its own exit code.
use e.js.interp as js
use e.js.realm as realm
use e.mem
use e.os
use e.str

fn run_bool(it: *js.Interp, source: str) -> (bool, err) {
    let (v, e) = realm.run(it, source)
    if e != ok { ret (false, e) }
    ret (js.to_boolean(v), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, realm_error) = realm.new_realm(a)
    if realm_error != ok { os.exit(1i32) }
    it.quiet = true
    // #819: 2^5000 is far past the finite range; the conversion answers Infinity.
    let (huge, huge_error) = run_bool(it, "Number(1n << 5000n) === Infinity")
    if huge_error != ok || !huge { os.exit(10i32) }
    let (large, large_error) = run_bool(it, "Number(1n << 1000n) > 1e300")
    if large_error != ok || !large { os.exit(11i32) }
    // #818: a view over a detached buffer is not an empty module.
    let (detached_view, detached_view_error) = run_bool(it, "(function () { var b = new ArrayBuffer(8); var v = new Uint8Array(b); var moved = b.transfer(); try { new WebAssembly.Module(v); return false; } catch (e) { return e instanceof TypeError; } })()")
    if detached_view_error != ok || !detached_view { os.exit(20i32) }
    // #818: nor is a detached ArrayBuffer.
    let (detached, detached_error) = run_bool(it, "(function () { var b = new ArrayBuffer(8); var moved = b.transfer(); try { WebAssembly.validate(b); return false; } catch (e) { return e instanceof TypeError; } })()")
    if detached_error != ok || !detached { os.exit(21i32) }
    // #817: the custom section's payload comes back as an ArrayBuffer.
    let custom = "(function () { var bytes = new Uint8Array([0,97,115,109,1,0,0,0,0,6,3,97,98,99,1,2]); var m = new WebAssembly.Module(bytes); var s = WebAssembly.Module.customSections(m, 'abc'); if (s.length !== 1 || s[0].byteLength !== 2) return false; var u = new Uint8Array(s[0]); return u[0] === 1 && u[1] === 2; })()"
    let (section, section_error) = run_bool(it, custom)
    if section_error != ok || !section { os.exit(30i32) }
    ret ok
}
