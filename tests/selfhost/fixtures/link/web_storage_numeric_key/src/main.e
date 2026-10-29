use e.fmt.dom as dom
use e.fmt.html as html
use e.mem
use e.os
use e.web.script as script

fn main(a: *mem.Arena, args: []str) -> err {
    let options = html.Options { max_bytes: 1048576usize, max_nodes: 4096usize, max_attributes: 64usize, max_depth: 64u16, preserve_comments: false }
    let (parsed, parse_error) = dom.parse(a, "<!doctype html><html><body></body></html>", options, 32usize)
    if parse_error != ok { os.exit(1i32) }
    var tree = parsed
    let (context, context_error) = script.new_context(a, &tree, "https://storage-numeric.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const storage = localStorage; storage.clear(); storage.setItem('0', 'one'); storage.setItem('01', 'leading'); const descriptor = Object.getOwnPropertyDescriptor(storage, '0'); window.storageBefore = [storage['0'], storage['01'], '0' in storage, '01' in storage, descriptor === undefined ? null : descriptor.value, Object.keys(storage).indexOf('0') >= 0, Object.keys(storage).indexOf('01') >= 0]; storage['0'] = 'two'; const deleted = delete storage['0']; window.storageAfter = [storage.getItem('0'), deleted, '0' in storage, Object.getOwnPropertyDescriptor(storage, '0') === undefined, Object.keys(storage).indexOf('0') < 0, storage.getItem('01')];"
    if !script.run_script(context, setup, "storage-numeric-key-setup.js") { os.exit(3i32) }
    let check = "const before = window.storageBefore; const after = window.storageAfter; if (before[0] !== 'one' || before[1] !== 'leading' || before[2] !== true || before[3] !== true || before[4] !== 'one' || before[5] !== true || before[6] !== true) throw new Error('numeric Storage key was not exposed as a named property'); if (after[0] !== null || after[1] !== true || after[2] !== false || after[3] !== true || after[4] !== true || after[5] !== 'leading') throw new Error('numeric Storage key was not written or deleted as a named property');"
    if !script.run_script(context, check, "storage-numeric-key-check.js") { os.exit(4i32) }
    ret ok
}
