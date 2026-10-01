const N: usize = 4_194_317;
const ITERS: usize = 8;

fn main() {
    let mut input = vec![0u8; N];
    let mut text = vec![0u8; 2 * N];
    let mut back = vec![0u8; N];
    let hex = b"0123456789abcdef";
    for (i, value) in input.iter_mut().enumerate() { *value = (i * 73 + 19) as u8; }
    for _ in 0..ITERS {
        for i in 0..N { text[2 * i] = hex[(input[i] >> 4) as usize]; text[2 * i + 1] = hex[(input[i] & 15) as usize]; }
        for i in 0..N {
            let nibble = |c: u8| if c <= b'9' { c - b'0' } else { c - b'a' + 10 };
            let (hi, lo) = (nibble(text[2 * i]), nibble(text[2 * i + 1]));
            if hi > 15 || lo > 15 { std::process::exit(2); }
            back[i] = (hi << 4) | lo;
        }
    }
    if back != input { std::process::exit(3); }
    let checksum: u64 = back.iter().map(|&x| x as u64).sum();
    println!("gp09 {checksum}");
}
