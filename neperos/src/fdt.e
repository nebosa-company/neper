// The flattened device tree a loader hands the kernel in x0 (Devicetree Specification
// v0.4, chapter 5): a header, a structure block of big-endian tokens and a strings block.
// Every device address NeperOS uses comes from here, never from a constant (D2119),
// because QEMU's `virt`, crosvm and a phone lay their machines out differently. Nothing is
// copied: a node is the offset of its BEGIN_NODE token and a property is a view of its
// value.

error BadTree
error Missing

const FDT_MAGIC: u32 = 3490578157u32
const FDT_BEGIN_NODE: u32 = 1u32
const FDT_END_NODE: u32 = 2u32
const FDT_PROP: u32 = 3u32
const FDT_NOP: u32 = 4u32
const FDT_END: u32 = 9u32

type Tree = struct { bytes: str, structure: usize, structure_end: usize, strings: usize, strings_end: usize }

fn be32(bytes: str, at: usize) -> u32 {
    if at + 4usize > bytes.len { ret 0u32 }
    ret (u32(bytes[at]) << 24u32) | (u32(bytes[at + 1usize]) << 16u32) | (u32(bytes[at + 2usize]) << 8u32) | u32(bytes[at + 3usize])
}

fn open(bytes: str) -> (Tree, err) {
    if bytes.len < 40usize || be32(bytes, 0usize) != FDT_MAGIC { ret (zero, BadTree) }
    let total = usize(be32(bytes, 4usize))
    let structure = usize(be32(bytes, 8usize))
    let strings = usize(be32(bytes, 12usize))
    let strings_size = usize(be32(bytes, 32usize))
    let structure_size = usize(be32(bytes, 36usize))
    if total > bytes.len || structure + structure_size > total || strings + strings_size > total { ret (zero, BadTree) }
    ret (Tree { bytes: bytes, structure: structure, structure_end: structure + structure_size, strings: strings, strings_end: strings + strings_size }, ok)
}

fn align4(value: usize) -> usize {
    ret (value + 3usize) & ~3usize
}

