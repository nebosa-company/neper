const N: usize = 1_048_576;
const ITERS: usize = 16;

fn main() {
    let x: Vec<u32> = (0..N).map(|i| (i & 1023) as u32).collect();
    let mut y = vec![1u32; N];
    for _ in 0..ITERS { for i in 0..N { y[i] = 3 * x[i] + y[i]; } }
    let checksum: u64 = y.iter().map(|&x| x as u64).sum();
    println!("gp10 {checksum}");
}
