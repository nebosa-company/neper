fn gcd(mut p: i32, mut q: i32) -> i32 {
    while q != 0 {
        let r = p % q;
        p = q;
        q = r;
    }
    p
}

fn main() {
    println!("{}", gcd(1071, 462));
}
