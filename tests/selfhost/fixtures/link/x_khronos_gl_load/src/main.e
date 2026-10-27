// x.khronos.gl's loader without a driver (L172, L173): a resolver that finds every entry
// fills the table for each profile; one that lacks glDispatchCompute fails the compute
// profiles (GL 4.3, GL 4.6, GLES 3.1) by name and passes GL 3.3 and GLES 3.0, which do not
// require it; one that lacks glClear fails every profile. EGL from a library that does not
// exist is NoLoader. The version parser reads desktop and ES strings through a fake glGetString.

use e.mem
use e.os
use x.khronos.egl
use x.khronos.gl

var version_text: [64]u8 = zero

fn fake_get_string(name: u32) -> *const u8 { ret &version_text[0usize] }

type ProcPun = union { function: fn(u32) -> *const u8, bits: usize }

fn every(a: *mem.Arena, context: usize, name: str) -> usize {
    if mem.eq[u8](name, "glGetString") {
        var pun: ProcPun = zero
        pun.function = fake_get_string
        ret pun.bits
    }
    ret 4096usize
}

fn without_dispatch(a: *mem.Arena, context: usize, name: str) -> usize {
    if mem.eq[u8](name, "glDispatchCompute") { ret 0usize }
    ret 4096usize
}

fn without_clear(a: *mem.Arena, context: usize, name: str) -> usize {
    if mem.eq[u8](name, "glClear") { ret 0usize }
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
    if gl.load(a, .Gl33Core, every, 0usize) != ok { os.exit(2i32) }
    if gl.load(a, .Gl46Core, every, 0usize) != ok { os.exit(3i32) }
    if gl.load(a, .Gles32, every, 0usize) != ok { os.exit(4i32) }
    if gl.missing().len != 0usize { os.exit(5i32) }

    if gl.load(a, .Gl33Core, without_dispatch, 0usize) != ok { os.exit(6i32) }
    if gl.load(a, .Gles30, without_dispatch, 0usize) != ok { os.exit(7i32) }
    if gl.load(a, .Gl43Core, without_dispatch, 0usize) != gl.Unsupported { os.exit(8i32) }
    if !mem.eq[u8](gl.missing(), "glDispatchCompute") { os.exit(9i32) }
    if gl.load(a, .Gl46Core, without_dispatch, 0usize) != gl.Unsupported { os.exit(10i32) }
    if gl.load(a, .Gles31, without_dispatch, 0usize) != gl.Unsupported { os.exit(11i32) }

    if gl.load(a, .Gl33Core, without_clear, 0usize) != gl.Unsupported { os.exit(12i32) }
    if !mem.eq[u8](gl.missing(), "glClear") { os.exit(13i32) }
    if gl.load(a, .Gles30, without_clear, 0usize) != gl.Unsupported { os.exit(14i32) }

    if gl.load(a, .Gl46Core, every, 0usize) != ok { os.exit(15i32) }
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
    ret ok
}
