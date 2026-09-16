// An error and the function that raises it (D451, H17): the error is named bare
// here and qualified from `main`.
error Stalled

fn attempt(fail: bool) -> err {
    if fail { ret Stalled }
    ret ok
}
