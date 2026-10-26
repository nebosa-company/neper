// Metal compute under `e.gpu` (C193, D5231): only a Mac has it. This is every other host's `e.gpu.metal`, with the Mac's
// interface (lib/e/gpu/metal.macos.e) and nothing behind it: no device, and `open` is `Unsupported`.
use e.mem

error NoDevice
error Unsupported
error Failed
error CompileFailed

type Context = struct { device: usize, queue: usize }
type Buffer = struct { handle: usize, bytes: []u8 }
type Pipeline = struct { state: usize, max_threads: usize }
type Size = struct { width: usize, height: usize, depth: usize }

fn available() -> bool { ret false }

fn name(context: Context, out: []u8) -> usize { ret 0usize }

fn open(a: *mem.Arena) -> (Context, err) {
    var none: Context = zero
    ret (none, Unsupported)
}

fn close(context: Context) {}

fn buffer(context: Context, bytes: usize) -> (Buffer, err) {
    var none: Buffer = zero
    ret (none, Unsupported)
}

fn free(buffer_value: Buffer) {}

fn compile(context: Context, source: str, entry: str) -> (Pipeline, err) {
    var none: Pipeline = zero
    ret (none, Unsupported)
}

fn destroy(pipeline: Pipeline) {}

fn dispatch(context: Context, pipeline: Pipeline, buffers: []const Buffer, groups: Size, per_group: Size, shared_bytes: usize) -> err {
    ret Unsupported
}
