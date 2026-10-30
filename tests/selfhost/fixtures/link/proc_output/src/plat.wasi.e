// A wasm module cannot choose to ignore a signal: the runner's group terminate is the host's, so
// there is nothing a descendant can elect to ignore.
fn ignore_gentle_termination() -> bool { ret true }
