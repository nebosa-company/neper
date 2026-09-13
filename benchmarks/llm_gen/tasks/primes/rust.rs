fn is_prime(n: i32) -> bool {
    if n < 2 { return false; }
    let mut d = 2;
    while d * d <= n {
        if n % d == 0 { return false; }
        d += 1;
    }
    true
}

fn main() {
    let count = (0..100).filter(|&n| is_prime(n)).count();
    println!("{}", count);
}
