use lowhelp

fn mix(x: u32) -> u32 {
    let (a, b) = lowhelp.pair(x)
    ret lowhelp.add3(a) ^ b
}
