// `x.khronos.context` on a host with no OpenGL context of its own (wasm32-wasi, macOS): the same
// declarations as the Linux and Windows variants, each answering Unsupported, so a program that
// offers `--gl` still builds there and falls back to its software frames.

use e.mem
use e.os
use x.khronos.eglcontext
use x.khronos.gl

error Unsupported
error Failed

type Api = eglcontext.Api
type Options = eglcontext.Options
type Context = struct { dispatch: gl.Dispatch }
type PointerPun = union { pointer: *void, bits: usize }
type BytesPun = union { pointer: *u8, bits: usize }

fn profile_of(options: Options) -> gl.Profile { ret eglcontext.profile_of(options) }

fn resolve(a: *mem.Arena, context: usize, name: str) -> usize { ret 0usize }

fn resolver_context(c: *const Context) -> usize { ret 0usize }

fn as_pointer(bits: usize) -> *void {
    var pun: PointerPun = zero
    pun.bits = bits
    ret pun.pointer
}

fn as_bytes(bits: usize) -> *u8 {
    var pun: BytesPun = zero
    pun.bits = bits
    ret pun.pointer
}

fn headless(a: *mem.Arena, options: Options) -> (Context, err) { ret (zero, Unsupported) }

fn for_window(a: *mem.Arena, w: os.Window, options: Options) -> (Context, err) { ret (zero, Unsupported) }

fn make_current(c: *const Context) -> err { ret Unsupported }

fn swap(c: *const Context) -> err { ret Unsupported }

fn swap_interval(c: *const Context, interval: i32) -> err { ret Unsupported }

fn load(a: *mem.Arena, c: *Context, options: Options) -> err { ret Unsupported }

fn close(c: *Context) -> err { ret ok }
