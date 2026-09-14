// `build-manifest --json` on a project (D265): inputs under their real roots, and every
// module but the root as a dependency with its interface and body hashes.
use helper

fn main() {
    let n = helper.twice(2i32)
}
