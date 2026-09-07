// The returned expression does not have the declared type. This used to report
// "ret is not legal inside defer", in a file with no defer anywhere.

fn width(n: usize) -> usize {
    ret n + "ab"
}

fn main() -> err { ret ok }
