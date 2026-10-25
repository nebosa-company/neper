// The module shape of a `--threads` build (D5671, C186): what wasm.e writes differently when
// the program may run on more than one thread. The memory is imported and shared, every data
// segment is passive and copied in by `_start`, and the wasi-threads entry `wasi_thread_start`
// is exported. The atomics are wasm_code.e's (D5672).
use wasm_code as w

// The global indices: `$sp` and `$floor` as in a plain module, then the thread's id.
const GLOBAL_SP: usize = 0usize
const GLOBAL_FLOOR: usize = 1usize
const GLOBAL_TID: usize = 2usize

// The number of data segments, in the order write_data writes them: the blob, then one
// per used global with a nonzero initial value.
fn segment_count(gen: *w.Gen) -> usize {
    var segments = 0usize
    if gen.data.count != 0usize { segments = 1usize }
    var global_at = 0usize
    while global_at < gen.b.global_count {
        if gen.global_used[global_at] && gen.b.globals[global_at].has_initial && gen.b.globals[global_at].initial != 0usize { segments += 1usize }
        global_at += 1usize
    }
    ret segments
}

// `memory.init k` of the whole segment to its address.
fn init_segment(gen: *w.Gen, address: usize, length: usize, k: usize) {
    w.i32c(gen, address)
    w.i32c(gen, 0usize)
    w.i32c(gen, length)
    w.op(gen, 252usize)
    w.op(gen, 8usize)
    w.put_uleb(&gen.code, k)
    w.op(gen, 0usize)
}

// What `_start` begins with: every passive segment copied to where an active one would have
// put it, then dropped. An active segment is applied again by each thread's instantiation and
// would reset what the program wrote over it (D5670).
fn write_segment_init(gen: *w.Gen) {
    var k = 0usize
    if gen.data.count != 0usize {
        init_segment(gen, gen.data_base, gen.data.count, k)
        k += 1usize
    }
    var global_at = 0usize
    while global_at < gen.b.global_count {
        let item = gen.b.globals[global_at]
        if gen.global_used[global_at] && item.has_initial && item.initial != 0usize {
            var width = item.size
            if width > 8usize { width = 8usize }
            init_segment(gen, gen.global_address[global_at], width, k)
            k += 1usize
        }
        global_at += 1usize
    }
    var drop_at = 0usize
    while drop_at < k {
        w.op(gen, 252usize)
        w.op(gen, 9usize)
        w.put_uleb(&gen.code, drop_at)
        drop_at += 1usize
    }
}

// `local.get`, `global.set`.
fn local_get(gen: *w.Gen, index: usize) {
    w.op(gen, 32usize)
    w.put_uleb(&gen.code, index)
}

fn global_set(gen: *w.Gen, index: usize) {
    w.op(gen, 36usize)
    w.put_uleb(&gen.code, index)
}

// `wasi_thread_start(tid, block)` (D5673): the thread's id, its stack from the block
// `os.wasi.e` wrote, the entry called with its context, and the block's state word cleared
// and its joiners woken, the last things the thread touches. `entry_signature` is the type
// `(i64) -> ()` of the function value.
fn write_thread_start(gen: *w.Gen, entry_signature: usize) {
    gen.code.count = 0usize
    w.put_uleb(&gen.code, 0usize)
    local_get(gen, 0usize)
    global_set(gen, GLOBAL_TID)
    local_get(gen, 1usize)
    w.op(gen, 41usize)
    w.memarg(gen, 24usize)
    global_set(gen, GLOBAL_SP)
    local_get(gen, 1usize)
    w.op(gen, 41usize)
    w.memarg(gen, 32usize)
    global_set(gen, GLOBAL_FLOOR)
    local_get(gen, 1usize)
    w.op(gen, 41usize)
    w.memarg(gen, 16usize)
    local_get(gen, 1usize)
    w.op(gen, 41usize)
    w.memarg(gen, 8usize)
    w.wrap(gen)
    w.op(gen, 17usize)
    w.put_uleb(&gen.code, entry_signature)
    w.op(gen, 0usize)
    local_get(gen, 1usize)
    w.i32c(gen, 0usize)
    w.atomic_instruction(gen, 23usize, 2usize)
    local_get(gen, 1usize)
    w.i32c(gen, 4294967295usize)
    w.atomic_instruction(gen, 0usize, 2usize)
    w.op(gen, 26usize)
    w.op(gen, 11usize)
    w.put_uleb(&gen.bodies, gen.code.count)
    w.put_bytes(&gen.bodies, &gen.code)
}

// The memory a threaded module imports: `env.memory`, shared, from `pages` pages to the
// 4 GiB a 32-bit memory can reach. A shared maximum costs nothing until it is grown (D5670).
fn write_memory_import(body: *w.Out, pages: usize) {
    w.put_name(body, "env")
    w.put_name(body, "memory")
    w.put(body, 2usize)
    w.put(body, 3usize)
    w.put_uleb(body, pages)
    w.put_uleb(body, 65536usize)
}
