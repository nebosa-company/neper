fn main() {
    let count = "benchmark harness".chars().filter(|c| "aeiou".contains(*c)).count();
    println!("{}", count);
}
