// Windows jobs have no cooperative signal: the host's gentle and forced operations are
// both TerminateJobObject, so there is nothing a descendant can elect to ignore.
fn ignore_gentle_termination() -> bool { ret true }
