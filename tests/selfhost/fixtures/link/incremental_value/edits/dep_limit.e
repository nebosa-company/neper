// The same module with the constant's value changed: `main` folds the other way.
const LIMIT: usize = 1usize

fn answer() -> i32 {
    ret 4i32
}
