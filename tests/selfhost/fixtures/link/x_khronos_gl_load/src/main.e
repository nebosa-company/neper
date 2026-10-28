// x.khronos.gl's loader without a driver (L172, L173): a resolver that finds every entry
// fills the table for each profile; one that lacks glDispatchCompute fails the compute
// profiles (GL 4.3, GL 4.6, GLES 3.1) by name and passes GL 3.3 and GLES 3.0, which do not
// require it; one that lacks glClear fails every profile. EGL from a library that does not
// exist is NoLoader. The version parser reads desktop and ES strings through a fake glGetString.

use e.atomic
use e.mem
use e.os
use e.sync
use x.khronos.egl
use x.khronos.gl

var version_text: [64]u8 = zero

fn fake_get_string(name: u32) -> *const u8 { ret &version_text[0usize] }

type ProcPun = union { function: fn(u32) -> *const u8, bits: usize }
type ErrorPun = union { function: fn() -> u32, bits: usize }

fn every(a: *mem.Arena, context: usize, name: str) -> usize {
    if mem.eq[u8](name, "glGetString") {
        var pun: ProcPun = zero
        pun.function = fake_get_string
        ret pun.bits
    }
    ret 4096usize
}

fn error_left() -> u32 { ret 17u32 }
fn error_right() -> u32 { ret 29u32 }

// Two resolvers that differ only in glGetError. Once both threads have loaded, each must still
// call the resolver it loaded rather than whichever context most recently rewrote a global table.
fn separated(a: *mem.Arena, context: usize, name: str) -> usize {
    if mem.eq[u8](name, "glGetError") {
        var pun: ErrorPun = zero
        if context == 1usize { pun.function = error_left } else { pun.function = error_right }
        ret pun.bits
    }
    ret 4096usize
}

type DispatchRace = struct { gate: sync.Semaphore, ready: sync.Semaphore, release: sync.Semaphore, abort: Atomic[u32], failed: Atomic[u32], answers: [2]Atomic[u32] }
type DispatchTask = struct { race: *DispatchRace, index: usize, context: usize }

fn load_on_thread(task: *DispatchTask) {
    sync.semaphore_wait(&task.race.gate)
    if atomic.load(&task.race.abort, .Acquire) != 0u32 { ret }
    var scratch: mem.Arena = zero
    var dispatch: gl.Dispatch = zero
    if gl.load(&scratch, .Gl33Core, separated, task.context, &dispatch) != ok {
        atomic.store(&task.race.failed, 1u32, .Release)
    }
    let posted = sync.semaphore_post(&task.race.ready, 1u32)
    sync.semaphore_wait(&task.race.release)
    if atomic.load(&task.race.failed, .Acquire) == 0u32 {
        // A lost activation mapping must be reported as a fixture failure rather than calling
        // through a null entry point.
        if !gl.present(gl.GET_ERROR_ENTRY) {
            atomic.store(&task.race.failed, 1u32, .Release)
        } else {
            atomic.store(&task.race.answers[task.index], gl.get_error(), .Release)
        }
    }
    gl.release(&dispatch)
}

fn isolated_dispatches_once() -> bool {
    var race: DispatchRace = zero
    race.gate = sync.semaphore(0u32)
    race.ready = sync.semaphore(0u32)
    race.release = sync.semaphore(0u32)
    var left = DispatchTask { race: &race, index: 0usize, context: 1usize }
    var right = DispatchTask { race: &race, index: 1usize, context: 2usize }
    let (first, first_error) = os.thread_create[DispatchTask](load_on_thread, &left, 1048576usize)
    if first_error != ok { ret false }
    let (second, second_error) = os.thread_create[DispatchTask](load_on_thread, &right, 1048576usize)
    if second_error != ok {
        atomic.store(&race.abort, 1u32, .Release)
        let opened = sync.semaphore_post(&race.gate, 1u32)
        let joined = os.thread_join(first)
        ret false
    }
    let opened = sync.semaphore_post(&race.gate, 2u32)
    sync.semaphore_wait(&race.ready)
    sync.semaphore_wait(&race.ready)
    let released = sync.semaphore_post(&race.release, 2u32)
    if os.thread_join(first) != ok || os.thread_join(second) != ok { ret false }
    if atomic.load(&race.failed, .Acquire) != 0u32 { ret false }
    ret atomic.load(&race.answers[0usize], .Acquire) == 17u32 && atomic.load(&race.answers[1usize], .Acquire) == 29u32
}

