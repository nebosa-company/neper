var retained: []const u8 = zero

// Global retention is checked for every input named by the contract.
@noescape("left", "right")
fn retain(left: []const u8, right: []const u8) {
    retained = right
}

fn main() {}
