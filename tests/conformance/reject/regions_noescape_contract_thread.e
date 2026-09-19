use e.os

type Context = struct { value: i64 }

fn work(ctx: *Context) {
    ctx.value = 1
}

// A detached execution context necessarily outlives the spawning call.
@noescape("ctx")
fn launch(ctx: *Context) -> err {
    let worker = try os.thread_create[Context](work, ctx, 65536usize)
    ret os.thread_join(worker)
}

fn main() {}
