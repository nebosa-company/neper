type Context = struct { released: usize }
type Token = resource(release) struct { slot: usize }

// The resource must be the cleanup's final parameter (D613).
fn release(token: own Token, ctx: *Context) -> err {
    ret ok
}

fn run() {}
