// Generic helpers two modules away from the kernel that calls them.
fn twice[T: type](x: T) -> T {
    ret x + x
}

fn clamp_to[T: type](x: T, high: T) -> T {
    var out = x
    if x > high { out = high }
    ret out
}
