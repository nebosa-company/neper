const WEIGHT = 10u32

fn checksum(n: u32) -> u32 {
    var total = 0u32
    var i = 1u32
    while i <= n {
        total += i * WEIGHT - i
        i += 1u32
    }
    ret total - 40u32 * 2u32 + WEIGHT * 8u32
}
