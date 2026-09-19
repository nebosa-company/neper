// A function value carries no checked no-escape summary.
@noescape("bytes")
fn invoke(callback: fn([]const u8), bytes: []const u8) {
    callback(bytes)
}

fn main() {}
