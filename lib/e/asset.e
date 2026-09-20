// The asset registry of a build with no declared assets: empty. When the root
// project's `project.yaml` declares `assets:`, the compiler generates this
// module's text from them (D80, D777) -- the same fence, over string literals in
// the read-only data and an attribute table filled once -- so a program reads its
// assets the same way on every target and never opens a file for them. Entries are
// sorted by UTF-8 logical name; a lookup allocates nothing and answers slices that
// live as long as the process.

type Attribute = struct { name: str, value: str }
type Asset = struct { name: str, media_type: str, bytes: []const u8, sha256: [32]u8, attributes: []const Attribute }

fn count() -> usize {
    ret 0usize
}

fn at(index: usize) -> (Asset, bool) {
    ret (zero, false)
}

fn get(name: str) -> (Asset, bool) {
    ret (zero, false)
}

fn attribute(value: Asset, name: str) -> (str, bool) {
    var i = 0usize
    while i < value.attributes.len {
        let candidate = value.attributes[i].name
        if candidate.len == name.len {
            var j = 0usize
            while j < name.len && candidate[j] == name[j] { j += 1usize }
            if j == name.len { ret (value.attributes[i].value, true) }
        }
        i += 1usize
    }
    ret ("", false)
}
