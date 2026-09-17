// A contextual resource closer is a semantic reference (D560, H17): renaming the
// function must rewrite this annotation as well as ordinary calls.
type Handle = resource(close) struct { raw: usize }

fn close(h: own Handle) {}

fn main() {}
