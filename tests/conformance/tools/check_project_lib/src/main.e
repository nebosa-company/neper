// A module outside src is walked by no child of its own (T003): its error comes
// from the src modules that reach it, once.
use helper

fn main() {
    helper.go()
}