// Repeat concurrent first activation enough times to cover the brief row-claim transition
// without making the no-driver loader fixture slow.
fn isolated_dispatches() -> bool {
    var round = 0usize
    while round < 16usize {
        if !isolated_dispatches_once() { ret false }
        round += 1usize
    }
    ret true
}

// Whether `name` is `entry` or `entry` with a vendor suffix: `load` asks for those too (glGetnTexImageARB on Intel).
fn spelled(name: str, entry: str) -> bool {
    if name.len < entry.len || !mem.eq[u8](name[0usize..entry.len], entry) { ret false }
    let rest = name[entry.len..name.len]
    ret rest.len == 0usize || mem.eq[u8](rest, "ARB") || mem.eq[u8](rest, "KHR") || mem.eq[u8](rest, "EXT")
}

fn without_dispatch(a: *mem.Arena, context: usize, name: str) -> usize {
    if spelled(name, "glDispatchCompute") { ret 0usize }
    ret 4096usize
}

fn without_clear(a: *mem.Arena, context: usize, name: str) -> usize {
    if spelled(name, "glClear") { ret 0usize }
    ret 4096usize
}

// Answers only the ARB spelling of glDispatchCompute: `load` takes it.
fn suffix_only(a: *mem.Arena, context: usize, name: str) -> usize {
    if mem.eq[u8](name, "glDispatchCompute") { ret 0usize }
    ret 4096usize
}

fn set_version(words: str) {
    var k = 0usize
    while k < words.len {
        version_text[k] = words[k]
        k += 1usize
    }
    version_text[words.len] = 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !isolated_dispatches() { os.exit(1i32) }
    var dispatch: gl.Dispatch = zero
    if gl.load(a, .Gl33Core, every, 0usize, &dispatch) != ok { os.exit(2i32) }
    if gl.load(a, .Gl46Core, every, 0usize, &dispatch) != ok { os.exit(3i32) }
    if gl.load(a, .Gles32, every, 0usize, &dispatch) != ok { os.exit(4i32) }
    if gl.missing().len != 0usize { os.exit(5i32) }

    if gl.load(a, .Gl33Core, without_dispatch, 0usize, &dispatch) != ok { os.exit(6i32) }
    if gl.load(a, .Gles30, without_dispatch, 0usize, &dispatch) != ok { os.exit(7i32) }
    if gl.load(a, .Gl43Core, without_dispatch, 0usize, &dispatch) != gl.Unsupported { os.exit(8i32) }
    if !mem.eq[u8](gl.missing(), "glDispatchCompute") { os.exit(9i32) }
    if gl.load(a, .Gl46Core, without_dispatch, 0usize, &dispatch) != gl.Unsupported { os.exit(10i32) }
    if gl.load(a, .Gles31, without_dispatch, 0usize, &dispatch) != gl.Unsupported { os.exit(11i32) }

    if gl.load(a, .Gl33Core, without_clear, 0usize, &dispatch) != gl.Unsupported { os.exit(12i32) }
    if !mem.eq[u8](gl.missing(), "glClear") { os.exit(13i32) }
    if gl.load(a, .Gles30, without_clear, 0usize, &dispatch) != gl.Unsupported { os.exit(14i32) }
    if gl.load(a, .Gl43Core, suffix_only, 0usize, &dispatch) != ok || !gl.present(gl.DISPATCH_COMPUTE_ENTRY) { os.exit(22i32) }

    if gl.load(a, .Gl46Core, every, 0usize, &dispatch) != ok { os.exit(15i32) }
    set_version("4.6.0 - Build 31.0.101.3962")
    let (major, minor, es, version_error) = gl.version()
    if version_error != ok || major != 4u32 || minor != 6u32 || es { os.exit(16i32) }
    set_version("OpenGL ES 3.2 Mesa 25.2.8")
    let (es_major, es_minor, is_es, es_error) = gl.version()
    if es_error != ok || es_major != 3u32 || es_minor != 2u32 || !is_es { os.exit(17i32) }
    set_version("garbage")
    let (_, _, _, garbage_error) = gl.version()
    if garbage_error != gl.Failed { os.exit(18i32) }

    if gl.COLOR_BUFFER_BIT != 16384u32 || gl.COMPUTE_SHADER != 37305u32 || gl.TIMEOUT_IGNORED != 18446744073709551615u64 { os.exit(19i32) }
    if egl.DONT_CARE != -1i32 || egl.NO_CONTEXT != 0usize || egl.TRUE != 1u32 || egl.PLATFORM_SURFACELESS_MESA != 12765i32 { os.exit(20i32) }

    if egl.load(a, "no-such-egl-library") != egl.NoLoader { os.exit(21i32) }
    gl.release(&dispatch)
    ret ok
}
