type Context = struct { released: usize }
type Token = resource(release) struct { slot: usize }

fn acquire() -> Token {
    ret Token { slot: 1usize }
}

fn release(ctx: *Context, token: own Token) -> err {
    ctx.released += token.slot
    ret ok
}

// A cleanup may take context before its final owned resource parameter (D613).
fn run() -> err {
    var ctx: Context = zero
    let token = acquire()
    defer let _ = release(&ctx, token)
    ret ok
}