// The NUL-terminated name at `at`, without its NUL.
fn text_at(t: Tree, at: usize, end: usize) -> str {
    var stop = at
    while stop < end && t.bytes[stop] != 0u8 { stop += 1usize }
    ret t.bytes[at..stop]
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

// A node's name against one path component: `memory` matches `memory@40000000`, but a
// component with its own unit address must match whole.
fn name_matches(name: str, component: str) -> bool {
    if same(name, component) { ret true }
    var at = 0usize
    while at < component.len {
        if component[at] == 64u8 { ret false }
        at += 1usize
    }
    ret name.len > component.len && name[component.len] == 64u8 && same(name[0usize..component.len], component)
}

// Where the token after the one at `at` starts, and the token's kind.
fn next_token(t: Tree, at: usize) -> (usize, u32) {
    let token = be32(t.bytes, at)
    if token == FDT_BEGIN_NODE {
        let name = text_at(t, at + 4usize, t.structure_end)
        ret (align4(at + 4usize + name.len + 1usize), token)
    }
    if token == FDT_PROP {
        let length = usize(be32(t.bytes, at + 4usize))
        ret (align4(at + 12usize + length), token)
    }
    ret (at + 4usize, token)
}

// The `index`th component of an absolute path, `/` not counted.
fn path_component(path: str, index: usize) -> str {
    var at = 1usize
    var seen = 0usize
    while at <= path.len {
        var stop = at
        while stop < path.len && path[stop] != 47u8 { stop += 1usize }
        if seen == index { ret path[at..stop] }
        seen += 1usize
        at = stop + 1usize
    }
    ret ""
}

fn component_count(path: str) -> usize {
    if path.len <= 1usize { ret 0usize }
    var count = 1usize
    var at = 1usize
    while at < path.len {
        if path[at] == 47u8 { count += 1usize }
        at += 1usize
    }
    ret count
}

// The node at an absolute path, `/chosen` or `/pl011@9000000`.
fn find_path(t: Tree, path: str) -> (usize, err) {
    if path.len == 0usize || path[0usize] != 47u8 { ret (0usize, Missing) }
    let wanted = component_count(path)
    var at = t.structure
    var depth = 0usize
    var matched = 0usize
    while at < t.structure_end {
        let (after, token) = next_token(t, at)
        if token == FDT_END { ret (0usize, Missing) }
        if token == FDT_BEGIN_NODE {
            if depth == 0usize {
                if wanted == 0usize { ret (at, ok) }
            } else {
                if matched + 1usize == depth && name_matches(text_at(t, at + 4usize, t.structure_end), path_component(path, depth - 1usize)) {
                    matched = depth
                    if matched == wanted { ret (at, ok) }
                }
            }
            depth += 1usize
        }
        if token == FDT_END_NODE {
            if depth == 0usize { ret (0usize, BadTree) }
            depth -= 1usize
            if matched == depth && matched != 0usize { matched -= 1usize }
        }
        at = after
    }
    ret (0usize, Missing)
}

// Whether node `node`'s `compatible` property lists `want` as one of its NUL-separated entries.
fn compatible_has(t: Tree, node: usize, want: str) -> bool {
    let (value, value_error) = property(t, node, "compatible")
    if value_error != ok { ret false }
    var start = 0usize
    var at = 0usize
    while at < value.len {
        if value[at] == 0u8 {
            if same(value[start..at], want) { ret true }
            start = at + 1usize
        }
        at += 1usize
    }
    ret start < value.len && same(value[start..value.len], want)
}

// The first node anywhere in the tree whose `compatible` lists `want`. Device addresses differ
// between machines (D2119), so a host is found by what it is, not where it sits or its node name:
// QEMU's `virt` names the PCI host `pcie@...` compatible `pci-host-ecam-generic`, crosvm names it
// `pci@...` compatible `pci-host-cam-generic`.
fn find_compatible(t: Tree, want: str) -> (usize, err) {
    var at = t.structure
    while at < t.structure_end {
        let (after, token) = next_token(t, at)
        if token == FDT_END { ret (0usize, Missing) }
        if token == FDT_BEGIN_NODE && compatible_has(t, at, want) { ret (at, ok) }
        at = after
    }
    ret (0usize, Missing)
}

// A property of the node at `node`, its own and not a child's.
fn property(t: Tree, node: usize, name: str) -> (str, err) {
    if be32(t.bytes, node) != FDT_BEGIN_NODE { ret (t.bytes[0usize..0usize], BadTree) }
    let (first, first_token) = next_token(t, node)
    var at = first
    while at < t.structure_end {
        let (after, token) = next_token(t, at)
        if token == FDT_PROP {
            let length = usize(be32(t.bytes, at + 4usize))
            let name_at = t.strings + usize(be32(t.bytes, at + 8usize))
            if name_at < t.strings_end && same(text_at(t, name_at, t.strings_end), name) { ret (t.bytes[at + 12usize..at + 12usize + length], ok) }
        }
        if token != FDT_PROP && token != FDT_NOP { ret (t.bytes[0usize..0usize], Missing) }
        at = after
    }
    ret (t.bytes[0usize..0usize], Missing)
}

// A string property, without the NUL that ends it.
fn property_text(t: Tree, node: usize, name: str) -> (str, err) {
    let (value, value_error) = property(t, node, name)
    if value_error != ok { ret ("", value_error) }
    var stop = 0usize
    while stop < value.len && value[stop] != 0u8 { stop += 1usize }
    ret (value[0usize..stop], ok)
}

// A number of `cells` 32-bit cells at `at` of a property's value.
fn cells_at(value: str, at: usize, cells: usize) -> u64 {
    var result = 0u64
    var cell = 0usize
    while cell < cells {
        result = (result << 32u64) | u64(be32(value, at + cell * 4usize))
        cell += 1usize
    }
    ret result
}

// The root's `#address-cells` and `#size-cells`: how wide a child's `reg` entries are.
fn root_cells(t: Tree) -> (usize, usize) {
    let (root, root_error) = find_path(t, "/")
    if root_error != ok { ret (2usize, 1usize) }
    var address_cells = 2usize
    var size_cells = 1usize
    let (address_value, address_error) = property(t, root, "#address-cells")
    if address_error == ok { address_cells = usize(be32(address_value, 0usize)) }
    let (size_value, size_error) = property(t, root, "#size-cells")
    if size_error == ok { size_cells = usize(be32(size_value, 0usize)) }
    ret (address_cells, size_cells)
}

// The first `reg` region of a child of the root: its address and size.
fn region(t: Tree, node: usize) -> (u64, u64, err) {
    let (address, size, region_error) = region_n(t, node, 0usize)
    ret (address, size, region_error)
}

// A property that holds one 32-bit or 64-bit big-endian number: `/chosen`'s initrd bounds
// come either way depending on the loader.
fn integer(t: Tree, node: usize, name: str) -> (u64, err) {
    let (value, value_error) = property(t, node, name)
    if value_error != ok { ret (0u64, value_error) }
    if value.len == 8usize { ret (cells_at(value, 0usize, 2usize), ok) }
    if value.len == 4usize { ret (u64(be32(value, 0usize)), ok) }
    ret (0u64, BadTree)
}

// The `index`th `reg` region of a child of the root (the GIC names two: distributor then
// redistributors).
fn region_n(t: Tree, node: usize, index: usize) -> (u64, u64, err) {
    let (value, value_error) = property(t, node, "reg")
    if value_error != ok { ret (0u64, 0u64, value_error) }
    let (address_cells, size_cells) = root_cells(t)
    let stride = (address_cells + size_cells) * 4usize
    let at = index * stride
    if address_cells > 2usize || size_cells > 2usize || value.len < at + stride { ret (0u64, 0u64, BadTree) }
    ret (cells_at(value, at, address_cells), cells_at(value, at + address_cells * 4usize, size_cells), ok)
}
